import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The PIN that guards leaving home screen mode. Stored salted and hashed,
/// never as the numbers themselves. Pure Dart so it can be unit tested.
class HomePin {
  HomePin._();

  static const minLength = 4;
  static const maxLength = 8;

  /// Wrong tries allowed before a wait.
  static const freeTries = 3;
  static const wait = Duration(seconds: 30);

  /// 4 to 8 digits, nothing else.
  static bool valid(String pin) => RegExp('^[0-9]{$minLength,$maxLength}\$').hasMatch(pin);

  /// 'salt:hash' for storing.
  static String hash(String pin, {Random? random}) {
    final r = random ?? Random.secure();
    final salt = base64Url.encode(List<int>.generate(12, (_) => r.nextInt(256)));
    return '$salt:${_digest(salt, pin)}';
  }

  static bool matches(String pin, String stored) {
    final i = stored.indexOf(':');
    if (i <= 0) return false;
    final salt = stored.substring(0, i);
    final want = stored.substring(i + 1);
    final got = _digest(salt, pin);
    // Compare every character so timing doesn't hint at how close a guess was.
    if (got.length != want.length) return false;
    var diff = 0;
    for (var k = 0; k < got.length; k++) {
      diff |= got.codeUnitAt(k) ^ want.codeUnitAt(k);
    }
    return diff == 0;
  }

  static String _digest(String salt, String pin) => sha256.convert(utf8.encode('aim-home|$salt|$pin')).toString();
}

/// Counts wrong PINs; after [HomePin.freeTries] in a row, makes you wait.
class PinLock {
  final DateTime Function() now;
  PinLock({DateTime Function()? now}) : now = now ?? DateTime.now;

  int _wrong = 0;
  DateTime? _until;

  /// How long until another try is allowed (zero = go ahead).
  Duration get waitLeft {
    final u = _until;
    if (u == null) return Duration.zero;
    final d = u.difference(now());
    return d.isNegative ? Duration.zero : d;
  }

  void wrong() {
    _wrong++;
    if (_wrong >= HomePin.freeTries) {
      _until = now().add(HomePin.wait);
      _wrong = 0;
    }
  }

  void right() {
    _wrong = 0;
    _until = null;
  }
}
