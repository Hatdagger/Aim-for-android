import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/history.dart';
import '../oscar/file_transfer.dart';
import '../oscar/oft.dart';
import 'retro.dart';

/// A strip above the messages for one Send File: an offer to answer,
/// waiting, or the files going across with a progress bar.
class FileBar extends StatelessWidget {
  final FileXfer xfer;
  final String name;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancel;

  const FileBar({
    super.key,
    required this.xfer,
    required this.name,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
  });

  Widget _btn(String label, VoidCallback f, {bool primary = false, bool autofocus = false}) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: RetroButton(
          minWidth: 0,
          minHeight: 34,
          isDefault: primary,
          autofocus: autofocus,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          onPressed: f,
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: primary ? FontWeight.bold : FontWeight.normal)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final x = xfer;
    final size = formatBytes(x.totalSize);
    final (Color color, IconData icon, String text, List<Widget> buttons) = switch (x.state) {
      XferState.offered => (
          const Color(0xFFFFF2B3),
          Icons.file_download_outlined,
          '$name wants to send you ${x.label} ($size). If you accept, $name can see your IP address.',
          [_btn('Accept', onAccept, primary: true, autofocus: true), _btn('Decline', onDecline)],
        ),
      XferState.offering => (
          const Color(0xFFE8E8E8),
          Icons.hourglass_top,
          'Waiting for $name to accept ${x.label} ($size)…',
          [_btn('Cancel', onCancel)],
        ),
      XferState.connecting => (
          const Color(0xFFE8E8E8),
          Icons.hourglass_top,
          'Connecting to $name…',
          [_btn('Cancel', onCancel)],
        ),
      _ => (
          const Color(0xFFD8F5D0),
          x.outgoing ? Icons.file_upload_outlined : Icons.file_download_outlined,
          '${x.outgoing ? 'Sending' : 'Receiving'} ${x.label} — '
              '${(100 * x.fraction).floor()}% of $size'
              '${x.speed > 0 ? ' · ${formatBytes(x.speed)}/s' : ''}',
          [_btn('Stop', onCancel)],
        ),
    };
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: bevel(sunken: true, color: color),
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 4,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Text(text, style: const TextStyle(fontSize: 13)),
              ),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: buttons),
          ],
        ),
        if (x.state == XferState.moving)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 2, 2),
            child: Container(
              height: 14,
              decoration: bevel(sunken: true, color: Colors.white, deep: false),
              padding: const EdgeInsets.all(2),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: x.fraction,
                child: Container(color: const Color(0xFF000080)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Received files inside a message bubble. Tap one to open it.
class ChatFiles extends StatelessWidget {
  final List<String> entries;
  final Future<bool> Function(String where) onOpen;
  const ChatFiles({super.key, required this.entries, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Builder(builder: (context) {
            final (name, where) = parseFileEntry(e);
            return RetroButton(
              minWidth: 0,
              minHeight: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              semanticLabel: 'Open $name',
              onPressed: () async {
                final ok = await onOpen(where);
                if (!ok && context.mounted) {
                  showRetroMessage(context, 'Open File', 'No app on this device can open $name.\n\nIt was saved to:\n$where');
                }
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.insert_drive_file_outlined, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, decoration: TextDecoration.underline)),
                ),
              ]),
            );
          }),
        ),
    ]);
  }
}

/// Lets the user pick files with the system's file picker and confirm
/// sending them. Returns (path, name) pairs, or null.
Future<List<(String, String)>?> pickFilesToSend(BuildContext context, String name) async {
  final FilePickerResult? res;
  try {
    res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
  } catch (_) {
    if (context.mounted) showRetroMessage(context, 'Send File', 'Could not open the file picker.');
    return null;
  }
  if (res == null || !context.mounted) return null;
  final files = [
    for (final f in res.files)
      if (f.path != null) (f.path!, f.name)
  ];
  if (files.isEmpty) return null;
  final total = res.files.fold<int>(0, (a, f) => a + f.size);
  final what = files.length == 1 ? files.first.$2 : '${files.length} files';
  final ok = await showRetroDialog<bool>(context, title: 'Send File', builder: (ctx) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(6),
        child: Text('Send $what (${formatBytes(total)}) to $name? Files go straight between your devices, '
            'not through the server. $name can see your IP address.'),
      ),
      const SizedBox(height: 8),
      RetroButton(autofocus: true, isDefault: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
      const SizedBox(height: 6),
      RetroButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
    ]);
  });
  return ok == true ? files : null;
}
