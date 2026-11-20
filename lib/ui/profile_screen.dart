import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../oscar/aim_html.dart';
import '../oscar/bytes.dart';
import '../oscar/models.dart';
import 'icon_crop.dart';
import 'retro.dart';
import 'retro_text_field.dart';

/// Buddy Info window. For your own screen name it lets you edit your
/// profile and buddy icon.
class ProfileScreen extends StatefulWidget {
  final String screenName;
  final bool isMe;
  const ProfileScreen({super.key, required this.screenName, this.isMe = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileInfo? _info;
  String? _error;
  bool _loading = true;
  final _profile = TextEditingController();

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    if (widget.isMe) {
      _profile.text = app.settings.profileFor(app.myScreenName);
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await context.read<AppState>().profileOf(widget.screenName);
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _profile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Desktop(
          maxWidth: 520,
          child: RetroWindow(
            title: widget.isMe ? 'My Profile' : 'Buddy Info: ${widget.screenName}',
            onClose: () => Navigator.of(context).pop(),
            child: SingleChildScrollView(child: widget.isMe ? _mine(app) : _theirs(app)),
          ),
        ),
      ),
    );
  }

  Widget _mine(AppState app) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        BuddyAvatar(bytes: app.myIcon, size: 64),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.myScreenName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text('Buddy icon: 48×48, up to 7 KB (classic AIM size)', style: TextStyle(fontSize: 12)),
          ]),
        ),
      ]),
      const SizedBox(height: 6),
      RetroButton(
        autofocus: true,
        onPressed: () async {
          final bytes = await Navigator.of(context).push<List<int>>(
              MaterialPageRoute(builder: (_) => const IconCropScreen()));
          if (bytes != null) {
            try {
              await app.setMyIcon(Uint8List.fromList(bytes));
            } catch (e) {
              if (mounted) showRetroMessage(context, 'Buddy Icon', 'Could not set icon: $e');
            }
          }
        },
        child: const Text('Choose Buddy Icon…'),
      ),
      const SizedBox(height: 12),
      const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
      RetroTextField(controller: _profile, hint: 'Tell people about yourself', minLines: 5, maxLines: 10),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        RetroButton(
          isDefault: true,
          onPressed: () {
            app.setProfile(_profile.text);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ]),
    ]);
  }

  Widget _theirs(AppState app) {
    if (_loading) return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Loading…')));
    if (_error != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        RetroButton(autofocus: true, onPressed: _load, child: const Text('Try Again')),
      ]);
    }
    final i = _info!;
    final u = i.user;
    final since = u?.onlineSince;
    final away = htmlToText(i.awayHtml ?? '');
    final profile = htmlToText(i.profileHtml ?? '');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        BuddyAvatar(bytes: app.buddyIcons[normalizeSn(widget.screenName)], size: 64),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u?.screenName ?? widget.screenName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (since != null)
              Text('Online since ${DateTime.fromMillisecondsSinceEpoch(since * 1000).toLocal().toString().substring(0, 16)}',
                  style: const TextStyle(fontSize: 12)),
            if ((u?.idleMinutes ?? 0) > 0) Text('Idle ${u!.idleMinutes} minutes', style: const TextStyle(fontSize: 12)),
            if ((u?.warningLevel ?? 0) > 0)
              Text('Warning level ${(u!.warningLevel / 10).round()}%', style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ]),
      if (away.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Text('Away Message', style: TextStyle(fontWeight: FontWeight.bold)),
        Sunken(padding: const EdgeInsets.all(8), color: const Color(0xFFFFFFE1), child: SelectableText(away)),
      ],
      const SizedBox(height: 10),
      const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
      Sunken(
        padding: const EdgeInsets.all(8),
        child: SelectableText(profile.isEmpty ? '(No profile)' : profile),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: RetroButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ),
    ]);
  }
}
