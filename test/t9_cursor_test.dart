import 'package:aim_for_android/app/t9.dart';
import 'package:flutter_test/flutter_test.dart';

T9Engine _multitap() {
  final e = T9Engine(initial: '', onText: (_) {}, predictive: false);
  e.caseMode = T9Case.lower;
  return e;
}

void main() {
  test('RB accepts a letter so the same key types the next one', () {
    final e = _multitap();
    e.press('4');
    e.press('4'); // h
    e.cursorRight();
    e.press('4');
    e.press('4');
    e.press('4'); // i
    expect(e.text, 'hi');
    expect(e.cursor, 2);
  });

  test('LB / RB move the cursor; typing and delete happen there', () {
    final e = _multitap();
    for (final k in ['4', '4', '6', '6', '6']) {
      e.press(k); // "ho"
    }
    e.cursorRight(); // accepts "o"
    e.cursorLeft();
    expect(e.cursor, 1);
    e.press('2'); // a
    expect(e.text, 'hao');
    e.backspace();
    expect(e.text, 'ho');
    expect(e.cursor, 1);
    e.cursorRight();
    expect(e.cursor, 2);
    e.cursorRight(); // already at the end
    expect(e.cursor, 2);
  });

  test('Select cycles CAPS, numbers, back to normal', () {
    final e = _multitap();
    e.cycleCase();
    expect(e.caseMode, T9Case.upper);
    e.cycleCase();
    expect(e.caseMode, T9Case.numbers);
    e.cycleCase();
    expect(e.caseMode, T9Case.sentence);
  });
}
