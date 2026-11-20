import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'platform_bridge.dart';
import 'settings.dart';

/// Build number of this copy of the app. GitHub Actions bakes it in with
/// --dart-define=AIM_BUILD=<run number>; local builds are 0 ("unknown").
const int kAppBuild = int.fromEnvironment('AIM_BUILD');
const String kAppCommit = String.fromEnvironment('AIM_COMMIT');

const String kReleaseBase = 'https://github.com/Hatdagger/Aim-for-android/releases/download/latest';
const String kReleasePage = 'https://github.com/Hatdagger/Aim-for-android/releases/tag/latest';

/// Asks GitHub whether the "latest" release is newer than this copy.
/// Each release carries a tiny version.json with its build number.
class UpdateChecker extends ChangeNotifier {
  final AppSettings settings;
  Timer? _timer;
  int? latestBuild;
  String? latestDate;
  bool checking = false;
  String? error;
  bool _pinged = false;

  UpdateChecker(this.settings);

  bool get available => kAppBuild > 0 && (latestBuild ?? 0) > kAppBuild;

  String get assetName {
    if (Platform.isAndroid) return 'aim-android.apk';
    if (Platform.isWindows) return 'aim-windows.zip';
    return 'aim-linux.tar.gz';
  }

  String get downloadUrl => '$kReleaseBase/$assetName';

  void start() {
    check();
    _timer = Timer.periodic(const Duration(hours: 3), (_) => check());
  }

  Future<void> check() async {
    if (checking) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final r = await http
          .get(Uri.parse('$kReleaseBase/version.json?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw 'GitHub answered ${r.statusCode}';
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      latestBuild = (j['build'] as num?)?.toInt();
      latestDate = j['date'] as String?;
    } catch (e) {
      error = 'Could not check for updates: $e';
    } finally {
      checking = false;
      notifyListeners();
    }
    if (available && !_pinged) {
      _pinged = true;
      if (settings.soundsOn) unawaited(playPing());
    }
  }

  void openDownload() => PlatformBridge.openUrl(downloadUrl);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// A short two-note "ping" made on the fly (the app ships no sound files).
Future<void> playPing() async {
  try {
    const rate = 22050;
    final samples = <int>[];
    for (final (freq, ms) in const [(1318.5, 90), (1975.5, 220)]) {
      final n = rate * ms ~/ 1000;
      for (var i = 0; i < n; i++) {
        final t = i / rate;
        final env = exp(-t * 14) * min(1.0, i / 60);
        samples.add((sin(2 * pi * freq * t) * env * 9000).round());
      }
    }
    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}aim_update_ping.wav');
    await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
    final p = AudioPlayer();
    p.onPlayerComplete.first.then((_) => p.dispose());
    await p.play(DeviceFileSource(f.path));
  } catch (_) {}
}
