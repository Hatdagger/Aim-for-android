import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/input_mode.dart';
import '../app/platform_bridge.dart';
import '../app/settings.dart';
import '../app/t9.dart';
import 'retro.dart';

/// Original early-2000s phone looks for the keypad (no real brands).
class PhoneStyle {
  final String id;
  final String name;
  final List<Color> body;
  final Color screen;
  final Color screenInk;
  final Color key;
  final Color keyInk;
  final Color accent;
  final double radius;
  final bool antenna;
  final bool flip;
  final bool slider;
  const PhoneStyle({
    required this.id,
    required this.name,
    required this.body,
    required this.screen,
    required this.screenInk,
    required this.key,
    required this.keyInk,
    required this.accent,
    this.radius = 36,
    this.antenna = false,
    this.flip = false,
    this.slider = false,
  });
}

const kPhoneStyles = [
  PhoneStyle(
    id: 'candybar',
    name: 'Candy Bar',
    body: [Color(0xFF2A4C9C), Color(0xFF15275A)],
    screen: Color(0xFF9BBC0F),
    screenInk: Color(0xFF0F380F),
    key: Color(0xFFE8ECF4),
    keyInk: Color(0xFF15275A),
    accent: Color(0xFFB0C4FF),
    radius: 44,
  ),
  PhoneStyle(
    id: 'flip',
    name: 'Flip',
    body: [Color(0xFFD9DCE1), Color(0xFF8E949C)],
    screen: Color(0xFFBFE3FF),
    screenInk: Color(0xFF0A2A4A),
    key: Color(0xFF3B3F45),
    keyInk: Color(0xFF7FD4FF),
    accent: Color(0xFF5A6068),
    radius: 28,
    flip: true,
  ),
  PhoneStyle(
    id: 'slider',
    name: 'Slider',
    body: [Color(0xFF2B2B2B), Color(0xFF050505)],
    screen: Color(0xFFFFB347),
    screenInk: Color(0xFF3A1A00),
    key: Color(0xFF1C1C1C),
    keyInk: Color(0xFFFF9A1F),
    accent: Color(0xFFC0C0C0),
    radius: 18,
    slider: true,
  ),
  PhoneStyle(
    id: 'brick',
    name: 'Brick',
    body: [Color(0xFF6E7468), Color(0xFF3E423A)],
    screen: Color(0xFF8FB08A),
    screenInk: Color(0xFF162414),
    key: Color(0xFFD8D2C0),
    keyInk: Color(0xFF2A2A2A),
    accent: Color(0xFFE05A3A),
    radius: 14,
    antenna: true,
  ),
];

PhoneStyle phoneStyleById(String id) => kPhoneStyles.firstWhere((s) => s.id == id, orElse: () => kPhoneStyles.first);

/// Session the keypad is editing.
class OskRequest {
  final TextEditingController controller;
  final String title;
  final bool obscure;
  final String doneLabel;
  final VoidCallback? onDone;
  final FocusNode? returnFocus;
  OskRequest(this.controller, this.title, this.obscure, this.doneLabel, this.onDone, this.returnFocus);
}

class OskController extends ChangeNotifier {
  OskRequest? current;

  void open({
    required TextEditingController controller,
    String title = 'Type',
    bool obscure = false,
    String doneLabel = 'Done',
    VoidCallback? onDone,
  }) {
    current = OskRequest(controller, title, obscure, doneLabel, onDone, FocusManager.instance.primaryFocus);
    notifyListeners();
  }

  void close({bool submitted = false}) {
    final r = current;
    current = null;
    notifyListeners();
    if (r == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final f = r.returnFocus;
      if (f != null && f.context != null) f.requestFocus();
      if (submitted) r.onDone?.call();
    });
  }
}

/// Wraps the whole app: docks the phone beside the content (landscape) or
/// below it (portrait) so it never covers the conversation.
class OskHost extends StatelessWidget {
  final Widget child;
  const OskHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final req = context.watch<OskController>().current;
    if (req == null) return child;
    return LayoutBuilder(builder: (ctx, c) {
      final landscape = c.maxWidth > c.maxHeight * 1.05;
      final phone = Material(
        color: Retro.desktop,
        child: SafeArea(child: T9Phone(key: ValueKey(req), request: req, compact: !landscape)),
      );
      if (landscape) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: child),
          SizedBox(width: (c.maxWidth * 0.36).clamp(250.0, 330.0).toDouble(), child: phone),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: child),
        SizedBox(height: (c.maxHeight * 0.42).clamp(200.0, 290.0).toDouble(), child: phone),
      ]);
    });
  }
}

class T9Phone extends StatefulWidget {
  final OskRequest request;
  final bool compact;
  const T9Phone({super.key, required this.request, this.compact = false});

  @override
  State<T9Phone> createState() => _T9PhoneState();
}

class _T9PhoneState extends State<T9Phone> {
  late final T9Engine _engine;
  late final InputMode _input;
  late final AppSettings _settings;
  final _scope = FocusScopeNode(debugLabel: 'T9 phone');

  @override
  void initState() {
    super.initState();
    _settings = context.read<AppSettings>();
    _input = context.read<InputMode>();
    final c = widget.request.controller;
    _engine = T9Engine(
      initial: c.text,
      predictive: _settings.t9Predictive && !widget.request.obscure,
      onText: (t) {
        c.text = t;
        c.selection = TextSelection.collapsed(offset: t.length);
        if (mounted) setState(() {});
      },
    );
    if (widget.request.obscure) _engine.caseMode = T9Case.lower;
    T9Dictionary.load().then((d) {
      _engine.dict = d;
      if (mounted) setState(() {});
    });
    _input.pushHandler(_onPad);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scope.requestFocus());
  }

  @override
  void dispose() {
    _input.removeHandler(_onPad);
    _scope.dispose();
    super.dispose();
  }

  void _click({bool pad = false}) {
    if (_settings.keyFeedback) PlatformBridge.keyClick(pad: pad);
  }

  bool _onPad(PadAction a) {
    const felt = {PadAction.b, PadAction.x, PadAction.y, PadAction.select, PadAction.start, PadAction.lb};
    if (felt.contains(a)) _click(pad: true);
    switch (a) {
      case PadAction.b:
        if (widget.request.controller.text.isEmpty && !_engine.composing) {
          _done(false);
        } else {
          _engine.backspace();
        }
        return true;
      case PadAction.x:
        _engine.space();
        return true;
      case PadAction.y:
        _engine.nextCandidate();
        return true;
      case PadAction.select:
        _togglePredictive();
        return true;
      case PadAction.start:
        _done(true);
        return true;
      case PadAction.lb:
        _engine.press('#');
        return true;
      default:
        return false;
    }
  }

  void _togglePredictive() {
    if (widget.request.obscure) return;
    _engine.togglePredictive();
    _settings.t9Predictive = _engine.predictive;
    setState(() {});
  }

  void _done(bool submitted) {
    _engine.finish();
    context.read<OskController>().close(submitted: submitted);
  }

  @override
  Widget build(BuildContext context) {
    final style = phoneStyleById(context.watch<AppSettings>().phoneStyle);
    return FocusScope(
      node: _scope,
      child: LayoutBuilder(builder: (ctx, c) {
        final keyH = widget.compact ? 40.0 : 46.0;
        // Just the keypad for now (no phone screen, no scrolling): it shrinks
        // to fit the space it's given instead.
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: widget.compact ? 420 : 300,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: style.body, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(2, 4))],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _softKeys(style),
                    const SizedBox(height: 6),
                    for (final row in const [
                      ['1', '2', '3'],
                      ['4', '5', '6'],
                      ['7', '8', '9'],
                      ['*', '0', '#'],
                    ])
                      Row(children: [for (final k in row) Expanded(child: _key(style, k, keyH))]),
                  ]),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // Phone screen and style picker: kept for the keyboard rework.
  // ignore: unused_element
  Widget _screen(PhoneStyle s) {
    final e = _engine;
    final text = widget.request.obscure ? '•' * widget.request.controller.text.length : e.text;
    final cands = e.candidates;
    return Container(
      height: widget.compact ? 86 : 110,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: s.screen,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x55000000), width: 3),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: s.screenInk, fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(widget.request.title, overflow: TextOverflow.ellipsis)),
            Text(e.modeLabel),
          ]),
          Container(height: 1, color: s.screenInk.withValues(alpha: 0.4), margin: const EdgeInsets.symmetric(vertical: 3)),
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text('$text▏', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            ),
          ),
          if (e.predictive && cands.length > 1)
            Text('${e.candidateIndex + 1}/${cands.length}  * next', style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _softKeys(PhoneStyle s) {
    return Row(children: [
      Expanded(child: _pill(s, 'Clear', _engine.backspace)),
      const SizedBox(width: 6),
      Expanded(
        child: _pill(s, widget.request.obscure ? 'abc' : (_engine.predictive ? 'T9 on' : 'T9 off'), _togglePredictive),
      ),
      const SizedBox(width: 6),
      Expanded(child: _pill(s, widget.request.doneLabel, () => _done(true))),
    ]);
  }

  Widget _pill(PhoneStyle s, String label, VoidCallback onTap) => _PhoneButton(
        onFeel: _click,
        color: s.accent,
        ink: s.body.last,
        height: 34,
        radius: 17,
        onTap: onTap,
        child: Text(label, style: TextStyle(color: s.body.last, fontWeight: FontWeight.bold, fontSize: 13)),
      );

  Widget _key(PhoneStyle s, String k, double h) {
    final sub = switch (k) {
      '1' => '.,?!',
      '0' => '␣',
      '*' => _engine.predictive ? 'next' : '',
      '#' => 'Aa',
      _ => (kT9Letters[k] ?? '').toUpperCase(),
    };
    return Padding(
      padding: const EdgeInsets.all(3),
      child: _PhoneButton(
        onFeel: _click,
        color: s.key,
        ink: s.keyInk,
        height: h,
        radius: s.radius > 30 ? 14 : 8,
        autofocus: k == '5',
        onTap: () => _engine.press(k),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(k, style: TextStyle(color: s.keyInk, fontSize: 18, fontWeight: FontWeight.bold, height: 1)),
          if (sub.isNotEmpty) Text(sub, style: TextStyle(color: s.keyInk.withValues(alpha: 0.75), fontSize: 9, height: 1.2)),
        ]),
      ),
    );
  }

  // ignore: unused_element
  Widget _styleRow() {
    final current = context.watch<AppSettings>().phoneStyle;
    return Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
      for (final s in kPhoneStyles)
        RetroButton(
          minWidth: 0,
          minHeight: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          onPressed: () => _settings.phoneStyle = s.id,
          child: Text(s.name, style: TextStyle(fontSize: 12, fontWeight: current == s.id ? FontWeight.bold : FontWeight.normal)),
        ),
    ]);
  }
}

/// Rounded phone key: tappable, and focusable for D-pad + A.
class _PhoneButton extends StatefulWidget {
  final Color color;
  final Color ink;
  final double height;
  final double radius;
  final bool autofocus;
  final VoidCallback onTap;
  final void Function({bool pad})? onFeel;
  final Widget child;
  const _PhoneButton({
    this.onFeel,
    required this.color,
    required this.ink,
    required this.height,
    required this.radius,
    required this.onTap,
    required this.child,
    this.autofocus = false,
  });

  @override
  State<_PhoneButton> createState() => _PhoneButtonState();
}

class _PhoneButtonState extends State<_PhoneButton> {
  bool _focused = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onFeel?.call(pad: true);
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          widget.onFeel?.call(pad: false); // buzz the moment the key goes down
          setState(() => _down = true);
        },
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _down ? Color.lerp(widget.color, Colors.black, 0.25) : widget.color,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: _focused ? const Color(0xFFFFE000) : const Color(0x33000000), width: _focused ? 3 : 1),
            boxShadow: _down ? null : const [BoxShadow(color: Color(0x55000000), offset: Offset(0, 2), blurRadius: 1)],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
