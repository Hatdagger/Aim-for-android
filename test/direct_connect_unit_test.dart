import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_for_android/app/history.dart';
import 'package:aim_for_android/oscar/odc.dart';
import 'package:aim_for_android/oscar/rendezvous.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n, [int seed = 7]) => Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xff));

void main() {
  final cookie = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

  test('ODC2 frame: 76-byte header, survives arriving one byte at a time', () {
    final f = OdcFrame(cookie: cookie, flags: OdcFrame.flagCookie, screenName: 'Alice');
    final b = f.encode();
    expect(b.length, OdcFrame.headerLength);
    expect(ascii.decode(b.sublist(0, 4)), 'ODC2');
    expect((b[4] << 8) | b[5], 76);

    final msg = OdcFrame(cookie: cookie, screenName: 'Alice', payload: Uint8List.fromList(ascii.encode('hi')));
    final all = [...b, ...msg.encode()];
    final p = OdcParser();
    final got = <OdcFrame>[];
    for (final x in all) {
      got.addAll(p.add(Uint8List.fromList([x])));
    }
    expect(got.length, 2);
    expect(got[0].isCookie, isTrue);
    expect(got[0].screenName, 'Alice');
    expect(got[0].cookie, cookie);
    expect(utf8.decode(got[1].payload), 'hi');
    expect(got[1].isCookie, isFalse);
  });

  test('ODC typing flags', () {
    for (final st in [0, 1, 2]) {
      final flags = OdcFrame.flagTypingEvent | (st == 2 ? OdcFrame.flagTyping : (st == 1 ? OdcFrame.flagTyped : 0));
      final f = OdcParser().add(OdcFrame(cookie: cookie, flags: flags).encode()).single;
      expect(f.isTyping, isTrue);
      expect(f.typingState, st);
    }
  });

  test('ODC parser hangs up on garbage and on huge messages', () {
    expect(() => OdcParser().add(Uint8List.fromList(ascii.encode('GET / HTTP/1.1\r\n'))), throwsFormatException);
    final big = OdcFrame(cookie: cookie, payload: _bytes(2000)).encode();
    expect(() => OdcParser(maxPayload: 1000).add(big), throwsFormatException);
  });

  test('message with pictures: text and exact bytes come back', () {
    final a = Uint8List.fromList([0xff, 0xd8, 0xff, ..._bytes(5000)]);
    final b = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, ..._bytes(300, 3)]);
    // Picture bytes that happen to contain the closing tags must not confuse it.
    final tricky = Uint8List.fromList([...ascii.encode('</DATA></BINARY><DATA ID="9" SIZE="1">'), ..._bytes(20)]);
    final (enc, payload) = encodeOdcMessage('look at <this> & that',
        images: [OdcImage(1, a, name: 'a.jpg'), OdcImage(2, b, name: 'b.png'), OdcImage(3, tricky, name: 'c.bin')]);
    final m = decodeOdcMessage(payload, enc);
    expect(m.text, 'look at <this> & that');
    expect(m.images.map((i) => i.id), [1, 2, 3]);
    expect(m.images[0].data, a);
    expect(m.images[1].data, b);
    expect(m.images[2].data, tricky);
    expect(m.images[0].name, 'a.jpg');
    expect(m.html, contains('<IMG SRC="a.jpg" ID="1"'));
  });

  test('picture with non-English text (UTF-16 text part)', () {
    final pic = Uint8List.fromList([0xff, 0xd8, 0xff, ..._bytes(64)]);
    final (enc, payload) = encodeOdcMessage('café ☕', images: [OdcImage(1, pic)]);
    expect(enc, 0x0002);
    final m = decodeOdcMessage(payload, enc);
    expect(m.text, 'café ☕');
    expect(m.images.single.data, pic);
  });

  test('reads a Pidgin/AIM-style payload', () {
    final pic = _bytes(10);
    final payload = Uint8List.fromList([
      ...ascii.encode('<HTML><BODY>hey<IMG SRC="cat.gif" ID="1" WIDTH="2" HEIGHT="3" DATASIZE="10"></BODY></HTML>'),
      ...ascii.encode('<binary><data id="1" size="10">'),
      ...pic,
      ...ascii.encode('</data></binary>'),
    ]);
    final m = decodeOdcMessage(payload, 0);
    expect(m.text, 'hey');
    expect(m.images.single.data, pic);
    expect(m.images.single.width, 2);
    expect(m.images.single.height, 3);
  });

  test('rendezvous proposal round trip, with every address to try', () {
    final data = Rendezvous.encodePropose(cookie, ip: '192.168.1.20', port: 5000, seq: 2, extra: ['203.0.113.7']);
    final r = Rendezvous.parse(data);
    expect(r.type, Rendezvous.propose);
    expect(r.isDirectIm, isTrue);
    expect(r.cookie, cookie);
    expect(r.port, 5000);
    expect(r.seq, 2);
    expect(r.addresses, ['192.168.1.20', '203.0.113.7']);
    expect(r.tlvs[0x0017]!.asU16, 5000 ^ 0xffff);

    final c = Rendezvous.parse(Rendezvous.encodeCancel(cookie));
    expect(c.type, Rendezvous.cancel);
    expect(c.cancelReason, Rendezvous.reasonDeclined);
    expect(Rendezvous.parse(Rendezvous.encodeAccept(cookie)).type, Rendezvous.accept);
  });

  test('addresses: the server-seen one is tried, loopback last, no duplicates', () {
    final base = Rendezvous.parse(Rendezvous.encodePropose(cookie, ip: '127.0.0.1', port: 1, extra: ['10.0.0.5']));
    final withServer = Rendezvous(base.type, base.cookie, base.cap, base.tlvs);
    expect(withServer.addresses, ['10.0.0.5', '127.0.0.1']);
  });

  test('picture types by their first bytes', () {
    expect(pictureExtension([0xff, 0xd8, 0xff, 0xe0]), '.jpg');
    expect(pictureExtension([0x89, 0x50, 0x4e, 0x47, 0x0d]), '.png');
    expect(pictureExtension(ascii.encode('GIF89a')), '.gif');
    expect(pictureExtension([0x4d, 0x5a, 0x90, 0x00]), '.bin');
    expect(isPicturePath('/x/1.bin'), isFalse);
  });
}
