import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/input_mode.dart';
import '../app/numpad_t9.dart';
import '../app/platform_bridge.dart';
import '../app/settings.dart';
import '../app/t9.dart';
import 'phone_art.dart';
import 'phone_theme.dart';
import 'retro.dart';

/// A recent chat line shown on the phone's little screen.
class OskLine {
  final String who;
  final String text;
  final bool mine;
  const OskLine(this.who, this.text, this.mine);
}

/// Session the phone is editing.
class OskRequest {
  final TextEditingController controller;
  final String title;
  final bool obscure;
  final String doneLabel;
  final VoidCallback? onDone;
  final FocusNode? returnFocus;
  final List<OskLine> Function()? preview;
  final Listenable? previewListen;
  OskRequest(this.controller, this.title, this.obscure, this.doneLabel, this.onDone, this.returnFocus,
      {this.preview, this.previewListen});
}

class OskController extends ChangeNotifier {
  OskRequest? current;

  /// Set by the host: true when the phone sits beside the app (landscape).
  bool wide = false;

  /// Controller "move and resize" mode (RB), landscape only.
  bool arranging = false;

  /// Set by the open phone so the keyboard's number pad presses its keys.
  void Function(String key)? numpadSink;

  void open({
    required TextEditingController controller,
    String title = 'Type',
    bool obscure = false,
    String doneLabel = 'Done',
    VoidCallback? onDone,
    List<OskLine> Function()? preview,
    Listenable? previewListen,
  }) {
    current = OskRequest(controller, title, obscure, doneLabel, onDone, FocusManager.instance.primaryFocus,
        preview: preview, previewListen: previewListen);
    notifyListeners();
  }

  void close({bool submitted = false}) {
    final r = current;
    current = null;
    arranging = false;
    notifyListeners();
    if (r == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final f = r.returnFocus;
      if (f != null && f.context != null) f.requestFocus();
      if (submitted) r.onDone?.call();
    });
  }

  void toggleArrange() {
    arranging = wide && !arranging;
    notifyListeners();
  }

  /// D-pad moves the phone, X shrinks, Y grows, A/B/RB/Start finish.
  bool arrangePad(PadAction a, AppSettings s) {
    final k = s.keyboardKind;
    switch (a) {
      case PadAction.up:
        s.setOskPlacement(k, y: s.oskY(k) - 0.1);
      case PadAction.down:
        s.setOskPlacement(k, y: s.oskY(k) + 0.1);
      case PadAction.left:
        s.setOskPlacement(k, x: s.oskX(k) - 0.1);
      case PadAction.right:
        s.setOskPlacement(k, x: s.oskX(k) + 0.1);
      case PadAction.x:
        s.setOskPlacement(k, width: s.oskWidth(k) - 0.04);
      case PadAction.y:
        s.setOskPlacement(k, width: s.oskWidth(k) + 0.04);
      default:
        arranging = false;
        notifyListeners();
    }
    return true;
  }
}

/// Wraps the whole app and shows the cartoon phone while typing.
///
/// Portrait: the phone slides up over a dimmed screen (its little screen shows
/// the conversation). Landscape: the phone floats over the app with a soft
/// shadow; it can be dragged anywhere, pinched or dragged by its corner to
/// resize, or arranged with a controller (RB).
/// Full-screen options (Prefs): the phone fills the screen and hides the chat;
/// portrait uses the tall keypad phones, landscape the sideways slider.
class OskHost extends StatefulWidget {
  final Widget child;
  const OskHost({super.key, required this.child});

  @override
  State<OskHost> createState() => _OskHostState();
}

class _OskHostState extends State<OskHost> {
  // Live values while a finger/mouse is moving the phone (saved when it lets go).
  double? _x, _y, _w;
  double _startW = 0;

  static const _bar = 34.0;

  @override
  Widget build(BuildContext context) {
    final osk = context.watch<OskController>();
    final s = context.watch<AppSettings>();
    final req = osk.current;
    return LayoutBuilder(builder: (ctx, c) {
      final W = c.maxWidth, H = c.maxHeight;
      final landscape = W > H * 1.05;
      osk.wide = landscape;
      if (req == null) {
        return Stack(children: [Positioned.fill(child: widget.child)]);
      }
      final full = landscape ? s.phoneFullLandscape : s.phoneFullPortrait;
      final kind = full ? (landscape ? 'qwerty' : 't9') : s.keyboardKind;
      final qwerty = kind == 'qwerty';
      final theme = phoneThemeById(s.phoneStyle);
      final art = PhoneArt.sizeFor(theme, qwerty);
      final aspect = art.width / art.height;
      final phone = CartoonPhone(key: ValueKey('${identityHashCode(req)}-$kind'), request: req, theme: theme, qwerty: qwerty);

      Widget fullToggle(bool on) => Tooltip(
            message: on ? 'Show the chat behind the phone' : 'Phone fills the screen',
            child: RetroButton(
              minWidth: 0,
              minHeight: 34,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () =>
                  landscape ? s.phoneFullLandscape = !on : s.phoneFullPortrait = !on,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(on ? Icons.fullscreen_exit : Icons.fullscreen, size: 18),
                const SizedBox(width: 4),
                Text(on ? 'Show chat' : 'Full screen', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          );

      // ---------------------------------------------------- full screen
      if (full) {
        const pad = 10.0, top = 52.0;
        var w = W - pad * 2;
        var h = w / aspect;
        if (h > H - top - pad) {
          h = H - top - pad;
          w = h * aspect;
        }
        return Stack(children: [
          Positioned.fill(child: widget.child),
          const Positioned.fill(child: ColoredBox(color: Retro.desktop)),
          Positioned(left: (W - w) / 2, top: top + (H - top - pad - h) / 2, width: w, height: h, child: phone),
          Positioned(left: 8, top: 8, child: SafeArea(child: fullToggle(true))),
        ]);
      }

      if (!landscape) {
        var w = qwerty ? W : min(W * 0.98, H * 0.66 * aspect);
        var h = w / aspect;
        if (h > H * 0.72) {
          h = H * 0.72;
          w = h * aspect;
        }
        return Stack(children: [
          Positioned.fill(child: widget.child),
          Positioned.fill(
            child: GestureDetector(
              onTap: () => osk.close(),
              child: const ColoredBox(color: Color(0x66000000)),
            ),
          ),
          Positioned(left: (W - w) / 2, width: w, bottom: 0, height: h, child: SafeArea(top: false, child: phone)),
          Positioned(right: 8, bottom: h + 8, child: fullToggle(false)),
        ]);
      }

      // ---------------------------------------------------- landscape, floating
      final x = _x ?? s.oskX(kind), y = _y ?? s.oskY(kind);
      final wf = (_w ?? s.oskWidth(kind)).clamp(AppSettings.oskMinWidth, AppSettings.oskMaxWidth);
      var w = wf * W;
      var h = w / aspect + _bar;
      if (h > H) {
        h = H;
        w = (H - _bar) * aspect;
      }
      final freeX = max(1.0, W - w), freeY = max(1.0, H - h);
      final left = freeX * x, top = freeY * y;
      final onRight = left + w / 2 > W / 2;

      void move(Offset d) => setState(() {
            _x = ((_x ?? x) + d.dx / freeX).clamp(0.0, 1.0);
            _y = ((_y ?? y) + d.dy / freeY).clamp(0.0, 1.0);
          });
      void resize(double newWf) =>
          setState(() => _w = newWf.clamp(AppSettings.oskMinWidth, AppSettings.oskMaxWidth));
      void save() {
        s.setOskPlacement(kind, x: _x, y: _y, width: _w);
        setState(() => _x = _y = _w = null);
      }

      return Stack(children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: left,
          top: top,
          width: w,
          height: h,
          child: Stack(clipBehavior: Clip.none, children: [
            Column(children: [
              _ArrangeBar(
                height: _bar,
                arranging: osk.arranging,
                onMove: move,
                onMoveEnd: save,
                onSmaller: () => s.setOskPlacement(kind, width: wf - 0.04),
                onBigger: () => s.setOskPlacement(kind, width: wf + 0.04),
                onDock: () => s.setOskPlacement(kind, x: 1.0, y: 0.5, width: qwerty ? 0.5 : 1 / 3),
                onFull: () => s.phoneFullLandscape = true,
                onWheel: (dy) {
                  resize((_w ?? wf) - dy * 0.0006);
                  save();
                },
              ),
              Expanded(
                child: GestureDetector(
                  // One finger drags the phone, two fingers pinch to resize.
                  onScaleStart: (_) => _startW = wf,
                  onScaleUpdate: (d) {
                    if (d.pointerCount >= 2) resize(_startW * d.scale);
                    move(d.focalPointDelta);
                  },
                  onScaleEnd: (_) => save(),
                  child: phone,
                ),
              ),
            ]),
            // Corner grip: drag outwards to grow, inwards to shrink.
            Positioned(
              left: onRight ? -6 : null,
              right: onRight ? null : -6,
              bottom: -6,
              child: GestureDetector(
                onPanStart: (_) => _startW = wf,
                onPanUpdate: (d) {
                  final dx = onRight ? -d.delta.dx : d.delta.dx;
                  resize((_w ?? wf) + (dx + d.delta.dy * 0.5) / W);
                },
                onPanEnd: (_) => save(),
                child: MouseRegion(
                  cursor: onRight ? SystemMouseCursors.resizeDownLeft : SystemMouseCursors.resizeDownRight,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(onRight ? Icons.south_west : Icons.south_east, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]);
    });
  }
}

/// Registered before the app starts so it sees Back first: while the phone
/// keyboard is open, Back closes it (showing the chat); the next Back then
/// leaves the chat as usual.
class OskBackObserver with WidgetsBindingObserver {
  final OskController osk;
  OskBackObserver(this.osk);

  @override
  Future<bool> didPopRoute() async {
    if (osk.current == null) return false;
    osk.close();
    return true;
  }
}

class _ArrangeBar extends StatelessWidget {
  final double height;
  final bool arranging;
  final void Function(Offset) onMove;
  final VoidCallback onMoveEnd, onSmaller, onBigger, onDock, onFull;
  final void Function(double dy) onWheel;
  const _ArrangeBar({
    required this.height,
    required this.arranging,
    required this.onMove,
    required this.onMoveEnd,
    required this.onSmaller,
    required this.onBigger,
    required this.onDock,
    required this.onFull,
    required this.onWheel,
  });

  Widget _btn(IconData i, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkResponse(
          onTap: onTap,
          radius: 18,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(i, color: Colors.white, size: 20)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) onWheel(e.scrollDelta.dy);
      },
      child: Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: arranging ? const Color(0xEE1F4FBF) : const Color(0xAA000000),
          borderRadius: BorderRadius.circular(height / 2),
          border: arranging ? Border.all(color: const Color(0xFFFFE000), width: 2) : null,
        ),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => onMove(d.delta),
              onPanEnd: (_) => onMoveEnd(),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Row(children: [
                  const SizedBox(width: 10),
                  const Icon(Icons.open_with, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      arranging ? 'D-pad move · X smaller · Y bigger · A done' : 'Drag to move · pinch or corner to resize',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          _btn(Icons.remove_circle_outline, 'Smaller', onSmaller),
          _btn(Icons.add_circle_outline, 'Bigger', onBigger),
          _btn(Icons.vertical_align_center, 'Put back on the right', onDock),
          _btn(Icons.fullscreen, 'Phone fills the screen', onFull),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }
}

/// The animated, working phone: rises in, opens (flip lid / slider screen),
/// powers on its screen, then types into [request].
class CartoonPhone extends StatefulWidget {
  final OskRequest request;
  final PhoneTheme theme;
  final bool qwerty;
  const CartoonPhone({super.key, required this.request, required this.theme, required this.qwerty});

  @override
  State<CartoonPhone> createState() => _CartoonPhoneState();
}

class _CartoonPhoneState extends State<CartoonPhone> with SingleTickerProviderStateMixin {
  late final T9Engine _engine;
  late final InputMode _input;
  late final AppSettings _settings;
  late final OskController _osk;
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  final _scope = FocusScopeNode(debugLabel: 'Phone keyboard');
  bool _shift = false, _sym = false, _leaving = false;
  static final _never = ValueNotifier<int>(0);

  TextEditingController get _c => widget.request.controller;
  late final NumpadT9 _numpadT9;

  /// A number-pad key (already mapped by position to a phone key).
  void _numpad(String key) {
    _click();
    if (key == 'send') {
      _leave(true);
    } else if (key == 'del') {
      _backspace();
    } else if (key == 'mode') {
      widget.qwerty ? _numpadT9.typeInto(_c, widget.request.obscure, 'mode') : _togglePredictive();
    } else if (widget.qwerty) {
      _numpadT9.typeInto(_c, widget.request.obscure, key);
      setState(() {});
    } else {
      _engine.press(key);
    }
  }

  @override
  void initState() {
    super.initState();
    _settings = context.read<AppSettings>();
    _input = context.read<InputMode>();
    _osk = context.read<OskController>();
    _engine = T9Engine(
      initial: _c.text,
      predictive: _settings.t9Predictive && !widget.request.obscure,
      onText: (t) {
        _c.text = t;
        _c.selection = TextSelection.collapsed(offset: t.length);
        if (mounted) setState(() {});
      },
    );
    if (widget.request.obscure) _engine.caseMode = T9Case.lower;
    T9Dictionary.load().then((d) {
      _engine.dict = d;
      if (mounted) setState(() {});
    });
    _input.pushHandler(_onPad);
    _osk.numpadSink = _numpad;
    _numpadT9 = context.read<NumpadT9>();
    _anim.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scope.requestFocus());
  }

  @override
  void dispose() {
    _input.removeHandler(_onPad);
    if (_osk.numpadSink == _numpad) _osk.numpadSink = null;
    _scope.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _click({bool pad = false}) {
    if (_settings.keyFeedback) PlatformBridge.keyClick(pad: pad);
  }

  // ------------------------------------------------------------ typing

  void _setText(String t) {
    _c.text = t;
    _c.selection = TextSelection.collapsed(offset: t.length);
    setState(() {});
  }

  void _press(String k) {
    if (!widget.qwerty) {
      _engine.press(k);
      return;
    }
    switch (k) {
      case 'shift':
        setState(() => _shift = !_shift);
      case 'sym':
        setState(() {
          _sym = !_sym;
          _shift = false;
        });
      case 'del':
        _backspace();
      case 'space':
        _setText('${_c.text} ');
      case ':)':
        _setText('${_c.text}:) ');
      default:
        final ch = _shift && !_sym ? k.toUpperCase() : k;
        _shift = false;
        _setText(_c.text + ch);
    }
  }

  void _backspace() {
    if (!widget.qwerty) {
      _engine.backspace();
      return;
    }
    final t = _c.text;
    if (t.isNotEmpty) _setText(t.substring(0, t.length - 1));
  }

  bool get _empty => _c.text.isEmpty && (widget.qwerty || !_engine.composing);

  void _togglePredictive() {
    if (widget.qwerty) {
      _press('sym');
      return;
    }
    if (widget.request.obscure) return;
    _engine.togglePredictive();
    _settings.t9Predictive = _engine.predictive;
    setState(() {});
  }

  Future<void> _leave(bool submitted) async {
    if (_leaving) return;
    _leaving = true;
    if (!widget.qwerty) _engine.finish();
    await _anim.animateBack(0, duration: const Duration(milliseconds: 380), curve: Curves.easeIn);
    if (mounted) _osk.close(submitted: submitted);
  }

  bool _onPad(PadAction a) {
    if (_osk.arranging) return _osk.arrangePad(a, _settings);
    const felt = {PadAction.b, PadAction.x, PadAction.y, PadAction.select, PadAction.start, PadAction.lb};
    if (felt.contains(a)) _click(pad: true);
    switch (a) {
      case PadAction.rb:
        _osk.toggleArrange();
        return true;
      case PadAction.b:
        if (_empty) {
          _leave(false);
        } else {
          _backspace();
        }
        return true;
      case PadAction.x:
        widget.qwerty ? _press('space') : _engine.space();
        return true;
      case PadAction.y:
        widget.qwerty ? _press('shift') : _engine.nextCandidate();
        return true;
      case PadAction.select:
        _togglePredictive();
        return true;
      case PadAction.start:
        _leave(true);
        return true;
      case PadAction.lb:
        widget.qwerty ? _press(':)') : _engine.press('#');
        return true;
      default:
        return false;
    }
  }

  // ------------------------------------------------------------ drawing

  double _seg(double v, double a, double b) => ((v - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final keys = PhoneKeys(
      press: _press,
      send: () => _leave(true),
      end: () => _leave(false),
      clear: _backspace,
      mode: _togglePredictive,
      feel: _click,
      sendLabel: widget.request.doneLabel,
      modeLabel: widget.request.obscure ? 'abc' : _engine.modeLabel,
      predictive: _engine.predictive,
      shift: _shift,
      sym: _sym,
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _leave(false)},
      child: FocusScope(
      node: _scope,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (ctx, _) {
          final v = _anim.value;
          final rise = Curves.easeOutBack.transform(_seg(v, 0, 0.4));
          final springs = t.flip || widget.qwerty;
          final open = springs ? Curves.easeInOutCubic.transform(_seg(v, 0.4, 0.66)) : 1.0;
          final squash = springs ? 1.0 : 1 - 0.07 * sin(pi * _seg(v, 0.34, 0.56));
          final power = _seg(v, 0.66, 0.72);
          final splash = v < 0.95;
          return FractionalTranslation(
            translation: Offset(0, (1 - rise) * 1.15),
            child: FittedBox(
              fit: BoxFit.contain,
              child: PhoneArt(
                t: t,
                qwerty: widget.qwerty,
                open: open,
                squash: squash,
                power: power,
                keys: keys,
                screen: splash ? _Splash(t: t) : _screen(t, _seg(v, 0.95, 1)),
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _screen(PhoneTheme t, double fade) {
    final r = widget.request;
    return ListenableBuilder(
      listenable: r.previewListen ?? _never,
      builder: (ctx, _) => Opacity(
        opacity: fade,
        child: MiniScreen(
          t: t,
          title: r.title,
          mode: widget.qwerty ? (_sym ? 'SYM' : (_shift ? 'SHIFT' : 'abc')) : _engine.modeLabel,
          lines: r.preview?.call() ?? const [],
          text: r.obscure ? '•' * _c.text.length : (widget.qwerty ? _c.text : _engine.text),
          footer: !widget.qwerty && _engine.predictive && _engine.candidates.length > 1
              ? '${_engine.candidateIndex + 1}/${_engine.candidates.length}  * next word'
              : 'Send ▸ green key',
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  final PhoneTheme t;
  const _Splash({required this.t});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        child: Text(
          t.splash,
          style: TextStyle(
            color: t.screenInk,
            fontSize: 54,
            fontWeight: FontWeight.w800,
            fontFamily: t.fontFamily,
            fontStyle: t.id == 'gyaru' ? FontStyle.italic : FontStyle.normal,
            shadows: t.glow ? [Shadow(color: t.screenInk.withValues(alpha: 0.7), blurRadius: 10)] : null,
          ),
        ),
      ),
    );
  }
}

/// What the phone's little screen shows: who you're writing to, the last few
/// messages, what you're typing, and a hint line.
class MiniScreen extends StatelessWidget {
  final PhoneTheme t;
  final String title;
  final String mode;
  final List<OskLine> lines;
  final String text;
  final String footer;
  const MiniScreen({
    super.key,
    required this.t,
    required this.title,
    required this.mode,
    required this.lines,
    required this.text,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final fs = t.mono ? 21.0 : 17.0;
    final glow = t.glow ? [Shadow(color: t.screenInk.withValues(alpha: 0.6), blurRadius: 6)] : null;
    return DefaultTextStyle(
      style: TextStyle(color: t.screenInk, fontSize: fs, fontFamily: t.fontFamily, height: 1.15, shadows: glow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(mode, style: TextStyle(color: t.screenDim, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            reverse: true,
            physics: const NeverScrollableScrollPhysics(),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final l in lines)
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${l.who}: ', style: TextStyle(color: l.mine ? t.me : t.them, fontWeight: FontWeight.w800)),
                    TextSpan(text: l.text),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ]),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: t.screenDim, width: 2))),
          child: Text('${text.length > 120 ? '…${text.substring(text.length - 120)}' : text}_',
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        Text(footer, style: TextStyle(color: t.screenDim, fontSize: fs * 0.72, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// A still picture of a phone for the style picker.
class PhonePreview extends StatelessWidget {
  final PhoneTheme t;
  final bool qwerty;
  const PhonePreview({super.key, required this.t, required this.qwerty});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.contain,
        child: PhoneArt(
          t: t,
          qwerty: qwerty,
          keys: const PhoneKeys(),
          screen: MiniScreen(
            t: t,
            title: 'SkaterGrl0414',
            mode: qwerty ? 'abc' : 'T9',
            lines: const [OskLine('SkaterGrl', 'u coming online tonight?', false), OskLine('me', 'ya after dinner', true)],
            text: 'bring ur A game lol',
            footer: 'Send ▸ green key',
          ),
        ),
      ),
    );
  }
}
