import 'dart:typed_data';

import 'package:aim_for_android/oscar/aim_html.dart';
import 'package:aim_for_android/oscar/bytes.dart';
import 'package:aim_for_android/oscar/chat_room.dart';
import 'package:aim_for_android/oscar/rendezvous.dart';
import 'package:aim_for_android/oscar/flap.dart';
import 'package:aim_for_android/oscar/models.dart';
import 'package:aim_for_android/oscar/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('away auto-replies show as text, not HTML tags', () {
    const away = '<HTML><BODY BGCOLOR="#ffffff"><FONT LANG="0">I am away from my phone right now.</FONT></BODY></HTML>';
    // What the old build sent: the away HTML escaped inside a new HTML message.
    final oldStyle = textToAimHtml(away);
    expect(messageText(oldStyle), 'I am away from my phone right now.');
    // What the fixed build sends: plain text wrapped once.
    expect(messageText(textToAimHtml(htmlToText(away))), 'I am away from my phone right now.');
    // Someone typing about tags in a normal message is left alone.
    expect(messageText(textToAimHtml('use <b> for bold')), 'use <b> for bold');
  });

  test('TLV round trip', () {
    final w = ByteWriter()
      ..tlvString(1, 'hello')
      ..tlvU16(2, 0xbeef)
      ..tlvU32(3, 0x01020304);
    final t = ByteReader(w.toBytes()).tlvs();
    expect(t[1]!.asString, 'hello');
    expect(t[2]!.asU16, 0xbeef);
    expect(t[3]!.asU32, 0x01020304);
    expect(t[9], isNull);
  });

  test('SNAC parse skips optional TLV prefix', () {
    final w = ByteWriter()
      ..u16(0x0004)
      ..u16(0x0007)
      ..u16(0x8000)
      ..u32(42)
      ..u16(4)
      ..bytes([1, 2, 3, 4])
      ..bytes([9, 9]);
    final s = Snac.parse(w.toBytes());
    expect(s.family, 4);
    expect(s.subtype, 7);
    expect(s.reqId, 42);
    expect(s.data, [9, 9]);
  });

  test('screen names normalise', () {
    expect(normalizeSn('Smarter Child'), 'smarterchild');
  });

  test('server address parsing', () {
    expect(ServerConfig.parse('aim.example.com').toString(), 'aim.example.com:5190');
    expect(ServerConfig.parse('aim.example.com:5191').port, 5191);
    expect(ServerConfig.parse('oscar://10.0.0.5:5190').host, '10.0.0.5');
    expect(ServerConfig.parse('[::1]:5190').host, '::1');
  });

  test('AIM HTML to text and back', () {
    expect(htmlToText('<HTML><BODY><FONT COLOR="#0000ff">hi &amp; bye<BR>line2</FONT></BODY></HTML>'),
        'hi & bye\nline2');
    expect(htmlToText(textToAimHtml('a < b & c\nnext')), 'a < b & c\nnext');
  });

  test('IM charset encode/decode', () {
    final (cs, b) = encodeImText('plain');
    expect(cs, 0);
    expect(decodeImText(cs, b), 'plain');
    final (cs2, b2) = encodeImText('café ☕');
    expect(cs2, 2);
    expect(decodeImText(cs2, b2), 'café ☕');
  });

  test('feedbag item round trip and order', () {
    final g = FeedbagItem('Buddies', 5, 0, FeedbagItem.classGroup, []);
    g.order = [3, 7, 9];
    final w = ByteWriter();
    g.write(w);
    final back = FeedbagItem.read(ByteReader(w.toBytes()));
    expect(back.name, 'Buddies');
    expect(back.groupId, 5);
    expect(back.order, [3, 7, 9]);
  });

  test('user info with buddy icon hash', () {
    final bart = ByteWriter()
      ..u16(1)
      ..u8(1)
      ..u8(16)
      ..bytes(Uint8List(16)..[0] = 0xab);
    final w = ByteWriter()
      ..str8('Alice')
      ..u16(0)
      ..u16(2)
      ..tlvU16(0x01, 0x0030)
      ..tlv(0x1d, bart.toBytes());
    final u = UserInfo.read(ByteReader(w.toBytes()));
    expect(u.screenName, 'Alice');
    expect(u.isAway, isTrue);
    expect(u.iconHash![0], 0xab);
  });

  test('chat room: names from cookies, full room info', () {
    expect(RoomInfo.nameFromCookie('4-0-Movie Night'), 'Movie Night');
    expect(RoomInfo.nameFromCookie('4-0-a-b'), 'a-b');
    expect(RoomInfo.nameFromCookie('weird'), 'weird');
    expect(cleanRoomName('  hi ☕   there '), 'hi there');

    final w = ByteWriter()
      ..u16(4)
      ..str8('4-0-lobby')
      ..u16(0)
      ..u8(2)
      ..u16(2)
      ..tlvU16(0x00c9, 15)
      ..tlvString(0x00d3, 'Lobby');
    final r = RoomInfo.readFull(ByteReader(w.toBytes()));
    expect(r.exchange, 4);
    expect(r.cookie, '4-0-lobby');
    expect(r.name, 'Lobby');
    expect(RoomInfo.readRef(ByteReader(r.ref)).cookie, '4-0-lobby');
  });

  test('chat room: message out and back in (ascii and unicode)', () {
    for (final text in ['hello room <3', 'coffee ☕ time']) {
      final out = encodeRoomMessage(textToAimHtml(text));
      // What the server sends back: same cookie/channel, sender + message info.
      final r = ByteReader(out);
      final head = r.bytes(10);
      final t = r.tlvs();
      final sender = ByteWriter()
        ..str8('Alice')
        ..u16(0)
        ..u16(0);
      final incoming = ByteWriter()
        ..bytes(head)
        ..tlv(0x0003, sender.toBytes())
        ..tlv(0x0005, t[0x0005]!.value);
      final m = parseRoomMessage(incoming.toBytes())!;
      expect(m.from, 'Alice');
      expect(m.text, text);
    }
  });

  test('chat room: invite round trip and decline', () {
    final cookie = Uint8List.fromList(List.generate(8, (i) => i));
    const room = RoomInfo(4, '4-0-Party', 0, 'Party');
    final rdv = Rendezvous.parse(encodeRoomInvite(cookie, room, 'come hang out'));
    expect(rdv.isDirectIm, isFalse);
    final inv = RoomInvite.fromRendezvous('bob', rdv)!;
    expect(inv.from, 'bob');
    expect(inv.room.cookie, '4-0-Party');
    expect(inv.room.name, 'Party');
    expect(inv.message, 'come hang out');
    expect(RoomInvite.fromRendezvous('bob', Rendezvous.parse(encodeRoomDecline(cookie))), isNull);
  });
}
