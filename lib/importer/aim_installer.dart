import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'lzx.dart';

/// Pulls the classic sound files out of the AIM 5.1.3036 Windows installer.
///
/// The installer is a Wise package: a raw-deflate stream inside it holds a
/// Microsoft Cabinet (LZX), whose single file `307patch.mld` is AOL's own
/// package format. The sounds are stored uncompressed at the end of the .mld.
class AimInstallerImporter {
  /// SHA-1 of aim513036.exe as distributed (also on archive.org).
  static const knownInstallerSha1 = '0f6d27d02fa3eca6acbc4fc8f4d564b0d8d7ac76';
  static const archiveOrgUrl = 'https://archive.org/download/aim513036/aim513036.exe';

  // Location of the cabinet inside the known installer.
  static const _cabStreamOffset = 388237;
  static const _cabStreamLength = 2203195;

  /// Expected SHA-1 of each extracted sound, used to verify the import.
  static const soundSha1 = {
    'cashregister.wav': 'd6411cc5610006f70a758d44965c83cbb28fd3fc',
    'dooropen.wav': '23733ec60e8c1e16852337be323a1076567e850b',
    'doorslam.wav': '6ea0d9cad201143d8b39b2fede515d81477abfd3',
    'imrcv.wav': '5e9a71cddc3384b2ed816d5881a06163a7e0c089',
    'imsend.wav': '38b90c156dbb1586aac92d06c91cc542632f584a',
    'moo.wav': '44f44001638e1fb56d854fbce7b595fb4835d0d0',
    'newalert.wav': '91eea596b75daeab9c852a304041b3ba137654b1',
    'newmail.wav': 'd4539b2af307bd09f22199c2be2b143b135f33cc',
    'phone.wav': 'f035ce481a9c7954bde6d3f0e831aeab10f9d18c',
    'ring.wav': 'c16ac3b2a1cf85a0a66bc68658dac77c9f9db9f3',
    'talkbeg.wav': '20b973e597caac29fbc29b7d19bf4e885bd2879c',
    'talkend.wav': '15cfbaee8b3abd2eb4d45cd80a947920e891ebba',
    'talkstop.wav': 'a93b4af294c08fba9b655342c859584836b7e0b8',
  };

  static String sha1Hex(List<int> b) => sha1.convert(b).toString();

  /// Returns file name -> WAV bytes. Throws [FormatException] with a
  /// user-readable message if the file is not the expected installer.
  static Map<String, Uint8List> extractSounds(Uint8List installer) {
    final hash = sha1Hex(installer);
    if (hash != knownInstallerSha1) {
      throw const FormatException(
          'This file isn\'t the AIM 5.1.3036 installer this app knows how to read. '
          'You can download it from archive.org from this screen, or import individual .wav files instead.');
    }
    final deflated = Uint8List.sublistView(installer, _cabStreamOffset, _cabStreamOffset + _cabStreamLength);
    final cab = Uint8List.fromList(ZLibDecoder(raw: true).convert(deflated));
    final files = extractCab(cab);
    final mld = files['307patch.mld'];
    if (mld == null) throw const FormatException('Installer cabinet is missing 307patch.mld');
    final sounds = extractMldSounds(mld);
    for (final e in sounds.entries) {
      final want = soundSha1[e.key];
      if (want != null && sha1Hex(e.value) != want) {
        throw FormatException('${e.key} did not unpack correctly');
      }
    }
    return sounds;
  }

  /// Minimal Microsoft Cabinet reader (stored and LZX folders).
  static Map<String, Uint8List> extractCab(Uint8List cab) {
    final bd = ByteData.sublistView(cab);
    if (ascii.decode(cab.sublist(0, 4)) != 'MSCF') throw const FormatException('Not a cabinet');
    final coffFiles = bd.getUint32(16, Endian.little);
    final cFolders = bd.getUint16(26, Endian.little);
    final cFiles = bd.getUint16(28, Endian.little);
    final flags = bd.getUint16(30, Endian.little);
    var p = 36;
    var cbFolder = 0, cbData = 0;
    if (flags & 4 != 0) {
      final cbHeader = bd.getUint16(p, Endian.little);
      cbFolder = cab[p + 2];
      cbData = cab[p + 3];
      p += 4 + cbHeader;
    }
    int skipStr(int q) {
      while (cab[q] != 0) {
        q++;
      }
      return q + 1;
    }

    if (flags & 1 != 0) p = skipStr(skipStr(p));
    if (flags & 2 != 0) p = skipStr(skipStr(p));
    final folders = <(int, int, int)>[];
    for (var i = 0; i < cFolders; i++) {
      folders.add((bd.getUint32(p, Endian.little), bd.getUint16(p + 4, Endian.little), bd.getUint16(p + 6, Endian.little)));
      p += 8 + cbFolder;
    }
    final files = <(String, int, int, int)>[];
    p = coffFiles;
    for (var i = 0; i < cFiles; i++) {
      final size = bd.getUint32(p, Endian.little);
      final off = bd.getUint32(p + 4, Endian.little);
      final folder = bd.getUint16(p + 8, Endian.little);
      p += 16;
      final e = cab.indexOf(0, p);
      final name = latin1.decode(cab.sublist(p, e));
      p = e + 1;
      files.add((name, size, off, folder));
    }
    final result = <String, Uint8List>{};
    for (var fi = 0; fi < folders.length; fi++) {
      final (coff, ndata, comp) = folders[fi];
      var q = coff;
      final chunks = BytesBuilder(copy: false);
      var total = 0;
      for (var i = 0; i < ndata; i++) {
        final cb = bd.getUint16(q + 4, Endian.little);
        final cbu = bd.getUint16(q + 6, Endian.little);
        q += 8 + cbData;
        chunks.add(Uint8List.sublistView(cab, q, q + cb));
        q += cb;
        total += cbu;
      }
      final stream = chunks.toBytes();
      Uint8List out;
      switch (comp & 0xf) {
        case 0:
          out = stream;
        case 3:
          out = lzxDecompress(stream, (comp >> 8) & 0x1f, total);
        default:
          throw FormatException('Unsupported cabinet compression ${comp & 0xf}');
      }
      for (final (name, size, off, folder) in files) {
        if (folder == fi) result[name] = Uint8List.sublistView(out, off, off + size);
      }
    }
    return result;
  }

  /// The .wav files sit uncompressed, in name-table order, in the .mld.
  static Map<String, Uint8List> extractMldSounds(Uint8List mld) {
    final bd = ByteData.sublistView(mld);
    final count = bd.getUint32(0, Endian.little);
    final namesLen = bd.getUint32(11, Endian.little);
    final names = latin1
        .decode(mld.sublist(15, 15 + namesLen))
        .split('\u0000')
        .take(count)
        .where((n) => n.toLowerCase().endsWith('.wav'))
        .toList();
    final result = <String, Uint8List>{};
    var i = 0;
    var search = 15 + namesLen;
    while (i < names.length) {
      final at = _findRiffWave(mld, search);
      if (at < 0) break;
      final len = bd.getUint32(at + 4, Endian.little) + 8;
      if (at + len > mld.length) break;
      result[names[i].toLowerCase()] = Uint8List.fromList(mld.sublist(at, at + len));
      search = at + len;
      i++;
    }
    if (result.isEmpty) throw const FormatException('No sounds found in installer');
    return result;
  }

  static int _findRiffWave(Uint8List d, int from) {
    for (var i = from; i + 12 <= d.length; i++) {
      if (d[i] == 0x52 && d[i + 1] == 0x49 && d[i + 2] == 0x46 && d[i + 3] == 0x46 &&
          d[i + 8] == 0x57 && d[i + 9] == 0x41 && d[i + 10] == 0x56 && d[i + 11] == 0x45) {
        return i;
      }
    }
    return -1;
  }
}
