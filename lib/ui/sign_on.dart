import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../app/platform_bridge.dart';
import '../oscar/client.dart';
import 'retro.dart';
import 'retro_text_field.dart';
import 'settings_screen.dart';
import 'sign_up.dart';
import 'update_button.dart';

class SignOnScreen extends StatefulWidget {
  const SignOnScreen({super.key});

  @override
  State<SignOnScreen> createState() => _SignOnScreenState();
}

class _SignOnScreenState extends State<SignOnScreen> {
  final _sn = TextEditingController();
  final _pw = TextEditingController();
  final _server = TextEditingController();
  bool _savePw = true;
  bool _auto = false;
  bool _showServer = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _server.text = s.server;
    _showServer = s.server.isEmpty;
    final last = s.lastScreenName;
    if (last != null) _selectAccount(last);
  }

  Future<void> _selectAccount(String sn) async {
    final s = context.read<AppState>().settings;
    final acct = s.accounts.where((a) => a.screenName == sn).firstOrNull;
    _sn.text = sn;
    _savePw = acct?.savePassword ?? true;
    _auto = acct?.autoLogin ?? false;
    final pw = await s.passwordFor(sn);
    if (!mounted) return;
    setState(() => _pw.text = pw ?? '');
  }

  Future<void> _signOn() async {
    final sn = _sn.text.trim();
    final server = _server.text.trim();
    if (sn.isEmpty || _pw.text.isEmpty) {
      await showRetroMessage(context, 'Sign On', 'Please enter your screen name and password.');
      return;
    }
    if (server.isEmpty) {
      setState(() => _showServer = true);
      await showRetroMessage(context, 'Sign On', 'Please enter the server address.');
      return;
    }
    await context.read<AppState>().signOn(
        server: server, screenName: sn, password: _pw.text, savePassword: _savePw, autoLogin: _auto);
  }

  @override
  void dispose() {
    _sn.dispose();
    _pw.dispose();
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final accounts = app.settings.accounts;
    final connecting = app.link == LinkState.connecting || app.link == LinkState.reconnecting;
    return Scaffold(
      body: SafeArea(
        child: Desktop(
          maxWidth: 380,
          child: SingleChildScrollView(
            child: RetroWindow(
              title: 'Sign On',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 110,
                    decoration: bevel(sunken: true, color: const Color(0xFF0A246A)),
                    alignment: Alignment.center,
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.directions_run, size: 56, color: Color(0xFFFFD800)),
                      Text('Instant Messenger',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('Screen Name', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (accounts.isNotEmpty)
                      PopupMenuButton<String>(
                        tooltip: 'Saved screen names',
                        onSelected: _selectAccount,
                        itemBuilder: (_) => [
                          for (final a in accounts) PopupMenuItem(value: a.screenName, child: Text(a.screenName)),
                        ],
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [Text('Saved'), Icon(Icons.arrow_drop_down)]),
                        ),
                      ),
                  ]),
                  RetroTextField(controller: _sn, hint: 'Screen name', autofocus: _sn.text.isEmpty),
                  const SizedBox(height: 8),
                  const Text('Password', style: TextStyle(fontWeight: FontWeight.bold)),
                  RetroTextField(controller: _pw, hint: 'Password', obscure: true, onSubmitted: (_) => _signOn()),
                  const SizedBox(height: 6),
                  Wrap(children: [
                    RetroCheckbox(value: _savePw, label: 'Save password', onChanged: (v) => setState(() {
                          _savePw = v;
                          if (!v) _auto = false;
                        })),
                    RetroCheckbox(value: _auto, label: 'Auto-login', onChanged: (v) => setState(() {
                          _auto = v;
                          if (v) _savePw = true;
                        })),
                  ]),
                  if (_showServer) ...[
                    const SizedBox(height: 6),
                    const Text('Server', style: TextStyle(fontWeight: FontWeight.bold)),
                    RetroTextField(controller: _server, hint: 'server:5190'),
                  ],
                  if (app.signOnError != null && app.link == LinkState.stopped)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(app.signOnError!, style: const TextStyle(color: Color(0xFFAA0000))),
                    ),
                  if (connecting)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(app.linkMessage == null ? 'Connecting…' : 'Retrying: ${app.linkMessage}'),
                    ),
                  const SizedBox(height: 10),
                  Row(children: [
                    RetroButton(
                      onPressed: () => setState(() => _showServer = !_showServer),
                      child: const Text('Setup'),
                    ),
                    const SizedBox(width: 6),
                    RetroButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      child: const Icon(Icons.settings),
                    ),
                    const SizedBox(width: 6),
                    const UpdateButton(),
                    // AIM-only phones: join a network without leaving AIM.
                    if (app.settings.homeMode) ...[
                      const SizedBox(width: 6),
                      RetroButton(minWidth: 0, onPressed: PlatformBridge.openWifi, child: const Icon(Icons.wifi)),
                    ],
                    const Spacer(),
                    if (connecting)
                      RetroButton(onPressed: () => app.signOff(), child: const Text('Cancel'))
                    else
                      RetroButton(isDefault: true, onPressed: _signOn, child: const Text('Sign On')),
                  ]),
                  const SizedBox(height: 6),
                  RetroButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignUpScreen())),
                    child: const Text('Get a Screen Name'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    app.settings.server.isEmpty ? '' : 'Server: ${app.settings.server}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF404040)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
