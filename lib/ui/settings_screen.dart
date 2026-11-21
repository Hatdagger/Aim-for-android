import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../app/platform_bridge.dart';
import '../app/settings.dart';
import 'retro.dart';
import 'retro_text_field.dart';
import 'setup_wizard.dart';
import 'chat.dart';
import 'phone_art.dart';
import 'phone_theme.dart';
import 't9_phone.dart';
import 'wallpaper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _files = [];
  late final TextEditingController _autoAway;
  late final TextEditingController _server;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _autoAway = TextEditingController(text: s.autoAwayMessage);
    _server = TextEditingController(text: s.server);
    _refresh();
  }

  Future<void> _refresh() async {
    final f = await context.read<AppState>().sounds.available();
    if (mounted) setState(() => _files = f);
  }

  @override
  void dispose() {
    _autoAway.dispose();
    _server.dispose();
    super.dispose();
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          decoration: bevel(sunken: true),
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            ...children,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Redraw as soon as any setting changes, so ticks and choices show at once.
    final s = context.watch<AppSettings>();
    return Scaffold(
      body: SafeArea(
        child: Desktop(
          maxWidth: 560,
          child: RetroWindow(
            title: 'Preferences',
            onClose: () => Navigator.of(context).pop(),
            child: ListView(children: [
              _section('Sounds', [
                RetroCheckbox(value: s.soundsOn, label: 'Play sounds while the app is open', onChanged: (v) => s.soundsOn = v),
                const Text('Sounds play at your media volume (on phones, the music/video volume).',
                    style: TextStyle(fontSize: 12)),
                if (_files.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(4), child: Text('No sounds imported yet.', style: TextStyle(fontStyle: FontStyle.italic))),
                for (final e in SoundEvent.values) _soundRow(app, e),
                const SizedBox(height: 4),
                RetroButton(
                  onPressed: () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const SetupWizard(soundsOnly: true)));
                    _refresh();
                  },
                  child: const Text('Import Sounds…'),
                ),
              ]),
              _section('Away', [
                RetroCheckbox(
                    value: s.autoAway,
                    label: 'Go away automatically when the app is closed for a while',
                    onChanged: (v) => s.autoAway = v),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                  const Text('After'),
                  for (final m in const [1, 5, 10, 20, 30])
                    RetroButton(
                      minWidth: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      selected: s.autoAwayMinutes == m,
                      onPressed: () => s.autoAwayMinutes = m,
                      child: Text('$m min'),
                    ),
                ]),
                const Text('Automatic away message'),
                RetroTextField(controller: _autoAway, hint: kDefaultAutoAway, maxLines: 3, onChanged: (v) => s.autoAwayMessage = v),
              ]),
              _section('Chat History', [
                RetroCheckbox(
                    value: s.historyEnabled,
                    label: 'Save chat history on this device',
                    onChanged: (v) => s.historyEnabled = v),
                const Text('History is cleared when you sign off. Losing the connection does not clear it.',
                    style: TextStyle(fontSize: 12)),
              ]),
              _section('Direct Connect', [
                RetroCheckbox(
                    value: s.allowDirectConnect,
                    label: 'Let buddies ask to Direct Connect',
                    onChanged: (v) => s.allowDirectConnect = v),
                const Text('Direct Connect sends pictures straight between your device and your buddy\'s. '
                    'They never go through the server. While you\'re connected, your buddy can see your IP address. '
                    'You\'re always asked first.',
                    style: TextStyle(fontSize: 12)),
              ]),
              _section('Controller', [
                const Text('Controller mode uses the built-in on-screen keyboard and big focus highlights. '
                    'On Auto, a chat where you picked a keyboard (⌨ in its title bar) always uses that phone or gadget.'),
                const SizedBox(height: 4),
                Wrap(spacing: 4, children: [
                  for (final m in ControllerMode.values)
                    RetroButton(
                      minWidth: 0,
                      selected: s.controllerMode == m,
                      onPressed: () => s.controllerMode = m,
                      child: Text(switch (m) {
                        ControllerMode.auto => 'Auto',
                        ControllerMode.on => 'Always',
                        ControllerMode.off => 'Never',
                      }),
                    ),
                ]),
              ]),
              _section('Phone Keyboard', [
                const Text('In controller mode, typing uses a cartoon phone. Tap the keys or use the D-pad and A. '
                    'B deletes, X space, Y next word (QWERTY: shift), Select T9 on/off (QWERTY: symbols), '
                    'Start sends. Sideways screens: RB lets you move and resize the phone with the D-pad.'),
                const SizedBox(height: 6),
                const Text('Keyboard'),
                Wrap(spacing: 4, children: [
                  for (final (id, label) in const [('t9', 'Phone keypad (T9)'), ('qwerty', 'Slide-out QWERTY')])
                    RetroButton(
                      minWidth: 0,
                      selected: s.keyboardKind == id,
                      onPressed: () => s.keyboardKind = id,
                      child: Text(label),
                    ),
                ]),
                const SizedBox(height: 6),
                RetroCheckbox(
                    value: s.phoneFullPortrait,
                    label: 'Upright screen: phone fills the whole screen (keypad phone)',
                    onChanged: (v) => s.phoneFullPortrait = v),
                RetroCheckbox(
                    value: s.phoneFullLandscape,
                    label: 'Sideways screen: phone fills the whole screen (slide-out QWERTY)',
                    onChanged: (v) => s.phoneFullLandscape = v),
                const Text('Full screen hides the chat; the phone\'s own screen shows the conversation. '
                    'Back closes the phone, Back again leaves the chat. Otherwise the phone floats over the chat '
                    'and you can drag it around.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                const Text('Phone or gadget (default; each chat can pick its own with the keyboard button in its title bar)'),
                const Text(
                    'Wide Flip is a keypad phone that opens sideways to a keyboard. Console TV, Pocket Mail, '
                    'Music Player and Pocket Brick always use their own keyboard. Arrows / D-pad move between keys, A presses.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final p in kPhoneThemes)
                    SizedBox(
                      width: 118,
                      child: RetroListTile(
                        onTap: () => s.phoneStyle = p.id,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: s.phoneStyle == p.id ? const Color(0xFFFFFFE1) : null,
                            border: Border.all(
                                color: s.phoneStyle == p.id ? Retro.navy : const Color(0x00000000), width: 3),
                          ),
                          child: Column(children: [
                            SizedBox(
                                height: PhoneArt.sizeFor(p, s.keyboardKind == 'qwerty').aspectRatio > 1.05 ? 90 : 150,
                                child: PhonePreview(t: p, qwerty: s.keyboardKind == 'qwerty')),
                            const SizedBox(height: 4),
                            Text(p.name, style: TextStyle(fontWeight: s.phoneStyle == p.id ? FontWeight.bold : FontWeight.normal)),
                            Text(p.blurb, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                          ]),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 6),
                RetroCheckbox(
                    value: s.t9Predictive,
                    label: 'Predictive text (T9): 43556 = hello',
                    onChanged: (v) => s.t9Predictive = v),
                RetroCheckbox(
                    value: s.numpadT9,
                    label: 'Number pad types like a phone (T9), in every text box',
                    onChanged: (v) => s.numpadT9 = v),
                const Text(
                    'Keys work by position, like a phone: the pad\'s top row 7 8 9 is ABC DEF GHI, the bottom row 1 2 3 '
                    'is PQRS TUV WXYZ, 0 is space, . changes case, + or * picks the next word, - deletes, / turns T9 on/off.',
                    style: TextStyle(fontSize: 12)),
                RetroCheckbox(
                    value: s.keyFeedback,
                    label: 'Buzz when I press a key (phone vibrates; controller rumbles on Android)',
                    onChanged: (v) => s.keyFeedback = v),
                RetroCheckbox(
                    value: s.phoneSounds,
                    label: 'Phone sounds: key clicks, flips, slides, TV switch-on, handheld boot beep',
                    onChanged: (v) => s.phoneSounds = v),
                RetroButton(
                  onPressed: s.resetOskPlacement,
                  child: const Text('Put the phone back in its usual spot and size'),
                ),
              ]),
              _section('Message Look', [
                MessageColorsEditor(settings: s),
                const SizedBox(height: 6),
                const Text('Default chat wallpaper (only you see it; each chat can have its own from its title bar)'),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    width: 90,
                    height: 50,
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Retro.shadow)),
                    child: ClipRect(child: ChatWallpaper(spec: s.defaultWallpaper)),
                  ),
                  const SizedBox(width: 8),
                  RetroButton(
                    onPressed: () async {
                      final r = await pickWallpaper(context, current: s.defaultWallpaper);
                      if (r != null && r != '*') s.defaultWallpaper = r;
                    },
                    child: const Text('Choose…'),
                  ),
                ]),
              ]),
              _section('Server', [
                RetroTextField(controller: _server, hint: 'server:5190', onChanged: (v) => s.server = v),
                RetroCheckbox(
                    value: s.fixLoopbackRedirects,
                    label: 'Use this address even if the server hands out 127.0.0.1',
                    onChanged: (v) => s.fixLoopbackRedirects = v),
              ]),
              if (Platform.isAndroid)
                _section('Android', [
                  const Text('Notifications only say how many new messages you have. They never show who sent them or what they say.'),
                  const SizedBox(height: 4),
                  RetroButton(onPressed: PlatformBridge.requestNotificationPermission, child: const Text('Allow notifications')),
                  const SizedBox(height: 4),
                  RetroButton(onPressed: PlatformBridge.requestBackgroundRunning, child: const Text('Allow background running')),
                  const SizedBox(height: 4),
                  const Text('Staying signed on with the screen off: tap "Allow background running" and choose Allow. '
                      'Some tablets (Lenovo, Xiaomi, Samsung…) also have their own switch: open Android Settings > Apps > AIM > '
                      'Battery and pick "No restrictions" / "Allow background activity". AIM keeps a small '
                      '"Signed on" notification while it is connected; swiping AIM away no longer signs you off — use Sign Off.',
                      style: TextStyle(fontSize: 12)),
                ]),
              _section('Saved Screen Names', [
                for (final a in s.accounts)
                  Row(children: [
                    Expanded(child: Text(a.screenName)),
                    RetroButton(minWidth: 0, onPressed: () => s.forgetAccount(a.screenName), child: const Text('Forget')),
                  ]),
                if (s.accounts.isEmpty) const Text('None'),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _soundRow(AppState app, SoundEvent e) {
    final s = app.settings;
    final current = s.soundFor(e);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(soundEventLabel(e))),
        PopupMenuButton<String>(
          tooltip: 'Choose sound',
          onSelected: (v) {
            s.setSoundFor(e, v);
            if (v.isNotEmpty) app.sounds.playFile(v);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: '', child: Text('(None)')),
            for (final f in _files) PopupMenuItem(value: f, child: Text(f)),
          ],
          child: Container(
            decoration: bevel(sunken: true, color: Colors.white),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(current.isEmpty ? '(None)' : current),
              const Icon(Icons.arrow_drop_down),
            ]),
          ),
        ),
        const SizedBox(width: 4),
        RetroButton(
          minWidth: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: current.isEmpty
              ? null
              : () async {
                  final err = await app.sounds.playFile(current);
                  if (err != null && context.mounted) showRetroMessage(context, 'Sound', err);
                },
          child: const Icon(Icons.play_arrow),
        ),
      ]),
    );
  }
}
