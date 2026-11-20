import 'dart:io';

import 'package:aim_for_android/app/sounds.dart';
import 'package:aim_for_android/importer/aim_installer.dart';
import 'package:aim_for_android/ui/setup_wizard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Needs the real installer: set AIM_INSTALLER=/path/to/aim513036.exe.
/// CI downloads it from archive.org; it is never committed.
void main() {
  final path = Platform.environment['AIM_INSTALLER'];
  test('setup wizard unpacks on a background thread without errors', () async {
    final sounds = await extractSoundsInBackground(File(path!).readAsBytesSync());
    expect(sounds.length, AimInstallerImporter.soundSha1.length);
  }, skip: path == null ? 'AIM_INSTALLER not set' : false);
  test('extracts all 13 classic sounds from aim513036.exe', () {
    final bytes = File(path!).readAsBytesSync();
    final sounds = AimInstallerImporter.extractSounds(bytes);
    expect(sounds.keys.toSet(), AimInstallerImporter.soundSha1.keys.toSet());
    for (final e in sounds.entries) {
      expect(AimInstallerImporter.sha1Hex(e.value), AimInstallerImporter.soundSha1[e.key], reason: e.key);
      // Report each sound's WAV format (shows as a CI annotation).
      final b = e.value;
      String fmt = 'no fmt chunk';
      for (var i = 12; i + 8 <= b.length;) {
        final id = String.fromCharCodes(b.sublist(i, i + 4));
        final len = b[i + 4] | b[i + 5] << 8 | b[i + 6] << 16 | b[i + 7] << 24;
        if (id == 'fmt ') {
          int u16(int o) => b[i + 8 + o] | b[i + 9 + o] << 8;
          final rate = b[i + 12] | b[i + 13] << 8 | b[i + 14] << 16 | b[i + 15] << 24;
          fmt = 'tag=0x${u16(0).toRadixString(16)} ch=${u16(2)} rate=$rate bits=${u16(14)} fmtlen=$len';
          break;
        }
        i += 8 + len + (len & 1);
      }
      // every classic sound converts to plain 16-bit 22050 Hz PCM for playback
      final info = WavInfo.parse(b);
      expect(info, isNotNull, reason: e.key);
      final pcm = toPcm16(b, info!);
      expect(pcm, isNotNull, reason: e.key);
      final out = WavInfo.parse(pcm!)!;
      expect([out.format, out.bits, out.rate, out.channels], [1, 16, 22050, 1], reason: e.key);
      final secondsIn = info.dataLength / (info.bits ~/ 8 * info.channels) / info.rate;
      expect(out.dataLength / 2 / 22050, closeTo(secondsIn, 0.01), reason: e.key);
      // ignore: avoid_print
      print('::notice title=wav-format::${e.key} ${b.length} bytes ${String.fromCharCodes(b.sublist(0, 4))} $fmt');
    }
  }, skip: path == null ? 'AIM_INSTALLER not set' : false, timeout: const Timeout(Duration(minutes: 2)));

  test('rejects files that are not the installer', () {
    expect(() => AimInstallerImporter.extractSounds(File(Platform.resolvedExecutable).readAsBytesSync().sublist(0, 4096)),
        throwsFormatException);
  });
}
