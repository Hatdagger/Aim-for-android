import 'package:flutter/material.dart';

import 'retro.dart';

const kPickerColors = [
  0xFF000000, 0xFF404040, 0xFF808080, 0xFFC0C0C0, 0xFFFFFFFF, 0xFFFFFFE1,
  0xFF800000, 0xFFCC0000, 0xFFFF5A5F, 0xFFFF8C00, 0xFFFFD23F, 0xFFFFF176,
  0xFF006400, 0xFF22AA44, 0xFF7CFC00, 0xFF008080, 0xFF00CED1, 0xFFB0F0FF,
  0xFF000080, 0xFF1F4FBF, 0xFF6495ED, 0xFFD6E4FF, 0xFF4B0082, 0xFF7B4AE2,
  0xFFC7A6FF, 0xFFD6247A, 0xFFFF4FA3, 0xFFFFC0DD, 0xFF8B4513, 0xFFE3A948,
];

/// Picks a colour. Returns the colour (ARGB), -1 for "default", or null if cancelled.
Future<int?> pickColor(BuildContext context, {required String title, int? current}) {
  final hex = TextEditingController(
      text: current == null ? '' : (current & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase());
  return showRetroDialog<int>(context, title: title, builder: (ctx) {
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final c in kPickerColors)
            Semantics(
              button: true,
              label: '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
              child: RetroButton(
                minWidth: 40,
                minHeight: 40,
                padding: const EdgeInsets.all(4),
                onPressed: () => Navigator.pop(ctx, c),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Color(c),
                    border: Border.all(color: c == current ? Colors.black : Retro.shadow, width: c == current ? 3 : 1),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Hex #'),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              decoration: bevel(sunken: true, color: Colors.white),
              child: TextField(
                controller: hex,
                maxLength: 6,
                decoration: const InputDecoration(
                    isDense: true, counterText: '', border: InputBorder.none, contentPadding: EdgeInsets.all(8)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          RetroButton(
            minWidth: 0,
            onPressed: () {
              final n = int.tryParse(hex.text.trim().replaceAll('#', ''), radix: 16);
              if (n != null && hex.text.trim().replaceAll('#', '').length == 6) Navigator.pop(ctx, 0xFF000000 | n);
            },
            child: const Text('Use'),
          ),
        ]),
        const SizedBox(height: 8),
        RetroButton(onPressed: () => Navigator.pop(ctx, -1), child: const Text('Back to default')),
        const SizedBox(height: 6),
        RetroButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ]),
    );
  });
}

/// Readable ink for text drawn on [bg].
bool isDark(Color bg) => bg.computeLuminance() < 0.33;
