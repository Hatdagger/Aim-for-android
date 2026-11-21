import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Windows 9x-era look: grey faces, bevelled edges, navy title bars and a
/// teal desktop behind anything that doesn't fill the screen.
class Retro {
  static const desktop = Color(0xFF008080);
  static const face = Color(0xFFC0C0C0);
  static const shadow = Color(0xFF808080);
  static const darkShadow = Color(0xFF000000);
  static const highlight = Color(0xFFFFFFFF);
  static const navy = Color(0xFF000080);
  static const titleEnd = Color(0xFF1084D0);
  static const inactiveTitle = Color(0xFF808080);
  static const myName = Color(0xFFCC0000); // classic AIM: you in red
  static const theirName = Color(0xFF0000CC); // them in blue

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: false,
      brightness: Brightness.light,
      scaffoldBackgroundColor: desktop,
      colorScheme: const ColorScheme.light(primary: navy, secondary: navy, surface: face),
      visualDensity: VisualDensity.standard,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.black, selectionColor: navy),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: Colors.black, displayColor: Colors.black),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.all(Colors.white),
        checkColor: WidgetStateProperty.all(Colors.black),
        side: const BorderSide(color: shadow, width: 2),
        shape: const RoundedRectangleBorder(),
      ),
    );
  }
}

BoxDecoration bevel({bool sunken = false, Color color = Retro.face, bool deep = true}) {
  final tl = sunken ? Retro.shadow : Retro.highlight;
  final br = sunken ? Retro.highlight : (deep ? Retro.darkShadow : Retro.shadow);
  return BoxDecoration(
    color: color,
    border: Border(
      top: BorderSide(color: tl, width: 2),
      left: BorderSide(color: tl, width: 2),
      bottom: BorderSide(color: br, width: 2),
      right: BorderSide(color: br, width: 2),
    ),
  );
}

/// Teal desktop that centres a window when it doesn't need the full screen.
class Desktop extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double? maxHeight;
  const Desktop({super.key, required this.child, this.maxWidth = 420, this.maxHeight});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Retro.desktop,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight ?? double.infinity),
        child: child,
      ),
    );
  }
}

class RetroWindow extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final List<Widget> titleActions;
  final Widget? leading;
  final bool active;
  final EdgeInsets padding;
  const RetroWindow({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.titleActions = const [],
    this.leading,
    this.active = true,
    this.padding = const EdgeInsets.all(6),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: bevel(),
      padding: const EdgeInsets.all(2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: active ? const [Retro.navy, Retro.titleEnd] : const [Retro.inactiveTitle, Color(0xFFB5B5B5)]),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 4)],
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                ...titleActions,
                if (onClose != null) TitleButton(label: '×', onPressed: onClose!, tooltip: 'Close'),
              ],
            ),
          ),
          Flexible(child: Padding(padding: padding, child: child)),
        ],
      ),
    );
  }
}

class TitleButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final String? tooltip;
  const TitleButton({super.key, required this.label, required this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: RetroButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        minWidth: 26,
        minHeight: 22,
        semanticLabel: tooltip,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, height: 1)),
      ),
    );
  }
}

/// Bevelled push button. Focusable with a clear focus ring for controllers.
class RetroButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsets padding;
  final double minWidth;
  final double minHeight;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final bool isDefault;

  /// This is the option currently chosen (in a row of choices): the button
  /// stays pushed in, tinted, with a check mark.
  final bool selected;
  const RetroButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.minWidth = 72,
    this.minHeight = 36,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
    this.isDefault = false,
    this.selected = false,
  });

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _down = false;
  bool _focused = false;

  void _fire() {
    if (widget.onPressed == null) return;
    setState(() => _down = true);
    Future.delayed(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => _down = false);
    });
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      enabled: enabled,
      selected: widget.selected,
      child: FocusableActionDetector(
        enabled: enabled,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onFocusChange: (v) => setState(() => _focused = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _fire())},
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled
              ? (_) {
                  setState(() => _down = false);
                  widget.onPressed!();
                }
              : null,
          child: Container(
            constraints: BoxConstraints(minWidth: widget.minWidth, minHeight: widget.minHeight),
            decoration: widget.isDefault
                ? BoxDecoration(border: Border.all(color: Colors.black, width: 1))
                : null,
            child: Container(
              decoration: bevel(
                  sunken: _down || widget.selected,
                  color: widget.selected ? const Color(0xFFFFFFE1) : Retro.face),
              padding: widget.padding,
              alignment: Alignment.center,
              foregroundDecoration: _focused
                  ? BoxDecoration(border: Border.all(color: Retro.navy, width: 3))
                  : null,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: enabled ? Colors.black : Retro.shadow, fontSize: 14),
                child: IconTheme.merge(
                  data: IconThemeData(color: enabled ? Colors.black : Retro.shadow, size: 20),
                  child: Transform.translate(
                    offset: _down || widget.selected ? const Offset(1, 1) : Offset.zero,
                    child: widget.selected
                        ? DefaultTextStyle.merge(
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.check, size: 16),
                              const SizedBox(width: 4),
                              Flexible(child: widget.child),
                            ]),
                          )
                        : widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White sunken well (lists, text areas).
class Sunken extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  const Sunken({super.key, required this.child, this.padding = const EdgeInsets.all(2), this.color = Colors.white});

  @override
  Widget build(BuildContext context) => Container(decoration: bevel(sunken: true, color: color), padding: padding, child: child);
}

/// A focusable row (buddy list entries etc.) with Win9x selection colours.
class RetroListTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  const RetroListTile({super.key, required this.child, this.onTap, this.onLongPress, this.autofocus = false});

  @override
  State<RetroListTile> createState() => _RetroListTileState();
}

class _RetroListTileState extends State<RetroListTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (v) {
        setState(() => _focused = v);
        if (v) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 120));
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.contextMenu): _ContextIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonY): _ContextIntent(),
      },
      child: Actions(
        actions: {
          _ContextIntent: CallbackAction<_ContextIntent>(onInvoke: (_) {
            widget.onLongPress?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onLongPress,
          child: Container(
            color: _focused ? Retro.navy : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: _focused ? Colors.white : Colors.black),
              child: IconTheme.merge(data: IconThemeData(color: _focused ? Colors.white : Colors.black), child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextIntent extends Intent {
  const _ContextIntent();
}

class RetroCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  const RetroCheckbox({super.key, required this.value, required this.onChanged, required this.label});

  @override
  Widget build(BuildContext context) {
    return RetroListTile(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: bevel(sunken: true, color: Colors.white),
            alignment: Alignment.center,
            child: value ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

Future<T?> showRetroDialog<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: const Color(0x55000000),
    pageBuilder: (ctx, a1, a2) => SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: Colors.transparent,
              child: RetroWindow(title: title, onClose: () => Navigator.of(ctx).pop(), child: builder(ctx)),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> showRetroMessage(BuildContext context, String title, String message) {
  return showRetroDialog<void>(
    context,
    title: title,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(message)),
        Align(
          alignment: Alignment.centerRight,
          child: RetroButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ),
      ],
    ),
  );
}

/// Generic "person" picture for buddies without an icon (no AOL artwork).
class BuddyAvatar extends StatelessWidget {
  final List<int>? bytes;
  final double size;
  final bool dim;
  const BuddyAvatar({super.key, this.bytes, this.size = 28, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final b = bytes;
    Widget inner;
    if (b != null && b.isNotEmpty) {
      inner = Image.memory(
        b is Uint8List ? b : Uint8List.fromList(b),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.none,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    } else {
      inner = _fallback();
    }
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: Container(decoration: bevel(sunken: true, color: Colors.white), padding: const EdgeInsets.all(1), child: inner),
    );
  }

  Widget _fallback() => Container(
        width: size,
        height: size,
        color: const Color(0xFFFFE680),
        child: Icon(Icons.person, size: size * 0.8, color: const Color(0xFF806000)),
      );
}
