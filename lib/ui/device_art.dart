import 'dart:math';

import 'package:flutter/material.dart';

import 'phone_art.dart';
import 'phone_theme.dart';

/// Gadgets that bring their own keyboard: a console dashboard on a tube TV,
/// a thumb-keyboard "pocket mail" phone, a click-wheel music player with a
/// keyboard that slides up over the wheel, and a green-screen handheld with a
/// name-entry letter box. Original designs: no real logos or brand names.
///
/// Each is drawn at a fixed design [size]; [PhoneArt] puts it in a FittedBox.

/// Runs a key: 'send' and 'end' use their own callbacks, the rest are typed.
void deviceAct(PhoneKeys k, String id) {
  switch (id) {
    case 'send':
      k.send?.call();
    case 'end':
      k.end?.call();
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

/// A gadget's screen: dark when off, lights up with [power].
Widget deviceScreen(PhoneTheme t, double power, Widget screen,
    {required BorderRadius radius, double border = 5, Color? borderColor, EdgeInsets padding = const EdgeInsets.fromLTRB(14, 10, 14, 10)}) {
  final p = power.clamp(0.0, 1.0);
  return Container(
    decoration: BoxDecoration(
      color: Color.lerp(t.screenOff, t.screenOn, p),
      borderRadius: radius,
      border: Border.all(color: borderColor ?? t.ink, width: border),
    ),
    padding: padding,
    child: ClipRect(child: Opacity(opacity: p, child: screen)),
  );
}

Widget _label(String s, TextStyle style) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(s, style: style, maxLines: 1)),
    );

const _floatShadow = [
  BoxShadow(color: Color(0x59000000), blurRadius: 34, spreadRadius: 2, offset: Offset(0, 16)),
];

// =================================================================== console TV

/// A chunky tube TV with the chat on it; a glowing green on-screen keyboard
/// panel slides up underneath. The TV switches on like an old CRT: a thin
/// line that opens into the picture.
class DashboardArt extends StatelessWidget {
  static const size = Size(880, 940);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const DashboardArt({super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  static const lime = Color(0xFF8CFF5A);

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
        left: 330,
        top: 560,
        width: 220,
        height: 44,
        child: Container(
          decoration: BoxDecoration(
              color: const Color(0xFF1E1E22), borderRadius: BorderRadius.circular(10), border: Border.all(color: t.ink, width: 5)),
        ),
      ),
      // the TV
      Positioned(
        left: 70,
        top: 20,
        width: 740,
        height: 560,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(44),
            border: Border.all(color: t.ink, width: 5),
            gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF45454C), Color(0xFF1C1C20)]),
            boxShadow: _floatShadow,
          ),
          child: Stack(children: [
            Positioned(left: 36, top: 30, right: 36, bottom: 92, child: _tube()),
            Positioned(left: 50, right: 50, bottom: 24, height: 44, child: _controls()),
          ]),
        ),
      ),
      // keyboard panel
      Positioned(
        left: 0,
        top: 590 + (1 - slide) * 420,
        width: 880,
        height: 340,
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(52),
        border: Border.all(color: t.ink, width: 6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(46),
        child: Stack(fit: StackFit.expand, children: [
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(max(0.001, px), sy, 1),
            child: Stack(fit: StackFit.expand, children: [
              Container(
                color: Color.lerp(t.screenOff, t.screenOn, py),
                padding: const EdgeInsets.fromLTRB(40, 28, 40, 26),
                child: Opacity(opacity: py, child: screen),
              ),
              if (flash > 0) ColoredBox(color: Colors.white.withValues(alpha: 0.9 * flash)),
            ]),
          ),
          IgnorePointer(child: CustomPaint(painter: _ScanlinePainter())),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(radius: 0.95, colors: [Color(0x00000000), Color(0x00000000), Color(0x99000000)], stops: [0, 0.62, 1]),
              ),
            ),
          ),
          // glass glint
          Positioned(
            left: 40,
            top: 24,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: -0.35,
                child: Container(
                  width: 150,
                  height: 46,
                  decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(40)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _controls() {
    Widget knob() => Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.ink, width: 3),
            gradient: const RadialGradient(colors: [Color(0xFF9A9AA2), Color(0xFF4A4A50)]),
          ),
        );
    final on = power > 0.05;
    return Row(children: [
      const Text('CH 03',
          style: TextStyle(color: Color(0xFF9A9AA2), fontSize: 18, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
      const Spacer(),
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? lime : const Color(0xFF2A3A2A),
          boxShadow: on ? const [BoxShadow(color: Color(0xAA8CFF5A), blurRadius: 10)] : null,
        ),
      ),
      knob(),
      knob(),
      knob(),
    ]);
  }

  Widget _panel() {
    final rows = keys.sym ? _symbols : _letters;
    const actions = [
      ('send', 'DONE'),
      ('space', 'SPACE'),
      ('del', 'BACK'),
      ('caps', 'CAPS'),
      ('sym', 'SYMBOLS'),
      ('end', 'CLOSE'),
    ];
    return Container(
      decoration: BoxDecoration(
        gradient: const RadialGradient(center: Alignment(0, -0.6), radius: 1.3, colors: [Color(0xFF1E5C14), Color(0xFF061806)]),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: lime.withValues(alpha: 0.8), width: 4),
        boxShadow: [BoxShadow(color: lime.withValues(alpha: 0.3), blurRadius: 30), ..._floatShadow],
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: 7,
          child: Column(children: [
            for (final row in rows)
              Expanded(
                child: Row(children: [
                  for (final c in row)
                    Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _key(c, keys.cased(c), autofocus: c == 'a'))),
                ]),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(children: [
            for (final (id, label) in actions)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _key(id, id == 'sym' && keys.sym ? 'ABC' : label,
                      lit: (id == 'caps' && keys.caps) || (id == 'sym' && keys.sym)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _key(String id, String label, {bool lit = false, bool autofocus = false}) => DeviceKey.of(
        keys,
        id,
        label,
        autofocus: autofocus,
        builder: (f, d) => Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: f
                  ? const [Color(0xFFE6FF9A), Color(0xFF8BE03A)]
                  : d
                      ? const [Color(0xFF2F8F18), Color(0xFF1A5A0C)]
                      : lit
                          ? const [Color(0xFFB4F06A), Color(0xFF4FAE24)]
                          : const [Color(0xFF63C93A), Color(0xFF237A12)],
            ),
            border: Border.all(color: d ? lime : const Color(0xFF062206), width: 2),
            boxShadow: f ? [BoxShadow(color: lime.withValues(alpha: 0.8), blurRadius: 16)] : null,
          ),
          child: _label(
            label,
            TextStyle(
              color: f ? const Color(0xFF0B2A0B) : Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              shadows: f ? null : const [Shadow(color: Color(0xAA000000), offset: Offset(0, 2), blurRadius: 2)],
            ),
          ),
        ),
      );
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0x2E000000);
    for (var y = 0.0; y < s.height; y += 4) {
      c.drawRect(Rect.fromLTWH(0, y, s.width, 2), p);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}

// =================================================================== pocket mail

/// A business-y thumb-keyboard phone: screen in a silver frame, a call /
/// menu / trackball / back / end row, and a full little keyboard. The red
/// light in the corner glows while it's on.
class PocketMailArt extends StatelessWidget {
  static const size = Size(520, 900);
  final PhoneTheme t;
  final double power;
  final PhoneKeys keys;
  final Widget screen;
  const PocketMailArt({super.key, required this.t, required this.power, required this.keys, required this.screen});

  @override
  Widget build(BuildContext context) {
    final p = power.clamp(0.0, 1.0);
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: 20,
        top: 20,
        width: 480,
        height: 860,
        child: ShellBox(
          color: t.body,
          ink: t.ink,
          radius: const BorderRadius.vertical(top: Radius.circular(54), bottom: Radius.circular(76)),
        ),
      ),
      Positioned(
        left: 44,
        top: 50,
        width: 432,
        height: 330,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE3E7EC), Color(0xFF8E96A2)]),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: t.ink, width: 4),
          ),
        ),
      ),
      Positioned(
        left: 62,
        top: 68,
        width: 396,
        height: 294,
        child: deviceScreen(t, power, screen, radius: BorderRadius.circular(10), border: 4),
      ),
      // message light
      Positioned(
        left: 446,
        top: 28,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(const Color(0xFF4A1010), const Color(0xFFFF3030), p),
            border: Border.all(color: t.ink, width: 2),
            boxShadow: p > 0.5 ? const [BoxShadow(color: Color(0xAAFF3030), blurRadius: 12)] : null,
          ),
        ),
      ),
      Positioned(
        left: 44,
        top: 398,
        width: 432,
        height: 70,
        child: Row(children: [
          Expanded(child: _navKey('send', 'Send', kSendGreen)),
          const SizedBox(width: 8),
          Expanded(child: _navKey('sym', 'Sym', t.softBg)),
          const SizedBox(width: 10),
          _trackball(),
          const SizedBox(width: 10),
          Expanded(child: _navKey('del', 'Del', t.softBg)),
          const SizedBox(width: 8),
          Expanded(child: _navKey('end', 'End', kEndRed)),
        ]),
      ),
      Positioned(left: 40, top: 486, width: 440, height: 360, child: _keyboard()),
    ]);
  }

  Widget _trackball() => Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.ink, width: 4),
          color: const Color(0xFF1A1B20),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(center: Alignment(-0.4, -0.4), colors: [Colors.white, Color(0xFFB8C4D2), Color(0xFF6E7C8C)]),
          ),
        ),
      );

  Widget _navKey(String id, String label, Color color) => DeviceKey.of(
        keys,
        id,
        label,
        builder: (f, d) => Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: d ? Color.lerp(color, Colors.black, 0.25) : color,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(color: f ? t.focus : t.ink, width: f ? 4 : 3),
          ),
          child: _label(label, TextStyle(color: t.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _keyboard() {
    final letters = keys.sym ? kQwertySymbols : kQwertyLetters;
    Widget k(String id, String label, {int flex = 10, bool lit = false, bool small = false, bool autofocus = false}) => Expanded(
          flex: flex,
          child: DeviceKey.of(
            keys,
            id,
            label,
            autofocus: autofocus,
            builder: (f, d) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: d
                      ? const [Color(0xFF55585F), Color(0xFF2A2C31)]
                      : lit
                          ? const [Color(0xFF2E4D6E), Color(0xFF16273A)]
                          : const [Color(0xFF3A3C43), Color(0xFF0E0F12)],
                ),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8), topRight: Radius.circular(8),
                    bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
                border: Border.all(color: f ? t.focus : Colors.black, width: f ? 3 : 2),
              ),
              child: _label(label, TextStyle(color: small ? t.keySub : t.keyInk, fontSize: small ? 17 : 22, fontWeight: FontWeight.w800)),
            ),
          ),
        );
    Widget row(List<Widget> c, {double pad = 0}) =>
        Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: c)));
    return Column(children: [
      row([for (final c in kQwertyNumbers) k(c, c, small: true)]),
      row([for (final c in letters[0]) k(c, keys.cased(c))]),
      row([for (final c in letters[1]) k(c, keys.cased(c), autofocus: c == 'g'), k('del', '⌫', flex: 10)]),
      row([
        k('shift', '⇧', flex: 13, lit: keys.shift),
        for (final c in letters[2]) k(c, keys.cased(c)),
        k('send', '⏎', flex: 17),
      ]),
      row([
        k('sym', keys.sym ? 'abc' : 'sym', flex: 14, lit: keys.sym, small: true),
        k(':)', ':)', flex: 10),
        k('space', 'space', flex: 46, small: true),
        k('caps', 'caps', flex: 14, lit: keys.caps, small: true),
      ]),
    ]);
  }
}

// =================================================================== music player

/// A white click-wheel music player. Its screen comes on first, then a clean
/// white keyboard slides up over the wheel, leaving just the screen showing.
class MusicPlayerArt extends StatelessWidget {
  static const size = Size(520, 900);
  final PhoneTheme t;
  final double open, power;
  final PhoneKeys keys;
  final Widget screen;
  const MusicPlayerArt(
      {super.key, required this.t, required this.open, required this.power, required this.keys, required this.screen});

  static const _keyText = Color(0xFF3A3C42);
  static const _keyEdge = Color(0xFFC3C6CC);

  @override
  Widget build(BuildContext context) {
    final up = Curves.easeOutCubic.transform(open.clamp(0.0, 1.0));
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: 20,
        top: 20,
        width: 480,
        height: 860,
        child: ShellBox(color: t.body, ink: t.ink, radius: BorderRadius.circular(58)),
      ),
      Positioned(
        left: 62,
        top: 70,
        width: 396,
        height: 300,
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFF26292E), borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.all(8),
          child: deviceScreen(t, power, screen, radius: BorderRadius.circular(8), border: 2, borderColor: const Color(0xFF111316)),
        ),
      ),
      Positioned(left: 90, top: 450, width: 340, height: 340, child: _wheel()),
      Positioned(
        left: 12,
        top: 394 + (1 - up) * 480,
        width: 496,
        height: 480,
        child: IgnorePointer(
          ignoring: open < 0.95,
          child: Opacity(opacity: up.clamp(0.0, 1.0), child: _keyboard()),
        ),
      ),
    ]);
  }

  Widget _wheel() {
    const label = TextStyle(color: Color(0xFFA6A9B0), fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFEAEBEE),
        border: Border.all(color: const Color(0xFFC7CACF), width: 3),
      ),
      child: Stack(alignment: Alignment.center, children: [
        const Positioned(top: 26, child: Text('MENU', style: label)),
        const Positioned(left: 26, child: Text('|◀◀', style: label)),
        const Positioned(right: 26, child: Text('▶▶|', style: label)),
        const Positioned(bottom: 24, child: Text('▶ ||', style: label)),
        Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: const Color(0xFFD3D5DA), width: 3),
          ),
        ),
      ]),
    );
  }

  Widget _keyboard() {
    final letters = keys.sym ? kQwertySymbols : kQwertyLetters;
    Widget k(String id, String label, {int flex = 10, bool lit = false, bool autofocus = false, double font = 24}) => Expanded(
          flex: flex,
          child: DeviceKey.of(
            keys,
            id,
            label,
            autofocus: autofocus,
            builder: (f, d) => Container(
              margin: const EdgeInsets.all(3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: d ? const Color(0xFFD5D7DC) : (lit ? const Color(0xFFDDE8FA) : Colors.white),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: f ? t.focus : _keyEdge, width: f ? 3 : 1.5),
                boxShadow: d ? null : const [BoxShadow(color: Color(0x2E000000), offset: Offset(0, 2))],
              ),
              child: _label(label, TextStyle(color: _keyText, fontSize: font, fontWeight: FontWeight.w500)),
            ),
          ),
        );
    Widget row(List<Widget> c, {double pad = 0}) =>
        Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: c)));
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF3F3F5), Color(0xFFD8D9DD)]),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFB4B7BD), width: 3),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, -6))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Column(children: [
        Container(
          width: 64,
          height: 6,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: const Color(0xFFB4B7BD), borderRadius: BorderRadius.circular(3)),
        ),
        row([for (final c in kQwertyNumbers) k(c, c, font: 20)]),
        row([for (final c in letters[0]) k(c, keys.cased(c))]),
        row([for (final c in letters[1]) k(c, keys.cased(c), autofocus: c == 'g')], pad: 22),
        row([
          k('shift', '⇧', flex: 15, lit: keys.shift || keys.caps),
          for (final c in letters[2]) k(c, keys.cased(c)),
          k('del', '⌫', flex: 15),
        ]),
        row([
          k('sym', keys.sym ? 'abc' : '.?123', flex: 15, lit: keys.sym, font: 18),
          k(':)', ':)', flex: 10, font: 20),
          k('space', 'space', flex: 40, font: 18),
          k('end', 'hide', flex: 12, font: 16),
          k('send', 'return', flex: 19, font: 18),
        ]),
      ]),
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
  static const pale = Color(0xFFC4CFA1);
  static const bezel = Color(0xFF5B5D6B);
  static const berry = Color(0xFF9A2257);
  static const navy = Color(0xFF26246B);

  /// The letter box, row by row (9 across). 'send' is ED (end = send).
  static const rows = [
    ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'],
    ['j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r'],
    ['s', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'space'],
    ['1', '2', '3', '4', '5', '6', '7', '8', '9'],
    ['0', '.', ',', '?', '!', '-', ':)', 'del', 'send'],
  ];

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
        child: ShellBox(
          color: t.body,
          ink: t.ink,
          shine: false,
          radius: const BorderRadius.only(
              topLeft: Radius.circular(24), topRight: Radius.circular(24),
              bottomLeft: Radius.circular(24), bottomRight: Radius.circular(120)),
        ),
      ),
      // top groove and power switch
      const Positioned(left: 26, top: 72, width: 488, height: 4, child: ColoredBox(color: Color(0x33000000))),
      const Positioned(
        left: 52,
        top: 40,
        child: Text('◁ OFF · ON ▷',
            style: TextStyle(color: Color(0x88000000), fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1)),
      ),
      // screen bezel
      Positioned(
        left: 55,
        top: 96,
        width: 430,
        height: 376,
        child: Container(
          decoration: BoxDecoration(
            color: bezel,
            border: Border.all(color: t.ink, width: 4),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14), bottomRight: Radius.circular(64)),
          ),
        ),
      ),
      Positioned(
        left: 74,
        top: 112,
        width: 392,
        child: Row(children: [
          Expanded(child: Container(height: 3, color: berry)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('DOT MATRIX · POCKET CHAT',
                style: TextStyle(color: Color(0xFFDADADA), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          Expanded(child: Container(height: 3, color: navy)),
        ]),
      ),
      Positioned(
        left: 70,
        top: 250,
        child: Column(children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? const Color(0xFFFF2A2A) : const Color(0xFF4A1414),
              boxShadow: on ? const [BoxShadow(color: Color(0xAAFF2A2A), blurRadius: 8)] : null,
            ),
          ),
          const SizedBox(height: 4),
          const Text('BATTERY', style: TextStyle(color: Color(0xFFDADADA), fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
      ),
      Positioned(
        left: 128,
        top: 140,
        width: 304,
        height: 300,
        child: deviceScreen(t, power, screen,
            radius: BorderRadius.circular(4), border: 3, borderColor: const Color(0xFF2A2B33), padding: const EdgeInsets.all(10)),
      ),
      const Positioned(
        left: 60,
        top: 486,
        child: Text('Pocket Chat',
            style: TextStyle(color: navy, fontSize: 32, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
      ),
      // controls (hidden by the letter box while typing)
      Positioned(left: 62, top: 590, child: _dpad()),
      Positioned(left: 326, top: 630, child: _round('B')),
      Positioned(left: 418, top: 584, child: _round('A')),
      Positioned(left: 168, top: 772, child: _pillButton('SELECT')),
      Positioned(left: 268, top: 772, child: _pillButton('START')),
      Positioned(
        left: 386,
        top: 728,
        child: Transform.rotate(
          angle: -0.5,
          child: Row(children: [
            for (var i = 0; i < 6; i++)
              Container(
                width: 8,
                height: 80,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(color: const Color(0x55000000), borderRadius: BorderRadius.circular(4)),
              ),
          ]),
        ),
      ),
      // the letter box floats up over the bottom half
      Positioned(
        left: 26,
        top: 500 + (1 - rise) * 420,
        width: 488,
        height: 372,
        child: IgnorePointer(
          ignoring: open < 0.95,
          child: Opacity(opacity: open.clamp(0.0, 1.0), child: _nameBox()),
        ),
      ),
    ]);
  }

  Widget _dpad() {
    const c = Color(0xFF2B2B2E);
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(alignment: Alignment.center, children: [
        Container(
            width: 140, height: 46, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.ink, width: 3))),
        Container(
            width: 46, height: 140, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.ink, width: 3))),
        Container(width: 40, height: 40, color: c),
        Container(width: 22, height: 22, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3A3A3E))),
      ]),
    );
  }

  Widget _round(String label) => Column(children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(color: berry, shape: BoxShape.circle, border: Border.all(color: t.ink, width: 4)),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: navy, fontSize: 20, fontWeight: FontWeight.w900)),
      ]);

  Widget _pillButton(String label) => Transform.rotate(
        angle: -0.45,
        child: Column(children: [
          Container(
            width: 70,
            height: 18,
            decoration: BoxDecoration(
                color: const Color(0xFF8E8C95), borderRadius: BorderRadius.circular(9), border: Border.all(color: t.ink, width: 3)),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: navy, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
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
              SizedBox(width: 22, child: Text(f ? '▶' : '', style: _pix.copyWith(fontSize: 22, color: d ? pale : dark))),
              Text(label, style: _pix.copyWith(color: d ? pale : dark)),
            ]),
          ),
        ),
      );

  Widget _nameBox() {
    Widget rivet() => Container(
        width: 14, height: 14, decoration: BoxDecoration(color: pale, shape: BoxShape.circle, border: Border.all(color: dark, width: 3)));
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            color: pale,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: dark, width: 5),
            boxShadow: _floatShadow,
          ),
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
      ),
      Positioned(left: -5, top: -5, child: rivet()),
      Positioned(right: -5, top: -5, child: rivet()),
      Positioned(left: -5, bottom: -5, child: rivet()),
      Positioned(right: -5, bottom: -5, child: rivet()),
    ]);
  }
}
