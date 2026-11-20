import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aim_for_android/oscar/aim_html.dart';
import 'package:aim_for_android/oscar/bytes.dart';
import 'package:aim_for_android/oscar/client.dart';
import 'package:aim_for_android/oscar/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end tests against a running Open OSCAR Server.
/// Set OSCAR_SERVER=host:port. Accounts alice/bob/carol with password
/// "password1" must exist (CI creates them through the management API).
final _server = Platform.environment['OSCAR_SERVER'];
const _pw = 'password1';

AimClient _client(String sn, {String pw = _pw}) => AimClient(
      server: ServerConfig.parse(_server!),
      screenName: sn,
      password: pw,
      backoff: const [Duration(milliseconds: 300), Duration(seconds: 1)],
    );

Future<void> _online(AimClient c) async {
  if (c.isOnline) return;
  await c.events
      .firstWhere((e) => e is LinkStateChanged && (e.state == LinkState.online || e.state == LinkState.stopped))
      .timeout(const Duration(seconds: 30));
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
    final b = _client('bob');
    final c = _client('carol');
    b.start();
    c.start();
    await _online(b);
    await _online(c);

    // bob watches carol
    bool carolIs(OscarEvent e, Type t) =>
        (e is BuddyArrived && t == BuddyArrived && normalizeSn(e.info.screenName) == 'carol') ||
        (e is BuddyDeparted && t == BuddyDeparted && normalizeSn(e.screenName) == 'carol');
    if (!b.session!.isBuddy('carol')) {
      await b.session!.addBuddy('carol', 'Buddies');
    }
    await Future<void>.delayed(const Duration(seconds: 1));

    // warn needs a message from bob first
    final got = _nextMessage(c);
    b.send('carol', 'spam spam');
    await got;
    final level = await c.session!.warn('bob');
    expect(level, greaterThan(0));

    // block: bob sees carol leave
    final left = b.events.firstWhere((e) => e is SessionEvent && carolIs(e.event, BuddyDeparted));
    await c.session!.block('bob');
    expect(c.session!.isBlocked('bob'), isTrue);
    await left.timeout(const Duration(seconds: 15));

    // unblock: carol comes back
    final back = b.events.firstWhere((e) => e is SessionEvent && carolIs(e.event, BuddyArrived));
    await c.session!.unblock('bob');
    expect(c.session!.isBlocked('bob'), isFalse);
    await back.timeout(const Duration(seconds: 15));

    await b.dispose();
    await c.dispose();
  }, skip: skip, timeout: t);
}
