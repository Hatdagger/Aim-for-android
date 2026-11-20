import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../app/platform_bridge.dart';
import '../app/settings.dart';
import 'retro.dart';
import 'retro_text_field.dart';
import 'setup_wizard.dart';
import 't9_phone.dart';

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
    final s = app.settings;
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
                    label: 'Go away automatically when the app is in the background',
                    onChanged: (v) => s.autoAway = v),
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
              _section('Controller', [
                const Text('Controller mode uses the built-in on-screen keyboard and big focus highlights.'),
                const SizedBox(height: 4),
                Wrap(spacing: 4, children: [
                  for (final m in ControllerMode.values)
                    RetroButton(
                      minWidth: 0,
                      onPressed: () => s.controllerMode = m,
                      child: Text(
                        switch (m) {
                          ControllerMode.auto => 'Auto',
                          ControllerMode.on => 'Always',
                          ControllerMode.off => 'Never',
                        },
                        style: TextStyle(fontWeight: s.controllerMode == m ? FontWeight.bold : FontWeight.normal),
                      ),
                    ),
                ]),
              ]),
              _section('Phone Keypad', [
                const Text('In controller mode, typing uses a T9 phone keypad beside the chat. '
                    'Tap the keys or use the D-pad and A. B deletes, X space, Y next word, Select T9 on/off, Start done.'),
                RetroCheckbox(
                    value: s.t9Predictive,
                    label: 'Predictive text (T9): 43556 = hello',
                    onChanged: (v) => s.t9Predictive = v),
                RetroCheckbox(
                    value: s.keyFeedback,
                    label: 'Buzz when I press a key (phone vibrates; controller rumbles on Android)',
                    onChanged: (v) => s.keyFeedback = v),
                const SizedBox(height: 4),
                const Text('Phone style'),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final p in kPhoneStyles)
                    RetroButton(
                      minWidth: 0,
                      onPressed: () => s.phoneStyle = p.id,
                      child: Text(p.name,
                          style: TextStyle(fontWeight: s.phoneStyle == p.id ? FontWeight.bold : FontWeight.normal)),
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
          onPressed: current.isEmpty ? null : () => app.sounds.playFile(current),
          child: const Icon(Icons.play_arrow),
        ),
      ]),
    );
  }
}
