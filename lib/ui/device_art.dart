import 'dart:math';

import 'package:flutter/material.dart';

import '../app/t9.dart';
import 'phone_art.dart';
import 'phone_theme.dart';

/// Gadgets drawn to look like real hardware (original designs, no real logos
/// or brand names): a wide flip phone, a tube TV with a console keyboard, a
/// thumb-keyboard "pocket mail" phone, a click-wheel music player with an
/// aluminium keyboard that slides up over the wheel, and a green-screen
/// handheld with a name-entry letter box.
///
/// Each is drawn at a fixed design size; [PhoneArt] puts it in a FittedBox.

// =================================================================== keys

/// Runs a key: 'send' and 'end' use their own callbacks, the rest are typed.
void deviceAct(PhoneKeys k, String id) {
  switch (id) {
    case 'send':
      k.send?.call();
    case 'end':
      k.end?.call();
    case 'clear':
      k.clear?.call();
    case 'mode':
      k.mode?.call();
    default:
      k.press?.call(id);
  }
}

/// A focusable key whose look is up to the gadget. D-pad/arrows move between
/// keys, A/Enter presses.
class DeviceKey extends StatefulWidget {
  final VoidCallback? onTap;
  final void Function({bool pad})? feel;
  final bool autofocus;
  final String semantics;
  final Widget Function(bool focused, bool down) builder;
  const DeviceKey({
    super.key,
    required this.semantics,
    required this.builder,
    this.onTap,
    this.feel,
    this.autofocus = false,
  });

  /// A key wired to [keys] for [id].
  factory DeviceKey.of(PhoneKeys keys, String id, String label,
          {bool autofocus = false, required Widget Function(bool focused, bool down) builder}) =>
      DeviceKey(
        semantics: label,
        autofocus: autofocus,
        feel: keys.feel,
        onTap: keys.live ? () => deviceAct(keys, id) : null,
        builder: builder,
      );

  @override
  State<DeviceKey> createState() => _DeviceKeyState();
}

class _DeviceKeyState extends State<DeviceKey> {
  bool _focused = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final face = widget.builder(_focused, _down);
    if (widget.onTap == null) return Semantics(label: widget.semantics, child: face);
    return Semantics(
      button: true,
      label: widget.semantics,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        onFocusChange: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.feel?.call(pad: true);
            widget.onTap!();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            widget.feel?.call(pad: false);
            setState(() => _down = true);
          },
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) {
            setState(() => _down = false);
            widget.onTap!();
          },
          child: face,
        ),
      ),
    );
  }
}

// =================================================================== materials

/// Lighter (amt > 0) or darker (amt < 0).
Color shade(Color c, double amt) => Color.lerp(c, amt > 0 ? Colors.white : Colors.black, amt.abs())!;

const _dropShadow = [
  BoxShadow(color: Color(0x55000000), blurRadius: 34, spreadRadius: 1, offset: Offset(0, 16)),
  BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
];

/// Molded plastic: soft top light, darker bottom, a bevelled edge and a faint
/// grain.
class Molded extends StatelessWidget {
  final Color color;
  final BorderRadius radius;
  final Widget? child;
  final EdgeInsets padding;
  final double sheen;
  final bool shadow;
  final bool grain;
  final Color? edge;
  final double bevel;
  const Molded({
    super.key,
    required this.color,
    required this.radius,
    this.child,
    this.padding = EdgeInsets.zero,
    this.sheen = 0.14,
    this.shadow = true,
    this.grain = true,
    this.edge,
    this.bevel = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: const Alignment(-0.35, -1),
          end: const Alignment(0.35, 1),
          colors: [shade(color, sheen), color, shade(color, -sheen)],
          stops: const [0, 0.45, 1],
        ),
        border: Border.all(color: edge ?? shade(color, -0.5), width: 1.5),
        boxShadow: shadow ? _dropShadow : null,
      ),
      child: CustomPaint(
        foregroundPainter: BevelPainter(radius, width: bevel),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(children: [
            if (grain) Positioned.fill(child: CustomPaint(painter: GrainPainter(color.toARGB32()))),
            Padding(padding: padding, child: child ?? const SizedBox.expand()),
          ]),
        ),
      ),
    );
  }
}

/// Light catching the top edge, shade on the bottom edge.
class BevelPainter extends CustomPainter {
  final BorderRadius radius;
  final double width;
  final double light, dark;
  final bool inset;
  BevelPainter(this.radius, {this.width = 3, this.light = 0.5, this.dark = 0.35, this.inset = false});

  @override
  void paint(Canvas c, Size s) {
    final rect = Offset.zero & s;
    final rr = radius.toRRect(rect).deflate(width / 2 + 1);
    final top = Colors.white.withValues(alpha: light), bottom = Colors.black.withValues(alpha: dark);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: inset ? [bottom, Colors.transparent, Colors.transparent, top] : [top, Colors.transparent, Colors.transparent, bottom],
        stops: const [0, 0.22, 0.75, 1],
      ).createShader(rect);
    c.drawRRect(rr, p);
  }

  @override
  bool shouldRepaint(BevelPainter old) => old.radius != radius || old.width != width || old.inset != inset;
}

/// Very faint speckle, like textured plastic.
class GrainPainter extends CustomPainter {
  final int seed;
  GrainPainter(this.seed);

  @override
  void paint(Canvas c, Size s) {
    final rnd = Random(seed);
    final n = (s.width * s.height / 160).clamp(0, 6000).toInt();
    final dark = Paint()..color = const Color(0x0C000000);
    final light = Paint()..color = const Color(0x0EFFFFFF);
    for (var i = 0; i < n; i++) {
      c.drawCircle(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height), rnd.nextDouble() * 1.1 + 0.3,
          rnd.nextBool() ? dark : light);
    }
  }

  @override
  bool shouldRepaint(GrainPainter old) => old.seed != seed;
}

/// Fine horizontal brushing on aluminium.
class BrushedPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final rnd = Random(3);
    for (var y = 0.0; y < s.height; y += 1.5) {
      final a = rnd.nextDouble() * 0.06;
      c.drawLine(Offset(0, y), Offset(s.width, y),
          Paint()..color = (rnd.nextBool() ? Colors.white : Colors.black).withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(BrushedPainter old) => false;
}

/// Glossy glass: a soft sheet of light across the top-left, with a sharp edge.
class GlassGlare extends StatelessWidget {
  final double strength;
  const GlassGlare({super.key, this.strength = 1});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.26 * strength),
                Colors.white.withValues(alpha: 0.07 * strength),
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const [0, 0.42, 0.43, 1],
            ),
          ),
        ),
      );
}

/// Shadow cast into a recess from its top edge.
class InnerShadow extends StatelessWidget {
  final double depth;
  const InnerShadow({super.key, this.depth = 0.5});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: depth), Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: depth * 0.3)],
              stops: const [0, 0.09, 0.92, 1],
            ),
          ),
        ),
      );
}

/// A fine LCD pixel grid.
class PixelGridPainter extends CustomPainter {
  final Color color;
  final double step;
  PixelGridPainter(this.color, {this.step = 3});

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 0.7;
    for (var x = 0.0; x < s.width; x += step) {
      c.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    for (var y = 0.0; y < s.height; y += step) {
      c.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(PixelGridPainter old) => old.color != color || old.step != step;
}

/// Rows of little round speaker holes.
class GrillePainter extends CustomPainter {
  final double gap;
  final double r;
  GrillePainter({this.gap = 9, this.r = 2.3});

  @override
  void paint(Canvas c, Size s) {
    final hole = Paint()..color = const Color(0xD0000000);
    final lip = Paint()..color = const Color(0x40FFFFFF);
    var row = 0;
    for (var y = r + 1; y < s.height - r; y += gap * 0.87, row++) {
      for (var x = r + 1 + (row.isOdd ? gap / 2 : 0); x < s.width - r; x += gap) {
        c.drawCircle(Offset(x, y + 0.8), r, lip);
        c.drawCircle(Offset(x, y), r, hole);
      }
    }
  }

  @override
  bool shouldRepaint(GrillePainter old) => false;
}

/// Polished chrome / steel.
const _chrome = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFF4F6F8), Color(0xFF8C939D), Color(0xFFE9ECEF), Color(0xFF6E757F), Color(0xFFD7DBE0)],
  stops: [0, 0.28, 0.5, 0.74, 1],
);

/// A raised key. [c] is the cap colour.
BoxDecoration keycap(Color c,
    {required BorderRadius r, bool down = false, bool focused = false, Color focus = const Color(0xFF3B82F6), Color? edge}) {
  return BoxDecoration(
    borderRadius: r,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: down ? [shade(c, -0.16), shade(c, -0.06), shade(c, -0.02)] : [shade(c, 0.24), c, shade(c, -0.16)],
      stops: const [0, 0.55, 1],
    ),
    border: Border.all(color: focused ? focus : (edge ?? shade(c, -0.55)), width: focused ? 3 : 1.2),
    boxShadow: [
      if (!down) const BoxShadow(color: Color(0x73000000), offset: Offset(0, 2.5), blurRadius: 2.5),
      if (focused) BoxShadow(color: focus.withValues(alpha: 0.6), blurRadius: 12),
    ],
  );
}

Widget _fit(String s, TextStyle style) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Text(s, style: style, maxLines: 1)),
    );

/// A screen: dark when off, lights up with [power]; recessed, with glass on top.
Widget lcd(PhoneTheme t, double power, Widget screen,
    {required BorderRadius radius,
    EdgeInsets padding = const EdgeInsets.fromLTRB(12, 8, 12, 8),
    bool grid = false,
    Widget? header,
    double glare = 1}) {
  final p = power.clamp(0.0, 1.0);
  return Container(
    decoration: BoxDecoration(color: Color.lerp(t.screenOff, t.screenOn, p), borderRadius: radius),
    child: ClipRRect(
      borderRadius: radius,
      child: Stack(fit: StackFit.expand, children: [
        Opacity(
          opacity: p,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (header != null) header,
            Expanded(child: Padding(padding: padding, child: ClipRect(child: screen))),
          ]),
        ),
        if (grid) IgnorePointer(child: CustomPaint(painter: PixelGridPainter(t.screenInk.withValues(alpha: 0.07)))),
        const InnerShadow(depth: 0.45),
        GlassGlare(strength: glare),
      ]),
    ),
  );
}

/// Phone status bar: signal bars, a label, battery.
Widget statusBar(Color ink, {String label = 'AIM', double height = 26}) {
  Widget bar(double h) => Container(width: 4, height: h, margin: const EdgeInsets.only(right: 2), color: ink);
  return SizedBox(
    height: height,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [bar(5), bar(8), bar(11), bar(14)]),
        ),
        Expanded(
          child: Center(
            child: Text(label, style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700, height: 1)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(children: [
            Container(
              width: 24,
              height: 12,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(border: Border.all(color: ink, width: 1.5), borderRadius: BorderRadius.circular(2)),
              child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: 0.75, child: Container(color: ink))),
            ),
            Container(width: 2.5, height: 5, color: ink),
          ]),
        ),
      ]),
    ),
  );
}

/// A little screw head.
Widget screw({double size = 14}) => Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(center: Alignment(-0.4, -0.4), colors: [Color(0xFFE6E8EB), Color(0xFF7D838C), Color(0xFF3E434A)]),
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 1, offset: Offset(0, 1))],
      ),
      alignment: Alignment.center,
      child: Transform.rotate(angle: 0.6, child: Container(width: size * 0.7, height: 1.6, color: const Color(0xFF2C3036))),
    );

// =================================================================== wide flip

/// Keypad phone in gunmetal that, with the keyboard setting on, opens the
/// long way like a tiny laptop: wide screen on top, keyboard below.
class WideFlipArt extends StatelessWidget {
  final PhoneTheme t;
  final bool letters;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const WideFlipArt(
      {super.key, required this.t, required this.letters, required this.open, required this.power, required this.keys, required this.screen});

  static const _metal = Color(0xFF474E58);
  static const _silverKey = Color(0xFFC3C9D1);
  static const _keyInk = Color(0xFF16191E);

  @override
  Widget build(BuildContext context) => letters ? _opened() : _front();

  Widget _earpiece(double w) => Container(
        width: w,
        height: 10,
        decoration: BoxDecoration(
            color: const Color(0xFF15181C), borderRadius: BorderRadius.circular(5), border: Border.all(color: const Color(0xFF6E7681))),
        child: CustomPaint(painter: GrillePainter(gap: 6, r: 1.4)),
      );

  Widget _screenWell(Widget child) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF80878F), width: 1.5),
        ),
        child: child,
      );

  Widget _t9Key(String k) {
    final sub = switch (k) {
      '1' => '.,?!',
      '0' => '␣',
      '*' => keys.predictive ? 'next' : '',
      '#' => 'mode',
      _ => (kT9Letters[k] ?? '').toUpperCase(),
    };
    return DeviceKey.of(
      keys,
      k,
      'Key $k',
      autofocus: k == '5',
      builder: (f, d) => Container(
        decoration: keycap(_silverKey, r: BorderRadius.circular(16), down: d, focused: f, focus: t.focus),
        alignment: Alignment.center,
        child: FittedBox(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(k, style: const TextStyle(color: _keyInk, fontSize: 28, fontWeight: FontWeight.w600, height: 1)),
            if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Color(0xFF4C5561), fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _pillKey(String id, String label, Color c, {IconData? icon, Color ink = Colors.white}) => DeviceKey.of(
        keys,
        id,
        label,
        builder: (f, d) => Container(
          decoration: keycap(c, r: BorderRadius.circular(30), down: d, focused: f, focus: t.focus),
          alignment: Alignment.center,
          child: icon != null ? Icon(icon, color: ink, size: 26) : _fit(label, TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      );

  /// Closed: a keypad phone (T9).
  Widget _front() {
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: 15,
        top: 15,
        width: 440,
        height: 760,
        child: Molded(
          color: _metal,
          sheen: 0.2,
          radius: BorderRadius.circular(54),
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
          child: Column(children: [
            _earpiece(96),
            const SizedBox(height: 12),
            SizedBox(
              height: 288,
              child: _screenWell(lcd(t, power, screen, radius: BorderRadius.circular(8), header: statusBar(t.screenInk))),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 118,
              child: Row(children: [
                Expanded(
                  child: Column(children: [
                    Expanded(child: _pillKey('mode', keys.modeLabel, const Color(0xFF8E98A6), ink: _keyInk)),
                    const SizedBox(height: 8),
                    Expanded(child: _pillKey('send', keys.sendLabel, const Color(0xFF2FA65A), icon: Icons.call)),
                  ]),
                ),
                const SizedBox(width: 12),
                _navRing(118),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(children: [
                    Expanded(child: _pillKey('clear', 'Clear', const Color(0xFF8E98A6), ink: _keyInk)),
                    const SizedBox(height: 8),
                    Expanded(child: _pillKey('end', 'End', const Color(0xFFD9433E), icon: Icons.call_end)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Column(children: [
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['*', '0', '#'],
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: _t9Key(row[i])),
                        ],
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF15181C), shape: BoxShape.circle)),
          ]),
        ),
      ),
    ]);
  }

  /// Round 4-way pad with an OK button (OK sends).
  Widget _navRing(double d) => SizedBox(
        width: d,
        height: d,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _chrome, boxShadow: [
              BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2)),
            ]),
          ),
          Container(
            width: d - 12,
            height: d - 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: Alignment(0, -0.5), colors: [Color(0xFF5B636E), Color(0xFF2A2F36)]),
            ),
          ),
          for (final (a, ic) in const [
            (Alignment.topCenter, Icons.arrow_drop_up),
            (Alignment.bottomCenter, Icons.arrow_drop_down),
            (Alignment.centerLeft, Icons.arrow_left),
            (Alignment.centerRight, Icons.arrow_right),
          ])
            Align(alignment: a, child: Padding(padding: const EdgeInsets.all(8), child: Icon(ic, color: const Color(0xFFB9C0C9), size: 22))),
          SizedBox(
            width: d * 0.42,
            height: d * 0.42,
            child: DeviceKey.of(
              keys,
              'send',
              'OK',
              builder: (f, dn) => Container(
                decoration: keycap(_silverKey, r: BorderRadius.circular(d), down: dn, focused: f, focus: t.focus),
                alignment: Alignment.center,
                child: const Text('OK', style: TextStyle(color: _keyInk, fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      );

  /// Open: lid swings up from lying over the keyboard.
  Widget _opened() {
    const w = 820.0, left = 10.0, lidTop = 20.0, lidH = 330.0, hingeH = 24.0, baseH = 326.0;
    const baseTop = lidTop + lidH + hingeH;
    final angle = (1 - open) * pi;
    final showBack = angle > pi / 2;
    final inside = Molded(
      color: _metal,
      sheen: 0.18,
      radius: const BorderRadius.vertical(top: Radius.circular(44), bottom: Radius.circular(16)),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Row(children: [
        SizedBox(
          width: 40,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            RotatedBox(quarterTurns: 1, child: _earpiece(80)),
            const SizedBox(height: 26),
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(center: Alignment(-0.3, -0.3), colors: [Color(0xFF6C8CB8), Color(0xFF0B0F18)]),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(child: _screenWell(lcd(t, power, screen, radius: BorderRadius.circular(8), header: statusBar(t.screenInk)))),
        const SizedBox(width: 16),
        SizedBox(
          width: 100,
          child: Column(children: [
            Expanded(child: _pillKey('send', keys.sendLabel, const Color(0xFF2FA65A))),
            const SizedBox(height: 10),
            Expanded(child: _pillKey('del', 'Clear', const Color(0xFF8E98A6), ink: _keyInk)),
            const SizedBox(height: 10),
            Expanded(child: _pillKey('end', 'End', const Color(0xFFD9433E))),
          ]),
        ),
      ]),
    );
    // The outside of the lid (a keypad phone turned sideways), seen while shut.
    final outside = Molded(
      color: _metal,
      sheen: 0.18,
      radius: const BorderRadius.vertical(top: Radius.circular(44), bottom: Radius.circular(16)),
      padding: const EdgeInsets.all(26),
      child: Row(children: [
        SizedBox(
          width: 250,
          child: _screenWell(Container(
            decoration: BoxDecoration(color: t.screenOff, borderRadius: BorderRadius.circular(8)),
            child: const Stack(fit: StackFit.expand, children: [InnerShadow(), GlassGlare()]),
          )),
        ),
        const SizedBox(width: 26),
        Expanded(
          child: Column(children: [
            for (final row in const [
              ['1', '2', '3', '*'],
              ['4', '5', '6', '0'],
              ['7', '8', '9', '#'],
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    for (final k in row)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: keycap(_silverKey, r: BorderRadius.circular(14)),
                          alignment: Alignment.center,
                          child: Text(k, style: const TextStyle(color: _keyInk, fontSize: 24, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: left,
        top: baseTop,
        width: w,
        height: baseH,
        child: Molded(
          color: _metal,
          sheen: 0.16,
          radius: const BorderRadius.vertical(top: Radius.circular(16), bottom: Radius.circular(44)),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: _keyboard(),
        ),
      ),
      // hinge barrel
      Positioned(
        left: left + 60,
        top: lidTop + lidH - 6,
        width: w - 120,
        height: hingeH + 12,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2A2F36), width: 1.5),
            gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF5E6670), Color(0xFFDDE2E8), Color(0xFF8A929C), Color(0xFF3B4149)],
                stops: [0, 0.35, 0.6, 1]),
          ),
        ),
      ),
      Positioned(
        left: left,
        top: lidTop,
        width: w,
        height: lidH,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0009)
            ..rotateX(-angle),
          child: showBack ? Transform(alignment: Alignment.center, transform: Matrix4.rotationX(pi), child: outside) : inside,
        ),
      ),
    ]);
  }

  Widget _keyboard() {
    final letters = keys.sym ? kQwertySymbols : kQwertyLetters;
    Widget k(String id, String label, {int flex = 10, Color? c, Color ink = _keyInk, bool autofocus = false, double font = 22}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            child: DeviceKey.of(
              keys,
              id,
              label,
              autofocus: autofocus,
              builder: (f, d) => Container(
                decoration: keycap(c ?? _silverKey, r: BorderRadius.circular(9), down: d, focused: f, focus: t.focus),
                alignment: Alignment.center,
                child: _fit(label, TextStyle(color: ink, fontSize: font, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        );
    Widget row(List<Widget> c, {double pad = 0}) => Expanded(
        child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: c)));
    const dark = Color(0xFF5B636E);
    return Column(children: [
      row([for (final c in kQwertyNumbers) k(c, c, c: const Color(0xFF9AA3AE), font: 19)]),
      row([for (final c in letters[0]) k(c, keys.cased(c))]),
      row([for (final c in letters[1]) k(c, keys.cased(c), autofocus: c == 'g')], pad: 30),
      row([
        k('shift', 'shift', flex: 16, c: keys.shift || keys.caps ? t.softBg : dark, ink: Colors.white, font: 16),
        for (final c in letters[2]) k(c, keys.cased(c)),
        k('del', 'del', flex: 16, c: dark, ink: Colors.white, font: 16),
      ]),
      row([
        k('sym', keys.sym ? 'abc' : 'sym', flex: 14, c: keys.sym ? t.softBg : dark, ink: Colors.white, font: 16),
        k(':)', ':)', flex: 10, c: dark, ink: Colors.white, font: 18),
        k('space', 'space', flex: 48, font: 15),
        k('send', '${keys.sendLabel} ⏎', flex: 22, c: const Color(0xFF2FA65A), ink: Colors.white, font: 16),
      ]),
    ]);
  }
}

// =================================================================== console TV

/// A chunky tube TV with the chat on it; a glowing green console keyboard
/// panel slides up underneath. The TV switches on like an old CRT: a thin
/// line that opens into the picture.
class DashboardArt extends StatelessWidget {
  static const size = Size(880, 940);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const DashboardArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  static const lime = Color(0xFF9CFF5E);

  static const _letters = [
    ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
    ['h', 'i', 'j', 'k', 'l', 'm', 'n'],
    ['o', 'p', 'q', 'r', 's', 't', 'u'],
    ['v', 'w', 'x', 'y', 'z', "'", '-'],
    ['1', '2', '3', '4', '5', '6', '7'],
    ['8', '9', '0', '.', ',', '?', '!'],
  ];
  static const _symbols = [
    ['@', '#', '\$', '%', '^', '&', '*'],
    ['(', ')', '_', '=', '+', '[', ']'],
    ['{', '}', ';', ':', '"', '<', '>'],
    ['/', '\\', '|', '~', '`', ':)', ';)'],
    ['1', '2', '3', '4', '5', '6', '7'],
    ['8', '9', '0', '.', ',', '?', '!'],
  ];

  @override
  Widget build(BuildContext context) {
    final slide = Curves.easeOutCubic.transform(open.clamp(0.0, 1.0));
    return Stack(clipBehavior: Clip.none, children: [
      // stand
      Positioned(
        left: 300,
        top: 548,
        width: 280,
        height: 52,
        child: Molded(color: const Color(0xFF26262A), radius: const BorderRadius.vertical(bottom: Radius.circular(14), top: Radius.circular(4))),
      ),
      Positioned(
        left: 60,
        top: 16,
        width: 760,
        height: 556,
        child: Molded(
          color: const Color(0xFF34343A),
          sheen: 0.12,
          radius: BorderRadius.circular(40),
          child: Stack(children: [
            // the recess around the tube
            Positioned(
              left: 30,
              top: 26,
              right: 30,
              bottom: 96,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(46),
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A0A0C), Color(0xFF26262B)]),
                  border: Border.all(color: const Color(0xFF4A4A52), width: 1.5),
                ),
                padding: const EdgeInsets.all(14),
                child: _tube(),
              ),
            ),
            Positioned(left: 36, right: 36, bottom: 22, height: 56, child: _frontPanel()),
          ]),
        ),
      ),
      // keyboard panel
      Positioned(
        left: 0,
        top: 584 + (1 - slide) * 420,
        width: 880,
        height: 346,
        child: IgnorePointer(
          ignoring: open < 0.95,
          child: Opacity(opacity: slide.clamp(0.0, 1.0), child: _panel()),
        ),
      ),
    ]);
  }

  Widget _tube() {
    final crt = power.clamp(0.0, 1.0);
    final px = (crt / 0.35).clamp(0.0, 1.0); // a line grows across...
    final py = ((crt - 0.35) / 0.65).clamp(0.0, 1.0); // ...then opens up
    final sy = 0.008 + 0.992 * Curves.easeOutCubic.transform(py);
    final flash = crt <= 0 ? 0.0 : 1 - py;
    return ClipRRect(
      borderRadius: BorderRadius.circular(38),
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Color(0xFF0B0E0B)),
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(max(0.001, px), sy, 1),
          child: Stack(fit: StackFit.expand, children: [
            Container(
              color: Color.lerp(t.screenOff, t.screenOn, py),
              padding: const EdgeInsets.fromLTRB(42, 30, 42, 28),
              child: Opacity(opacity: py, child: screen),
            ),
            if (flash > 0) ColoredBox(color: Colors.white.withValues(alpha: 0.92 * flash)),
          ]),
        ),
        IgnorePointer(child: CustomPaint(painter: _ScanlinePainter())),
        // the tube's curve: dark corners, a bulge of light
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(radius: 0.9, colors: [Color(0x00000000), Color(0x00000000), Color(0xB0000000)], stops: [0, 0.6, 1]),
            ),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                  center: Alignment(-0.55, -0.65), radius: 0.7, colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)]),
            ),
          ),
        ),
        const GlassGlare(strength: 0.45),
      ]),
    );
  }

  Widget _frontPanel() {
    final on = power > 0.05;
    Widget btn(double w) => Container(
          width: w,
          height: 18,
          margin: const EdgeInsets.only(left: 10),
          decoration: keycap(const Color(0xFF55555C), r: BorderRadius.circular(6)),
        );
    return Row(children: [
      SizedBox(width: 170, height: 46, child: CustomPaint(painter: GrillePainter(gap: 8, r: 2.2))),
      const SizedBox(width: 24),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFF070907), borderRadius: BorderRadius.circular(4)),
        child: Text('CH 03',
            style: TextStyle(
                color: on ? const Color(0xFF7CFFB0) : const Color(0xFF16301E),
                fontSize: 18,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                shadows: on ? const [Shadow(color: Color(0xAA7CFFB0), blurRadius: 6)] : null)),
      ),
      const Spacer(),
      btn(34),
      btn(34),
      btn(34),
      const SizedBox(width: 18),
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? const Color(0xFF55FF6A) : const Color(0xFF213A22),
          boxShadow: on ? const [BoxShadow(color: Color(0xAA55FF6A), blurRadius: 8)] : null,
        ),
      ),
      const SizedBox(width: 10),
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFF76767E), Color(0xFF26262A)]),
          border: Border.all(color: const Color(0xFF111113), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 2))],
        ),
        child: const Icon(Icons.power_settings_new, color: Color(0xFFB7B7BE), size: 22),
      ),
    ]);
  }

  Widget _panel() {
    final rows = keys.sym ? _symbols : _letters;
    const actions = [
      ('send', 'Done'),
      ('space', 'Space'),
      ('del', 'Backspace'),
      ('caps', 'Caps'),
      ('sym', 'Symbols'),
      ('end', 'Close'),
    ];
    return Container(
      decoration: BoxDecoration(
        gradient: const RadialGradient(center: Alignment(0, -0.9), radius: 1.4, colors: [Color(0xFF2A6B1C), Color(0xFF0B260A), Color(0xFF031003)], stops: [0, 0.55, 1]),
        borderRadius: BorderRadius.circular(44),
        border: Border.all(color: lime.withValues(alpha: 0.9), width: 3),
        boxShadow: [BoxShadow(color: lime.withValues(alpha: 0.35), blurRadius: 32), ..._dropShadow],
      ),
      child: CustomPaint(
        foregroundPainter: BevelPainter(BorderRadius.circular(44), width: 4, light: 0.35, dark: 0.4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              flex: 7,
              child: Column(children: [
                for (final row in rows)
                  Expanded(
                    child: Row(children: [
                      for (final c in row)
                        Expanded(child: Padding(padding: const EdgeInsets.all(3.5), child: _jewel(c, keys.cased(c), autofocus: c == 'a'))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: Column(children: [
                for (final (id, label) in actions)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3.5),
                      child: _jewel(id, id == 'sym' && keys.sym ? 'ABC' : label,
                          lit: (id == 'caps' && keys.caps) || (id == 'sym' && keys.sym), function: true),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// A glassy green jewel key with a highlight across its top half.
  Widget _jewel(String id, String label, {bool lit = false, bool autofocus = false, bool function = false}) => DeviceKey.of(
        keys,
        id,
        label,
        autofocus: autofocus,
        builder: (f, d) {
          final colors = f
              ? const [Color(0xFFF6FFB0), Color(0xFFC9F25A), Color(0xFF7DBA1E)]
              : d
                  ? const [Color(0xFF2E7A16), Color(0xFF1E5A0C), Color(0xFF143E08)]
                  : function
                      ? (lit
                          ? const [Color(0xFF9BE46A), Color(0xFF4FAE24), Color(0xFF2A7A10)]
                          : const [Color(0xFF3C5A3A), Color(0xFF213A20), Color(0xFF142612)])
                      : const [Color(0xFF86E85A), Color(0xFF3EA81E), Color(0xFF1E6A0C)];
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors, stops: const [0, 0.55, 1]),
              border: Border.all(color: f ? const Color(0xFFFFFFD0) : const Color(0xFF041A04), width: f ? 2.5 : 1.5),
              boxShadow: [
                if (!d) const BoxShadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 3)),
                if (f) const BoxShadow(color: Color(0xCCD8FF6A), blurRadius: 18),
              ],
            ),
            child: Stack(fit: StackFit.expand, children: [
              // glassy highlight
              Positioned(
                left: 6,
                right: 6,
                top: 3,
                height: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withValues(alpha: d ? 0.1 : 0.45), Colors.white.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
              Center(
                child: _fit(
                  label,
                  TextStyle(
                    color: f ? const Color(0xFF15330A) : (function && !lit ? lime : Colors.white),
                    fontSize: function ? 20 : 26,
                    fontWeight: FontWeight.w700,
                    shadows: f ? null : const [Shadow(color: Color(0xCC000000), offset: Offset(0, 1.5), blurRadius: 2)],
                  ),
                ),
              ),
            ]),
          );
        },
      );
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0x33000000);
    for (var y = 0.0; y < s.height; y += 4) {
      c.drawRect(Rect.fromLTWH(0, y, s.width, 2), p);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}

// =================================================================== pocket mail

/// A glossy black thumb-keyboard phone with a chrome rim: earpiece and message
/// light, screen, a call / menu / trackball / back / end row, and keys with
/// little blue number/symbol labels between chrome frets.
class PocketMailArt extends StatelessWidget {
  static const size = Size(520, 900);
  final PhoneTheme t;
  final double power;
  final PhoneKeys keys;
  final Widget screen;
  const PocketMailArt({super.key, required this.t, required this.power, required this.keys, required this.screen});

  static const _alt = {
    'q': '#', 'w': '1', 'e': '2', 'r': '3', 't': '(', 'y': ')', 'u': '_', 'i': '-', 'o': '+', 'p': '@',
    'a': '*', 's': '4', 'd': '5', 'f': '6', 'g': '/', 'h': ':', 'j': ';', 'k': "'", 'l': '"',
    'z': '7', 'x': '8', 'c': '9', 'v': '?', 'b': '!', 'n': ',', 'm': '.',
  };

  static const _symRows = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['@', '#', '\$', '%', '&', '*', '(', ')', '-'],
    ['!', '?', ',', '.', "'", '"', ':'],
  ];

  static const _blue = Color(0xFF5EB6FF);

  @override
  Widget build(BuildContext context) {
    final p = power.clamp(0.0, 1.0);
    return Stack(clipBehavior: Clip.none, children: [
      // chrome rim
      Positioned(
        left: 16,
        top: 16,
        width: 488,
        height: 868,
        child: Container(
          decoration: BoxDecoration(
            gradient: _chrome,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(62), bottom: Radius.circular(84)),
            boxShadow: _dropShadow,
          ),
        ),
      ),
      Positioned(
        left: 24,
        top: 24,
        width: 472,
        height: 852,
        child: Molded(
          color: const Color(0xFF1B1C21),
          sheen: 0.1,
          shadow: false,
          edge: const Color(0xFF000000),
          radius: const BorderRadius.vertical(top: Radius.circular(56), bottom: Radius.circular(78)),
        ),
      ),
      // earpiece + message light
      Positioned(
        left: 205,
        top: 42,
        width: 110,
        height: 12,
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFF07080A), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF4A4E57))),
          child: CustomPaint(painter: GrillePainter(gap: 6, r: 1.4)),
        ),
      ),
      Positioned(
        left: 430,
        top: 40,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(const Color(0xFF3A0E0E), const Color(0xFFFF2B2B), p),
            border: Border.all(color: const Color(0xFF000000), width: 1.5),
            boxShadow: p > 0.5 ? const [BoxShadow(color: Color(0xCCFF2B2B), blurRadius: 12, spreadRadius: 1)] : null,
          ),
        ),
      ),
      // screen
      Positioned(
        left: 52,
        top: 68,
        width: 416,
        height: 302,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF050506),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF5A5F68), width: 1.5),
          ),
          child: lcd(t, power, screen, radius: BorderRadius.circular(7), header: statusBar(t.screenInk, label: 'AIM')),
        ),
      ),
      // nav row on a chrome strip
      Positioned(
        left: 44,
        top: 386,
        width: 432,
        height: 74,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(gradient: _chrome, borderRadius: BorderRadius.circular(37)),
          child: Row(children: [
            Expanded(child: _navKey('send', 'Send', Icons.call, const Color(0xFF3ED36F), left: true)),
            const SizedBox(width: 3),
            Expanded(child: _navKey('sym', 'Menu', Icons.menu, const Color(0xFFDDE3EA))),
            const SizedBox(width: 6),
            _trackball(),
            const SizedBox(width: 6),
            Expanded(child: _navKey('del', 'Back', Icons.undo, const Color(0xFFDDE3EA))),
            const SizedBox(width: 3),
            Expanded(child: _navKey('end', 'End', Icons.call_end, const Color(0xFFFF5252), right: true)),
          ]),
        ),
      ),
      Positioned(left: 40, top: 474, width: 440, height: 372, child: _keyboard()),
    ]);
  }

  Widget _trackball() => Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0C0D10),
          border: Border.all(color: const Color(0xFF8A919B), width: 2),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(center: Alignment(-0.45, -0.5), radius: 0.9, colors: [Colors.white, Color(0xFFC9D3DE), Color(0xFF5D6B7C)], stops: [0, 0.35, 1]),
            boxShadow: [BoxShadow(color: Color(0x885EB6FF), blurRadius: 10)],
          ),
        ),
      );

  Widget _navKey(String id, String label, IconData icon, Color ink, {bool left = false, bool right = false}) => DeviceKey.of(
        keys,
        id,
        label,
        builder: (f, d) => Container(
          decoration: keycap(
            const Color(0xFF26282E),
            r: BorderRadius.horizontal(left: Radius.circular(left ? 30 : 10), right: Radius.circular(right ? 30 : 10)),
            down: d,
            focused: f,
            focus: t.focus,
            edge: const Color(0xFF000000),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: ink, size: 28),
        ),
      );

  Widget _keyboard() {
    final letters = keys.sym ? _symRows : kQwertyLetters;
    Widget k(String id, String label, {String alt = '', int flex = 10, bool lit = false, bool small = false, bool autofocus = false}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: DeviceKey.of(
              keys,
              id,
              label,
              autofocus: autofocus,
              builder: (f, d) => Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: d
                        ? const [Color(0xFF202227), Color(0xFF34373E)]
                        : lit
                            ? const [Color(0xFF3B5E86), Color(0xFF13263B)]
                            : const [Color(0xFF4A4D55), Color(0xFF17181C), Color(0xFF0A0A0C)],
                  ),
                  // the "frown": flat on top, curling down at the sides
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6), topRight: Radius.circular(6),
                      bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
                  border: Border.all(color: f ? t.focus : const Color(0xFF000000), width: f ? 3 : 1.5),
                  boxShadow: [
                    if (!d) const BoxShadow(color: Color(0xAA000000), offset: Offset(0, 2), blurRadius: 2),
                    if (f) BoxShadow(color: t.focus.withValues(alpha: 0.6), blurRadius: 10),
                  ],
                ),
                child: Stack(children: [
                  if (alt.isNotEmpty)
                    Positioned(left: 6, top: 2, child: Text(alt, style: const TextStyle(color: _blue, fontSize: 13, fontWeight: FontWeight.w700))),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _fit(label, TextStyle(color: Colors.white, fontSize: small ? 16 : 24, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
    Widget fret() => Container(
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(gradient: _chrome, borderRadius: BorderRadius.circular(2)),
        );
    Widget row(List<Widget> c) => Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: c));
    String alt(String c) => keys.sym ? '' : (_alt[c] ?? '');
    return Column(children: [
      row([for (final c in letters[0]) k(c, keys.cased(c), alt: alt(c))]),
      fret(),
      row([for (final c in letters[1]) k(c, keys.cased(c), alt: alt(c), autofocus: c == 'g'), k('del', '⌫', flex: 10)]),
      fret(),
      row([
        k('shift', 'aA', flex: 12, lit: keys.shift, small: true),
        for (final c in letters[2]) k(c, keys.cased(c), alt: alt(c)),
        k('send', '⏎', flex: 16),
      ]),
      fret(),
      row([
        k('sym', keys.sym ? 'abc' : 'sym', flex: 14, lit: keys.sym, small: true),
        k(':)', ':)', flex: 10, small: true),
        k('space', 'space', flex: 44, small: true),
        k('caps', 'CAP', flex: 14, lit: keys.caps, small: true),
      ]),
    ]);
  }
}

// =================================================================== music player

/// A white click-wheel music player on a polished steel back. Its screen comes
/// on first, then an aluminium keyboard with white keys slides up over the
/// wheel, leaving just the screen showing.
class MusicPlayerArt extends StatelessWidget {
  static const size = Size(520, 900);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const MusicPlayerArt(
      {super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  static const _keyText = Color(0xFF4A4D55);
  static const _keyEdge = Color(0xFFB9BCC3);
  static const _wheelGrey = Color(0xFFA3A7AE);

  @override
  Widget build(BuildContext context) {
    final up = Curves.easeOutCubic.transform(open.clamp(0.0, 1.0));
    return Stack(clipBehavior: Clip.none, children: [
      // steel back peeking round the edge
      Positioned(
        left: 14,
        top: 14,
        width: 492,
        height: 872,
        child: Container(
          decoration: BoxDecoration(gradient: _chrome, borderRadius: BorderRadius.circular(64), boxShadow: _dropShadow),
        ),
      ),
      // white glossy front
      Positioned(
        left: 20,
        top: 20,
        width: 480,
        height: 860,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(58),
            gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFFFF), Color(0xFFF3F3F1), Color(0xFFE2E2DF)]),
            border: Border.all(color: const Color(0xFFCFCFCB), width: 1.2),
          ),
          child: CustomPaint(
            foregroundPainter: BevelPainter(BorderRadius.circular(58), width: 3, light: 0.9, dark: 0.12),
            child: ClipRRect(borderRadius: BorderRadius.circular(58), child: const GlassGlare(strength: 0.5)),
          ),
        ),
      ),
      // screen
      Positioned(
        left: 64,
        top: 66,
        width: 392,
        height: 300,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF121417),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBDBDBA), width: 1.5),
          ),
          child: lcd(t, power, screen,
              radius: BorderRadius.circular(4), header: _titleBar(), glare: 0.7, padding: const EdgeInsets.fromLTRB(10, 6, 10, 6)),
        ),
      ),
      Positioned(left: 95, top: 455, width: 330, height: 330, child: _wheel()),
      Positioned(
        left: 10,
        top: 392 + (1 - up) * 480,
        width: 500,
        height: 482,
        child: IgnorePointer(
          ignoring: open < 0.95,
          child: Opacity(opacity: up.clamp(0.0, 1.0), child: _keyboard()),
        ),
      ),
    ]);
  }

  Widget _titleBar() => Container(
        height: 28,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFDFEFF), Color(0xFFC9D3DD)]),
          border: Border(bottom: BorderSide(color: Color(0xFF8C9AA8))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          const Icon(Icons.play_arrow, size: 16, color: Color(0xFF2B6FD6)),
          const Expanded(
              child: Center(
                  child: Text('AIM', style: TextStyle(color: Color(0xFF1B2733), fontSize: 15, fontWeight: FontWeight.w700, height: 1)))),
          Container(
            width: 24,
            height: 11,
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF3A4652)), borderRadius: BorderRadius.circular(2)),
            child: Container(color: const Color(0xFF39B54A)),
          ),
        ]),
      );

  Widget _wheel() {
    return Stack(alignment: Alignment.center, children: [
      Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE7E8EA), Color(0xFFF7F7F8)]),
          border: Border.all(color: const Color(0xFFC6C8CC), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, -1))],
        ),
      ),
      const Positioned(
          top: 22, child: Text('MENU', style: TextStyle(color: _wheelGrey, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.5))),
      const Positioned(left: 20, child: Icon(Icons.fast_rewind, color: _wheelGrey, size: 34)),
      const Positioned(right: 20, child: Icon(Icons.fast_forward, color: _wheelGrey, size: 34)),
      const Positioned(
        bottom: 20,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_arrow, color: _wheelGrey, size: 28),
          Icon(Icons.pause, color: _wheelGrey, size: 26),
        ]),
      ),
      Container(
        width: 124,
        height: 124,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFFFF), Color(0xFFEDEDEB)]),
          border: Border.all(color: const Color(0xFFCDCFD3), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1.5))],
        ),
      ),
    ]);
  }

  Widget _keyboard() {
    final letters = keys.sym ? kQwertySymbols : kQwertyLetters;
    Widget k(String id, String label, {int flex = 10, bool lit = false, bool autofocus = false, double font = 24, Alignment at = Alignment.center}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.all(3.5),
            child: DeviceKey.of(
              keys,
              id,
              label,
              autofocus: autofocus,
              builder: (f, d) => Container(
                alignment: at,
                padding: at == Alignment.center ? null : const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: d
                        ? const [Color(0xFFDADCE0), Color(0xFFE6E7EA)]
                        : lit
                            ? const [Color(0xFFEAF2FF), Color(0xFFD6E4FA)]
                            : const [Color(0xFFFFFFFF), Color(0xFFF3F3F5)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: f ? t.focus : _keyEdge, width: f ? 3 : 1),
                  boxShadow: [
                    if (!d) const BoxShadow(color: Color(0x40000000), offset: Offset(0, 1.5), blurRadius: 1.5),
                    if (f) BoxShadow(color: t.focus.withValues(alpha: 0.45), blurRadius: 8),
                  ],
                ),
                child: _fit(label, TextStyle(color: _keyText, fontSize: font, fontWeight: FontWeight.w400)),
              ),
            ),
          ),
        );
    Widget row(List<Widget> c, {double pad = 0}) => Expanded(
        child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: c)));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEDEEF0), Color(0xFFD3D5DA), Color(0xFFC4C7CC)]),
        border: Border.all(color: const Color(0xFF9EA2A9), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x4D000000), blurRadius: 26, offset: Offset(0, -4)),
          BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 2)),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: BevelPainter(BorderRadius.circular(24), width: 2.5, light: 0.85, dark: 0.25),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: BrushedPainter())),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: Column(children: [
                row([for (final c in kQwertyNumbers) k(c, c, font: 20)]),
                row([for (final c in letters[0]) k(c, keys.cased(c))]),
                row([for (final c in letters[1]) k(c, keys.cased(c), autofocus: c == 'g')], pad: 22),
                row([
                  k('shift', 'shift', flex: 15, lit: keys.shift || keys.caps, font: 14, at: Alignment.bottomLeft),
                  for (final c in letters[2]) k(c, keys.cased(c)),
                  k('del', 'delete', flex: 15, font: 14, at: Alignment.bottomRight),
                ]),
                row([
                  k('sym', keys.sym ? 'abc' : '.?123', flex: 15, lit: keys.sym, font: 14, at: Alignment.bottomLeft),
                  k(':)', ':)', flex: 10, font: 18),
                  k('space', '', flex: 38),
                  k('end', 'hide', flex: 13, font: 14),
                  k('send', 'return', flex: 19, font: 14, at: Alignment.bottomRight),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// =================================================================== pocket brick

/// The chunky green-screen handheld. It boots with its name sliding down the
/// screen and a beeeep; then a name-entry style letter box floats up over the
/// bottom half (covering the buttons). Arrows / D-pad move the ▶ cursor.
class PocketBrickArt extends StatelessWidget {
  static const size = Size(540, 900);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const PocketBrickArt(
      {super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  static const dark = Color(0xFF0F380F);
  static const boxBg = Color(0xFFCADC9F);
  static const navy = Color(0xFF2A2878);
  static const berry = Color(0xFF9A2257);
  static const _body = Color(0xFFCCC8BF);
  static const _well = Color(0xFFB9B5AC);

  /// The letter box, row by row (9 across). 'send' is ED (end = send).
  static const rows = [
    ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'],
    ['j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r'],
    ['s', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'space'],
    ['1', '2', '3', '4', '5', '6', '7', '8', '9'],
    ['0', '.', ',', '?', '!', '-', ':)', 'del', 'send'],
  ];

  static const _engraved = TextStyle(
    color: Color(0xFF6E6A63),
    fontWeight: FontWeight.w800,
    shadows: [Shadow(color: Color(0xAAFFFFFF), offset: Offset(0, 1))],
  );

  @override
  Widget build(BuildContext context) {
    final rise = Curves.easeOutBack.transform(open.clamp(0.0, 1.0));
    final on = power.clamp(0.0, 1.0) > 0.5;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: 20,
        top: 20,
        width: 500,
        height: 860,
        child: Molded(
          color: _body,
          sheen: 0.12,
          radius: const BorderRadius.only(
              topLeft: Radius.circular(26), topRight: Radius.circular(26),
              bottomLeft: Radius.circular(26), bottomRight: Radius.circular(130)),
        ),
      ),
      // engraved line along the top and the power switch
      Positioned(left: 24, top: 74, width: 492, height: 3, child: _groove()),
      Positioned(left: 60, top: 26, width: 54, height: 18, child: _slot()),
      Positioned(left: 60, top: 48, child: Text('◁OFF·ON▷', style: _engraved.copyWith(fontSize: 13, letterSpacing: 1))),
      // screen bezel (under glass)
      Positioned(
        left: 52,
        top: 96,
        width: 436,
        height: 376,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF6A6D7E), Color(0xFF515465)]),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14), bottomRight: Radius.circular(70)),
            border: Border.all(color: const Color(0xFF3A3C48), width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1.5))],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14), bottomRight: Radius.circular(70)),
            child: Stack(children: [
              Positioned(
                left: 20,
                top: 14,
                right: 20,
                child: Row(children: [
                  Expanded(child: Column(children: [Container(height: 2.5, color: berry), const SizedBox(height: 3), Container(height: 2.5, color: navy)])),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('DOT MATRIX WITH CHAT SOUND',
                        style: TextStyle(color: Color(0xFFE0E0E6), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  ),
                  SizedBox(width: 40, child: Column(children: [Container(height: 2.5, color: berry), const SizedBox(height: 3), Container(height: 2.5, color: navy)])),
                ]),
              ),
              Positioned(
                left: 16,
                top: 150,
                child: Column(children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? const Color(0xFFFF2A2A) : const Color(0xFF4A1414),
                      border: Border.all(color: const Color(0xFF2A2B33), width: 1.5),
                      boxShadow: on ? const [BoxShadow(color: Color(0xCCFF2A2A), blurRadius: 10)] : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('BATTERY', style: TextStyle(color: Color(0xFFE0E0E6), fontSize: 8.5, fontWeight: FontWeight.w700)),
                ]),
              ),
              Positioned(
                left: 76,
                top: 44,
                width: 300,
                height: 290,
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFF2E303A), width: 2)),
                  child: lcd(t, power, screen,
                      radius: BorderRadius.zero, grid: true, glare: 0, padding: const EdgeInsets.all(10)),
                ),
              ),
              const Positioned.fill(child: GlassGlare(strength: 0.55)),
            ]),
          ),
        ),
      ),
      Positioned(
        left: 56,
        top: 486,
        child: const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Pocket ', style: TextStyle(fontStyle: FontStyle.italic)),
            TextSpan(text: 'CHAT', style: TextStyle(fontStyle: FontStyle.italic, letterSpacing: 1)),
          ]),
          style: TextStyle(color: navy, fontSize: 32, fontWeight: FontWeight.w900),
        ),
      ),
      // controls (hidden by the letter box while typing)
      Positioned(left: 50, top: 582, child: _dpad()),
      Positioned(left: 300, top: 596, child: _abWell()),
      Positioned(left: 160, top: 770, child: _pillButton('SELECT')),
      Positioned(left: 262, top: 770, child: _pillButton('START')),
      Positioned(left: 372, top: 730, child: _speaker()),
      Positioned(left: 240, top: 852, child: Text('PHONES', style: _engraved.copyWith(fontSize: 11))),
      // the letter box floats up over the bottom half
      Positioned(
        left: 24,
        top: 498 + (1 - rise) * 420,
        width: 492,
        height: 376,
        child: IgnorePointer(
          ignoring: open < 0.95,
          child: Opacity(opacity: open.clamp(0.0, 1.0), child: _nameBox()),
        ),
      ),
    ]);
  }

  Widget _groove() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x55000000), Color(0x80FFFFFF)]),
        ),
      );

  Widget _slot() => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF6E6A63), Color(0xFFB5B1A8)]),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 20,
          decoration: keycap(const Color(0xFF9C988F), r: BorderRadius.circular(6)),
        ),
      );

  Widget _dpad() {
    const black = Color(0xFF26262A);
    BoxDecoration arm(BorderRadius r) => BoxDecoration(
          borderRadius: r,
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A4A50), black, Color(0xFF141416)]),
        );
    return Container(
      width: 170,
      height: 170,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [shade(_well, -0.05), _well, shade(_body, 0.05)], stops: const [0, 0.85, 1]),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 2, offset: Offset(0, -1))],
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 138,
        height: 138,
        child: Stack(alignment: Alignment.center, children: [
          // shadow under the cross
          Transform.translate(
            offset: const Offset(0, 4),
            child: Stack(alignment: Alignment.center, children: [
              Container(width: 138, height: 44, decoration: BoxDecoration(color: const Color(0x55000000), borderRadius: BorderRadius.circular(6))),
              Container(width: 44, height: 138, decoration: BoxDecoration(color: const Color(0x55000000), borderRadius: BorderRadius.circular(6))),
            ]),
          ),
          Container(width: 138, height: 44, decoration: arm(BorderRadius.circular(6))),
          Container(width: 44, height: 138, decoration: arm(BorderRadius.circular(6))),
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: Alignment(0.3, 0.3), colors: [Color(0xFF3C3C42), Color(0xFF16161A)]),
            ),
          ),
          for (final (a, angle) in const [
            (Alignment.topCenter, 0.0),
            (Alignment.bottomCenter, pi),
            (Alignment.centerLeft, -pi / 2),
            (Alignment.centerRight, pi / 2),
          ])
            Align(
              alignment: a,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Transform.rotate(angle: angle, child: const Text('▲', style: TextStyle(color: Color(0xFF3E3E44), fontSize: 12))),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _abWell() {
    Widget btn(String label) => Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: Alignment(-0.35, -0.4), radius: 0.85, colors: [Color(0xFFD45A8E), Color(0xFF9A2257), Color(0xFF6A1238)]),
              boxShadow: [BoxShadow(color: Color(0x88000000), blurRadius: 4, offset: Offset(0, 4))],
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: navy, fontSize: 20, fontWeight: FontWeight.w900)),
        ]);
    return Transform.rotate(
      angle: -0.45,
      child: Container(
        width: 210,
        height: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(52),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [shade(_well, -0.08), _well]),
        ),
        child: OverflowBox(
          maxHeight: 140,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 15),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.start, children: [btn('B'), btn('A')]),
          ),
        ),
      ),
    );
  }

  Widget _pillButton(String label) => Transform.rotate(
        angle: -0.45,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [shade(_well, -0.12), _well]),
            ),
            child: Container(decoration: keycap(const Color(0xFF8B8994), r: BorderRadius.circular(9))),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: navy, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ]),
      );

  Widget _speaker() => Transform.rotate(
        angle: -0.5,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 6; i++)
            Container(
              width: 10,
              height: 92,
              margin: const EdgeInsets.symmetric(horizontal: 4.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: const LinearGradient(
                    begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF1E1D1B), Color(0xFF55524C), Color(0xFFE2DED6)], stops: [0, 0.7, 1]),
              ),
            ),
        ]),
      );

  static const _pix = TextStyle(color: dark, fontSize: 30, fontWeight: FontWeight.w800, fontFamily: 'monospace', height: 1);

  String _glyph(String id) => switch (id) {
        'space' => '␣',
        'del' => 'DEL',
        'send' => 'ED',
        _ => keys.cased(id),
      };

  Widget _cell(String id, String label, {bool autofocus = false}) => DeviceKey.of(
        keys,
        id,
        id == 'send' ? 'End (send)' : (id == 'space' ? 'Space' : label),
        autofocus: autofocus,
        builder: (f, d) => Container(
          color: d ? dark : null,
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 22, child: Text(f ? '▶' : '', style: _pix.copyWith(fontSize: 22, color: d ? boxBg : dark))),
              Text(label, style: _pix.copyWith(color: d ? boxBg : dark)),
            ]),
          ),
        ),
      );

  Widget _nameBox() {
    Widget rivet() => Container(
        width: 14, height: 14, decoration: BoxDecoration(color: boxBg, shape: BoxShape.circle, border: Border.all(color: dark, width: 3)));
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            color: boxBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: dark, width: 5),
            boxShadow: _dropShadow,
          ),
          child: Stack(children: [
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: PixelGridPainter(const Color(0x120F380F))))),
            Padding(
              padding: const EdgeInsets.all(5),
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: dark, width: 2)),
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 4),
                child: Column(children: [
                  Expanded(
                    child: Column(children: [
                      for (final row in rows)
                        Expanded(
                          child: Row(children: [
                            for (final id in row) Expanded(child: _cell(id, _glyph(id), autofocus: id == 'a')),
                          ]),
                        ),
                    ]),
                  ),
                  SizedBox(
                    height: 48,
                    child: Row(children: [
                      Expanded(flex: 5, child: _cell('caps', keys.caps ? 'lower case' : 'UPPER CASE')),
                      Expanded(flex: 3, child: _cell('end', 'CLOSE')),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
      Positioned(left: -5, top: -5, child: rivet()),
      Positioned(right: -5, top: -5, child: rivet()),
      Positioned(left: -5, bottom: -5, child: rivet()),
      Positioned(right: -5, bottom: -5, child: rivet()),
    ]);
  }
}
