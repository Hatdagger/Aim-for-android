import 'package:aim_for_android/app/numpad_t9.dart';
import 'package:aim_for_android/app/sounds.dart';
import 'package:aim_for_android/app/ui_sounds.dart';
import 'package:aim_for_android/oscar/aim_html.dart';
import 'package:aim_for_android/ui/phone_art.dart';
import 'package:aim_for_android/ui/phone_theme.dart';
import 'package:aim_for_android/ui/t9_phone.dart';
import 'package:aim_for_android/ui/update_button.dart';
import 'package:aim_for_android/ui/wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    for (final (id, letter, sendLabel) in const [
      ('pocketbrick', 'a', 'ED'),
      ('dashboard', 'a', 'DONE'),
      ('musicplayer', 'g', 'return'),
      ('pocketmail', 'g', '⏎'),
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
      await tester.tap(find.text(letter).first);
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
