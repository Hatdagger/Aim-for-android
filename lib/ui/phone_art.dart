import 'dart:math';

import 'package:flutter/material.dart';

import '../app/t9.dart';
import 'phone_theme.dart';

/// What the keys do. Every callback null = a still picture (settings preview).
class PhoneKeys {
  /// T9: '0'-'9', '*', '#'. QWERTY: a character, or 'shift', 'sym', 'del', 'space', ':)'.
  final void Function(String key)? press;
  final VoidCallback? send;
  final VoidCallback? end;
  final VoidCallback? clear;
  final VoidCallback? mode;
  final void Function({bool pad})? feel;
  final String sendLabel;
  final String modeLabel;
  final bool predictive;
  final bool shift;
  final bool sym;
  const PhoneKeys({
    this.press,
    this.send,
    this.end,
    this.clear,
    this.mode,
    this.feel,
    this.sendLabel = 'Send',
    this.modeLabel = 'T9',
    this.predictive = true,
    this.shift = false,
    this.sym = false,
  });

  bool get live => press != null;
}

const kQwertyNumbers = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
const kQwertyLetters = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
];
const kQwertySymbols = [
  ['!', '@', '#', '\$', '%', '^', '&', '*', '(', ')'],
  ['-', '_', '=', '+', ':', ';', "'", '"', '?'],
  [',', '.', '/', '<', '>', '~', '|'],
];

/// Draws a cartoon phone at a fixed design size; wrap it in a FittedBox.
class PhoneArt extends StatelessWidget {
  final PhoneTheme t;
  final bool qwerty;

  /// 0 = closed (flip lid shut / slider screen down), 1 = open.
  final double open;

  /// Vertical squash when a candybar lands (1 = none).
  final double squash;

  /// What's on the little screen (already sized to fit it).
  final Widget screen;

  /// 0 = screen off, 1 = on.
  final double power;
  final PhoneKeys keys;

  const PhoneArt({
    super.key,
    required this.t,
    required this.qwerty,
    required this.screen,
    required this.keys,
    this.open = 1,
    this.squash = 1,
    this.power = 1,
  });

  static Size sizeFor(PhoneTheme t, bool qwerty) =>
      qwerty ? const Size(840, 720) : (t.flip ? const Size(470, 830) : const Size(470, 790));

  @override
  Widget build(BuildContext context) {
    final size = sizeFor(t, qwerty);
    return SizedBox.fromSize(
      size: size,
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.diagonal3Values(1 + (1 - squash) * 0.6, squash, 1),
        child: qwerty ? _slider(size) : (t.flip ? _flip() : _candybar()),
      ),
    );
  }

  // ------------------------------------------------------------ pieces

  Widget _screenBox({double? width, double height = 250}) {
    final bg = Color.lerp(t.screenOff, t.screenOn, power)!;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.ink, width: 5),
        boxShadow: t.glow && power > 0.5
            ? [BoxShadow(color: t.screenInk.withValues(alpha: 0.35 * power), blurRadius: 18)]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: ClipRect(child: Opacity(opacity: power.clamp(0.0, 1.0), child: screen)),
    );
  }

  Widget _pill(String label, Color bg, Color ink, VoidCallback? onTap, {double height = 52, double font = 19}) {
    return CartoonKey(
      t: t,
      bg: bg,
      radius: BorderRadius.circular(height / 2),
      height: height,
      onTap: onTap,
      feel: keys.feel,
      semantics: label,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(label, style: TextStyle(color: ink, fontSize: font, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  Widget _softRow() {
    return SizedBox(
      height: 58,
      child: Row(children: [
        Expanded(flex: 5, child: _pill(keys.sendLabel, kSendGreen, t.ink, keys.send)),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: _pill(keys.modeLabel, t.softBg, t.softInk, keys.mode)),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: _pill('Clear', t.softBg, t.softInk, keys.clear)),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: _pill('End', kEndRed, t.ink, keys.end)),
      ]),
    );
  }

  String _sub(String k) => switch (k) {
        '1' => '.,?!',
        '0' => '␣',
        '*' => keys.predictive ? 'next' : '',
        '#' => 'mode',
        _ => (kT9Letters[k] ?? '').toUpperCase(),
      };

  Widget _keypad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(
                child: CartoonKey(
                  t: t,
                  height: 60,
                  autofocus: row[i] == '5',
                  feel: keys.feel,
                  semantics: 'Key ${row[i]}',
                  onTap: keys.press == null ? null : () => keys.press!(row[i]),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(row[i], style: _keyText(26)),
                    if (_sub(row[i]).isNotEmpty)
                      Text(_sub(row[i]),
                          style: TextStyle(color: t.keySub, fontSize: 12, fontWeight: FontWeight.w700, height: 1.1)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
    ]);
  }

  TextStyle _keyText(double size) => TextStyle(
        color: t.keyInk,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1,
        shadows: t.glow ? [Shadow(color: t.keyInk.withValues(alpha: 0.7), blurRadius: 8)] : null,
      );

  Widget _decorations(double bodyWidth, Color stick) => TopDecor(t: t, width: bodyWidth, stickColor: stick);

  // ------------------------------------------------------------ candybar

  Widget _candybar() {
    const left = 14.0, w = 400.0, top = 60.0, h = 692.0;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: left, top: 0, child: _decorations(w, t.body)),
      Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: ShellBox(
          color: t.body,
          pattern: t.pattern,
          ink: t.ink,
          radius: const BorderRadius.vertical(top: Radius.circular(60), bottom: Radius.circular(80)),
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: Stack(children: [
            if (t.bubbles) const Positioned.fill(child: BubblesDecor()),
            Column(children: [
              _screenBox(height: 246),
              const SizedBox(height: 16),
              _softRow(),
              _keypad(),
              const Spacer(),
              _speakerSlot(),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _speakerSlot() => Container(
      width: 90, height: 10, decoration: BoxDecoration(color: t.ink.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(5)));

  // ------------------------------------------------------------ flip

  Widget _flip() {
    const left = 14.0, w = 400.0, top = 60.0, lidH = 300.0, hingeH = 24.0, baseH = 430.0;
    const baseTop = top + lidH + hingeH;
    final angle = (1 - open) * pi; // 0 = open, pi = folded down over the keys
    final showBack = angle > pi / 2;
    final lidFront = ShellBox(
      color: t.lid,
      ink: t.ink,
      radius: const BorderRadius.vertical(top: Radius.circular(70), bottom: Radius.circular(26)),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      child: Stack(children: [
        if (t.rhinestones) Positioned.fill(child: CustomPaint(painter: RhinestonePainter(t.ink))),
        Center(child: _screenBox(height: 236, width: w - 44 - (t.rhinestones ? 28 : 0))),
      ]),
    );
    final lidBack = ShellBox(
      color: t.shell,
      pattern: t.shellPattern,
      ink: t.ink,
      radius: const BorderRadius.vertical(top: Radius.circular(70), bottom: Radius.circular(26)),
      child: Center(child: _outerDisplay()),
    );
    return Stack(clipBehavior: Clip.none, children: [
      // base with the keys
      Positioned(
        left: left,
        top: baseTop,
        width: w,
        height: baseH,
        child: ShellBox(
          color: t.body,
          pattern: t.pattern,
          ink: t.ink,
          radius: const BorderRadius.vertical(top: Radius.circular(26), bottom: Radius.circular(80)),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: ClipRect(child: OverflowBox(alignment: Alignment.topCenter, maxHeight: double.infinity, child: Column(mainAxisSize: MainAxisSize.min, children: [_softRow(), _keypad(), const SizedBox(height: 16), _speakerSlot()]))),
        ),
      ),
      if (t.strap != null)
        Positioned(left: left + w - 6, top: baseTop + 40, child: Strap(colors: t.strap!, ink: t.ink)),
      // hinge
      Positioned(
        left: left + 30,
        top: top + lidH - 4,
        width: w - 60,
        height: hingeH + 8,
        child: Container(
          decoration: BoxDecoration(
            color: t.hinge,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.ink, width: 5),
          ),
        ),
      ),
      // lid (+ what sticks out of its top) folds about the hinge
      Positioned(
        left: left,
        top: 0,
        width: w,
        height: top + lidH,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateX(-angle),
          child: Stack(clipBehavior: Clip.none, children: [
            if (!showBack) Positioned(left: 0, top: 0, child: _decorations(w, t.lid)),
            Positioned(left: 0, top: top, width: w, height: lidH, child: showBack ? _flipBack(lidBack) : lidFront),
          ]),
        ),
      ),
    ]);
  }

  Widget _flipBack(Widget back) => Transform(alignment: Alignment.center, transform: Matrix4.rotationX(pi), child: back);

  Widget _outerDisplay() {
    final now = TimeOfDay.now();
    final time = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    if (t.id == 'girlypop') {
      return SizedBox(
        width: 190,
        height: 170,
        child: CustomPaint(
          painter: HeartPainter(const Color(0xFFFF4FA3), t.ink, stroke: 5),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text('$time\nnew IM!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1)),
            ),
          ),
        ),
      );
    }
    if (t.id == 'gyaru') {
      return SizedBox(
        width: 240,
        height: 200,
        child: CustomPaint(
          painter: HeartPainter(const Color(0xFFFF2E93), t.ink, stroke: 5),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Love',
                    style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                        shadows: [Shadow(color: t.ink, offset: const Offset(3, 3))])),
                Text('$time · 1 IM',
                    style: TextStyle(color: const Color(0xFFFFD76A), fontSize: 18, fontWeight: FontWeight.w800,
                        shadows: [Shadow(color: t.ink, offset: const Offset(2, 2))])),
              ]),
            ),
          ),
        ),
      );
    }
    return Container(
      width: 160,
      height: 110,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.screenOn,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: t.ink, width: 5),
      ),
      child: FittedBox(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(time, style: TextStyle(color: t.screenInk, fontSize: 34, fontWeight: FontWeight.w800)),
          Text('AIM', style: TextStyle(color: t.screenInk, fontSize: 12)),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ QWERTY slider

  Widget _slider(Size size) {
    const w = 820.0, top = 60.0;
    const bodyTop = top + 300.0, bodyH = 340.0;
    const slabH = 330.0, slabClosedTop = top + 310.0;
    final slabTop = slabClosedTop - 310 * open;
    final slabColor = t.flip ? t.lid : t.body;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: 0,
        top: bodyTop,
        width: w,
        height: bodyH,
        child: ShellBox(
          color: t.body,
          pattern: t.pattern,
          ink: t.ink,
          shine: false,
          radius: const BorderRadius.vertical(top: Radius.circular(30), bottom: Radius.circular(70)),
          padding: const EdgeInsets.fromLTRB(20, 34, 20, 6),
          child: _qwertyKeys(),
        ),
      ),
      Positioned(
        left: 0,
        top: slabTop - 60,
        width: w,
        height: slabH + 60,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(left: 0, top: 0, child: _decorations(w, slabColor)),
          Positioned(
            left: 0,
            top: 60,
            width: w,
            height: slabH,
            child: ShellBox(
              color: slabColor,
              pattern: t.flip && t.id == 'girlypop' ? BodyPattern.plain : t.pattern,
              ink: t.ink,
              radius: BorderRadius.circular(70),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Stack(children: [
                if (t.rhinestones) Positioned.fill(child: CustomPaint(painter: RhinestonePainter(t.ink))),
                Row(children: [
                  _dpad(),
                  const SizedBox(width: 18),
                  Expanded(child: Center(child: _screenBox(height: 262))),
                  const SizedBox(width: 18),
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 92, child: _pill(keys.sendLabel, kSendGreen, t.ink, keys.send, height: 56, font: 16)),
                    const SizedBox(height: 14),
                    SizedBox(width: 92, child: _pill('End', kEndRed, t.ink, keys.end, height: 56, font: 16)),
                  ]),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _dpad() => Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(color: t.softBg, shape: BoxShape.circle, border: Border.all(color: t.ink, width: 5)),
        alignment: Alignment.center,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: t.ink, width: 4)),
        ),
      );

  Widget _qwertyKeys() {
    final letters = keys.sym ? kQwertySymbols : kQwertyLetters;
    String lab(String c) => keys.shift && !keys.sym ? c.toUpperCase() : c;
    Widget k(String id, String label, {int flex = 10, Color? bg, Color? ink, double font = 22, bool autofocus = false, bool on = false}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3.5),
          child: CartoonKey(
            t: t,
            height: 48,
            bg: bg,
            radius: BorderRadius.circular(12),
            lit: on,
            autofocus: autofocus,
            feel: keys.feel,
            semantics: label,
            onTap: keys.press == null ? null : () => keys.press!(id),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: _keyText(font).copyWith(color: ink ?? t.keyInk)),
            ),
          ),
        ),
      );
    }

    Widget row(List<Widget> c, {double pad = 0}) =>
        Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, 8), child: Row(children: c));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      row([for (final c in kQwertyNumbers) k(c, c)]),
      row([for (final c in letters[0]) k(c, lab(c))]),
      row([for (final c in letters[1]) k(c, lab(c), autofocus: c == 'g')], pad: 34),
      row([
        k('shift', '⇧ shift', flex: 16, font: 16, on: keys.shift),
        for (final c in letters[2]) k(c, lab(c)),
        k('del', '⌫ del', flex: 16, font: 16),
      ]),
      row([
        k('sym', keys.sym ? 'abc' : 'sym', flex: 14, font: 16, on: keys.sym),
        k(':)', ':)', flex: 10, font: 19),
        k('space', 'SPACE', flex: 50, font: 15),
        Expanded(
          flex: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3.5),
            child: CartoonKey(
              t: t,
              height: 48,
              bg: kSendGreen,
              radius: BorderRadius.circular(12),
              feel: keys.feel,
              semantics: keys.sendLabel,
              onTap: keys.send,
              child: Text('${keys.sendLabel} ⏎', style: TextStyle(color: t.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ]),
    ]);
  }
}

/// A chunky cartoon key: ink outline and a hard drop shadow that disappears
/// when pressed. Focusable for D-pad + A.
class CartoonKey extends StatefulWidget {
  final PhoneTheme t;
  final double height;
  final Color? bg;
  final BorderRadius? radius;
  final VoidCallback? onTap;
  final void Function({bool pad})? feel;
  final bool autofocus;
  final bool lit;
  final String semantics;
  final Widget child;
  const CartoonKey({
    super.key,
    required this.t,
    required this.height,
    required this.child,
    required this.semantics,
    this.bg,
    this.radius,
    this.onTap,
    this.feel,
    this.autofocus = false,
    this.lit = false,
  });

  @override
  State<CartoonKey> createState() => _CartoonKeyState();
}

class _CartoonKeyState extends State<CartoonKey> {
  bool _focused = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final radius = widget.radius ?? t.keyRadius;
    final bg = widget.bg ?? t.keyBg;
    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 50),
      height: widget.height,
      transform: Matrix4.translationValues(0, _down ? 4 : 0, 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _down ? Color.lerp(bg, t.ink, 0.18) : bg,
        borderRadius: radius,
        border: Border.all(color: t.ink, width: 4),
        boxShadow: [
          if (!_down) BoxShadow(color: t.ink, offset: const Offset(0, 5)),
          if (t.glow && widget.bg == null)
            BoxShadow(color: t.keyInk.withValues(alpha: 0.25), blurRadius: 10),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: widget.lit || (t.keyInset != null && widget.bg == null)
            ? Border.all(color: widget.lit ? t.focus : t.keyInset!, width: 3)
            : null,
      ),
      child: widget.child,
    );
    final focusRing = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: _focused ? Border.all(color: t.focus, width: 5, strokeAlign: BorderSide.strokeAlignOutside) : null,
      ),
      child: face,
    );
    if (widget.onTap == null) return Semantics(label: widget.semantics, child: focusRing);
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
          child: focusRing,
        ),
      ),
    );
  }
}
