import 'dart:math';

import 'package:flutter/material.dart';

import '../app/t9.dart';
import 'device_art.dart';
import 'phone_art.dart';
import 'phone_theme.dart';

/// The second batch of cartoon gadgets (original designs, no real brands):
/// a swivel music phone, a pop-tilt messenger, a mirror compact, a sideways
/// game phone, a lipstick phone, a two-way pager, a see-through cordless
/// phone, a calculator watch, a rotating-screen candybar, a jelly slider, a
/// keychain pet egg and a wide two-thumb T9 phone.
///
/// Each is drawn at a fixed design size; [PhoneArt] puts it in a FittedBox.
/// They all have a full-screen version too: [FullPhoneArt] draws any theme
/// from its colours (the Wide T9 has its own landscape layout there).

// =================================================================== shared parts

const _toonShadow = [
  BoxShadow(color: Color(0x59000000), blurRadius: 34, spreadRadius: 2, offset: Offset(0, 16)),
  BoxShadow(color: Color(0x38000000), offset: Offset(12, 12)),
];

/// A cartoon shell with a gradient fill: thick ink outline, soft drop shadow
/// and white shine marks.
class ToonBody extends StatelessWidget {
  final List<Color> colors;
  final List<double>? stops;
  final Alignment begin, end;
  final Color ink;
  final BorderRadius radius;
  final Widget? child;
  final EdgeInsets padding;
  final bool shadow;
  final bool shine;
  final double border;
  final BodyPattern pattern;
  const ToonBody({
    super.key,
    required this.colors,
    required this.ink,
    required this.radius,
    this.stops,
    this.begin = const Alignment(-0.6, -1),
    this.end = const Alignment(0.6, 1),
    this.child,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
    this.shine = true,
    this.border = 5,
    this.pattern = BodyPattern.plain,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(begin: begin, end: end, colors: colors, stops: stops),
        border: Border.all(color: ink, width: border),
        boxShadow: shadow ? _toonShadow : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(fit: StackFit.expand, children: [
          if (pattern != BodyPattern.plain) CustomPaint(painter: PatternPainter(pattern, colors.first)),
          if (shine) const Positioned(left: 18, top: 16, child: Shine()),
          Padding(padding: padding, child: child ?? const SizedBox()),
        ]),
      ),
    );
  }
}

/// Three-stop gradient from one colour: lighter top-left, darker bottom-right.
List<Color> toonShades(Color c, {double light = 0.25, double dark = 0.15}) => [shade(c, light), c, shade(c, -dark)];

/// The little screen. [render] lays the chat out at that size and scales it
/// to fit (for small or oddly shaped windows).
Widget toonScreen(PhoneTheme t, double power, Widget screen,
    {double radius = 18, double border = 5, EdgeInsets padding = const EdgeInsets.fromLTRB(12, 8, 12, 8), Size? render}) {
  final p = power.clamp(0.0, 1.0);
  Widget content = Opacity(opacity: p, child: screen);
  if (render != null) content = FittedBox(fit: BoxFit.contain, child: SizedBox.fromSize(size: render, child: content));
  return Container(
    decoration: BoxDecoration(
      color: Color.lerp(t.screenOff, t.screenOn, p),
      borderRadius: BorderRadius.circular(radius),
      border: border > 0 ? Border.all(color: t.ink, width: border) : null,
      boxShadow: t.glow && p > 0.5 ? [BoxShadow(color: t.screenInk.withValues(alpha: 0.35 * p), blurRadius: 18)] : null,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(max(0.0, radius - border)),
      child: Stack(fit: StackFit.expand, children: [
        Padding(padding: padding, child: ClipRect(child: content)),
        const InnerShadow(depth: 0.3),
        const GlassGlare(strength: 0.6),
      ]),
    ),
  );
}

TextStyle toonKeyText(PhoneTheme t, double size, {Color? color}) => TextStyle(
      color: color ?? t.keyInk,
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1,
      shadows: t.glow ? [Shadow(color: (color ?? t.keyInk).withValues(alpha: 0.7), blurRadius: 8)] : null,
    );

/// A cartoon key wired to [keys] for [id] ('send', 'end', 'clear', 'mode' or
/// something to type).
Widget toonKey(PhoneTheme t, PhoneKeys keys, String id, Widget child,
        {required double height, Color? bg, BorderRadius? radius, bool lit = false, bool autofocus = false, String? semantics}) =>
    CartoonKey(
      t: t,
      height: height,
      bg: bg,
      radius: radius,
      lit: lit,
      autofocus: autofocus,
      feel: keys.feel,
      semantics: semantics ?? id,
      onTap: keys.live ? () => deviceAct(keys, id) : null,
      child: child,
    );

/// A rounded pill key with a text label.
Widget toonPill(PhoneTheme t, PhoneKeys keys, String id, String label, Color bg, Color ink,
        {double height = 44, double font = 18, IconData? icon}) =>
    toonKey(
      t,
      keys,
      id,
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: icon != null
              ? Icon(icon, color: ink, size: font * 1.3)
              : Text(label, style: TextStyle(color: ink, fontSize: font, fontWeight: FontWeight.w800, height: 1)),
        ),
      ),
      height: height,
      bg: bg,
      radius: BorderRadius.circular(height / 2),
      semantics: label,
    );

/// Send · mode · Clear · End in a row.
Widget toonSoftRow(PhoneTheme t, PhoneKeys keys, {double height = 40, double font = 16}) => Row(children: [
      Expanded(flex: 5, child: toonPill(t, keys, 'send', keys.sendLabel, kSendGreen, t.ink, height: height, font: font)),
      const SizedBox(width: 6),
      Expanded(flex: 4, child: toonPill(t, keys, 'mode', keys.modeLabel, t.softBg, t.softInk, height: height, font: font)),
      const SizedBox(width: 6),
      Expanded(flex: 4, child: toonPill(t, keys, 'clear', 'Clear', t.softBg, t.softInk, height: height, font: font)),
      const SizedBox(width: 6),
      Expanded(flex: 4, child: toonPill(t, keys, 'end', 'End', kEndRed, t.ink, height: height, font: font)),
    ]);

String t9Sub(PhoneKeys keys, String k) => switch (k) {
      '1' => '.,?!',
      '0' => '␣',
      '*' => keys.predictive ? 'next' : '',
      '#' => 'mode',
      _ => (kT9Letters[k] ?? '').toUpperCase(),
    };

bool _isT9Key(String id) => kT9Letters.containsKey(id) || id == '0' || id == '1' || id == '*' || id == '#';

/// A T9 key's face: the digit with its letters under it, sized to [h].
Widget t9Label(PhoneTheme t, PhoneKeys keys, String id, double h, {double scale = 1}) {
  final sub = t9Sub(keys, id);
  return Padding(
    padding: const EdgeInsets.all(2),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(id, style: toonKeyText(t, (h * 0.44 * scale).clamp(10.0, 60.0))),
        if (sub.isNotEmpty)
          Text(sub,
              style: TextStyle(
                  color: t.keySub, fontSize: (h * 0.2 * scale).clamp(7.0, 24.0), fontWeight: FontWeight.w700, height: 1.15)),
      ]),
    ),
  );
}

/// One cell of a [ToonGrid]: a key (or an empty gap when [id] is '').
class K {
  final String id;
  final String? label;
  final int flex;
  final Color? bg, ink;
  final bool lit;
  const K(this.id, {this.label, this.flex = 2, this.bg, this.ink, this.lit = false});
  const K.gap([this.flex = 1])
      : id = '',
        label = null,
        bg = null,
        ink = null,
        lit = false;
}

const kT9Rows = [
  [K('1'), K('2'), K('3')],
  [K('4'), K('5'), K('6')],
  [K('7'), K('8'), K('9')],
  [K('*'), K('0'), K('#')],
];

/// A thumb keyboard: numbers, three letter rows, then sym · :) · space · send.
List<List<K>> qwertyRows(PhoneKeys keys, {bool numbers = true, Color? sendInk, bool end = false}) {
  final l = keys.sym ? kQwertySymbols : kQwertyLetters;
  return [
    if (numbers) [for (final c in kQwertyNumbers) K(c, label: c)],
    [for (final c in l[0]) K(c, label: keys.cased(c))],
    [const K.gap(), for (final c in l[1]) K(c, label: keys.cased(c)), const K.gap()],
    [K('shift', label: '⇧', flex: 3, lit: keys.shift), for (final c in l[2]) K(c, label: keys.cased(c)), const K('del', label: '⌫', flex: 3)],
    [
      K('sym', label: keys.sym ? 'abc' : 'sym', flex: 3, lit: keys.sym),
      const K(':)', label: ':)'),
      const K('space', label: 'SPACE', flex: 8),
      if (end) const K('end', label: 'End', flex: 3, bg: kEndRed),
      K('send', label: '${keys.sendLabel} ⏎', flex: 5, bg: kSendGreen, ink: sendInk),
    ],
  ];
}

/// Rows of keys that stretch to fill the space they're given.
class ToonGrid extends StatelessWidget {
  final PhoneTheme t;
  final PhoneKeys keys;
  final List<List<K>> rows;
  final double hGap, vGap;
  final String? autofocus;
  final BorderRadius? radius;
  final double labelScale;
  const ToonGrid({
    super.key,
    required this.t,
    required this.keys,
    required this.rows,
    this.hGap = 10,
    this.vGap = 10,
    this.autofocus = '5',
    this.radius,
    this.labelScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var r = 0; r < rows.length; r++) ...[
        if (r > 0) SizedBox(height: vGap),
        Expanded(
          child: Row(children: [
            for (var i = 0; i < rows[r].length; i++) ...[
              if (i > 0) SizedBox(width: hGap),
              Expanded(flex: rows[r][i].flex, child: rows[r][i].id.isEmpty ? const SizedBox() : _key(rows[r][i])),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget _key(K k) => LayoutBuilder(builder: (ctx, c) {
        final h = (c.maxHeight - 6).clamp(14.0, 400.0);
        final face = k.label == null && _isT9Key(k.id)
            ? t9Label(t, keys, k.id, h, scale: labelScale)
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(k.label ?? k.id,
                      style: toonKeyText(t, (h * 0.46 * labelScale).clamp(9.0, 44.0), color: k.ink ?? (k.bg != null ? t.ink : null))),
                ),
              );
        return toonKey(t, keys, k.id, face,
            height: h, bg: k.bg, radius: radius, lit: k.lit, autofocus: k.id == autofocus, semantics: k.label ?? 'Key ${k.id}');
      });
}

/// A round navigation pad (just for looks; the arrows on a controller or
/// keyboard move between the keys).
Widget toonDpad(PhoneTheme t, double d) {
  Widget arrow(double angle) =>
      Transform.rotate(angle: angle, child: CustomPaint(size: Size(d * 0.17, d * 0.12), painter: _TriPainter(t.ink)));
  return Container(
    width: d,
    height: d,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4), radius: 0.9, colors: [shade(t.softBg, 0.55), t.softBg, shade(t.softBg, -0.12)]),
      border: Border.all(color: t.ink, width: 4),
      boxShadow: [BoxShadow(color: t.ink, offset: const Offset(0, 5))],
    ),
    child: Stack(alignment: Alignment.center, children: [
      Align(alignment: Alignment.topCenter, child: Padding(padding: EdgeInsets.only(top: d * 0.07), child: arrow(0))),
      Align(alignment: Alignment.bottomCenter, child: Padding(padding: EdgeInsets.only(bottom: d * 0.07), child: arrow(pi))),
      Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: d * 0.05), child: arrow(-pi / 2))),
      Align(alignment: Alignment.centerRight, child: Padding(padding: EdgeInsets.only(right: d * 0.05), child: arrow(pi / 2))),
      Container(
        width: d * 0.38,
        height: d * 0.38,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: t.ink, width: 4)),
        alignment: Alignment.center,
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Text('ok', style: TextStyle(color: t.ink, fontWeight: FontWeight.w900, fontSize: 14)),
          ),
        ),
      ),
    ]),
  );
}

/// Mode + Send on the left, the pad, Clear + End on the right.
Widget toonNav(PhoneTheme t, PhoneKeys keys, {double dpad = 96}) {
  Widget side(Widget a, Widget b) =>
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [a, const SizedBox(height: 10), b]));
  return Row(children: [
    side(toonPill(t, keys, 'mode', keys.modeLabel, t.softBg, t.softInk, height: 36, font: 16),
        toonPill(t, keys, 'send', keys.sendLabel, kSendGreen, t.ink, height: 42, font: 17)),
    const SizedBox(width: 12),
    toonDpad(t, dpad),
    const SizedBox(width: 12),
    side(toonPill(t, keys, 'clear', 'Clear', t.softBg, t.softInk, height: 36, font: 16),
        toonPill(t, keys, 'end', 'End', kEndRed, t.ink, height: 42, font: 17)),
  ]);
}

/// A speaker grille in a rounded slot.
Widget toonGrille(Color ink, {double radius = 12, double gap = 9, double r = 2.3}) => Container(
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ink.withValues(alpha: 0.6), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Padding(padding: const EdgeInsets.all(4), child: CustomPaint(painter: GrillePainter(gap: gap, r: r))),
      ),
    );

class _TriPainter extends CustomPainter {
  final Color color;
  _TriPainter(this.color);

  @override
  void paint(Canvas c, Size s) {
    c.drawPath(
        Path()
          ..moveTo(s.width / 2, 0)
          ..lineTo(s.width, s.height)
          ..lineTo(0, s.height)
          ..close(),
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TriPainter old) => old.color != color;
}

class _StarPainter extends CustomPainter {
  final Color fill, ink;
  _StarPainter(this.fill, this.ink);

  @override
  void paint(Canvas c, Size s) {
    final p = Path();
    final cx = s.width / 2, cy = s.height / 2, ro = s.width / 2, ri = ro * 0.45;
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? ro : ri;
      final a = -pi / 2 + i * pi / 5;
      final pt = Offset(cx + r * cos(a), cy + r * sin(a));
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    p.close();
    c.drawPath(p, Paint()..color = fill);
    c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round
          ..color = ink);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.fill != fill || old.ink != ink;
}

Widget _circleButton(double d, Color c, Color ink, {Widget? child, bool down = false, bool focused = false, Color? focus}) =>
    Container(
      width: d,
      height: d,
      transform: Matrix4.translationValues(0, down ? 4 : 0, 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
            center: const Alignment(-0.35, -0.4), radius: 0.85, colors: [shade(c, 0.6), c, shade(c, down ? -0.25 : -0.1)]),
        border: Border.all(color: focused ? (focus ?? ink) : ink, width: focused ? 6 : 5),
        boxShadow: down ? null : [BoxShadow(color: ink, offset: const Offset(0, 5))],
      ),
      alignment: Alignment.center,
      child: child,
    );

/// Letters picked one at a time on the lipstick's wheel and the pet egg.
final kPickChars = <String>[
  for (var c = 97; c <= 122; c++) String.fromCharCode(c),
  'space', 'del', '.', ',', '?', '!', ':)',
  for (var d = 0; d <= 9; d++) '$d',
  'shift',
];

String pickGlyph(PhoneKeys keys, String id) => switch (id) {
      'space' => '␣',
      'del' => '⌫',
      'shift' => keys.shift ? '⇩' : '⇧',
      _ => keys.cased(id),
    };

// =================================================================== 1 swivel

/// Chunky orange music phone. Closed it's all screen and music keys; the top
/// half spins round on a corner pin to show the keypad underneath.
class SwivelArt extends StatelessWidget {
  static const size = Size(460, 720);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const SwivelArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  static const _s = 320.0, _x = 40.0, _y = 360.0, _pin = 38.0;

  @override
  Widget build(BuildContext context) {
    final o = open.clamp(0.0, 1.0);
    // The top orbits the pin a quarter turn (plus a jaunty tilt) while its
    // face turns back the other way, so the screen ends up upright on top.
    final orbit = -(pi / 2 + 0.14) * o;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: _x, top: _y, width: _s, height: _s, child: _base()),
      if (t.strap != null) Positioned(left: _x + _s - 12, top: _y + 80, child: Strap(colors: t.strap!, ink: t.ink)),
      Positioned(
        left: _x,
        top: _y,
        width: _s,
        height: _s,
        child: Transform.rotate(
          angle: orbit,
          alignment: Alignment.topLeft,
          origin: const Offset(_pin, _pin),
          child: Transform.rotate(angle: pi / 2 * o, child: _top()),
        ),
      ),
      Positioned(left: _x + _pin - 17, top: _y + _pin - 17, child: _pinHead()),
    ]);
  }

  Widget _base() => ToonBody(
        colors: toonShades(t.body, light: 0.22, dark: 0.12),
        ink: t.ink,
        radius: BorderRadius.circular(56),
        padding: const EdgeInsets.fromLTRB(26, 74, 26, 22),
        child: Column(children: [
          SizedBox(height: 40, child: toonSoftRow(t, keys, height: 34, font: 15)),
          const SizedBox(height: 8),
          Expanded(child: ToonGrid(t: t, keys: keys, rows: kT9Rows, hGap: 9, vGap: 7)),
        ]),
      );

  Widget _top() => ToonBody(
        colors: const [Color(0xFF3E444C), Color(0xFF24282D), Color(0xFF15181B)],
        ink: t.ink,
        radius: BorderRadius.circular(56),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
        child: Column(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(18)),
              child: toonScreen(t, power, screen, radius: 13, border: 0, render: const Size(300, 216)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 58,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _music(44, Icons.skip_previous),
              _music(58, Icons.play_arrow),
              _music(44, Icons.skip_next),
            ]),
          ),
        ]),
      );

  Widget _music(double d, IconData icon) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF68717C), Color(0xFF2B3036)]),
          border: Border.all(color: Colors.black, width: 4),
        ),
        child: Icon(icon, color: t.body, size: d * 0.55),
      );

  Widget _pinHead() => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Colors.white, Color(0xFFE6E8EB), Color(0xFFA9AFB7)], stops: [0, 0.25, 1]),
          border: Border.all(color: t.ink, width: 5),
        ),
      );
}

// =================================================================== 2 pop-tilt

/// Wide teal messenger: the screen pops up off a full thumb keyboard and tilts
/// back. Menu / Back on the left of the lid, Send / End on the right.
class PopTiltArt extends StatelessWidget {
  static const size = Size(900, 660);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const PopTiltArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  @override
  Widget build(BuildContext context) {
    final o = open.clamp(0.0, 1.0);
    final lidTop = 330 - 290 * o;
    return Stack(clipBehavior: Clip.none, children: [
      // hinge arms behind the lid
      for (final x in const [180.0, 692.0])
        Positioned(
          left: x,
          top: 300 - 80 * o,
          width: 28,
          height: 40 + 80 * o,
          child: Opacity(opacity: o, child: _arm()),
        ),
      Positioned(left: 40, top: 300, width: 820, height: 320, child: _base()),
      Positioned(left: 430, top: 580, child: _trackball()),
      Positioned(
        left: 90,
        top: lidTop,
        width: 720,
        height: 260,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateX(0.22 * o),
          child: _lid(),
        ),
      ),
    ]);
  }

  Widget _base() => ToonBody(
        colors: toonShades(t.body, light: 0.3),
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        ink: t.ink,
        shine: false,
        radius: const BorderRadius.vertical(top: Radius.circular(40), bottom: Radius.circular(110)),
        padding: const EdgeInsets.fromLTRB(44, 34, 44, 44),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16191D),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: t.ink, width: 4),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: ToonGrid(t: t, keys: keys, rows: qwertyRows(keys, sendInk: t.ink), hGap: 6, vGap: 6, autofocus: 'g'),
        ),
      );

  Widget _lid() => ToonBody(
        colors: [shade(t.body, 0.45), shade(t.body, 0.15), t.body],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        ink: t.ink,
        radius: BorderRadius.circular(40),
        child: Stack(children: [
          Positioned(
            left: 140,
            top: 18,
            right: 140,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.ink, width: 5)),
              child: toonScreen(t, power, screen, radius: 12, border: 0),
            ),
          ),
          Positioned(left: 22, top: 50, width: 100, child: toonPill(t, keys, 'mode', 'MENU', Colors.white, t.ink, height: 48, font: 16)),
          Positioned(left: 22, top: 128, width: 100, child: toonPill(t, keys, 'clear', 'BACK', Colors.white, t.ink, height: 48, font: 16)),
          Positioned(right: 22, top: 50, width: 100, child: toonPill(t, keys, 'send', keys.sendLabel, kSendGreen, t.ink, height: 48, font: 16)),
          Positioned(right: 22, top: 128, width: 100, child: toonPill(t, keys, 'end', 'END', kEndRed, t.ink, height: 48, font: 16)),
        ]),
      );

  Widget _arm() => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF9AA3AF), Color(0xFFE6E9ED), Color(0xFF9AA3AF)]),
          border: Border.all(color: t.ink, width: 4),
          borderRadius: BorderRadius.circular(14),
        ),
      );

  Widget _trackball() => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: const Alignment(-0.3, -0.4), colors: [Colors.white, const Color(0xFF9FE7FF), t.body], stops: const [0, 0.25, 1]),
          border: Border.all(color: t.ink, width: 4),
        ),
      );
}

// =================================================================== 3 compact

/// A round gold makeup compact: the mirror lid holds the screen and flips up;
/// the keys sit in a ring around a big 5.
class CompactArt extends StatelessWidget {
  static const size = Size(540, 960);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const CompactArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  static const _d = 400.0, _x = 60.0, _lidY = 30.0, _baseY = 450.0;
  static const _ring = ['1', '2', '3', '6', '9', '#', '0', '*', '7', '4'];
  static const _pink = Color(0xFFF7C6D6);

  @override
  Widget build(BuildContext context) {
    final angle = (1 - open.clamp(0.0, 1.0)) * pi;
    final showBack = angle > pi / 2;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: _x, top: _baseY, width: _d, height: _d, child: _base()),
      if (t.strap != null) Positioned(left: _x + _d - 34, top: _baseY + 170, child: Strap(colors: t.strap!, ink: t.ink)),
      Positioned(
        left: 40,
        top: 872,
        width: 460,
        height: 56,
        child: Row(children: [
          Expanded(flex: 5, child: toonPill(t, keys, 'send', keys.sendLabel, kSendGreen, t.ink, height: 46)),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: toonPill(t, keys, 'mode', keys.modeLabel, t.softBg, t.softInk, height: 46)),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: toonPill(t, keys, 'clear', 'Clear', t.softBg, t.softInk, height: 46)),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: toonPill(t, keys, 'end', 'End', kEndRed, t.ink, height: 46)),
        ]),
      ),
      Positioned(left: 196, top: 418, width: 148, height: 48, child: _hinge()),
      // The lid folds about the line between the lid and the base.
      Positioned(
        left: _x,
        top: _lidY,
        width: _d,
        height: _d + 10,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateX(-angle),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: _d,
              height: _d,
              child: showBack
                  ? Transform(alignment: Alignment.center, transform: Matrix4.rotationX(pi), child: _lidBack())
                  : _lidFront(),
            ),
          ),
        ),
      ),
    ]);
  }

  BoxDecoration _gold(Color c) => BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [shade(c, 0.6), c, shade(c, -0.18), shade(c, 0.45)],
          stops: const [0, 0.4, 0.62, 1],
        ),
        border: Border.all(color: t.ink, width: 5),
        boxShadow: _toonShadow,
      );

  Widget _hinge() => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [shade(t.hinge, 0.5), t.hinge, shade(t.hinge, -0.2)]),
          border: Border.all(color: t.ink, width: 5),
        ),
      );

  Widget _lidFront() => Container(
        decoration: _gold(t.shell),
        padding: const EdgeInsets.all(18),
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: t.lid, border: Border.all(color: t.ink, width: 5)),
          child: ClipOval(
            child: Stack(children: [
              // mirror sheen
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.2)],
                    ),
                  ),
                ),
              ),
              Positioned(left: 52, top: 64, right: 52, bottom: 64, child: toonScreen(t, power, screen, radius: 30, border: 4, render: const Size(290, 250))),
              Positioned(
                left: 46,
                top: 30,
                child: Transform.rotate(
                  angle: -0.5,
                  child: Container(width: 84, height: 18, decoration: BoxDecoration(color: const Color(0x99FFFFFF), borderRadius: BorderRadius.circular(9))),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _lidBack() {
    final now = TimeOfDay.now();
    return Container(
      decoration: _gold(t.shell),
      alignment: Alignment.center,
      child: Container(
        width: 300,
        height: 300,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: shade(t.shell, -0.3), width: 6)),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CustomPaint(size: const Size(96, 86), painter: HeartPainter(const Color(0xFFFF8FB8), t.ink, stroke: 5)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(color: t.screenOn, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.ink, width: 4)),
            child: Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: t.screenInk, fontSize: 26, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }

  Widget _base() => Container(
        decoration: _gold(t.body),
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: _pink, border: Border.all(color: t.ink, width: 4)),
          child: LayoutBuilder(builder: (ctx, c) {
            final cx = c.maxWidth / 2, cy = c.maxHeight / 2;
            const r = 120.0, k = 64.0;
            return Stack(children: [
              for (var i = 0; i < _ring.length; i++)
                Positioned(
                  left: cx + r * cos(-pi / 2 + i * 2 * pi / _ring.length) - k / 2,
                  top: cy + r * sin(-pi / 2 + i * 2 * pi / _ring.length) - k / 2,
                  width: k,
                  height: k,
                  child: toonKey(t, keys, _ring[i], t9Label(t, keys, _ring[i], k - 6), height: k - 6, semantics: 'Key ${_ring[i]}'),
                ),
              Positioned(
                left: cx - 50,
                top: cy - 50,
                width: 100,
                height: 100,
                child: toonKey(t, keys, '5', t9Label(t, keys, '5', 80), height: 94, bg: t.softBg, autofocus: true, semantics: 'Key 5'),
              ),
            ]);
          }),
        ),
      );
}

// =================================================================== 4 taco

/// A sideways game phone like a green taco: D-pad on the left, screen in the
/// middle, keypad on the right.
class TacoArt extends StatelessWidget {
  static const size = Size(960, 440);
  final PhoneTheme t;
  final double power;
  final PhoneKeys keys;
  final Widget screen;
  const TacoArt({super.key, required this.t, required this.power, required this.keys, required this.screen});

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: 20,
        top: 30,
        width: 920,
        height: 360,
        child: ToonBody(
          colors: toonShades(t.body, light: 0.25, dark: 0.22),
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          ink: t.ink,
          shine: false,
          radius: const BorderRadius.vertical(top: Radius.elliptical(200, 170), bottom: Radius.elliptical(200, 150)),
          child: Stack(children: [
            const Positioned(left: 150, top: 22, child: Shine()),
            Positioned(left: 100, top: 46, width: 118, child: toonPill(t, keys, 'end', 'End', kEndRed, t.ink, height: 40, font: 17)),
            Positioned(left: 88, top: 104, child: toonDpad(t, 140)),
            Positioned(left: 100, top: 262, width: 118, child: toonPill(t, keys, 'send', keys.sendLabel, kSendGreen, t.ink, height: 40, font: 17)),
            Positioned(left: 244, top: 92, width: 74, child: toonPill(t, keys, 'mode', keys.modeLabel, t.softBg, t.softInk, height: 40, font: 15)),
            Positioned(left: 244, top: 150, width: 74, child: toonPill(t, keys, 'clear', 'Clear', t.softBg, t.softInk, height: 40, font: 15)),
            Positioned(left: 256, top: 214, width: 50, height: 50, child: toonGrille(t.ink, radius: 25, gap: 8, r: 2)),
            Positioned(
              left: 334,
              top: 36,
              width: 264,
              height: 280,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF0B140D), borderRadius: BorderRadius.circular(22), border: Border.all(color: t.ink, width: 5)),
                child: toonScreen(t, power, screen, radius: 12, border: 0, render: const Size(270, 290)),
              ),
            ),
            Positioned(left: 612, top: 50, width: 218, height: 262, child: ToonGrid(t: t, keys: keys, rows: kT9Rows, hGap: 8, vGap: 8)),
          ]),
        ),
      ),
    ]);
  }
}

// =================================================================== 5 lipstick

/// A slim red lipstick: messages glow through the mirror in red dots; letters
/// are picked on a gold spin wheel and typed with OK. The gold cap slides off
/// as it opens.
class LipstickArt extends StatefulWidget {
  static const size = Size(300, 960);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const LipstickArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  @override
  State<LipstickArt> createState() => _LipstickArtState();
}

class _LipstickArtState extends State<LipstickArt> {
  int _i = 6; // 'g'
  double _spin = 0;
  double? _last;

  static const _gold = [Color(0xFF7A5A14), Color(0xFFD6B04A), Color(0xFFFFF4C8), Color(0xFFF6DC8A), Color(0xFF8A6A1E)];

  void _step(int d, {bool sound = false}) {
    if (sound) widget.keys.feel?.call(pad: false);
    setState(() => _i = (_i + d) % kPickChars.length);
  }

  double _angle(Offset p) => atan2(p.dy - 65, p.dx - 65);

  @override
  Widget build(BuildContext context) {
    final t = widget.t, keys = widget.keys;
    final o = widget.open.clamp(0.0, 1.0);
    final capTop = 780 - 300 * (1 - o);
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: 50,
        top: 40,
        width: 200,
        height: 740,
        child: ToonBody(
          colors: const [Color(0xFF6A0A24), Color(0xFFC21845), Color(0xFFFF6E8F), Color(0xFFD3204F), Color(0xFF7A0F2B)],
          stops: const [0, 0.3, 0.46, 0.62, 1],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          ink: t.ink,
          shine: false,
          radius: const BorderRadius.vertical(top: Radius.circular(44), bottom: Radius.circular(30)),
          child: Stack(children: [
            Positioned(left: 62, top: 12, width: 66, height: 18, child: toonGrille(t.ink, radius: 9, gap: 7, r: 1.8)),
            Positioned(left: 12, top: 38, width: 166, height: 340, child: _mirror()),
            Positioned(left: 22, top: 392, width: 146, height: 50, child: _letterWindow()),
            Positioned(left: 30, top: 454, width: 130, height: 130, child: _wheel()),
            Positioned(left: 10, top: 604, width: 82, child: toonPill(t, keys, 'send', keys.sendLabel, kSendGreen, t.ink, height: 42, font: 15)),
            Positioned(right: 10, top: 604, width: 82, child: toonPill(t, keys, 'end', 'End', kEndRed, t.ink, height: 42, font: 15)),
            const Positioned(
              left: 0,
              right: 0,
              top: 670,
              child: Text('rouge',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFFE1E9), fontSize: 18, fontStyle: FontStyle.italic, fontWeight: FontWeight.w900, letterSpacing: 3)),
            ),
          ]),
        ),
      ),
      Positioned(
        left: 42,
        top: capTop,
        width: 216,
        height: 160,
        child: ToonBody(
          colors: _gold,
          stops: const [0, 0.35, 0.5, 0.62, 1],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          ink: t.ink,
          shine: false,
          radius: const BorderRadius.vertical(top: Radius.circular(14), bottom: Radius.circular(34)),
          child: Column(children: [
            const SizedBox(height: 22),
            for (var i = 0; i < 3; i++) Container(height: 3, margin: const EdgeInsets.only(bottom: 6), color: const Color(0x557A5A14)),
          ]),
        ),
      ),
    ]);
  }

  Widget _mirror() {
    final t = widget.t;
    final p = widget.power.clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(t.screenOff, t.screenOn, p),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.ink, width: 4),
        boxShadow: p > 0.5 ? [BoxShadow(color: t.screenInk.withValues(alpha: 0.4 * p), blurRadius: 16)] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(fit: StackFit.expand, children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Opacity(
              opacity: p,
              child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: 200, height: 420, child: widget.screen)),
            ),
          ),
          IgnorePointer(child: CustomPaint(painter: PixelGridPainter(t.screenInk.withValues(alpha: 0.12), step: 4))),
          const GlassGlare(strength: 1.3),
        ]),
      ),
    );
  }

  Widget _letterWindow() {
    final t = widget.t, keys = widget.keys;
    final n = kPickChars.length;
    String g(int d) => pickGlyph(keys, kPickChars[(_i + d) % n]);
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1A0308), borderRadius: BorderRadius.circular(10), border: Border.all(color: t.ink, width: 3)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final d in const [-2, -1, 0, 1, 2])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(g(d),
                  style: TextStyle(
                    color: d == 0 ? const Color(0xFFFFE1E9) : t.screenInk.withValues(alpha: d.abs() == 1 ? 0.75 : 0.4),
                    fontSize: d == 0 ? 30 : 20,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    shadows: [Shadow(color: t.screenInk, blurRadius: d == 0 ? 10 : 4)],
                  )),
            ),
        ]),
      ),
    );
  }

  Widget _wheel() {
    final t = widget.t, keys = widget.keys;
    Widget arrow(int d, String glyph) => DeviceKey(
          semantics: d < 0 ? 'Previous letter' : 'Next letter',
          feel: keys.feel,
          onTap: keys.live ? () => _step(d) : null,
          builder: (f, down) => Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: down ? const Color(0x337A5A14) : null,
              borderRadius: BorderRadius.circular(10),
              border: f ? Border.all(color: t.focus, width: 3) : null,
            ),
            child: Text(glyph, style: TextStyle(color: t.ink, fontSize: 20, fontWeight: FontWeight.w900)),
          ),
        );
    return GestureDetector(
      onPanStart: keys.live ? (d) => _last = _angle(d.localPosition) : null,
      onPanUpdate: keys.live
          ? (d) {
              final a = _angle(d.localPosition);
              var da = a - (_last ?? a);
              if (da > pi) da -= 2 * pi;
              if (da < -pi) da += 2 * pi;
              _last = a;
              _spin += da;
              while (_spin > 0.4) {
                _spin -= 0.4;
                _step(1, sound: true);
              }
              while (_spin < -0.4) {
                _spin += 0.4;
                _step(-1, sound: true);
              }
            }
          : null,
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(colors: [..._gold, Color(0xFF7A5A14)]),
              border: Border.all(color: t.ink, width: 5),
              boxShadow: [BoxShadow(color: t.ink, offset: const Offset(0, 4))],
            ),
            child: Transform.rotate(angle: _i * 0.4, child: CustomPaint(painter: _TicksPainter(t.ink))),
          ),
        ),
        Positioned(left: 8, top: 45, width: 28, height: 40, child: arrow(-1, '◀')),
        Positioned(right: 8, top: 45, width: 28, height: 40, child: arrow(1, '▶')),
        Positioned(
          left: 38,
          top: 38,
          width: 54,
          height: 54,
          child: DeviceKey(
            semantics: 'Type the letter',
            autofocus: true,
            feel: keys.feel,
            onTap: keys.live ? () => deviceAct(keys, kPickChars[_i]) : null,
            builder: (f, down) => _circleButton(54, const Color(0xFFD3204F), t.ink,
                down: down,
                focused: f,
                focus: t.focus,
                child: const Text('OK', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900))),
          ),
        ),
      ]),
    );
  }
}

/// Little ridges round the edge of a dial.
class _TicksPainter extends CustomPainter {
  final Color ink;
  _TicksPainter(this.ink);

  @override
  void paint(Canvas c, Size s) {
    final ctr = s.center(Offset.zero);
    final r = s.shortestSide / 2;
    final p = Paint()
      ..color = ink.withValues(alpha: 0.45)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 24; i++) {
      final a = i * pi / 12;
      final d = Offset(cos(a), sin(a));
      c.drawLine(ctr + d * (r - 12), ctr + d * (r - 4), p);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => old.ink != ink;
}

// =================================================================== 6 pager

/// A belt-clip two-way pager: the lid opens on a wide mono screen over a tiny
/// keyboard; scroll wheel on the side.
class PagerArt extends StatelessWidget {
  static const size = Size(860, 700);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const PagerArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  @override
  Widget build(BuildContext context) {
    final angle = (1 - open.clamp(0.0, 1.0)) * pi;
    final showBack = angle > pi / 2;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: 280, top: 580, width: 300, height: 54, child: _clip()),
      Positioned(left: 716, top: 380, width: 40, height: 124, child: _wheel()),
      Positioned(left: 130, top: 330, width: 600, height: 260, child: _base()),
      Positioned(left: 170, top: 312, width: 520, height: 28, child: _hinge()),
      Positioned(
        left: 130,
        top: 56,
        width: 600,
        height: 267,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateX(-angle),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 600,
              height: 260,
              child: showBack
                  ? Transform(alignment: Alignment.center, transform: Matrix4.rotationX(pi), child: _lidBack())
                  : _lidFront(),
            ),
          ),
        ),
      ),
    ]);
  }

  List<Color> get _metal => [shade(t.body, 0.25), t.body, shade(t.body, -0.25)];

  Widget _base() => ToonBody(
        colors: _metal,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        ink: t.ink,
        shine: false,
        radius: const BorderRadius.vertical(top: Radius.circular(14), bottom: Radius.circular(40)),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        child: ToonGrid(t: t, keys: keys, rows: qwertyRows(keys, end: true, sendInk: t.ink), hGap: 6, vGap: 6, autofocus: 'g'),
      );

  Widget _led() {
    final on = power > 0.5;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? t.softBg : shade(t.softBg, -0.6),
        border: Border.all(color: t.ink, width: 2),
        boxShadow: on ? [BoxShadow(color: t.softBg, blurRadius: 12)] : null,
      ),
    );
  }

  Widget _lidFront() => ToonBody(
        colors: [shade(t.body, 0.35), t.body],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        ink: t.ink,
        radius: const BorderRadius.vertical(top: Radius.circular(30), bottom: Radius.circular(14)),
        child: Stack(children: [
          Positioned(
            left: 38,
            top: 22,
            right: 38,
            bottom: 26,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: const Color(0xFF20252C), borderRadius: BorderRadius.circular(12), border: Border.all(color: t.ink, width: 5)),
              child: toonScreen(t, power, screen, radius: 6, border: 0),
            ),
          ),
          Positioned(right: 14, top: 8, child: _led()),
        ]),
      );

  Widget _lidBack() => ToonBody(
        colors: [shade(t.body, 0.2), shade(t.body, -0.15)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        ink: t.ink,
        radius: const BorderRadius.vertical(top: Radius.circular(30), bottom: Radius.circular(14)),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 220, height: 44, child: toonGrille(t.ink, radius: 22)),
            const SizedBox(height: 14),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('2-WAY', style: TextStyle(color: shade(t.body, 0.5), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 4)),
              const SizedBox(width: 14),
              _led(),
            ]),
          ]),
        ),
      );

  Widget _hinge() => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD7DCE2), Color(0xFFB8C0CA), Color(0xFF6A727C)]),
          border: Border.all(color: t.ink, width: 4),
        ),
      );

  Widget _wheel() => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.ink, width: 4),
          color: const Color(0xFF5A626C),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Column(children: [
            for (var i = 0; i < 14; i++) Expanded(child: Container(color: i.isEven ? const Color(0xFFA9B1BC) : const Color(0xFF4A515B))),
          ]),
        ),
      );

  Widget _clip() => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2E35),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
          border: Border.all(color: t.ink, width: 5),
        ),
      );
}

// =================================================================== 7 cordless

/// A see-through 90s cordless house phone: neon circuit guts, glowing keys,
/// TALK / FLASH / OFF, and a base with a pink neon strip. It lifts out of the
/// base as it opens.
class CordlessArt extends StatelessWidget {
  static const size = Size(520, 980);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const CordlessArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  static const _clear = [Color(0xC8D2FFEB), Color(0x8C78F0C8), Color(0xB05AD2BE)];

  @override
  Widget build(BuildContext context) {
    final lift = 120 * (1 - open.clamp(0.0, 1.0));
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: 60, top: 730, width: 400, height: 200, child: _cradle()),
      Positioned(left: 145, top: lift, width: 230, height: 760, child: _handset()),
      Positioned(left: 60, top: 836, width: 400, height: 94, child: _lip()),
    ]);
  }

  Widget _cradle() {
    final on = power > 0.5;
    return ToonBody(
      colors: _clear,
      ink: t.ink,
      radius: const BorderRadius.vertical(top: Radius.circular(40), bottom: Radius.circular(60)),
      child: Stack(children: [
        Positioned(
          right: 40,
          top: 22,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? const Color(0xFFFF3B3B) : const Color(0xFF5A1414),
              boxShadow: on ? const [BoxShadow(color: Color(0xFFFF3B3B), blurRadius: 12)] : null,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _lip() => ToonBody(
        colors: _clear,
        ink: t.ink,
        shadow: false,
        shine: false,
        radius: const BorderRadius.vertical(top: Radius.circular(26), bottom: Radius.circular(60)),
        child: Align(
          alignment: const Alignment(0, 0.35),
          child: Container(
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4FA3),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Color(0xB3FF4FA3), blurRadius: 18, spreadRadius: 4)],
            ),
          ),
        ),
      );

  Widget _handset() => Stack(clipBehavior: Clip.none, children: [
        Positioned(
          right: 28,
          top: 0,
          width: 36,
          height: 84,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xCC96F0D2), Color(0x9978F0C8)]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border.all(color: t.ink, width: 5),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 60,
          width: 230,
          height: 700,
          child: ToonBody(
            colors: _clear,
            ink: t.ink,
            radius: const BorderRadius.vertical(top: Radius.circular(90), bottom: Radius.circular(70)),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _CircuitPainter())),
              Positioned(left: 64, top: 24, width: 92, height: 38, child: toonGrille(t.ink, radius: 19, gap: 8, r: 2)),
              Positioned(left: 22, top: 78, width: 176, height: 122, child: toonScreen(t, power, screen, radius: 12, border: 4, render: const Size(250, 174))),
              Positioned(
                left: 16,
                right: 16,
                top: 212,
                height: 38,
                child: Row(children: [
                  Expanded(child: toonPill(t, keys, 'send', 'TALK', kSendGreen, t.ink, height: 32, font: 14)),
                  const SizedBox(width: 8),
                  Expanded(child: toonPill(t, keys, 'end', 'OFF', kEndRed, t.ink, height: 32, font: 14)),
                ]),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: 254,
                height: 38,
                child: Row(children: [
                  Expanded(child: toonPill(t, keys, 'mode', 'FLASH', const Color(0xFFFFE066), t.ink, height: 32, font: 14)),
                  const SizedBox(width: 8),
                  Expanded(child: toonPill(t, keys, 'clear', 'CLR', t.softBg, t.softInk, height: 32, font: 14)),
                ]),
              ),
              Positioned(left: 20, right: 20, top: 304, height: 326, child: ToonGrid(t: t, keys: keys, rows: kT9Rows, hGap: 10, vGap: 10)),
              Positioned(left: 92, top: 646, width: 36, height: 24, child: toonGrille(t.ink, radius: 8, gap: 7, r: 1.8)),
            ]),
          ),
        ),
      ]);
}

/// Neon guts seen through the clear case: a circuit board, chips, LEDs and
/// wires.
class _CircuitPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final board = RRect.fromRectAndRadius(Rect.fromLTWH(18, s.height * 0.42, s.width - 36, s.height * 0.48), const Radius.circular(16));
    c.drawRRect(board, Paint()..color = const Color(0x8C1BC47D));
    final trace = Paint()
      ..color = const Color(0xCCFFE066)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (var i = 0; i < 10; i++) {
      final x = 30.0 + i * 17;
      final y = board.top + 14;
      c.drawPath(
          Path()
            ..moveTo(x, y)
            ..lineTo(x, y + 50 + (i % 4) * 34)
            ..lineTo(x + 12, y + 62 + (i % 4) * 34),
          trace);
    }
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.width / 2 - 36, board.bottom - 70, 72, 40), const Radius.circular(4)),
        Paint()..color = const Color(0xCC20242C));
    c.drawCircle(Offset(44, board.bottom - 40), 11, Paint()..color = const Color(0xFFFF4FA3));
    c.drawCircle(Offset(s.width - 44, board.bottom - 40), 11, Paint()..color = const Color(0xFF5AA9FF));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.width / 2 - 50, 20, 100, 30), const Radius.circular(8)),
        Paint()..color = const Color(0x5520242C));
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = const Color(0xCCFF6FB1);
    c.drawPath(
        Path()
          ..moveTo(30, board.bottom + 10)
          ..quadraticBezierTo(s.width / 2, board.bottom + 40, s.width - 30, board.bottom + 10),
        wire);
  }

  @override
  bool shouldRepaint(_CircuitPainter old) => false;
}

// =================================================================== 8 watch

/// A chunky databank watch: chat on the face, T9 on calculator keys with
/// SEND / MODE / CLR / END down the side.
class WatchArt extends StatelessWidget {
  static const size = Size(480, 1000);
  final PhoneTheme t;
  final double power;
  final PhoneKeys keys;
  final Widget screen;
  const WatchArt({super.key, required this.t, required this.power, required this.keys, required this.screen});

  static const _orange = Color(0xFFF5A623);

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: 130, top: 0, width: 220, height: 240, child: _band(false)),
      Positioned(left: 130, top: 750, width: 220, height: 240, child: _band(true)),
      for (final (x, y) in const [(46.0, 300.0), (46.0, 610.0), (408.0, 300.0), (408.0, 610.0)])
        Positioned(left: x, top: y, width: 28, height: 52, child: _pusher()),
      Positioned(left: 70, top: 200, width: 340, height: 590, child: _face()),
    ]);
  }

  Widget _band(bool holes) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F2125),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.ink, width: 5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(children: [
            Column(children: [
              for (var i = 0; i < 8; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF26282D), Color(0xFF3A3D44), Color(0xFF26282D)])),
                  ),
                ),
            ]),
            if (holes)
              Positioned.fill(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(bottom: 22),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0A0A0C),
                        border: Border.all(color: const Color(0xFF4A4D55), width: 2),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      );

  Widget _pusher() => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF8E939B), Color(0xFFE6E8EC), Color(0xFF8E939B)]),
          border: Border.all(color: t.ink, width: 4),
          borderRadius: BorderRadius.circular(8),
        ),
      );

  Widget _face() {
    const label = TextStyle(color: _orange, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1);
    final rows = [
      [const K('1'), const K('2'), const K('3'), K('send', label: 'SEND', bg: kSendGreen, ink: t.ink)],
      [const K('4'), const K('5'), const K('6'), K('mode', label: 'MODE', bg: _orange, ink: t.ink)],
      [const K('7'), const K('8'), const K('9'), K('clear', label: 'CLR', bg: const Color(0xFFC9CCD2), ink: t.ink)],
      [const K('*'), const K('0'), const K('#'), K('end', label: 'END', bg: kEndRed, ink: t.ink)],
    ];
    return ToonBody(
      colors: const [Color(0xFF7C8088), Color(0xFFE6E8EC), Color(0xFF9EA2AA), Color(0xFFE0E2E6), Color(0xFF7C8088)],
      stops: const [0, 0.3, 0.55, 0.8, 1],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      ink: t.ink,
      border: 6,
      shine: false,
      radius: BorderRadius.circular(46),
      padding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF141519), borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.black, width: 3)),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(children: [
          const SizedBox(
            height: 18,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('LIGHT', style: label),
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: Text('AIM · DATABANK', style: label))),
              Text('MODE', style: label),
            ]),
          ),
          const SizedBox(height: 6),
          SizedBox(height: 200, child: toonScreen(t, power, screen, radius: 6, border: 4, render: const Size(290, 224))),
          const SizedBox(height: 14),
          Expanded(child: ToonGrid(t: t, keys: keys, rows: rows, hGap: 8, vGap: 8)),
        ]),
      ),
    );
  }
}

// =================================================================== 9 rotator

/// A purple candybar whose screen twists sideways on a pivot for a wide chat.
class RotatorArt extends StatelessWidget {
  static const size = Size(620, 900);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const RotatorArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  @override
  Widget build(BuildContext context) {
    final o = open.clamp(0.0, 1.0);
    final a = -pi / 2 * (1 - o) - 0.07 * o;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: 130, top: 300, width: 360, height: 560, child: _body()),
      Positioned(left: 30, top: 150, width: 560, height: 300, child: Transform.rotate(angle: a, child: _panel())),
    ]);
  }

  Widget _body() => ToonBody(
        colors: toonShades(t.body, light: 0.3, dark: 0.15),
        ink: t.ink,
        radius: const BorderRadius.vertical(top: Radius.circular(40), bottom: Radius.circular(80)),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
        child: Column(children: [
          const SizedBox(height: 186),
          SizedBox(height: 104, child: toonNav(t, keys)),
          const SizedBox(height: 12),
          Expanded(child: ToonGrid(t: t, keys: keys, rows: kT9Rows, hGap: 12, vGap: 9)),
        ]),
      );

  Widget _panel() => ToonBody(
        colors: [shade(t.body, 0.6), shade(t.body, 0.3)],
        ink: t.ink,
        radius: BorderRadius.circular(40),
        child: Stack(children: [
          Positioned(
            left: 36,
            top: 26,
            right: 36,
            bottom: 30,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(22), border: Border.all(color: t.ink, width: 5)),
              child: toonScreen(t, power, screen, radius: 12, border: 0),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 8,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: t.ink, width: 3)),
            ),
          ),
        ]),
      );
}

// =================================================================== 10 jelly

/// A squishy see-through gummy slider; the top slides up off the keys.
class JellyArt extends StatelessWidget {
  static const size = Size(480, 940);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const JellyArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  static const _jelly = [Color(0xD996FFD2), Color(0xB33CDCAA), Color(0xCC1EBE96)];

  @override
  Widget build(BuildContext context) {
    final upperTop = 80 + 330 * (1 - open.clamp(0.0, 1.0));
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: 60, top: 440, width: 360, height: 470, child: _lower()),
      if (t.strap != null) Positioned(left: 404, top: 610, child: Strap(colors: t.strap!, ink: t.ink)),
      Positioned(
        left: 14,
        top: 560,
        child: Transform.rotate(
            angle: -0.25, child: CustomPaint(size: const Size(58, 58), painter: _StarPainter(const Color(0xFFFFE066), t.ink))),
      ),
      Positioned(left: 60, top: upperTop, width: 360, height: 440, child: _upper()),
    ]);
  }

  Widget _bubble(double s) => Container(
        width: s,
        height: s,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: Alignment(-0.4, -0.4), colors: [Color(0xE6FFFFFF), Color(0x40FFFFFF)], stops: [0.25, 0.3]),
        ),
      );

  Widget _lower() => ToonBody(
        colors: _jelly,
        ink: t.ink,
        shine: false,
        radius: const BorderRadius.vertical(top: Radius.circular(30), bottom: Radius.circular(90)),
        child: Stack(children: [
          Positioned(left: 300, top: 410, child: _bubble(22)),
          Positioned(left: 22, top: 420, child: _bubble(14)),
          Positioned(left: 300, top: 86, child: _bubble(12)),
          Positioned(left: 30, right: 30, top: 116, bottom: 56, child: ToonGrid(t: t, keys: keys, rows: kT9Rows, hGap: 12, vGap: 12)),
        ]),
      );

  Widget _upper() => ToonBody(
        colors: _jelly,
        ink: t.ink,
        radius: const BorderRadius.vertical(top: Radius.circular(80), bottom: Radius.circular(40)),
        child: Stack(children: [
          Positioned(left: 134, top: 20, width: 86, height: 18, child: toonGrille(t.ink, radius: 9, gap: 7, r: 1.8)),
          Positioned(
            left: 24,
            right: 24,
            top: 48,
            height: 254,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0x400F5B4A), borderRadius: BorderRadius.circular(24), border: Border.all(color: t.ink, width: 5)),
              child: toonScreen(t, power, screen, radius: 14, border: 0),
            ),
          ),
          Positioned(left: 20, right: 20, top: 314, height: 106, child: toonNav(t, keys)),
          Positioned(left: 280, top: 40, child: _bubble(16)),
        ]),
      );
}

// =================================================================== 11 egg pet

/// A keychain pet egg: three buttons pick letters (◀ ▶ / TYPE / SEND) while a
/// little pixel pet hangs out on the screen.
class EggPetArt extends StatefulWidget {
  static const size = Size(520, 760);
  final PhoneTheme t;
  final double power;
  final PhoneKeys keys;
  final Widget screen;
  const EggPetArt({super.key, required this.t, required this.power, required this.keys, required this.screen});

  @override
  State<EggPetArt> createState() => _EggPetArtState();
}

class _EggPetArtState extends State<EggPetArt> {
  int _i = 6; // 'g'

  void _step(int d) => setState(() => _i = (_i + d) % kPickChars.length);

  @override
  Widget build(BuildContext context) {
    final t = widget.t, keys = widget.keys;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: 222, top: 6, width: 76, height: 92, child: _ring()),
      Positioned(left: 244, top: 86, width: 32, height: 28, child: _clasp()),
      Positioned(left: 60, top: 104, width: 400, height: 540, child: CustomPaint(painter: _EggPainter(t.body, t.ink))),
      Positioned(left: 116, top: 196, width: 288, height: 256, child: _screenFrame()),
      Positioned(
        left: 116,
        top: 474,
        width: 104,
        height: 86,
        child: Row(children: [
          Expanded(child: _rocker(-1, '◀', const BorderRadius.horizontal(left: Radius.circular(30)))),
          Expanded(child: _rocker(1, '▶', const BorderRadius.horizontal(right: Radius.circular(30)))),
        ]),
      ),
      Positioned(
        left: 228,
        top: 488,
        width: 64,
        height: 90,
        child: _button('TYPE', const Color(0xFF7CE0FF), keys.live ? () => deviceAct(keys, kPickChars[_i]) : null, autofocus: true),
      ),
      Positioned(left: 312, top: 474, width: 64, height: 90, child: _button('SEND', const Color(0xFFFF7AB6), keys.live ? () => deviceAct(keys, 'send') : null)),
      Positioned(left: 236, top: 590, width: 48, height: 30, child: _endHole()),
    ]);
  }

  Widget _ring() => Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.elliptical(38, 46)),
          border: Border.all(color: const Color(0xFFC9CDD2), width: 9),
          boxShadow: [BoxShadow(color: widget.t.ink, spreadRadius: 3)],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.elliptical(38, 46)),
          border: Border.all(color: const Color(0xFFE9ECEF), width: 3),
        ),
      );

  Widget _clasp() => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFC9CDD2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: widget.t.ink, width: 3),
        ),
      );

  Widget _screenFrame() {
    final t = widget.t, keys = widget.keys;
    final p = widget.power.clamp(0.0, 1.0);
    final n = kPickChars.length;
    final pix = TextStyle(color: t.screenInk, fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'monospace', height: 1);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E6FF),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: t.ink, width: 5),
      ),
      child: Container(
        decoration: BoxDecoration(color: Color.lerp(t.screenOff, t.screenOn, p), borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(fit: StackFit.expand, children: [
            Opacity(
              opacity: p,
              child: Column(children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                    child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: 300, height: 206, child: widget.screen)),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: Row(children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Transform.translate(
                        offset: Offset(0, _i.isEven ? 0 : -3),
                        child: CustomPaint(size: const Size(50, 40), painter: _PetPainter(t.screenInk)),
                      ),
                    ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('◀', style: pix),
                          for (var d = -2; d <= 2; d++)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              color: d == 0 ? t.screenInk : null,
                              child: Text(pickGlyph(keys, kPickChars[(_i + d) % n]),
                                  style: pix.copyWith(color: d == 0 ? t.screenOn : t.screenInk)),
                            ),
                          Text('▶', style: pix),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
            IgnorePointer(child: CustomPaint(painter: PixelGridPainter(t.screenInk.withValues(alpha: 0.07)))),
            const InnerShadow(depth: 0.35),
          ]),
        ),
      ),
    );
  }

  Widget _rocker(int d, String glyph, BorderRadius r) {
    final t = widget.t, keys = widget.keys;
    const yellow = Color(0xFFFFE066);
    return DeviceKey(
      semantics: d < 0 ? 'Previous letter' : 'Next letter',
      feel: keys.feel,
      onTap: keys.live ? () => _step(d) : null,
      builder: (f, down) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 58,
          transform: Matrix4.translationValues(0, down ? 4 : 0, 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [shade(yellow, 0.5), yellow, shade(yellow, -0.15)]),
            border: Border.all(color: f ? t.focus : t.ink, width: f ? 6 : 5),
            boxShadow: down ? null : [BoxShadow(color: t.ink, offset: const Offset(0, 5))],
          ),
          child: Text(glyph, style: TextStyle(color: t.ink, fontSize: 20, fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  Widget _button(String label, Color c, VoidCallback? onTap, {bool autofocus = false}) {
    final t = widget.t;
    return DeviceKey(
      semantics: label,
      autofocus: autofocus,
      feel: widget.keys.feel,
      onTap: onTap,
      builder: (f, down) => Column(mainAxisSize: MainAxisSize.min, children: [
        _circleButton(60, c, t.ink, down: down, focused: f, focus: t.focus),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: t.ink, fontSize: 13, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _endHole() {
    final t = widget.t;
    return DeviceKey(
      semantics: 'End',
      feel: widget.keys.feel,
      onTap: widget.keys.live ? () => deviceAct(widget.keys, 'end') : null,
      builder: (f, down) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: down ? shade(t.body, -0.4) : shade(t.body, -0.2),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: f ? t.focus : t.ink, width: 3),
        ),
        child: Text('END', style: TextStyle(color: t.ink, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
      ),
    );
  }
}

class _EggPainter extends CustomPainter {
  final Color body, ink;
  _EggPainter(this.body, this.ink);

  static Path egg(Size s) {
    final w = s.width, h = s.height;
    return Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * 0.86, 0, w, h * 0.4, w, h * 0.62)
      ..cubicTo(w, h * 0.86, w * 0.78, h, w / 2, h)
      ..cubicTo(w * 0.22, h, 0, h * 0.86, 0, h * 0.62)
      ..cubicTo(0, h * 0.4, w * 0.14, 0, w / 2, 0)
      ..close();
  }

  @override
  void paint(Canvas c, Size s) {
    final p = egg(s);
    c.drawShadow(p.shift(const Offset(0, 8)), Colors.black, 16, false);
    c.drawPath(p.shift(const Offset(12, 12)), Paint()..color = const Color(0x38000000));
    final rect = Offset.zero & s;
    c.drawPath(
        p,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [shade(body, 0.4), body, shade(body, -0.15)],
            stops: const [0, 0.55, 1],
          ).createShader(rect));
    c.save();
    c.clipPath(p);
    final dot = Paint()..color = const Color(0xB3FFFFFF);
    for (var y = 20.0; y < s.height; y += 40) {
      for (var x = (y ~/ 40).isOdd ? 40.0 : 20.0; x < s.width; x += 40) {
        c.drawCircle(Offset(x, y), 7, dot);
      }
    }
    c.drawOval(Rect.fromLTWH(s.width * 0.18, s.height * 0.08, 46, 70), Paint()..color = const Color(0x99FFFFFF));
    c.restore();
    c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = ink);
  }

  @override
  bool shouldRepaint(_EggPainter old) => old.body != body || old.ink != ink;
}

/// The little pixel pet (10 × 8).
class _PetPainter extends CustomPainter {
  final Color ink;
  _PetPainter(this.ink);

  static const _pix = ['..XX..XX..', '.X..XX..X.', 'X........X', 'X.X....X.X', 'X........X', 'X..XXXX..X', '.X......X.', '..XXXXXX..'];

  @override
  void paint(Canvas c, Size s) {
    final px = min(s.width / 10, s.height / 8);
    final p = Paint()..color = ink;
    for (var y = 0; y < _pix.length; y++) {
      for (var x = 0; x < _pix[y].length; x++) {
        if (_pix[y][x] == 'X') c.drawRect(Rect.fromLTWH(x * px, y * px, px, px), p);
      }
    }
  }

  @override
  bool shouldRepaint(_PetPainter old) => old.ink != ink;
}

// =================================================================== 12 wide T9

/// Wide sky-blue phone for two thumbs: a long screen on top and the T9 keypad
/// in two rows of eight with a half-key gap down the middle.
class WideT9Art extends StatelessWidget {
  static const size = Size(980, 540);
  final PhoneTheme t;
  final double power;
  final PhoneKeys keys;
  final Widget screen;
  const WideT9Art({super.key, required this.t, required this.power, required this.keys, required this.screen});

  /// top: 1 2 3 | 7 8 9 ⌫ Send — bottom: 4 5 6 | * 0 # SPACE
  static List<List<K>> rows(PhoneTheme t, PhoneKeys keys) => [
        [const K('1'), const K('2'), const K('3'), const K.gap(), const K('7'), const K('8'), const K('9'),
          K('clear', label: '⌫', bg: t.softBg, ink: t.softInk), K('send', label: keys.sendLabel, bg: kSendGreen, ink: t.ink)],
        [const K('4'), const K('5'), const K('6'), const K.gap(), const K('*'), const K('0'), const K('#'),
          K('space', label: 'SPACE', flex: 4, bg: t.softBg, ink: t.softInk)],
      ];

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: 20,
        top: 20,
        width: 940,
        height: 480,
        child: ToonBody(
          colors: toonShades(t.body, light: 0.35, dark: 0.15),
          ink: t.ink,
          radius: const BorderRadius.vertical(top: Radius.circular(60), bottom: Radius.circular(90)),
          child: Stack(children: [
            Positioned(left: 30, top: 88, width: 62, height: 118, child: toonGrille(t.ink, radius: 14)),
            Positioned(right: 30, top: 88, width: 62, height: 118, child: toonGrille(t.ink, radius: 14)),
            Positioned(
              left: 120,
              right: 120,
              top: 22,
              height: 220,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0x2E000000), borderRadius: BorderRadius.circular(24), border: Border.all(color: t.ink, width: 5)),
                child: toonScreen(t, power, screen, radius: 14, border: 0),
              ),
            ),
            Positioned(left: 22, top: 222, width: 86, child: toonPill(t, keys, 'end', 'End', kEndRed, t.ink, height: 40, font: 16)),
            Positioned(right: 22, top: 222, width: 86, child: toonPill(t, keys, 'mode', keys.modeLabel, t.softBg, t.softInk, height: 40, font: 16)),
            Positioned(left: 44, right: 44, top: 282, height: 160, child: ToonGrid(t: t, keys: keys, rows: rows(t, keys), hGap: 10, vGap: 12)),
          ]),
        ),
      ),
    ]);
  }
}
