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
    this.onShowChat,
  });

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final portrait = c.maxHeight >= c.maxWidth;
      final inner = portrait ? _portrait(c.maxHeight) : _landscape(c.maxWidth);
      return ShellBox(
        color: t.body,
        pattern: t.pattern,
        ink: t.ink,
        shadow: false,
        radius: BorderRadius.circular(36),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: SizedBox.expand(child: inner),
      );
    });
  }

  // ------------------------------------------------------------ layouts

  Widget _portrait(double h) {
    // Screen on top, a row of soft keys, then the keys take the rest.
    final screenH = (h * (letters ? 0.36 : 0.32)).clamp(150.0, 360.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: screenH, child: _screenBox()),
      const SizedBox(height: 10),
      SizedBox(height: 50, child: _softRow(withSend: !letters)),
      const SizedBox(height: 10),
      Expanded(child: letters ? _qwerty() : _keypad()),
    ]);
  }

  Widget _landscape(double w) {
    // Screen on the left with the soft keys under it, keys on the right.
    final screenW = (w * (letters ? 0.3 : 0.42)).clamp(200.0, 460.0);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: screenW,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _screenBox()),
          const SizedBox(height: 10),
          SizedBox(height: 46, child: _softRow(withSend: !letters, compact: true)),
        ]),
      ),
      const SizedBox(width: 12),
      Expanded(child: letters ? _qwerty() : _keypad()),
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
