import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/updater.dart';
import 'retro.dart';

/// "Update" button with a status light: grey when you're up to date, green
/// and pinging (a ring that keeps rippling out) when a newer build is out.
class UpdateButton extends StatelessWidget {
  /// Small icon-only version for the Buddy List title bar.
  final bool compact;
  const UpdateButton({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateChecker>();
    final dot = PingDot(on: u.available, size: compact ? 9 : 11);
    final label = u.available ? 'Update available' : 'Check for updates';
    if (compact) {
      return Tooltip(
        message: label,
        child: RetroButton(
          minWidth: 0,
          minHeight: 22,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          semanticLabel: label,
          onPressed: () => showUpdateDialog(context),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.system_update_alt, size: 14),
            const SizedBox(width: 3),
            dot,
          ]),
        ),
      );
    }
    return RetroButton(
      minWidth: 0,
      semanticLabel: label,
      onPressed: () => showUpdateDialog(context),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        dot,
        const SizedBox(width: 6),
        Text(u.available ? 'Update!' : 'Update',
            style: TextStyle(fontWeight: u.available ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }
}

Future<void> showUpdateDialog(BuildContext context) async {
  final u = context.read<UpdateChecker>();
  if (!u.available && !u.checking) u.check();
  await showRetroDialog<void>(context, title: 'Update', builder: (ctx) {
    return ListenableBuilder(
      listenable: u,
      builder: (ctx, _) {
        final mine = kAppBuild > 0 ? 'build $kAppBuild' : 'a test build (no build number)';
        final String status;
        if (u.checking) {
          status = 'Checking GitHub for a newer version…';
        } else if (u.error != null) {
          status = u.error!;
        } else if (u.available) {
          status = 'A new version is ready: build ${u.latestBuild}'
              '${u.latestDate == null ? '' : ' (${u.latestDate})'}.';
        } else if (u.latestBuild != null) {
          status = 'You have the newest version.';
        } else {
          status = '';
        }
        final how = switch (u.assetName) {
          'aim-android.apk' => 'Tap Download, then open aim-android.apk and choose Update. '
              'Your screen names, buddies and settings stay.',
          'aim-windows.zip' => 'Download aim-windows.zip, close AIM, then unzip it over the old AIM folder.',
          _ => 'Download aim-linux.tar.gz, close AIM, then extract it over the old AIM folder.',
        };
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            PingDot(on: u.available, size: 12),
            const SizedBox(width: 8),
            Expanded(child: Text(status, style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 6),
          Text('You are running $mine.', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Text(how),
          const SizedBox(height: 10),
          RetroButton(
            isDefault: u.available,
            autofocus: u.available,
            onPressed: () {
              u.openDownload();
              Navigator.pop(ctx);
            },
            child: Text(u.available ? 'Download update' : 'Download anyway'),
          ),
          const SizedBox(height: 6),
          RetroButton(onPressed: u.checking ? null : u.check, child: const Text('Check again')),
          const SizedBox(height: 6),
          RetroButton(autofocus: !u.available, onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ]);
      },
    );
  });
}

/// A status light. When [on], it glows green and a ring pings outwards.
class PingDot extends StatefulWidget {
  final bool on;
  final double size;
  const PingDot({super.key, required this.on, this.size = 11});

  @override
  State<PingDot> createState() => _PingDotState();
}

class _PingDotState extends State<PingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.on) _c.repeat();
  }

  @override
  void didUpdateWidget(PingDot old) {
    super.didUpdateWidget(old);
    if (widget.on && !_c.isAnimating) _c.repeat();
    if (!widget.on && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    const green = Color(0xFF22DD55);
    return SizedBox(
      width: s * 2.2,
      height: s * 2.2,
      child: AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) {
          final t = _c.value;
          return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            if (widget.on)
              Container(
                width: s * (1 + 1.2 * t),
                height: s * (1 + 1.2 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: green.withValues(alpha: (1 - t) * 0.9), width: 2),
                ),
              ),
            Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.on ? green : const Color(0xFF7A7A7A),
                border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
                boxShadow: widget.on
                    ? [BoxShadow(color: green.withValues(alpha: 0.8), blurRadius: 6 + 4 * (1 - t), spreadRadius: 1)]
                    : null,
              ),
            ),
          ]);
        },
      ),
    );
  }
}
