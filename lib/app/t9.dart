import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:shared_preferences/shared_preferences.dart';

/// Classic phone keypad.
const Map<String, String> kT9Letters = {
  '2': 'abc',
  '3': 'def',
  '4': 'ghi',
  '5': 'jkl',
  '6': 'mno',
  '7': 'pqrs',
  '8': 'tuv',
  '9': 'wxyz',
};
const String kPunct = '.,?!\'-@:;()1';

final Map<String, String> _letterToKey = {
  for (final e in kT9Letters.entries)
    for (final c in e.value.split('')) c: e.key,
};

String keysFor(String word) => word.toLowerCase().split('').map((c) => _letterToKey[c] ?? '1').join();

enum T9Case { sentence, lower, upper, numbers }

/// Dictionary: key sequence -> words, most likely first. Loaded once.
class T9Dictionary {
  static T9Dictionary? _instance;
  static Future<T9Dictionary>? _loading;

  final Map<String, List<String>> byKeys;
  final Map<String, int> learned;
  final SharedPreferences _prefs;

  T9Dictionary._(this.byKeys, this.learned, this._prefs);

  static Future<T9Dictionary> load() {
    if (_instance != null) return Future.value(_instance!);
    return _loading ??= () async {
      final raw = await rootBundle.loadString('assets/t9_words.txt');
      final map = await Isolate.run(() {
        final m = <String, List<String>>{};
        for (final w in raw.split('\n')) {
          if (w.isEmpty) continue;
          (m[keysFor(w)] ??= <String>[]).add(w);
        }
        return m;
      });
      final prefs = await SharedPreferences.getInstance();
      final learned = <String, int>{};
      for (final s in prefs.getStringList('t9learned') ?? const <String>[]) {
        final i = s.lastIndexOf(':');
        if (i > 0) learned[s.substring(0, i)] = int.tryParse(s.substring(i + 1)) ?? 1;
      }
      for (final w in learned.keys) {
        final k = keysFor(w);
        final l = map[k] ??= <String>[];
        if (!l.contains(w)) l.add(w);
      }
      return _instance = T9Dictionary._(map, learned, prefs);
    }();
  }

  /// Candidates for an exact key sequence, learned words first.
  List<String> candidates(String keys) {
    final exact = byKeys[keys];
    if (exact != null && exact.isNotEmpty) {
      final list = List<String>.of(exact);
      list.sort((a, b) {
        final la = learned[a] ?? 0, lb = learned[b] ?? 0;
        if (la != lb) return lb.compareTo(la);
        return exact.indexOf(a).compareTo(exact.indexOf(b));
      });
      return list;
    }
    // No whole word yet: show the start of the most likely longer word.
    for (final e in byKeys.entries) {
      if (e.key.length > keys.length && e.key.startsWith(keys)) {
        return [e.value.first.substring(0, keys.length)];
      }
    }
    return [keys.split('').map((k) => (kT9Letters[k] ?? '?')[0]).join()];
  }

  void learn(String word) {
    final w = word.toLowerCase();
    if (!RegExp(r'^[a-z]+$').hasMatch(w)) return;
    learned[w] = (learned[w] ?? 0) + 1;
    final l = byKeys[keysFor(w)] ??= <String>[];
    if (!l.contains(w)) l.add(w);
    final top = learned.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    _prefs.setStringList('t9learned', top.take(2000).map((e) => '${e.key}:${e.value}').toList());
  }
}

/// Typing state for one text field.
class T9Engine {
  final void Function(String text) onText;
  bool predictive;
  T9Case caseMode = T9Case.sentence;
  T9Dictionary? dict;

  /// Text before the cursor (the word being typed goes right after it).
  String _base;

  /// Text after the cursor (empty unless the cursor was moved left).
  String _after = '';
  String _keys = '';
  List<String> _cands = const [];
  int _ci = 0;

  // multi-tap state
  String? _lastKey;
  int _tapIndex = 0;
  DateTime _lastTap = DateTime(2000);
  static const tapTimeout = Duration(milliseconds: 900);

  T9Engine({required String initial, required this.onText, required this.predictive}) : _base = initial {
    if (initial.isNotEmpty) caseMode = T9Case.lower;
    if (_shouldCapitalize()) caseMode = T9Case.sentence;
  }

  String get text => _base + _composing + _after;

  /// Where the cursor is in [text].
  int get cursor => _base.length + _composing.length;
  String get composingWord => _composing;
  List<String> get candidates => _cands;
  int get candidateIndex => _ci;
  bool get composing => _keys.isNotEmpty;

  String get modeLabel => switch (caseMode) {
        T9Case.sentence => predictive ? 'T9 Abc' : 'Abc',
        T9Case.lower => predictive ? 'T9 abc' : 'abc',
        T9Case.upper => predictive ? 'T9 ABC' : 'ABC',
        T9Case.numbers => '123',
      };

  bool _shouldCapitalize() {
    final t = _base.trimRight();
    return t.isEmpty || t.endsWith('.') || t.endsWith('!') || t.endsWith('?');
  }

  String _applyCase(String w, {bool atWordStart = true}) {
    switch (caseMode) {
      case T9Case.upper:
        return w.toUpperCase();
      case T9Case.sentence:
        if (atWordStart && _shouldCapitalize() && w.isNotEmpty) return w[0].toUpperCase() + w.substring(1);
        return w;
      default:
        return w;
    }
  }

  String get _composing {
    if (_keys.isEmpty || _cands.isEmpty) return '';
    final w = _cands[_ci % _cands.length];
    final cased = _applyCase(w);
    // 'i' alone is always "I"
    return (w == 'i' && caseMode != T9Case.upper) ? 'I' : cased;
  }

  void _emit() => onText(text);

  void _commitWord({String suffix = ''}) {
    if (_keys.isNotEmpty) {
      final w = _composing;
      dict?.learn(w);
      _base += w;
      _keys = '';
      _cands = const [];
      _ci = 0;
    }
    _base += suffix;
  }

  void _endMultitap() {
    _lastKey = null;
  }

  /// A keypad press: '0'-'9', '*', '#'.
  void press(String k) {
    final now = DateTime.now();
    if (k == '#') {
      _commitWordIfMultitap();
      caseMode = T9Case.values[(caseMode.index + 1) % T9Case.values.length];
      _emit();
      return;
    }
    if (caseMode == T9Case.numbers) {
      if (k == '*') return;
      _commitWord();
      _base += k;
      _emit();
      return;
    }
    if (predictive) {
      if (kT9Letters.containsKey(k)) {
        _keys += k;
        _cands = dict?.candidates(_keys) ?? [_keys.split('').map((x) => kT9Letters[x]![0]).join()];
        _ci = 0;
      } else if (k == '*') {
        if (_cands.length > 1) _ci = (_ci + 1) % _cands.length;
      } else if (k == '0') {
        _commitWord(suffix: ' ');
      } else if (k == '1') {
        final repeat = _lastKey == '1' && now.difference(_lastTap) < tapTimeout && _base.isNotEmpty;
        if (repeat) {
          _tapIndex = (_tapIndex + 1) % kPunct.length;
          _base = _base.substring(0, _base.length - 1) + kPunct[_tapIndex];
        } else {
          _commitWord();
          _tapIndex = 0;
          _base += kPunct[0];
        }
      }
    } else {
      final letters = k == '0' ? ' 0' : (k == '1' ? kPunct : kT9Letters[k]);
      if (letters == null) {
        _endMultitap();
      } else {
        final repeat = _lastKey == k && now.difference(_lastTap) < tapTimeout && _base.isNotEmpty;
        if (repeat) {
          _tapIndex = (_tapIndex + 1) % letters.length;
          _base = _base.substring(0, _base.length - 1);
        } else {
          _tapIndex = 0;
        }
        var ch = letters[_tapIndex];
        if (caseMode == T9Case.upper || (caseMode == T9Case.sentence && _shouldCapitalize())) ch = ch.toUpperCase();
        _base += ch;
      }
    }
    _lastKey = k;
    _lastTap = now;
    _emit();
  }

  void _commitWordIfMultitap() {
    if (predictive) _commitWord();
    _endMultitap();
  }

  void space() {
    if (predictive) {
      _commitWord(suffix: ' ');
    } else {
      _base += ' ';
      _endMultitap();
    }
    _emit();
  }

  void nextCandidate() => press('*');

  void backspace() {
    if (_keys.isNotEmpty) {
      _keys = _keys.substring(0, _keys.length - 1);
      _cands = _keys.isEmpty ? const [] : (dict?.candidates(_keys) ?? const []);
      _ci = 0;
    } else if (_base.isNotEmpty) {
      final chars = _base.characters;
      _base = chars.take(chars.length - 1).toString();
    }
    _endMultitap();
    _emit();
  }

  /// Finish the word in progress (before sending or closing).
  String finish() {
    _commitWord();
    _endMultitap();
    _emit();
    return text;
  }

  /// True right after a multi-tap letter, while pressing the same key again
  /// would still change it.
  bool get letterPending =>
      !predictive && _lastKey != null && _lastKey != '#' && DateTime.now().difference(_lastTap) < tapTimeout;

  /// Accept the letter (or word) being typed without moving.
  void confirm() {
    _commitWord();
    _endMultitap();
    _emit();
  }

  /// Move the cursor one character left.
  void cursorLeft() {
    _commitWord();
    _endMultitap();
    if (_base.isNotEmpty) {
      final chars = _base.characters;
      final last = chars.last;
      _base = chars.take(chars.length - 1).toString();
      _after = last + _after;
    }
    _emit();
  }

  /// Move the cursor one character right. Right after a multi-tap letter it
  /// only accepts that letter, so the same key can type the next one at once
  /// (44 [RB] 444 = "hi").
  void cursorRight() {
    if (letterPending || _keys.isNotEmpty) {
      confirm();
      return;
    }
    _endMultitap();
    if (_after.isNotEmpty) {
      final chars = _after.characters;
      _base += chars.first;
      _after = chars.skip(1).toString();
    }
    _emit();
  }

  /// Select: lower case → CAPS → numbers → back to normal.
  void cycleCase() {
    _commitWord();
    _endMultitap();
    caseMode = switch (caseMode) {
      T9Case.sentence || T9Case.lower => T9Case.upper,
      T9Case.upper => T9Case.numbers,
      T9Case.numbers => T9Case.sentence,
    };
    _emit();
  }

  void togglePredictive() {
    _commitWord();
    predictive = !predictive;
    _endMultitap();
    _emit();
  }
}
