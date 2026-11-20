import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'settings.dart';

/// Plays the classic AIM sounds the user imported. The app ships no sounds of
/// its own; without an import, events are silent.
class SoundEngine {
  final AppSettings settings;
  Directory? _dir;
  bool foreground = true;

  SoundEngine(this.settings);

  Future<Directory> soundsDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}sounds');
    await d.create(recursive: true);
    return _dir = d;
  }

  Future<List<String>> available() async {
    final d = await soundsDir();
    final files = await d
        .list()
        .where((f) => f is File && f.path.toLowerCase().endsWith('.wav'))
        .map((f) => f.uri.pathSegments.last)
        .toList();
    files.sort();
    return files;
  }

  Future<void> saveSound(String name, List<int> bytes) async {
    final d = await soundsDir();
    await File('${d.path}${Platform.pathSeparator}${name.toLowerCase()}').writeAsBytes(bytes, flush: true);
  }

  Future<void> play(SoundEvent e) async {
    if (!foreground || !settings.soundsOn) return;
    final name = settings.soundFor(e);
    if (name.isEmpty) return;
    await playFile(name);
  }

  Future<void> playFile(String name) async {
    try {
      final d = await soundsDir();
      final f = File('${d.path}${Platform.pathSeparator}$name');
      if (!await f.exists()) return;
      final p = AudioPlayer();
      p.onPlayerComplete.first.then((_) => p.dispose());
      await p.play(DeviceFileSource(f.path));
    } catch (_) {
      // Sound is a nicety; never let it break messaging.
    }
  }
}
