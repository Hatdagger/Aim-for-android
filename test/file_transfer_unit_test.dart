import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aim_for_android/oscar/bytes.dart';
import 'package:aim_for_android/oscar/file_transfer.dart';
import 'package:aim_for_android/oscar/oft.dart';
import 'package:aim_for_android/oscar/peer_link.dart';
import 'package:aim_for_android/oscar/peer_path.dart';
import 'package:aim_for_android/oscar/rendezvous.dart';
import 'package:aim_for_android/oscar/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// A network where nobody can reach anybody directly.
class _Unreachable extends PeerPath {
  _Unreachable() : super(useUpnp: false);
  @override
  Future<(String, List<String>, List<String>, PortLease?)> addresses(int port) async => ('0.0.0.0', <String>[], <String>[], null);
}

/// One end of an in-memory pipe.
class _MemLink implements PeerLink {
  final _in = StreamController<Uint8List>();
  late _MemLink other;
  bool _closed = false;
  @override
  Stream<Uint8List> get input => _in.stream;
  @override
  void add(List<int> data) {
    if (!_closed && !other._in.isClosed) other._in.add(Uint8List.fromList(data));
  }

  @override
  Future<void> flush() async {}
  @override
  Future<void> addStream(Stream<List<int>> data) async {
    await for (final c in data) {
      add(c);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> close() async => destroy();
  @override
  void destroy() {
    if (_closed) return;
    _closed = true;
    if (!_in.isClosed) _in.close();
    if (!other._in.isClosed) other._in.close();
  }

  @override
  String get kind => 'punched';
}

/// Pretend hole punching: works whenever both sides swap their texts.
class _FakePuncher implements HolePuncher {
  static final _waiting = <String, Completer<PeerLink?>>{};
  static var _n = 0;

  @override
  Future<PunchCall> call() async {
    final id = 'offer-${_n++}';
    final mine = Completer<PeerLink?>();
    _waiting[id] = mine;
    return PunchCall(id, (answer) async {
      expect(answer, 'answer-to-$id');
      return mine.future;
    }, () {});
  }

  @override
  Future<PunchAnswer> answer(String offer) async {
    final a = _MemLink(), b = _MemLink();
    a.other = b;
    b.other = a;
    _waiting.remove(offer)!.complete(a);
    return PunchAnswer('answer-to-$offer', Future.value(b), () {});
  }
}

/// Two devices whose "server" just passes handshakes between them.
class _Pair {
  late final FileTransfers alice;
  late final FileTransfers bob;
  final Directory aliceDir;
  final Directory bobDir;
  final sent = <(String, Rendezvous)>[];

  _Pair(this.aliceDir, this.bobDir, {bool blocked = false, bool punch = false}) {
    Future<SendResult> relay(String from, FileTransfers to, Uint8List data) async {
      final r = Rendezvous.parse(data);
      sent.add((from, r));
      scheduleMicrotask(() => to.onRendezvous(from, r));
      return SendResult.delivered;
    }

    alice = FileTransfers(
      sendRdv: (to, cookie, data) => relay('Alice', bob, data),
      receiveDir: () async => aliceDir.path,
      path: blocked ? _Unreachable() : PeerPath(useUpnp: false),
      puncher: punch ? _FakePuncher() : null,
      reverseTimeout: const Duration(seconds: 15),
    );
    bob = FileTransfers(
      sendRdv: (to, cookie, data) => relay('Bob', alice, data),
      receiveDir: () async => bobDir.path,
      path: blocked ? _Unreachable() : PeerPath(useUpnp: false),
      puncher: punch ? _FakePuncher() : null,
      reverseTimeout: const Duration(seconds: 15),
    );
  }

  Future<void> dispose() async {
    await alice.dispose();
    await bob.dispose();
  }
}

Future<FileXfer> _until(FileTransfers t, bool Function(FileXfer) ok,
    {Duration timeout = const Duration(seconds: 30)}) async {
  for (final x in t.xfers.values) {
    if (ok(x)) return x;
  }
  return t.events.map((e) => e.xfer).firstWhere(ok).timeout(timeout);
}

Uint8List _random(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  final cookie = Uint8List.fromList([9, 8, 7, 6, 5, 4, 3, 2]);

  test('OFT2 header: 256 bytes, round trip, UTF-8 names', () {
    final h = OftHeader(
        type: OftHeader.prompt, cookie: cookie, totalFiles: 3, filesLeft: 2, totalSize: 900, size: 300, name: 'café ☕.txt');
    final b = h.encode();
    expect(b.length, 256);
    expect(String.fromCharCodes(b.sublist(0, 4)), 'OFT2');
    final p = OftHeader.parse(b);
    expect(p.type, OftHeader.prompt);
    expect(p.cookie, cookie);
    expect(p.totalFiles, 3);
    expect(p.filesLeft, 2);
    expect(p.totalSize, 900);
    expect(p.size, 300);
    expect(p.name, 'café ☕.txt');
  });

  test('OFT2 header: files over 4 GB keep their real size; long names fit', () {
    const big = 6 * 1024 * 1024 * 1024 + 123;
    final name = 'v' * 150;
    final b = OftHeader(type: OftHeader.prompt, cookie: cookie, totalSize: big + 5, size: big, name: name).encode();
    expect(b.length, greaterThan(256));
    final p = OftHeader.parse(b);
    expect(p.size, big);
    expect(p.totalSize, big + 5);
    expect(p.name, name);
  });

  test('not a file transfer: hangs up', () {
    expect(() => OftHeader.lengthOf(Uint8List.fromList('GET / '.codeUnits)), throwsFormatException);
  });

  test('Send File invite: files, size and IPv6 addresses survive the trip', () {
    final data = Rendezvous.encodePropose(cookie,
        ip: '192.168.1.20',
        port: 5190,
        extra: ['203.0.113.7'],
        ipv6: ['2001:db8::1', 'fe80::1'],
        cap: capSendFile,
        moreTlvs: const OftOffer(4, 5 * 1024 * 1024 * 1024, 'holiday.mp4').toTlvs());
    final r = Rendezvous.parse(data);
    expect(r.isSendFile, isTrue);
    expect(r.isDirectIm, isFalse);
    expect(r.port, 5190);
    expect(r.addresses, containsAll(['192.168.1.20', '203.0.113.7']));
    expect(r.addresses6, ['2001:db8::1', 'fe80::1']);
    final o = OftOffer.fromTlvs(r.tlvs)!;
    expect(o.count, 4);
    expect(o.totalSize, 5 * 1024 * 1024 * 1024);
    expect(o.name, 'holiday.mp4');
  });

  test('address order: home network, then IPv6, then public', () {
    expect(PeerPath.order(['203.0.113.7', '192.168.1.5', '127.0.0.1'], ['2001:db8::2']),
        ['192.168.1.5', '2001:db8::2', '203.0.113.7', '127.0.0.1']);
  });

  test('safe file names', () {
    expect(safeFileName('../../etc/passwd'), 'passwd');
    expect(safeFileName(r'C:\Windows\evil.exe'), 'evil.exe');
    expect(safeFileName('.hidden'), 'hidden');
    expect(safeFileName('a<b>:c?.txt'), 'a_b__c_.txt');
    expect(safeFileName(''), 'file');
  });

  group('device to device', () {
    late Directory root;
    late _Pair pair;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('aim_xfer');
      pair = _Pair(await Directory('${root.path}/alice').create(), await Directory('${root.path}/bob').create());
    });

    tearDown(() async {
      await pair.dispose();
      await root.delete(recursive: true);
    });

    Future<List<(String, String)>> files(List<(String, Uint8List)> list) async {
      final out = <(String, String)>[];
      for (final (name, data) in list) {
        final f = File('${root.path}/out_$name');
        await f.writeAsBytes(data);
        out.add((f.path, name));
      }
      return out;
    }

    test('several files arrive byte for byte; the server only saw the handshake', () async {
      final big = _random(6 * 1024 * 1024 + 17, 1);
      final small = _random(1000, 2);
      final toSend = await files([('movie.bin', big), ('empty.txt', Uint8List(0)), ('note.txt', small)]);
      final offered = _until(pair.bob, (x) => x.state == XferState.offered);
      final out = await pair.alice.offer('Bob', toSend);
      final inc = await offered;
      expect(inc.count, 3);
      expect(inc.totalSize, big.length + small.length);
      expect(inc.firstName, 'movie.bin');

      final aliceDone = _until(pair.alice, (x) => x.id == out.id && !x.isActive);
      final bobDone = _until(pair.bob, (x) => x.id == inc.id && !x.isActive);
      await pair.bob.accept(inc.id);
      expect((await aliceDone).state, XferState.done);
      expect((await bobDone).state, XferState.done);

      expect(inc.files.map((f) => f.name), ['movie.bin', 'empty.txt', 'note.txt']);
      expect(await File(inc.files[0].path!).readAsBytes(), big);
      expect(await File(inc.files[1].path!).length(), 0);
      expect(await File(inc.files[2].path!).readAsBytes(), small);
      expect(out.moved, big.length + small.length);
      // No half-written files left behind.
      expect(pair.bobDir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
      // Only small handshake messages went through the "server".
      expect(pair.sent.every((s) => s.$2.isSendFile), isTrue);
    });

    test('a file with the same name is not overwritten', () async {
      await File('${pair.bobDir.path}/photo.jpg').writeAsString('old');
      final toSend = await files([('photo.jpg', _random(5000, 3))]);
      final offered = _until(pair.bob, (x) => x.state == XferState.offered);
      await pair.alice.offer('Bob', toSend);
      final inc = await offered;
      final done = _until(pair.bob, (x) => x.id == inc.id && !x.isActive);
      await pair.bob.accept(inc.id);
      expect((await done).state, XferState.done);
      expect(await File('${pair.bobDir.path}/photo.jpg').readAsString(), 'old');
      expect(inc.files.single.path, endsWith('photo (2).jpg'));
    });

    test('a stranger connecting to the port gets nothing and does not spoil it', () async {
      final toSend = await files([('secret.txt', _random(20000, 4))]);
      final offered = _until(pair.bob, (x) => x.state == XferState.offered);
      final out = await pair.alice.offer('Bob', toSend);
      final inc = await offered;
      final port = pair.sent.first.$2.port!;

      final stranger = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final got = <int>[];
      final sub = stranger.listen(got.addAll, onError: (_) {});
      stranger.add(OftHeader(type: OftHeader.ack, cookie: Uint8List(8)).encode());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(got, isEmpty, reason: 'nothing is sent before the buddy proves the cookie');
      expect(out.isActive, isTrue);
      await sub.cancel();
      stranger.destroy();

      final done = _until(pair.alice, (x) => x.id == out.id && !x.isActive);
      await pair.bob.accept(inc.id);
      expect((await done).state, XferState.done);
    });

    test('decline and withdraw', () async {
      final toSend = await files([('a.txt', _random(10, 5))]);
      var offered = _until(pair.bob, (x) => x.state == XferState.offered);
      final out = await pair.alice.offer('Bob', toSend);
      final inc = await offered;
      final declined = _until(pair.alice, (x) => x.id == out.id && !x.isActive);
      pair.bob.decline(inc.id);
      expect((await declined).state, XferState.declined);

      offered = _until(pair.bob, (x) => x.state == XferState.offered && x.id != inc.id);
      final out2 = await pair.alice.offer('Bob', toSend);
      final inc2 = await offered;
      final gone = _until(pair.bob, (x) => x.id == inc2.id && !x.isActive);
      pair.alice.cancel(out2.id);
      expect((await gone).state, XferState.cancelled);
    });

    test('stopping mid-way leaves no half file', () async {
      // A 1 GB file (sparse, so it's quick to make) takes long enough to stop half way.
      final hugePath = '${root.path}/huge.bin';
      final raf = await File(hugePath).open(mode: FileMode.write);
      await raf.truncate(1024 * 1024 * 1024);
      await raf.close();
      final toSend = [(hugePath, 'huge.bin')];
      final offered = _until(pair.bob, (x) => x.state == XferState.offered);
      final out = await pair.alice.offer('Bob', toSend);
      final inc = await offered;
      final moving = _until(pair.bob, (x) => x.id == inc.id && x.moved > 0);
      final over = _until(pair.alice, (x) => x.id == out.id && !x.isActive);
      final bobOver = _until(pair.bob, (x) => x.id == inc.id && !x.isActive);
      unawaited(pair.bob.accept(inc.id));
      await moving;
      pair.bob.cancel(inc.id);
      expect((await bobOver).state, XferState.cancelled);
      expect((await over).state, XferState.failed);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(pair.bobDir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
      expect(hex(out.cookie), out.id);
    });
  });

  test('no direct path: hole punching takes over and the files still arrive', () async {
    final root = await Directory.systemTemp.createTemp('aim_punch');
    final pair = _Pair(await Directory('${root.path}/a').create(), await Directory('${root.path}/b').create(),
        blocked: true, punch: true);
    final data = _random(2 * 1024 * 1024 + 3, 9);
    final f = File('${root.path}/song.mp3')..writeAsBytesSync(data);
    final offered = _until(pair.bob, (x) => x.state == XferState.offered);
    final out = await pair.alice.offer('Bob', [(f.path, 'song.mp3')]);
    final inc = await offered;
    final aDone = _until(pair.alice, (x) => x.id == out.id && !x.isActive);
    final bDone = _until(pair.bob, (x) => x.id == inc.id && !x.isActive);
    await pair.bob.accept(inc.id);
    expect((await aDone).state, XferState.done, reason: out.failReason);
    expect((await bDone).state, XferState.done, reason: inc.failReason);
    expect(out.via, 'punched');
    expect(await File(inc.files.single.path!).readAsBytes(), data);
    // The offer and answer went through the "server" as small pieces.
    expect(pair.sent.where((s) => s.$2.tlvs[tagSignal] != null).length, greaterThanOrEqualTo(2));
    await pair.dispose();
    await root.delete(recursive: true);
  });

  test('no direct path and no hole punching: it just fails', () async {
    final root = await Directory.systemTemp.createTemp('aim_nopunch');
    final pair = _Pair(await Directory('${root.path}/a').create(), await Directory('${root.path}/b').create(),
        blocked: true);
    final f = File('${root.path}/x.txt')..writeAsStringSync('hi');
    final offered = _until(pair.bob, (x) => x.state == XferState.offered);
    final out = await pair.alice.offer('Bob', [(f.path, 'x.txt')]);
    final inc = await offered;
    final aDone = _until(pair.alice, (x) => x.id == out.id && !x.isActive);
    await pair.bob.accept(inc.id);
    expect((await aDone).state, XferState.failed);
    await pair.dispose();
    await root.delete(recursive: true);
  });
}
