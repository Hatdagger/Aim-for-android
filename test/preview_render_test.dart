import 'dart:io';
import 'dart:ui' as ui;

import 'package:aim_for_android/ui/phone_art.dart';
import 'package:aim_for_android/ui/phone_theme.dart';
import 'package:aim_for_android/ui/t9_phone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Draws the phones and gadgets to PNG files, for looking at them without a
/// device. Only runs when AIM_PREVIEWS names an output folder (CI does this).
void main() {
  final out = Platform.environment['AIM_PREVIEWS'];

  setUpAll(() async {
    if (out == null) return;
    Directory(out).createSync(recursive: true);
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      var any = false;
      for (final f in files) {
        final file = File(f);
        if (!file.existsSync()) continue;
        loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        any = true;
      }
      if (any) await loader.load();
    }

    const dj = '/usr/share/fonts/truetype/dejavu';
    await load('DejaVu', ['$dj/DejaVuSans.ttf', '$dj/DejaVuSans-Bold.ttf']);
    await load('monospace', ['$dj/DejaVuSansMono.ttf', '$dj/DejaVuSansMono-Bold.ttf']);
    final root = _flutterRoot();
    if (root != null) await load('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  Widget chat(PhoneTheme t) => MiniScreen(
        t: t,
        title: 'SkaterGrl0414',
        mode: 'abc',
        lines: const [
          OskLine('SkaterGrl', 'u coming online tonight?', false),
          OskLine('me', 'ya after dinner', true),
          OskLine('SkaterGrl', 'k bring ur A game lol', false),
        ],
        text: 'oh its ON',
        footer: t.sendHint,
      );

  Widget boot(PhoneTheme t, double scroll) => Align(
        alignment: Alignment(0, -2.4 + 2.3 * scroll),
        child: Text(t.splash,
            style: TextStyle(color: t.screenInk, fontSize: 64, fontWeight: FontWeight.w900, fontFamily: t.fontFamily, letterSpacing: 4)),
      );

  final shots = <(String, String, bool, double, double, Widget Function(PhoneTheme))>[
    ('pocketbrick', 'pocketbrick', true, 1, 1, chat),
    ('pocketbrick_boot_scroll', 'pocketbrick', true, 0, 1, (t) => boot(t, 0.5)),
    ('pocketbrick_boot_landed', 'pocketbrick', true, 0, 1, (t) => boot(t, 1)),
    ('dashboard', 'dashboard', true, 1, 1, chat),
    ('dashboard_crt_line', 'dashboard', true, 0, 0.25, chat),
    ('dashboard_crt_opening', 'dashboard', true, 0, 0.6, chat),
    ('pocketmail', 'pocketmail', true, 1, 1, chat),
    ('musicplayer', 'musicplayer', true, 1, 1, chat),
    ('musicplayer_before_keyboard', 'musicplayer', true, 0, 1, chat),
    ('wideflip_closed_t9', 'wideflip', false, 1, 1, chat),
    ('wideflip_open', 'wideflip', true, 1, 1, chat),
    ('wideflip_half_open', 'wideflip', true, 0.6, 1, chat),
    ('girlypop_flip', 'girlypop', false, 1, 1, chat),
  ];

  for (final (name, id, qwerty, open, power, screen) in shots) {
    testWidgets('picture $name', (tester) async {
      final t = phoneThemeById(id);
      final size = PhoneArt.sizeFor(t, qwerty);
      tester.view.physicalSize = Size(size.width + 80, size.height + 80);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'DejaVu'),
        home: Scaffold(
          backgroundColor: const Color(0xFF5E7F96),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: const Color(0xFF5E7F96),
                padding: const EdgeInsets.all(40),
                child: SizedBox.fromSize(
                  size: size,
                  child: PhoneArt(
                    t: t,
                    qwerty: qwerty,
                    open: open,
                    power: power,
                    keys: PhoneKeys(press: (_) {}, send: () {}, end: () {}, clear: () {}, mode: () {}),
                    screen: screen(t),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await ro.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }, skip: out == null);
  }
}

String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null) return env;
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    if (Directory('${dir.path}/bin/cache/artifacts/material_fonts').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return null;
}
