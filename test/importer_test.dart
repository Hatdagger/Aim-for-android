import 'dart:io';

import 'package:aim_for_android/importer/aim_installer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Needs the real installer: set AIM_INSTALLER=/path/to/aim513036.exe.
/// CI downloads it from archive.org; it is never committed.
void main() {
  final path = Platform.environment['AIM_INSTALLER'];
  test('extracts all 13 classic sounds from aim513036.exe', () {
    final bytes = File(path!).readAsBytesSync();
    final sounds = AimInstallerImporter.extractSounds(bytes);
    expect(sounds.keys.toSet(), AimInstallerImporter.soundSha1.keys.toSet());
    for (final e in sounds.entries) {
      expect(AimInstallerImporter.sha1Hex(e.value), AimInstallerImporter.soundSha1[e.key], reason: e.key);
    }
  }, skip: path == null ? 'AIM_INSTALLER not set' : false, timeout: const Timeout(Duration(minutes: 2)));

  test('rejects files that are not the installer', () {
    expect(() => AimInstallerImporter.extractSounds(File(Platform.resolvedExecutable).readAsBytesSync().sublist(0, 4096)),
        throwsFormatException);
  });
}
