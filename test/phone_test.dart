import 'package:aim_for_android/app/numpad_t9.dart';
import 'package:aim_for_android/app/settings.dart';
import 'package:aim_for_android/app/sounds.dart';
import 'package:aim_for_android/app/ui_sounds.dart';
import 'package:aim_for_android/oscar/aim_html.dart';
import 'package:aim_for_android/ui/full_phone_art.dart';
import 'package:aim_for_android/ui/phone_art.dart';
import 'package:aim_for_android/ui/phone_theme.dart';
import 'package:aim_for_android/ui/t9_phone.dart';
import 'package:aim_for_android/ui/update_button.dart';
import 'package:aim_for_android/ui/wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('number pad maps by position like a phone', () {
    final m = NumpadT9.keyMap;
    expect(m[PhysicalKeyboardKey.numpad7], '1'); // top-left = phone 1 (punctuation)
    expect(m[PhysicalKeyboardKey.numpad8], '2'); // ABC
    expect(m[PhysicalKeyboardKey.numpad1], '7'); // PQRS
    expect(m[PhysicalKeyboardKey.numpad3], '9'); // WXYZ
    expect(m[PhysicalKeyboardKey.numpad5], '5');
    expect(m[PhysicalKeyboardKey.numpad0], '0');
  });

  group('message colours', () {
    test('outgoing HTML carries colours and reads back', () {
      final html = textToAimHtml('hi', fg: 0xFFFF0000, bg: 0xFF000080);
      expect(html, contains('COLOR="#ff0000"'));
      expect(html, contains('BGCOLOR="#000080"'));
      expect(htmlToText(html), 'hi');
      expect(aimHtmlColors(html), (0xFFFF0000, 0xFF000080));
    });

    test('defaults (black on white) count as no colour', () {
      expect(aimHtmlColors(textToAimHtml('hi')), (null, null));
    });

    test('classic AIM HTML with named and short colours', () {
      const html = '<HTML><BODY BGCOLOR=navy><FONT FACE="Arial" COLOR="#f0f">yo</FONT></BODY></HTML>';
      expect(aimHtmlColors(html), (0xFFFF00FF, 0xFF000080));
    });
  });

  Future<void> pumpArt(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: w))));
    await tester.pump();
  }

  for (final t in kPhoneThemes) {
    for (final qwerty in [false, true]) {
      testWidgets('${t.name} ${qwerty ? 'QWERTY' : 'T9'} draws open, half open and closed', (tester) async {
        for (final open in [0.0, 0.5, 1.0]) {
          final size = PhoneArt.sizeFor(t, qwerty);
          await pumpArt(
            tester,
            SizedBox.fromSize(
              size: size,
              child: PhoneArt(
                t: t,
                qwerty: qwerty,
                open: open,
                squash: 0.95,
                keys: PhoneKeys(press: (_) {}, send: () {}, end: () {}, clear: () {}, mode: () {}),
                screen: const MiniScreen(
                  t: kTestTheme,
                  title: 'A very long screen name that will not fit',
                  mode: 'T9',
                  lines: [OskLine('them', 'hello there how are you doing today friend', false), OskLine('me', 'ok', true)],
                  text: 'typing something rather long to see that the screen copes with it',
                  footer: 'Send ▸ green key',
                ),
              ),
            ),
          );
          final ex = tester.takeException();
          expect(ex, isNull, reason: 'open=$open: ${ex is FlutterError ? ex.toStringDeep() : ex}');
        }
      });
    }
    testWidgets('${t.name} preview fits a small tile', (tester) async {
      await pumpArt(tester, SizedBox(width: 110, height: 150, child: PhonePreview(t: t, qwerty: false)));
      expect(tester.takeException(), isNull);
    });
  }

  test('each chat can have its own keyboard', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.load();
    s.phoneStyle = 'girlypop';
    s.keyboardKind = 't9';
    s.setKeyboardFor('Skater Grl', 'pocketbrick');
    s.setKeyboardFor('bob', 'wideflip', kind: 'qwerty');
    expect(s.phoneStyleFor('skatergrl'), 'pocketbrick'); // screen names ignore case and spaces
    expect(s.phoneStyleFor('bob'), 'wideflip');
    expect(s.keyboardKindFor('bob'), 'qwerty');
    expect(s.phoneStyleFor('carol'), 'girlypop'); // no choice: the default
    expect(s.phoneStyleFor(null), 'girlypop'); // sign-on boxes etc.
    s.setKeyboardFor('bob', null);
    expect(s.keyboardOverride('bob'), isNull);
    expect(s.keyboardKindFor('bob'), 't9');
  });

  test('T9 gadgets keep their keypad, letter gadgets their letters', () {
    for (final t in kPhoneThemes) {
      if (t.t9Gadget) {
        expect(t.letters(true), isFalse, reason: t.id);
        expect(t.letters(false), isFalse, reason: t.id);
      }
    }
    expect(phoneThemeById('lipstick').letters(false), isTrue);
    expect(phoneThemeById('widet9').t9Gadget, isTrue);
  });

  for (final t in kPhoneThemes) {
    for (final view in const [Size(390, 844), Size(844, 390)]) {
      testWidgets('${t.name} full screen ${view.width < view.height ? 'portrait' : 'landscape'}', (tester) async {
        tester.view.physicalSize = view;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final open in [0.0, 0.5, 1.0]) {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: FullPhoneArt(
                t: t,
                letters: t.letters(view.width > view.height),
                open: open,
                keys: PhoneKeys(press: (_) {}, send: () {}, end: () {}, clear: () {}, mode: () {}),
                onShowChat: () {},
                screen: const MiniScreen(t: kTestTheme, title: 'x', mode: 'T9', lines: [], text: 'hi', footer: 'f'),
              ),
            ),
          ));
          await tester.pump();
          final ex = tester.takeException();
          expect(ex, isNull, reason: 'open=$open: ${ex is FlutterError ? ex.toStringDeep() : ex}');
        }
      });
    }
  }

  test('phone and gadget ids are unique', () {
    final ids = kPhoneThemes.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('gadget sounds make valid, unclipped WAVs', () {
    for (final s in UiSound.values) {
      final samples = synthSamples(s);
      expect(samples, isNotEmpty, reason: s.name);
      expect(samples.every((x) => x.abs() <= 1.0), isTrue, reason: '${s.name} clips');
      final wav = WavInfo.parse(wavFromSamples(samples));
      expect(wav, isNotNull, reason: s.name);
      expect(wav!.bits, 16);
      expect(wav.dataLength, samples.length * 2);
    }
    // The handheld's boot beep is long and the key click is short.
    expect(synthSamples(UiSound.beep).length, greaterThan(synthSamples(UiSound.key).length * 10));
  });

  testWidgets('gadget keyboards type and send', (tester) async {
    for (final (id, tapText, letter, sendLabel) in const [
      ('pocketbrick', 'a', 'a', 'ED'),
      ('dashboard', 'a', 'a', 'Done'),
      ('musicplayer', 'g', 'g', 'return'),
      ('pocketmail', 'g', 'g', '⏎'),
      ('swivel', '5', '5', 'Send'),
      ('poptilt', 'g', 'g', 'Send'),
      ('compact', '5', '5', 'Send'),
      ('taco', '5', '5', 'Send'),
      ('lipstick', 'OK', 'g', 'Send'),
      ('pager', 'g', 'g', 'Send ⏎'),
      ('cordless', '5', '5', 'TALK'),
      ('watch', '5', '5', 'SEND'),
      ('rotator', '5', '5', 'Send'),
      ('jelly', '5', '5', 'Send'),
      ('eggpet', 'TYPE', 'g', 'SEND'),
      ('widet9', '5', '5', 'Send'),
    ]) {
      final t = phoneThemeById(id);
      final typed = <String>[];
      var sent = 0;
      await pumpArt(
        tester,
        SizedBox.fromSize(
          size: PhoneArt.sizeFor(t, false),
          child: PhoneArt(
            t: t,
            qwerty: false,
            keys: PhoneKeys(press: typed.add, send: () => sent++, end: () {}, clear: () {}, mode: () {}),
            screen: const SizedBox(),
          ),
        ),
      );
      await tester.tap(find.text(tapText).first);
      await tester.tap(find.text(sendLabel).first);
      expect(typed, [letter], reason: id);
      expect(sent, 1, reason: id);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('wallpapers paint', (tester) async {
    for (final w in kBuiltinWallpapers) {
      await pumpArt(tester, SizedBox(width: 300, height: 200, child: ChatWallpaper(spec: 'builtin:${w.id}')));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('update dot pings', (tester) async {
    await pumpArt(tester, const PingDot(on: true));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  });
}

const kTestTheme = PhoneTheme(
  id: 'test',
  name: 'Test',
  blurb: '',
  ink: Colors.black,
  body: Colors.blue,
  screenOn: Colors.white,
  screenOff: Colors.grey,
  screenInk: Colors.black,
  screenDim: Colors.grey,
  me: Colors.red,
  them: Colors.blue,
  keyBg: Colors.white,
  keyInk: Colors.black,
  keySub: Colors.grey,
  softBg: Colors.yellow,
  softInk: Colors.black,
  focus: Colors.red,
);
