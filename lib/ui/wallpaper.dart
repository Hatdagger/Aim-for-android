import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'retro.dart';

/// Chat wallpapers. They are only shown on this device; buddies never see them.
/// A wallpaper is stored as '' (none), 'builtin:<id>' or 'file:<path>'.
class BuiltinWallpaper {
  final String id;
  final String name;
  final List<Color> colors;
  const BuiltinWallpaper(this.id, this.name, this.colors);
}

const kBuiltinWallpapers = [
  BuiltinWallpaper('clouds', 'Clouds', [Color(0xFF8EC9FF), Color(0xFFFFFFFF)]),
  BuiltinWallpaper('hearts', 'Hearts', [Color(0xFFFFD6EA), Color(0xFFFF7FBF)]),
  BuiltinWallpaper('stars', 'Night Stars', [Color(0xFF14123A), Color(0xFFFFE680)]),
  BuiltinWallpaper('checker', 'Checkers', [Color(0xFFE8F0E0), Color(0xFFC8DCB8)]),
  BuiltinWallpaper('bubbles', 'Bubbles', [Color(0xFFDDF7F7), Color(0xFF7ED8E0)]),
  BuiltinWallpaper('sunset', 'Sunset', [Color(0xFFFFB36B), Color(0xFFB45CD6)]),
  BuiltinWallpaper('leopard', 'Leopard', [Color(0xFFE9B864), Color(0xFF5A3415)]),
];

/// Fills its area with the wallpaper [spec] (nothing for '').
class ChatWallpaper extends StatelessWidget {
  final String spec;
  const ChatWallpaper({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    if (spec.startsWith('file:')) {
      final f = File(spec.substring(5));
      return Image.file(f, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.expand());
    }
    if (spec.startsWith('builtin:')) {
      final id = spec.substring(8);
      final w = kBuiltinWallpapers.where((b) => b.id == id).firstOrNull;
      if (w == null) return const SizedBox.expand();
      return CustomPaint(painter: _WallPainter(w), child: const SizedBox.expand());
    }
    return const SizedBox.expand();
  }
}

class _WallPainter extends CustomPainter {
  final BuiltinWallpaper w;
  _WallPainter(this.w);

  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    final a = w.colors[0], b = w.colors[1];
    final rnd = Random(w.id.hashCode);
    switch (w.id) {
      case 'clouds':
        c.drawRect(r, Paint()..shader = LinearGradient(colors: [a, Color.lerp(a, b, 0.6)!], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r));
        final p = Paint()..color = b.withValues(alpha: 0.9);
        for (var y = 30.0; y < s.height + 60; y += 110) {
          for (var x = (y ~/ 110).isOdd ? -40.0 : 30.0; x < s.width + 80; x += 170) {
            for (final (dx, dy, rad) in const [(0.0, 0.0, 22.0), (24.0, -10.0, 26.0), (50.0, 0.0, 20.0), (26.0, 8.0, 22.0)]) {
              c.drawCircle(Offset(x + dx, y + dy), rad, p);
            }
          }
        }
      case 'hearts':
        c.drawRect(r, Paint()..color = a);
        final p = Paint()..color = b.withValues(alpha: 0.45);
        for (var y = 10.0; y < s.height + 40; y += 56) {
          for (var x = (y ~/ 56).isOdd ? 6.0 : 34.0; x < s.width + 40; x += 56) {
            _heart(c, Offset(x, y), 18, p);
          }
        }
      case 'stars':
        c.drawRect(r, Paint()..shader = LinearGradient(colors: [a, const Color(0xFF3A2A6E)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r));
        for (var i = 0; i < (s.width * s.height / 2200).clamp(30, 500); i++) {
          final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
          c.drawCircle(o, rnd.nextDouble() * 1.8 + 0.4, Paint()..color = b.withValues(alpha: 0.4 + rnd.nextDouble() * 0.6));
        }
      case 'checker':
        c.drawRect(r, Paint()..color = a);
        final p = Paint()..color = b;
        const sq = 28.0;
        for (var y = 0; y * sq < s.height; y++) {
          for (var x = 0; x * sq < s.width; x++) {
            if ((x + y).isEven) c.drawRect(Rect.fromLTWH(x * sq, y * sq, sq, sq), p);
          }
        }
      case 'bubbles':
        c.drawRect(r, Paint()..color = a);
        for (var i = 0; i < (s.width * s.height / 9000).clamp(12, 160); i++) {
          final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
          final rad = rnd.nextDouble() * 22 + 6;
          c.drawCircle(o, rad, Paint()..color = b.withValues(alpha: 0.25));
          c.drawCircle(o, rad, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: 0.8));
        }
      case 'sunset':
        c.drawRect(r, Paint()..shader = LinearGradient(colors: [a, const Color(0xFFFF6F91), b], begin: Alignment.bottomCenter, end: Alignment.topCenter).createShader(r));
        c.drawCircle(Offset(s.width * 0.75, s.height * 0.8), s.shortestSide * 0.22, Paint()..color = const Color(0x66FFF3A0));
      case 'leopard':
        c.drawRect(r, Paint()..color = a);
        for (var i = 0; i < (s.width * s.height / 2600).clamp(20, 600); i++) {
          final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
          final rad = rnd.nextDouble() * 6 + 5;
          c.drawOval(Rect.fromCenter(center: o, width: rad * 2.2, height: rad * 1.7), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2
            ..color = b);
          c.drawOval(Rect.fromCenter(center: o, width: rad * 1.2, height: rad * 0.9), Paint()..color = const Color(0xFFB8742A));
        }
    }
  }

  void _heart(Canvas c, Offset o, double size, Paint p) {
    final path = Path()
      ..moveTo(o.dx, o.dy + size * 0.3)
      ..cubicTo(o.dx, o.dy, o.dx - size * 0.5, o.dy, o.dx - size * 0.5, o.dy + size * 0.3)
      ..cubicTo(o.dx - size * 0.5, o.dy + size * 0.6, o.dx, o.dy + size * 0.8, o.dx, o.dy + size)
      ..cubicTo(o.dx, o.dy + size * 0.8, o.dx + size * 0.5, o.dy + size * 0.6, o.dx + size * 0.5, o.dy + size * 0.3)
      ..cubicTo(o.dx + size * 0.5, o.dy, o.dx, o.dy, o.dx, o.dy + size * 0.3);
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_WallPainter old) => old.w.id != w.id;
}

/// Asks which wallpaper to use. Returns the new spec, '' for none,
/// '*' for "use my default", or null if cancelled.
Future<String?> pickWallpaper(BuildContext context, {required String current, bool allowDefault = false}) {
  return showRetroDialog<String>(context, title: 'Chat Wallpaper', builder: (ctx) {
    Widget tile(String spec, String name) {
      final selected = spec == current;
      return SizedBox(
        width: 92,
        child: RetroListTile(
          onTap: () => Navigator.pop(ctx, spec),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: selected ? Retro.navy : Retro.shadow, width: selected ? 3 : 1),
              ),
              child: ClipRect(child: ChatWallpaper(spec: spec)),
            ),
            const SizedBox(height: 2),
            Text(name, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          ]),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Only you see your wallpaper. Your buddies never do.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: [
          tile('', 'None'),
          for (final w in kBuiltinWallpapers) tile('builtin:${w.id}', w.name),
          if (current.startsWith('file:')) tile(current, 'Your picture'),
        ]),
        const SizedBox(height: 8),
        RetroButton(
          onPressed: () async {
            final spec = await _pickPicture();
            if (spec != null && ctx.mounted) Navigator.pop(ctx, spec);
          },
          child: const Text('Use a picture from this device…'),
        ),
        if (allowDefault) ...[
          const SizedBox(height: 6),
          RetroButton(onPressed: () => Navigator.pop(ctx, '*'), child: const Text('Use my default wallpaper')),
        ],
        const SizedBox(height: 6),
        RetroButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ]),
    );
  });
}

Future<String?> _pickPicture() async {
  try {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400);
    if (file == null) return null;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}wallpapers');
    await dir.create(recursive: true);
    final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
    final out = File('${dir.path}${Platform.pathSeparator}wall_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await out.writeAsBytes(await file.readAsBytes(), flush: true);
    return 'file:${out.path}';
  } catch (_) {
    return null;
  }
}
