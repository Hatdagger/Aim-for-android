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

enum UpdateStep { idle, needsPermission, downloading, installing, failed }

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

  // ------------------------------------------------------------ install inside the app

  UpdateStep step = UpdateStep.idle;

  /// 0..1 while downloading.
  double progress = 0;

  /// What went wrong, in plain words.
  String? problem;
  File? _apk;

  bool get busy => step == UpdateStep.downloading || step == UpdateStep.installing;

  void _to(UpdateStep s, {String? why}) {
    step = s;
    problem = why;
    notifyListeners();
  }

  /// Downloads the update and installs it without leaving the app:
  /// Android shows its own "Update?" box; Windows/Linux close, swap files and
  /// reopen.
  Future<void> installUpdate() async {
    if (busy) return;
    PlatformBridge.onInstallFailed = (m) => _to(UpdateStep.failed, why: 'Android didn\'t install it ($m).');
    try {
      if (Platform.isAndroid && !await PlatformBridge.canInstallUpdates()) {
        // One-time Android switch. When the user comes back, carry on.
        _to(UpdateStep.needsPermission);
        PlatformBridge.onResumed = () async {
          if (step != UpdateStep.needsPermission) return;
          if (await PlatformBridge.canInstallUpdates()) {
            PlatformBridge.onResumed = null;
            step = UpdateStep.idle;
            unawaited(installUpdate());
          }
        };
        await PlatformBridge.allowInstallUpdates();
        return;
      }
      if (!Platform.isAndroid && !_installDirWritable()) {
        _to(UpdateStep.failed,
            why: 'AIM can\'t replace its own files in ${_installDir.path}. Use "Download in browser" instead.');
        return;
      }
      final file = _apk != null && await _apk!.exists() ? _apk! : await _download();
      _to(UpdateStep.installing);
      if (Platform.isAndroid) {
        _apk = file;
        await PlatformBridge.installApk(file.path);
        // Android's box is up now; if it's dismissed, the button works again.
        Timer(const Duration(seconds: 4), () {
          if (step == UpdateStep.installing) _to(UpdateStep.idle);
        });
      } else if (Platform.isWindows) {
        await _swapWindows(file);
      } else {
        await _swapLinux(file);
      }
    } catch (e) {
      _to(UpdateStep.failed, why: 'The update didn\'t finish: $e');
    }
  }

  Future<File> _download() async {
    progress = 0;
    _to(UpdateStep.downloading);
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}${Platform.pathSeparator}aim-update-${latestBuild ?? 0}-$assetName');
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(downloadUrl))).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) throw 'GitHub answered ${resp.statusCode}';
      final total = resp.contentLength ?? 0;
      final sink = out.openWrite();
      var got = 0;
      var shown = 0.0;
      try {
        await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            progress = got / total;
            if (progress - shown >= 0.01) {
              shown = progress;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (got < 1024 || (total > 0 && got != total)) throw 'the download was cut short';
      progress = 1;
      return out;
    } finally {
      client.close();
    }
  }

  Directory get _installDir => File(Platform.resolvedExecutable).parent;

  bool _installDirWritable() {
    try {
      final probe = File('${_installDir.path}${Platform.pathSeparator}.aim-update-check');
      probe.writeAsStringSync('ok');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Linux / Steam Deck: unpack next to us, then a tiny script waits for AIM
  /// to close, copies the new files over and starts AIM again.
  Future<void> _swapLinux(File archive) async {
    final tmp = await Directory.systemTemp.createTemp('aim-update');
    final r = await Process.run('tar', ['xzf', archive.path, '-C', tmp.path]);
    if (r.exitCode != 0) throw 'could not unpack it (${r.stderr})';
    final src = Directory('${tmp.path}/bundle');
    if (!await src.exists()) throw 'the download looks wrong';
    final exe = Platform.resolvedExecutable;
    final script = File('${tmp.path}/update.sh');
    String q(String v) => "'${v.replaceAll("'", "'\\''")}'";
    await script.writeAsString('#!/bin/sh\n'
        'while kill -0 $pid 2>/dev/null; do sleep 0.3; done\n'
        'cp -a ${q('${src.path}/.')} ${q(_installDir.path)}/ || exit 1\n'
        'cd ${q(_installDir.path)} && nohup ${q(exe)} >/dev/null 2>&1 &\n'
        'sleep 2; rm -rf ${q(tmp.path)}\n');
    await Process.start('sh', [script.path], mode: ProcessStartMode.detached);
    exit(0);
  }

  /// Windows: unzip, then a tiny script waits for AIM to close, copies the
  /// new files over and starts AIM again.
  Future<void> _swapWindows(File zip) async {
    final tmp = await Directory.systemTemp.createTemp('aim-update');
    final src = '${tmp.path}\\new';
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Expand-Archive -LiteralPath '${zip.path.replaceAll("'", "''")}' -DestinationPath '${src.replaceAll("'", "''")}' -Force",
    ]);
    if (r.exitCode != 0) throw 'could not unpack it (${r.stderr})';
    final exe = Platform.resolvedExecutable;
    final dst = _installDir.path;
    final script = File('${tmp.path}\\update.cmd');
    await script.writeAsString('@echo off\r\n'
        ':wait\r\n'
        'tasklist /FI "PID eq $pid" 2>NUL | find " $pid " >NUL && (timeout /t 1 /nobreak >NUL & goto wait)\r\n'
        'robocopy "$src" "$dst" /E /NFL /NDL /NJH /NJS /NP >NUL\r\n'
        'start "" "$exe"\r\n');
    await Process.start('cmd', ['/c', script.path], mode: ProcessStartMode.detached);
    exit(0);
  }

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
