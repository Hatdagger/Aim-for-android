import 'dart:math';

import 'package:flutter/material.dart';

import '../app/t9.dart';
import 'phone_art.dart';
import 'phone_theme.dart';

/// The phone laid out to fill the whole screen (full-screen setting).
///
/// The normal phones are drawn at a fixed design size and scaled to fit, which
/// leaves empty space and small keys on a real touch screen. Here the phone's
/// body is the screen: the little screen sits on top (portrait) or on the left
/// (landscape) and the keys stretch to fill everything else, so each key is as
/// big as the screen allows. Colours, key shapes and patterns come from the
/// chosen phone style.
class FullPhoneArt extends StatelessWidget {
  final PhoneTheme t;

  /// Letter-by-letter keyboard (true) or the T9 keypad (false).
  final bool letters;
  final Widget screen;

  /// 0 = screen off, 1 = on.
  final double power;

  /// Opening animation, 0 = closed, 1 = open: flip phones fold their screen
  /// lid open over the keys; sliders and gadgets slide their keys out.
  final double open;

  /// Vertical squash when a candybar lands (1 = none).
  final double squash;
  final PhoneKeys keys;

  /// Leaves full screen (shows the chat behind the phone again).
  final VoidCallback? onShowChat;

  const FullPhoneArt({
    super.key,
    required this.t,
    required this.letters,
    required this.screen,
    required this.keys,
    this.power = 1,
    this.open = 1,
    this.squash = 1,
    this.onShowChat,
  });

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final portrait = c.maxHeight >= c.maxWidth;
      final inner = portrait
          ? _portrait(c.maxHeight)
          : (t.device == Device.wideT9 ? _wideLandscape(c.maxHeight) : _landscape(c.maxWidth));
      return Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.diagonal3Values(1 + (1 - squash) * 0.6, squash, 1),
        child: ShellBox(
        color: t.body,
        pattern: t.pattern,
        ink: t.ink,
        shadow: false,
        radius: BorderRadius.circular(36),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: SizedBox.expand(child: inner),
      ));
    });
  }

  // ------------------------------------------------------------ layouts

  /// A flip phone typing on its keypad: the screen is a lid that folds open.
  bool get _flips => !letters && t.flip;

  /// Everything else that opens with a moving part slides its keys out.
  bool get _slides => !_flips && (letters || t.ownKeyboard);

  /// The keys, sliding out from under the screen while the phone opens.
  Widget _keysPart(Offset closed) => _slideIn(letters ? _qwerty() : _keypad(), closed);

  Widget _slideIn(Widget k, Offset closed) {
    if (!_slides || open >= 1) return k;
    return ClipRect(child: FractionalTranslation(translation: closed * (1 - open), child: k));
  }

  /// The screen; on a flip phone it folds about [hinge] ([vertical]: top to
  /// bottom, else sideways), showing the outside of the lid while shut.
  Widget _lid(Widget front, {required Alignment hinge, required bool vertical}) {
    if (!_flips || open >= 1) return front;
    final angle = (1 - open) * pi; // 0 = open, pi = folded over the keys
    final m = Matrix4.identity()..setEntry(3, 2, 0.0011);
    if (vertical) {
      m.rotateX(-angle);
    } else {
      m.rotateY(angle);
    }
    final back = Transform(
      alignment: Alignment.center,
      transform: vertical ? Matrix4.rotationX(pi) : Matrix4.rotationY(pi),
      child: _lidBack(),
    );
    return Transform(alignment: hinge, transform: m, child: angle > pi / 2 ? back : front);
  }

  /// Outside of the lid: the shell colour with a little clock display.
  Widget _lidBack() {
    final now = TimeOfDay.now();
    return ShellBox(
      color: t.shell,
      pattern: t.shellPattern,
      ink: t.ink,
      shadow: false,
      radius: BorderRadius.circular(26),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: t.screenOn,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: t.ink, width: 5),
          ),
          child: Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}',
              style: TextStyle(color: t.screenInk, fontSize: 30, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  Widget _portrait(double h) {
    // Screen on top, a row of soft keys, then the keys take the rest. The
    // screen is drawn last so a flip lid folds down over the keys.
    final screenH = (h * (letters ? 0.36 : 0.32)).clamp(150.0, 360.0);
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: screenH),
          const SizedBox(height: 10),
          SizedBox(height: 50, child: _softRow(withSend: !letters)),
          const SizedBox(height: 10),
          Expanded(child: _keysPart(const Offset(0, 1))),
        ]),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: screenH,
        child: _lid(_screenBox(), hinge: Alignment.bottomCenter, vertical: true),
      ),
    ]);
  }

  Widget _landscape(double w) {
    // Screen on the left with the soft keys under it, keys on the right. A
    // flip lid folds sideways over the keys.
    final screenW = (w * (letters ? 0.3 : 0.42)).clamp(200.0, 460.0);
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: screenW),
          const SizedBox(width: 12),
          Expanded(child: _keysPart(const Offset(1, 0))),
        ]),
      ),
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: screenW,
        child: _lid(
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _screenBox()),
            const SizedBox(height: 10),
            SizedBox(height: 46, child: _softRow(withSend: !letters, compact: true)),
          ]),
          hinge: Alignment.centerRight,
          vertical: false,
        ),
      ),
    ]);
  }

  /// Wide T9 on its side: the long screen across the top with End / mode /
  /// Show chat beside it, then the keypad in two rows of eight (half-key gap
  /// down the middle) stretched across the whole width.
  Widget _wideLandscape(double h) {
    final screenH = (h * 0.42).clamp(110.0, 320.0);
    final side = <Widget>[
      _pill('End', kEndRed, t.ink, keys.end),
      _pill(keys.modeLabel, t.softBg, t.softInk, keys.mode),
      if (onShowChat != null) _pill('Show chat', t.softBg, t.softInk, onShowChat, icon: Icons.fullscreen_exit),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: screenH,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _screenBox()),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < side.length; i++) ...[
                if (i > 0) const SizedBox(height: _gap),
                Expanded(child: side[i]),
              ],
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Expanded(child: _slideIn(_wideGrid(), const Offset(0, 1))),
    ]);
  }

  Widget _wideGrid() {
    Widget digit(String d) => _cell(
          d,
          (h) => Column(mainAxisSize: MainAxisSize.min, children: [
            Text(d, style: _keyText((h * 0.42).clamp(18.0, 56.0))),
            if (_sub(d).isNotEmpty)
              Text(_sub(d),
                  style: TextStyle(
                      color: t.keySub, fontSize: (h * 0.17).clamp(10.0, 22.0), fontWeight: FontWeight.w700, height: 1.2)),
          ]),
          autofocus: d == '5',
        );
    Widget fn(String id, String label, Color bg, Color ink, VoidCallback? onTap) => _cell(
          id,
          (h) => Text(label, style: _keyText((h * 0.34).clamp(14.0, 36.0)).copyWith(color: ink)),
          bg: bg,
          onTap: onTap,
        );
    Widget row(List<(int, Widget?)> cells) => Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(flex: cells[i].$1, child: cells[i].$2 ?? const SizedBox()),
            ],
          ]),
        );
    final space = keys.press == null ? null : () => keys.press!('space');
    return Column(children: [
      row([
        (2, digit('1')), (2, digit('2')), (2, digit('3')), (1, null),
        (2, digit('7')), (2, digit('8')), (2, digit('9')),
        (2, fn('clear', '⌫', t.softBg, t.softInk, keys.clear)),
        (2, fn('send', keys.sendLabel, kSendGreen, t.ink, keys.send)),
      ]),
      const SizedBox(height: 10),
      row([
        (2, digit('4')), (2, digit('5')), (2, digit('6')), (1, null),
        (2, digit('*')), (2, digit('0')), (2, digit('#')),
        (4, fn('space', 'SPACE', t.softBg, t.softInk, space)),
      ]),
    ]);
  }

  // ------------------------------------------------------------ pieces

  Widget _screenBox() {
    final bg = Color.lerp(t.screenOff, t.screenOn, power)!;
    return Container(
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

  Widget _pill(String label, Color bg, Color ink, VoidCallback? onTap, {IconData? icon}) {
    return LayoutBuilder(
      builder: (ctx, c) => CartoonKey(
        t: t,
        bg: bg,
        radius: BorderRadius.circular(c.maxHeight / 2),
        height: (c.maxHeight - 6).clamp(20.0, 200.0),
        onTap: onTap,
        feel: keys.feel,
        semantics: label,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: icon != null
                ? Icon(icon, color: ink, size: 22)
                : Text(label, style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }

  Widget _softRow({required bool withSend, bool compact = false}) {
    final items = <(int, Widget)>[
      if (withSend) (5, _pill(keys.sendLabel, kSendGreen, t.ink, keys.send)),
      if (!letters) (4, _pill(keys.modeLabel, t.softBg, t.softInk, keys.mode)),
      if (!letters) (4, _pill('Clear', t.softBg, t.softInk, keys.clear)),
      (4, _pill('End', kEndRed, t.ink, keys.end)),
      if (onShowChat != null) (compact ? 4 : 3, _pill('Show chat', t.softBg, t.softInk, onShowChat, icon: Icons.fullscreen_exit)),
    ];
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: _gap),
        Expanded(flex: items[i].$1, child: items[i].$2),
      ],
    ]);
  }

  TextStyle _keyText(double size) => TextStyle(
        color: t.keyInk,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1,
        shadows: t.glow ? [Shadow(color: t.keyInk.withValues(alpha: 0.7), blurRadius: 8)] : null,
      );

  String _sub(String k) => switch (k) {
        '1' => '.,?!',
        '0' => '␣',
        '*' => keys.predictive ? 'next' : '',
        '#' => 'mode',
        _ => (kT9Letters[k] ?? '').toUpperCase(),
      };

  /// One key that fills its cell; the label grows with the key.
  Widget _cell(String id, Widget Function(double h) label,
      {Color? bg, bool autofocus = false, bool lit = false, BorderRadius? radius, VoidCallback? onTap}) {
    return LayoutBuilder(builder: (ctx, c) {
      final h = (c.maxHeight - 6).clamp(24.0, 400.0);
      return CartoonKey(
        t: t,
        height: h,
        bg: bg,
        radius: radius,
        lit: lit,
        autofocus: autofocus,
        feel: keys.feel,
        semantics: id,
        onTap: onTap ?? (keys.press == null ? null : () => keys.press!(id)),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(fit: BoxFit.scaleDown, child: label(h)),
        ),
      );
    });
  }

  Widget _keypad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];
    return Column(children: [
      for (var r = 0; r < rows.length; r++) ...[
        if (r > 0) const SizedBox(height: 12),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: _cell(
                  rows[r][i],
                  (h) => Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(rows[r][i], style: _keyText((h * 0.42).clamp(18.0, 56.0))),
                    if (_sub(rows[r][i]).isNotEmpty)
                      Text(_sub(rows[r][i]),
                          style: TextStyle(
                              color: t.keySub,
                              fontSize: (h * 0.17).clamp(10.0, 22.0),
                              fontWeight: FontWeight.w700,
                              height: 1.2)),
                  ]),
                  autofocus: rows[r][i] == '5',
                ),
              ),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget _qwerty() {
    final rowsL = keys.sym ? kQwertySymbols : kQwertyLetters;
    final r = BorderRadius.circular(12);
    Widget k(String id, String label, {int flex = 10, Color? bg, Color? ink, bool autofocus = false, bool on = false, VoidCallback? onTap, double scale = 1}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _cell(
              id,
              (h) => Text(label, style: _keyText((h * 0.46 * scale).clamp(12.0, 40.0)).copyWith(color: ink ?? t.keyInk)),
              bg: bg,
              radius: r,
              lit: on,
              autofocus: autofocus,
              onTap: onTap,
            ),
          ),
        );
    Widget row(List<Widget> c, {int pad = 0}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (pad > 0) Spacer(flex: pad),
              ...c,
              if (pad > 0) Spacer(flex: pad),
            ]),
          ),
        );
    return Column(children: [
      row([for (final c in kQwertyNumbers) k(c, c)]),
      row([for (final c in rowsL[0]) k(c, keys.cased(c))]),
      row([for (final c in rowsL[1]) k(c, keys.cased(c), autofocus: c == 'g')], pad: 5),
      row([
        k('shift', '⇧ shift', flex: 15, on: keys.shift, scale: 0.7),
        for (final c in rowsL[2]) k(c, keys.cased(c)),
        k('del', '⌫ del', flex: 15, scale: 0.7),
      ]),
      row([
        k('sym', keys.sym ? 'abc' : 'sym', flex: 14, on: keys.sym, scale: 0.7),
        k(':)', ':)', flex: 10, scale: 0.8),
        k('space', 'SPACE', flex: 46, scale: 0.6),
        k('send', '${keys.sendLabel} ⏎', flex: 24, bg: kSendGreen, ink: t.ink, onTap: keys.send, scale: 0.7),
      ]),
    ]);
  }
}
