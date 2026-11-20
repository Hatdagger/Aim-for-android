import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/t9_phone.dart';
import 'settings.dart';
import 't9.dart';

/// Lets a keyboard's number pad type like a phone keypad, by position.
///
/// A PC number pad has 7 8 9 on top; a phone has 1 2 3 (ABC DEF) on top. So
/// the keys are mapped by where they sit, not by what's printed on them:
///
///   PC pad        acts as phone key
///   7 8 9    →    1 2 3
///   4 5 6    →    4 5 6
///   1 2 3    →    7 8 9
///   0  .     →    0  #     (+ and * = next word, - = delete,
///                           / = T9 on/off, Enter = send)
///
/// Works in any text box, and on the on-screen phone keyboards.
/// Uses the physical key, so it works with Num Lock on or off.
class NumpadT9 {
  final AppSettings settings;
  final OskController osk;
  NumpadT9(this.settings, this.osk) {
    T9Dictionary.load().then((d) => _dict = d).ignore();
  }

  static final Map<PhysicalKeyboardKey, String> keyMap = {
    PhysicalKeyboardKey.numpad7: '1',
    PhysicalKeyboardKey.numpad8: '2',
    PhysicalKeyboardKey.numpad9: '3',
    PhysicalKeyboardKey.numpad4: '4',
    PhysicalKeyboardKey.numpad5: '5',
    PhysicalKeyboardKey.numpad6: '6',
    PhysicalKeyboardKey.numpad1: '7',
    PhysicalKeyboardKey.numpad2: '8',
    PhysicalKeyboardKey.numpad3: '9',
    PhysicalKeyboardKey.numpad0: '0',
    PhysicalKeyboardKey.numpadDecimal: '#',
    PhysicalKeyboardKey.numpadAdd: '*',
    PhysicalKeyboardKey.numpadMultiply: '*',
    PhysicalKeyboardKey.numpadSubtract: 'del',
    PhysicalKeyboardKey.numpadDivide: 'mode',
    PhysicalKeyboardKey.numpadEnter: 'send',
  };

  T9Dictionary? _dict;
  T9Engine? _engine;
  TextEditingController? _target;
  String _last = '';

  bool handle(KeyEvent e) {
    final key = keyMap[e.physicalKey];
    if (key == null || !settings.numpadT9) {
      // Another key: lock in the word being typed before it lands.
      if (e is KeyDownEvent && (_engine?.composing ?? false)) _engine!.finish();
      return false;
    }

    // The on-screen T9 phone is open: press its keys.
    final sink = osk.numpadSink;
    if (sink != null) {
      if (e is! KeyUpEvent && (e is KeyDownEvent || key == 'del')) sink(key);
      return true;
    }

    // Otherwise type into the focused text box.
    final f = _focusedField();
    if (f == null) return false;
    if (key == 'send') {
      if (e is KeyDownEvent && (_engine?.composing ?? false)) _engine!.finish();
      return false; // let Enter do what it normally does (send / next line)
    }
    if (e is KeyUpEvent) return true;
    if (e is KeyRepeatEvent && key != 'del') return true;
    typeInto(f.$1, f.$2, key);
    return true;
  }

  /// Applies one phone key ('0'-'9', '*', '#', 'del', 'mode') to [ctrl].
  void typeInto(TextEditingController ctrl, bool obscure, String key) {
    if (!identical(_target, ctrl) || ctrl.text != _last || _engine == null) {
      _target = ctrl;
      _last = ctrl.text;
      _engine = T9Engine(
        initial: ctrl.text,
        predictive: settings.t9Predictive && !obscure,
        onText: (t) {
          _last = t;
          ctrl.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
        },
      )..dict = _dict;
      if (obscure) _engine!.caseMode = T9Case.lower;
    }
    final eng = _engine!;
    switch (key) {
      case 'del':
        eng.backspace();
      case 'mode':
        if (!obscure) {
          eng.togglePredictive();
          settings.t9Predictive = eng.predictive;
        }
      case 'send':
        eng.finish();
      default:
        eng.press(key);
    }
  }

  (TextEditingController, bool)? _focusedField() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    final st = ctx.findAncestorStateOfType<EditableTextState>();
    if (st == null || st.widget.readOnly) return null;
    return (st.widget.controller, st.widget.obscureText);
  }
}
