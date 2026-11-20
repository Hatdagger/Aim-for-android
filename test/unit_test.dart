import 'dart:typed_data';

import 'package:aim_for_android/oscar/aim_html.dart';
import 'package:aim_for_android/oscar/bytes.dart';
import 'package:aim_for_android/oscar/flap.dart';
import 'package:aim_for_android/oscar/models.dart';
import 'package:aim_for_android/oscar/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
