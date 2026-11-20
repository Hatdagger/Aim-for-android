import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/input_mode.dart';
import 'retro.dart';
import 't9_phone.dart';

/// Text field that uses the system keyboard (or a hardware keyboard) normally,
/// and switches to a focusable box + built-in T9 phone keypad when the
/// user is on a controller.
class RetroTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final int minLines;
  final int maxLines;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputAction? action;
  final String doneLabel;

  /// When true, Enter submits and Shift+Enter adds a new line (chat input).
  final bool enterSubmits;
  final FocusNode? focusNode;

  /// Recent messages to show on the phone keyboard's little screen.
  final List<OskLine> Function()? oskPreview;
  final Listenable? oskPreviewListen;

  const RetroTextField({
    super.key,
    required this.controller,
    this.hint = '',
    this.obscure = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
    this.action,
    this.doneLabel = 'Done',
    this.enterSubmits = false,
    this.focusNode,
    this.oskPreview,
    this.oskPreviewListen,
  });

  @override
  Widget build(BuildContext context) {
    final pad = context.watch<InputMode>().controller;
    if (pad) {
      return ListenableBuilder(
        listenable: controller,
        builder: (ctx, _) {
          final t = controller.text;
          final shown = t.isEmpty ? hint : (obscure ? '•' * t.length : t);
          return RetroListTile(
            autofocus: autofocus,
            onTap: () => context.read<OskController>().open(
              controller: controller,
              title: hint.isEmpty ? 'Type' : hint,
              obscure: obscure,
              doneLabel: doneLabel,
              preview: oskPreview,
              previewListen: oskPreviewListen,
              onDone: () {
                onChanged?.call(controller.text);
                onSubmitted?.call(controller.text);
              },
            ),
            child: Sunken(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Text(shown,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.isEmpty ? Retro.shadow : Colors.black, fontSize: 15)),
                ),
                const Icon(Icons.keyboard, size: 18, color: Retro.shadow),
              ]),
            ),
          );
        },
      );
    }
    Widget field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: obscure,
      minLines: obscure ? 1 : minLines,
      maxLines: obscure ? 1 : maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: () => context.read<InputMode>().noteTouchOrKeyboard(),
      keyboardType: maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      textInputAction: action ?? (maxLines > 1 && !enterSubmits ? TextInputAction.newline : TextInputAction.done),
      style: const TextStyle(fontSize: 15, color: Colors.black),
      cursorColor: Colors.black,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: InputBorder.none,
      ),
    );
    if (enterSubmits) {
      field = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, e) {
          if (e is KeyDownEvent &&
              (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) &&
              !HardwareKeyboard.instance.isShiftPressed) {
            onSubmitted?.call(controller.text);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: field,
      );
    }
    return Container(decoration: bevel(sunken: true, color: Colors.white), child: field);
  }
}
