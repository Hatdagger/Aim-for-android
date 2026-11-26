import 'dart:math';

import 'package:aim_for_android/app/home_pin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PIN must be 4 to 8 numbers', () {
    expect(HomePin.valid('1234'), isTrue);
    expect(HomePin.valid('12345678'), isTrue);
    expect(HomePin.valid('123'), isFalse);
    expect(HomePin.valid('123456789'), isFalse);
    expect(HomePin.valid('12a4'), isFalse);
    expect(HomePin.valid(''), isFalse);
  });

  test('stored PIN matches only the right numbers and is not stored plainly', () {
    final stored = HomePin.hash('2468', random: Random(1));
    expect(stored.contains('2468'), isFalse);
    expect(HomePin.matches('2468', stored), isTrue);
    expect(HomePin.matches('2469', stored), isFalse);
    expect(HomePin.matches('2468', ''), isFalse);
    // Same PIN, different salt: different stored text.
    expect(HomePin.hash('2468', random: Random(2)), isNot(stored));
  });

  test('three wrong PINs in a row mean a 30 second wait', () {
    var t = DateTime(2026, 1, 1, 12);
    final lock = PinLock(now: () => t);
    lock.wrong();
    lock.wrong();
    expect(lock.waitLeft, Duration.zero);
    lock.wrong();
    expect(lock.waitLeft, HomePin.wait);
    t = t.add(const Duration(seconds: 31));
    expect(lock.waitLeft, Duration.zero);
    lock.wrong();
    lock.right();
    lock.wrong();
    lock.wrong();
    expect(lock.waitLeft, Duration.zero);
  });
}
