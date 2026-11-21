import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../oscar/direct_connect.dart';
import 'retro.dart';

/// The strip above the messages that shows Direct Connect: an invite to
/// answer, waiting, connected (with Send Picture), or nothing.
class DirectBar extends StatelessWidget {
  final DirectState? state;
  final String name;

  /// (got, total) bytes of a picture arriving right now.
  final (int, int)? progress;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;
  final VoidCallback? onPicture;
  final VoidCallback? onClose;

  const DirectBar({
    super.key,
    required this.state,
    required this.name,
    this.progress,
    this.onAccept,
    this.onDecline,
    this.onCancel,
    this.onPicture,
    this.onClose,
  });

  Widget _btn(String label, VoidCallback? f, {IconData? icon, bool primary = false, bool autofocus = false}) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: RetroButton(
          minWidth: 0,
          minHeight: 34,
          isDefault: primary,
          autofocus: autofocus,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          onPressed: f,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: primary ? FontWeight.bold : FontWeight.normal)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null || s == DirectState.closed || s == DirectState.failed || s == DirectState.declined) {
      return const SizedBox.shrink();
    }
    final (Color color, IconData icon, String text, List<Widget> buttons) = switch (s) {
      DirectState.invited => (
          const Color(0xFFFFF2B3),
          Icons.photo_library_outlined,
          '$name wants to Direct Connect to share pictures. If you accept, $name can see your IP address.',
          [_btn('Accept', onAccept, primary: true, autofocus: true), _btn('Decline', onDecline)],
        ),
      DirectState.inviting => (
          const Color(0xFFE8E8E8),
          Icons.hourglass_top,
          'Asking $name to Direct Connect…',
          [_btn('Cancel', onCancel)],
        ),
      DirectState.connecting => (
          const Color(0xFFE8E8E8),
          Icons.hourglass_top,
          'Connecting to $name…',
          [_btn('Cancel', onCancel)],
        ),
      _ => (
          const Color(0xFFD8F5D0),
          Icons.link,
          progress != null
              ? 'Receiving a picture… ${(100 * progress!.$1 / (progress!.$2 == 0 ? 1 : progress!.$2)).round()}%'
              : 'Direct Connect with $name',
          [_btn('Send Picture', onPicture, icon: Icons.image, primary: true), _btn('Close', onClose)],
        ),
    };
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: bevel(sunken: true, color: color),
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      child: Wrap(
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
    );
  }
}

/// A picture inside a message bubble. Tap to see it full size.
class ChatPicture extends StatelessWidget {
  final ImageProvider image;
  final VoidCallback? onTap;
  const ChatPicture({super.key, required this.image, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: bevel(sunken: true, color: Colors.white, deep: false),
          padding: const EdgeInsets.all(2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 260, minWidth: 40, minHeight: 40),
            child: Image(
              image: image,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(8),
                child: Text('(picture can\'t be shown)', style: TextStyle(fontStyle: FontStyle.italic)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen view of a chat picture, with Save.
class PictureViewer extends StatelessWidget {
  final String path;
  final String title;
  const PictureViewer({super.key, required this.path, required this.title});

  static Future<void> open(BuildContext context, String path, String title) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => PictureViewer(path: path, title: title)));

  Future<void> _save(BuildContext context) async {
    final f = File(path);
    final bytes = await f.readAsBytes();
    final name = 'aim-${DateTime.now().millisecondsSinceEpoch}${path.substring(path.lastIndexOf('.'))}';
    try {
      final out = await FilePicker.platform.saveFile(dialogTitle: 'Save picture', fileName: name, bytes: bytes);
      if (out == null) return;
      // On desktops the picker only returns a path; write the file there.
      final dst = File(out);
      if (!await dst.exists() || await dst.length() == 0) await dst.writeAsBytes(bytes, flush: true);
      if (context.mounted) showRetroMessage(context, 'Save Picture', 'Picture saved.');
    } catch (e) {
      if (context.mounted) showRetroMessage(context, 'Save Picture', 'Could not save the picture.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RetroWindow(
          title: title,
          onClose: () => Navigator.of(context).pop(),
          padding: const EdgeInsets.all(4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Container(
                color: Colors.black,
                child: InteractiveViewer(
                  maxScale: 6,
                  child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              RetroButton(onPressed: () => _save(context), child: const Text('Save…')),
              const SizedBox(width: 6),
              RetroButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// "Direct Connect with X?" Returns true to go ahead.
Future<bool> confirmDirectConnect(BuildContext context, String name) async {
  final ok = await showRetroDialog<bool>(context, title: 'Direct Connect', builder: (ctx) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(6),
        child: Text('Ask $name to Direct Connect? Pictures go straight between your devices, not through the server. '
            'While you\'re connected, $name can see your IP address.'),
      ),
      const SizedBox(height: 8),
      RetroButton(autofocus: true, isDefault: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Connect')),
      const SizedBox(height: 6),
      RetroButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
    ]);
  });
  return ok == true;
}

/// Lets the user take or choose a picture. Returns its bytes.
Future<List<int>?> pickPicture(BuildContext context) async {
  var source = ImageSource.gallery;
  if (Platform.isAndroid || Platform.isIOS) {
    final s = await showRetroDialog<ImageSource>(context, title: 'Send Picture', builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RetroButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text('Choose a picture')),
        const SizedBox(height: 6),
        RetroButton(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const Text('Take a photo')),
        const SizedBox(height: 6),
        RetroButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ]);
    });
    if (s == null) return null;
    source = s;
  }
  final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
  if (f == null) return null;
  return f.readAsBytes();
}
