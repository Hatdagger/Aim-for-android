import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:aim_for_android/oscar/direct_connect.dart';
import 'package:aim_for_android/ui/direct_connect_ui.dart';
import 'package:aim_for_android/ui/phone_art.dart';
import 'package:aim_for_android/ui/retro.dart';
import 'package:aim_for_android/ui/phone_theme.dart';
import 'package:aim_for_android/ui/t9_phone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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

  testWidgets('picture direct_connect', (tester) async {
    tester.view.physicalSize = const Size(720, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // A stand-in photo: a sunset-ish gradient with a sun.
    final photo = img.Image(width: 320, height: 220);
    for (var y = 0; y < 220; y++) {
      for (var x = 0; x < 320; x++) {
        final dx = x - 220, dy = y - 120;
        final sun = dx * dx + dy * dy < 900;
        photo.setPixelRgb(x, y, sun ? 255 : 255 - y ~/ 2, sun ? 230 : 120 + y ~/ 4, sun ? 120 : 60 + y ~/ 2);
      }
    }
    final pic = MemoryImage(Uint8List.fromList(img.encodePng(photo)));
    Widget bubble(String who, String text, bool mine, {bool picture = false}) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
            decoration: bevel(color: Color(mine ? 0xFFD6E4FF : 0xFFF4F4F4), deep: false),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('$who  9:41 PM',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: mine ? Retro.myName : Retro.theirName)),
              if (text.isNotEmpty) Text(text, style: const TextStyle(fontSize: 15)),
              if (picture) ChatPicture(image: pic),
            ]),
          ),
        );
    Widget note(String t) => Center(
        child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            color: const Color(0xCCFFFFFF),
            child: Text(t, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF404040)))));
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'DejaVu'),
      home: Scaffold(
        backgroundColor: Retro.desktop,
        body: RepaintBoundary(
          key: key,
          child: Container(
            color: Retro.desktop,
            padding: const EdgeInsets.all(16),
            child: RetroWindow(
              title: 'SkaterGrl0414 - Instant Message',
              padding: const EdgeInsets.all(4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Invite from a buddy:', style: TextStyle(fontSize: 11)),
                DirectBar(state: DirectState.invited, name: 'SkaterGrl0414', onAccept: () {}, onDecline: () {}),
                const SizedBox(height: 6),
                const Text('After you ask:', style: TextStyle(fontSize: 11)),
                DirectBar(state: DirectState.inviting, name: 'SkaterGrl0414', onCancel: () {}),
                const SizedBox(height: 6),
                const Text('A picture coming in:', style: TextStyle(fontSize: 11)),
                DirectBar(state: DirectState.connected, name: 'SkaterGrl0414', progress: (310000, 540000), onPicture: () {}, onClose: () {}),
                const SizedBox(height: 6),
                const Text('Connected:', style: TextStyle(fontSize: 11)),
                DirectBar(state: DirectState.connected, name: 'SkaterGrl0414', onPicture: () {}, onClose: () {}),
                const SizedBox(height: 4),
                Expanded(
                  child: Sunken(
                    padding: const EdgeInsets.all(6),
                    child: Column(children: [
                      note('Direct Connect with SkaterGrl0414 is open. Pictures go straight between you.'),
                      bubble('SkaterGrl0414', 'look at the sunset from the skatepark!!', false, picture: true),
                      bubble('me', 'omg thats so pretty', true),
                      note('Direct Connect failed.'),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ));
    await tester.runAsync(() => precacheImage(pic, key.currentContext!));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final im = await ro.toImage(pixelRatio: 1);
      final png = await im.toByteData(format: ui.ImageByteFormat.png);
      File('$out/direct_connect.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }, skip: out == null);

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
