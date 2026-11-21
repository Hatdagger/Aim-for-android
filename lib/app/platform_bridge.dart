import 'dart:io';

import 'package:flutter/services.dart';

/// Android-only helpers implemented in MainActivity.kt / AimConnectionService.kt:
/// a foreground service that keeps the connection alive while backgrounded,
/// and a detail-free "new messages" notification.
class PlatformBridge {
  static const _ch = MethodChannel('aim/platform');
  static bool get _android => Platform.isAndroid;

  static Future<void> startKeepAlive(String text) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('startService', {'text': text});
    } catch (_) {}
  }

  static Future<void> stopKeepAlive() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('stopService');
    } catch (_) {}
  }

  /// Shows "You have N new AIM messages" with no sender or preview.
  static Future<void> showUnread(int count) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('notifyUnread', {'count': count});
    } catch (_) {}
  }

  static Future<void> clearUnread() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('clearUnread');
    } catch (_) {}
  }

  /// A short "key click" you can feel. [pad] = the press came from a game
  /// controller, so rumble the controller instead of the phone.
  static void keyClick({bool pad = false}) {
    if (_android) {
      _ch.invokeMethod('keyClick', {'pad': pad}).catchError((_) {
        HapticFeedback.selectionClick();
      });
    } else if (!pad) {
      HapticFeedback.selectionClick(); // no-op on most desktops
    }
  }

  /// Opens a web link in the browser (downloads go to the browser too).
  static Future<void> openUrl(String url) async {
    try {
      if (_android) {
        await _ch.invokeMethod('openUrl', {'url': url});
      } else if (Platform.isWindows) {
        await Process.run('explorer', [url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------ in-app updates

  /// Android's installer said no (message from Android).
  static void Function(String message)? onInstallFailed;

  /// The app came back to the front (e.g. from the "allow installs" switch).
  static void Function()? onResumed;

  /// Whether Android lets AIM install its own updates yet.
  static Future<bool> canInstallUpdates() async {
    if (!_android) return true;
    try {
      return await _ch.invokeMethod<bool>('canInstallUpdates') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's one-time "Allow from this source" switch for AIM.
  static Future<void> allowInstallUpdates() async {
    if (!_android) return;
    await _ch.invokeMethod('allowInstallUpdates');
  }

  /// Hands a downloaded APK to Android's installer (it shows its own prompt).
  static Future<void> installApk(String path) async {
    await _ch.invokeMethod('installApk', {'path': path});
  }

  static Future<void> requestNotificationPermission() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  /// Opens the system prompt to exempt the app from battery optimisation so
  /// the connection survives with the screen off.
  static Future<void> requestBackgroundRunning() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }
}
