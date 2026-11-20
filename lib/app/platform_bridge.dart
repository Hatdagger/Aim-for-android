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
