import 'package:flutter/material.dart';

import 'phone_art.dart';
import 'phone_theme.dart';
import 'retro.dart';
import 't9_phone.dart';

/// Picks the phone or gadget keyboard for one chat.
///
/// Returns null when cancelled, (null, _) for "use my default keyboard",
/// otherwise (style id, 't9' or 'qwerty').
Future<(String?, String)?> pickKeyboard(BuildContext context,
    {required String style, required String kind, required String name, bool allowDefault = false}) {
  var k = kind;
  return showRetroDialog<(String?, String)>(context, title: 'Keyboard for $name', builder: (ctx) {
    return StatefulBuilder(builder: (ctx, setState) {
      final qwerty = k == 'qwerty';
      Widget tile(PhoneTheme t) {
        final selected = t.id == style;
        final wide = PhoneArt.sizeFor(t, qwerty).aspectRatio > 1.05;
        return SizedBox(
          width: 100,
          child: RetroListTile(
            autofocus: selected,
            onTap: () => Navigator.pop(ctx, (t.id, k)),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFFFE1) : null,
                border: Border.all(color: selected ? Retro.navy : const Color(0x00000000), width: 3),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(height: 112, child: Center(child: SizedBox(height: wide ? 70 : 112, child: PhonePreview(t: t, qwerty: qwerty)))),
                const SizedBox(height: 3),
                Text(t.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
              ]),
            ),
          ),
        );
      }

      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Pick what pops up when you type to $name, even without a controller (unless Controller is set to Never). Other chats keep their own.', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Phones type with: ', style: TextStyle(fontSize: 12)),
            for (final (id, label) in const [('t9', 'Keypad (T9)'), ('qwerty', 'Slide-out QWERTY')])
              RetroButton(
                minWidth: 0,
                selected: k == id,
                onPressed: () => setState(() => k = id),
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
          ]),
          const Text('(Console TV, Pocket Mail, Music Player and Pocket Brick always use their own keyboard.)',
              style: TextStyle(fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [for (final t in kPhoneThemes) tile(t)]),
          if (allowDefault) ...[
            const SizedBox(height: 8),
            RetroButton(onPressed: () => Navigator.pop(ctx, (null, 't9')), child: const Text('Use my default keyboard')),
          ],
          const SizedBox(height: 6),
          RetroButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ]),
      );
    });
  });
}
