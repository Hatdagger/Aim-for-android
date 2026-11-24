import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aim_for_android/oscar/aim_html.dart';
import 'package:aim_for_android/oscar/bytes.dart';
import 'package:aim_for_android/oscar/chat_room.dart';
import 'package:aim_for_android/oscar/client.dart';
import 'package:aim_for_android/oscar/direct_connect.dart';
import 'package:aim_for_android/oscar/odc.dart';
import 'package:aim_for_android/oscar/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end tests against a running Open OSCAR Server.
/// Set OSCAR_SERVER=host:port. Accounts alice/bob/carol/dave/erin with password
/// "password1" must exist (CI creates them through the management API).
final _server = Platform.environment['OSCAR_SERVER'];
const _pw = 'password1';

AimClient _client(String sn, {String pw = _pw}) => AimClient(
      server: ServerConfig.parse(_server!),
      screenName: sn,
      password: pw,
      useUpnp: false,
      backoff: const [Duration(milliseconds: 300), Duration(seconds: 1)],
    );

Future<void> _dcState(AimClient c, DirectState s, {Duration wait = const Duration(seconds: 40)}) => c.events
    .firstWhere((e) => e is DirectConnectEvent && e.event is DirectStateChanged && (e.event as DirectStateChanged).state == s)
    .timeout(wait, onTimeout: () => throw TestFailure('${c.screenName}: no Direct Connect state $s '
        '(now ${c.direct.links.values.map((l) => '${l.peer}=${l.state}').join(', ')})'));

Future<DirectMessage> _dcMessage(AimClient c) async {
  final e = await c.events
      .firstWhere((e) => e is DirectConnectEvent && e.event is DirectMessageIn)
      .timeout(const Duration(seconds: 30));
  return ((e as DirectConnectEvent).event as DirectMessageIn).message;
}

Future<void> _online(AimClient c, {Duration wait = const Duration(seconds: 30)}) async {
  if (c.isOnline) return;
  await c.events
      .firstWhere((e) => e is LinkStateChanged && (e.state == LinkState.online || e.state == LinkState.stopped))
      .timeout(wait);
  if (!c.isOnline) fail('${c.screenName} did not sign on: ${c.lastMessage}');
}

Future<String> _nextMessage(AimClient c, {bool auto = false}) async {
  final e = await c.events
      .firstWhere((e) => e is SessionEvent && e.event is MessageReceived &&
          (e.event as MessageReceived).message.autoResponse == auto)
      .timeout(const Duration(seconds: 30));
  return ((e as SessionEvent).event as MessageReceived).message.text;
}

void main() {
  final skip = _server == null ? 'OSCAR_SERVER not set' : false;
  const t = Timeout(Duration(minutes: 2));

  test('wrong password stops without retry loop', () async {
    final c = _client('carol', pw: 'wrong-password');
    c.start();
    final e = await c.events
        .firstWhere((e) => e is LinkStateChanged && (e.state == LinkState.stopped || e.state == LinkState.online))
        .timeout(const Duration(seconds: 30));
    expect((e as LinkStateChanged).state, LinkState.stopped);
    await c.dispose();
  }, skip: skip, timeout: t);

  test('sign on, buddy list, IM both ways, typing, profile, away + auto-reply', () async {
    final a = _client('alice');
    final b = _client('bob');
    a.start();
    b.start();
    await _online(a);
    await _online(b);

    // alice adds bob, sees him online
    final arrived = a.events.firstWhere((e) =>
        e is SessionEvent && e.event is BuddyArrived && normalizeSn((e.event as BuddyArrived).info.screenName) == 'bob');
    if (!a.session!.groups.any((g) => g.buddies.any((x) => normalizeSn(x) == 'bob'))) {
      await a.session!.addBuddy('bob', 'Buddies');
    }
    expect(a.session!.groups.expand((g) => g.buddies).map(normalizeSn), contains('bob'));
    await arrived.timeout(const Duration(seconds: 20), onTimeout: () => SessionEvent(BuddyListChanged()));

    final got = _nextMessage(b);
    a.send('bob', 'hello <bob> & co');
    expect(await got, 'hello <bob> & co');

    final got2 = _nextMessage(a);
    b.send('alice', 'unicode ☕ ok');
    expect(await got2, 'unicode ☕ ok');

    final typing = b.events.firstWhere((e) => e is SessionEvent && e.event is TypingChanged);
    a.session!.sendTyping('bob', 2);
    final te = await typing.timeout(const Duration(seconds: 10));
    expect(((te as SessionEvent).event as TypingChanged).state, 2);

    a.setProfile(textToAimHtml('alice profile text'));
    a.setAway(textToAimHtml('gone fishing'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final p = await b.session!.getProfile('alice');
    expect(htmlToText(p.profileHtml ?? ''), contains('alice profile text'));
    expect(htmlToText(p.awayHtml ?? ''), contains('gone fishing'));

    final auto = _nextMessage(b, auto: true);
    b.send('alice', 'are you there?');
    expect(await auto, contains('gone fishing'));
    a.setAway(null);

    await a.dispose();
    await b.dispose();
  }, skip: skip, timeout: t);

  test('reconnects after a dropped link and delivers queued messages', () async {
    final a = _client('alice');
    final b = _client('bob');
    a.start();
    b.start();
    await _online(a);
    await _online(b);

    a.debugDropConnection();
    final m = a.send('bob', 'sent while reconnecting');
    expect(m.isPending, isTrue);
    final got = _nextMessage(b);
    expect(await got, 'sent while reconnecting');
    expect(a.isOnline, isTrue);
    expect(a.outbox, isEmpty);

    await a.dispose();
    await b.dispose();
  }, skip: skip, timeout: t);

  test('holds messages for an offline buddy, delivers on sign-on, and can cancel', () async {
    final a = _client('alice');
    a.start();
    await _online(a);
    if (!a.session!.groups.any((g) => g.buddies.any((x) => normalizeSn(x) == 'bob'))) {
      await a.session!.addBuddy('bob', 'Buddies');
    }

    final waiting = a.send('bob', 'for later');
    final cancelMe = a.send('bob', 'never mind');
    await a.events
        .firstWhere((e) => e is OutboxChanged && e.message.id == cancelMe.id && e.message.status == OutboxStatus.waitingForBuddy)
        .timeout(const Duration(seconds: 20));
    expect(waiting.status, OutboxStatus.waitingForBuddy);
    expect(a.cancel(cancelMe.id), isTrue);

    final b = _client('bob');
    final got = <String>[];
    final sub = b.events.listen((e) {
      if (e is SessionEvent && e.event is MessageReceived) got.add((e.event as MessageReceived).message.text);
    });
    b.start();
    await _online(b);
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!got.contains('for later') && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(got, contains('for later'));
    expect(got, isNot(contains('never mind')));
    await sub.cancel();
    await a.dispose();
    await b.dispose();
  }, skip: skip, timeout: t);

  test('buddy icon upload and download', () async {
    final a = _client('alice');
    final b = _client('bob');
    a.start();
    b.start();
    await _online(a);
    await _online(b);
    // 1x1 GIF
    final gif = Uint8List.fromList([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 0, 1, 0, 0x80, 0, 0, 0xff, 0, 0, 0, 0, 0, 0x21, 0xf9, 4, 1, 0, 0, 0, 0,
      0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x44, 1, 0, 0x3b,
    ]);
    await a.session!.setBuddyIcon(gif);
    final hash = Uint8List.fromList(md5.convert(gif).bytes);
    Uint8List? got;
    for (var i = 0; i < 10 && got == null; i++) {
      got = await b.session!.fetchBuddyIcon('alice', hash);
      if (got == null) await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(got, gif);
    await a.dispose();
    await b.dispose();
  }, skip: skip, timeout: t);

  test('warn, block (buddy sees you go offline) and unblock', () async {
    final b = _client('dave');
    final c = _client('erin');
    b.start();
    c.start();
    // The server allows ~10 quick sign-ons per address; earlier tests use them
    // up, so these may wait for its one-minute window.
    await _online(b, wait: const Duration(seconds: 100));
    await _online(c, wait: const Duration(seconds: 100));

    // dave watches erin
    bool erinIs(OscarEvent e, Type t) =>
        (e is BuddyArrived && t == BuddyArrived && normalizeSn(e.info.screenName) == 'erin') ||
        (e is BuddyDeparted && t == BuddyDeparted && normalizeSn(e.screenName) == 'erin');
    if (!b.session!.isBuddy('erin')) {
      await b.session!.addBuddy('erin', 'Buddies');
    }
    await Future<void>.delayed(const Duration(seconds: 1));

    // warn needs a message from dave first
    final got = _nextMessage(c);
    b.send('erin', 'spam spam');
    await got;
    final level = await c.session!.warn('dave');
    expect(level, greaterThan(0));

    // block: dave sees erin leave
    final left = b.events.firstWhere((e) => e is SessionEvent && erinIs(e.event, BuddyDeparted));
    await c.session!.block('dave');
    expect(c.session!.isBlocked('dave'), isTrue);
    await left.timeout(const Duration(seconds: 15));

    // unblock: erin comes back
    final back = b.events.firstWhere((e) => e is SessionEvent && erinIs(e.event, BuddyArrived));
    await c.session!.unblock('dave');
    expect(c.session!.isBlocked('dave'), isFalse);
    await back.timeout(const Duration(seconds: 15));

    await b.dispose();
    await c.dispose();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  test('buddy list editing: new, rename, move, reorder and delete groups', () async {
    final c = _client('carol');
    c.start();
    await _online(c, wait: const Duration(minutes: 2));
    final s = c.session!;
    int gid(String name) => s.groups.firstWhere((g) => g.name == name).groupId;
    final tag = DateTime.now().millisecondsSinceEpoch % 100000;
    final g1 = 'Friends$tag', g2 = 'School$tag', g3 = 'Pals$tag';

    await s.addGroup(g1);
    await s.addBuddy('alice', g1);
    await s.addBuddy('bob', g1);
    await s.addGroup(g2);
    expect(s.groups.map((g) => g.name), containsAll([g1, g2]));

    await s.moveBuddyWithinGroup('bob', -1);
    expect(s.groups.firstWhere((g) => g.name == g1).buddies.first.toLowerCase(), 'bob');

    await s.moveBuddy('alice', gid(g2));
    expect(s.groups.firstWhere((g) => g.name == g2).buddies.map((b) => b.toLowerCase()), contains('alice'));
    expect(s.groups.firstWhere((g) => g.name == g1).buddies.map((b) => b.toLowerCase()), isNot(contains('alice')));

    await s.renameGroup(gid(g1), g3);
    expect(s.groups.map((g) => g.name), contains(g3));

    final before = s.groups.map((g) => g.groupId).toList();
    await s.moveGroup(gid(g2), -1);
    final after = s.groups.map((g) => g.groupId).toList();
    expect(after.indexOf(gid(g2)), before.indexOf(gid(g2)) - 1);

    // Delete one group, moving its buddy over; then delete the other with its buddies.
    await s.removeGroup(gid(g3), moveTo: gid(g2));
    expect(s.groups.map((g) => g.name), isNot(contains(g3)));
    expect(s.groups.firstWhere((g) => g.name == g2).buddies.map((b) => b.toLowerCase()), containsAll(['alice', 'bob']));
    await s.removeGroup(gid(g2));
    expect(s.groups.map((g) => g.name), isNot(contains(g2)));
    expect(s.isBuddy('alice'), isFalse);
    await c.dispose();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  test('Direct Connect: decline, pictures both ways, reverse connect, and failure', () async {
    final a = _client('alice');
    final b = _client('bob');
    a.start();
    b.start();
    await _online(a);
    await _online(b);

    // 1. bob says no
    var invited = _dcState(b, DirectState.invited);
    var declined = _dcState(a, DirectState.declined);
    await a.direct.invite('bob');
    await invited;
    await b.direct.decline('alice');
    await declined;

    // 2. bob accepts: messages and pictures go straight between them
    invited = _dcState(b, DirectState.invited);
    var aOpen = _dcState(a, DirectState.connected);
    var bOpen = _dcState(b, DirectState.connected);
    await a.direct.invite('bob');
    await invited;
    final prop = b.direct.linkFor('alice')!.proposal!;
    expect(prop.addresses, isNotEmpty);
    await b.direct.accept('alice');
    await aOpen;
    await bOpen;
    expect(a.direct.isOpen('bob'), isTrue);

    final pic = Uint8List.fromList([0xff, 0xd8, 0xff, ...List.generate(600000, (i) => (i * 7) & 0xff)]);
    var got = _dcMessage(b);
    await a.direct.send('bob', 'look at this', images: [OdcImage(1, pic, name: 'cat.jpg')]);
    var m = await got;
    expect(m.text, 'look at this');
    expect(m.images.single.data, pic);

    got = _dcMessage(a);
    await b.direct.send('alice', 'cute ☕');
    expect((await got).text, 'cute ☕');

    final typing = a.events.firstWhere((e) => e is DirectConnectEvent && e.event is DirectTypingIn);
    b.direct.sendTyping('alice', 2);
    final te = await typing.timeout(const Duration(seconds: 10));
    expect(((te as DirectConnectEvent).event as DirectTypingIn).state, 2);

    final aClosed = _dcState(a, DirectState.closed);
    await b.direct.close('alice');
    await aClosed;
    expect(a.direct.isOpen('bob'), isFalse);

    // 3. bob can't reach alice, so alice connects to bob instead
    a.direct.debugUnreachable = true;
    invited = _dcState(b, DirectState.invited);
    aOpen = _dcState(a, DirectState.connected);
    bOpen = _dcState(b, DirectState.connected);
    await a.direct.invite('bob');
    await invited;
    await b.direct.accept('alice');
    await aOpen;
    await bOpen;
    got = _dcMessage(a);
    await b.direct.send('alice', 'reverse ok', images: [OdcImage(1, pic.sublist(0, 1000))]);
    m = await got;
    expect(m.text, 'reverse ok');
    expect(m.images.single.data, pic.sublist(0, 1000));
    final bClosed = _dcState(b, DirectState.closed);
    await a.direct.close('bob');
    await bClosed;

    // 4. neither can reach the other: both just say it failed
    b.direct.debugUnreachable = true;
    invited = _dcState(b, DirectState.invited);
    final aFail = _dcState(a, DirectState.failed);
    final bFail = _dcState(b, DirectState.failed);
    await a.direct.invite('bob');
    await invited;
    await b.direct.accept('alice');
    await aFail;
    await bFail;

    await a.dispose();
    await b.dispose();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('chat rooms: make, invite, talk, members come and go, rejoin after a drop', () async {
    final a = _client('dave');
    final b = _client('erin');
    a.start();
    b.start();
    await _online(a);
    await _online(b);

    Future<RoomEvent> roomEvent(AimClient c, bool Function(RoomEvent) test) async {
      final e = await c.events
          .firstWhere((e) => e is RoomUpdate && e.event != null && test(e.event!))
          .timeout(const Duration(seconds: 20),
              onTimeout: () => throw TestFailure('${c.screenName}: room event did not arrive'));
      return (e as RoomUpdate).event!;
    }

    final name = 'Test Room ${DateTime.now().millisecondsSinceEpoch % 100000}';
    final room = await a.joinRoom(name);
    expect(room.isOpen, isTrue);
    expect(room.name, name);
    // dave sees himself in the room
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(room.members.map(normalizeSn), contains('dave'));

    // invite erin
    final invited = b.events
        .firstWhere((e) => e is SessionEvent && e.event is RoomInviteReceived)
        .timeout(const Duration(seconds: 20));
    final failed = await a.inviteToRoom(room.key, ['erin'], 'come in');
    expect(failed, isEmpty);
    final inv = ((await invited) as SessionEvent).event as RoomInviteReceived;
    expect(inv.invite.message, 'come in');
    expect(inv.invite.room.key, room.key);

    // erin joins; dave sees her arrive
    final arrived = roomEvent(a, (e) => e is RoomMembersChanged && e.joined.map(normalizeSn).contains('erin'));
    final bRoom = await b.acceptRoomInvite(inv.invite);
    await arrived;
    expect(bRoom.isOpen, isTrue);

    // talk both ways
    var heard = roomEvent(b, (e) => e is RoomMessageReceived);
    expect(a.sendToRoom(room.key, 'hi erin ☕'), isTrue);
    var m = (await heard) as RoomMessageReceived;
    expect(normalizeSn(m.message.from), 'dave');
    expect(m.message.text, 'hi erin ☕');

    heard = roomEvent(a, (e) => e is RoomMessageReceived);
    expect(b.sendToRoom(bRoom.key, 'hey dave'), isTrue);
    m = (await heard) as RoomMessageReceived;
    expect(m.message.text, 'hey dave');

    // erin's link drops: she rejoins the room by herself after reconnecting
    final reopened = b.events
        .firstWhere((e) => e is RoomUpdate && e.event == null && !e.left && e.room.isOpen)
        .timeout(const Duration(seconds: 40));
    b.debugDropConnection();
    await reopened;
    heard = roomEvent(b, (e) => e is RoomMessageReceived);
    expect(a.sendToRoom(room.key, 'welcome back'), isTrue);
    m = (await heard) as RoomMessageReceived;
    expect(m.message.text, 'welcome back');

    // erin leaves; dave sees it
    final gone = roomEvent(a, (e) => e is RoomMembersChanged && e.left.map(normalizeSn).contains('erin'));
    await b.leaveRoom(bRoom.key);
    await gone;
    expect(b.rooms, isEmpty);

    await a.dispose();
    await b.dispose();
  }, skip: skip, timeout: t);
}
