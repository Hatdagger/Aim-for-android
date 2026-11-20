import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../app/invite.dart';
import 'retro.dart';
import 'retro_text_field.dart';

/// "Get a Screen Name": create an account with an invite link or code.
class SignUpScreen extends StatefulWidget {
  final Invite? invite;
  const SignUpScreen({super.key, this.invite});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _link = TextEditingController();
  final _sn = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  Invite? _invite;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _invite = widget.invite;
  }

  @override
  void dispose() {
    _link.dispose();
    _sn.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = context.read<AppState>();
    final inv = _invite ?? Invite.parse(_link.text);
    setState(() => _error = null);
    if (inv == null) {
      setState(() => _error = 'Paste the invite link you were sent.');
      return;
    }
    final sn = _sn.text.trim();
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9 ]{2,15}$').hasMatch(sn)) {
      setState(() => _error = 'Screen names are 3–16 letters, numbers or spaces, starting with a letter.');
      return;
    }
    if (_pw.text.length < 6) {
      setState(() => _error = 'Passwords need at least 6 characters.');
      return;
    }
    if (_pw.text != _pw2.text) {
      setState(() => _error = 'The passwords don\'t match.');
      return;
    }
    setState(() => _busy = true);
    try {
      await app.signUpWithInvite(inv, sn, _pw.text);
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invite;
    return Scaffold(
      body: SafeArea(
        child: Desktop(
          maxWidth: 420,
          child: SingleChildScrollView(
            child: RetroWindow(
              title: 'Get a Screen Name',
              onClose: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : () => context.read<AppState>().dismissInvite(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                if (inv != null)
                  Container(
                    decoration: bevel(sunken: true, color: const Color(0xFFFFFFE1)),
                    padding: const EdgeInsets.all(8),
                    child: Text(inv.invitedBy != null
                        ? '${inv.invitedBy} invited you to ${inv.server}'
                        : 'You\'re invited to ${inv.server}'),
                  )
                else ...[
                  const Text('Invite link'),
                  RetroTextField(controller: _link, hint: 'http://…/i/CODE', autofocus: true),
                ],
                const SizedBox(height: 8),
                const Text('Pick a screen name'),
                RetroTextField(controller: _sn, hint: 'Screen name', autofocus: inv != null),
                const SizedBox(height: 6),
                const Text('Password'),
                RetroTextField(controller: _pw, hint: 'Password', obscure: true),
                const SizedBox(height: 6),
                const Text('Password again'),
                RetroTextField(controller: _pw2, hint: 'Password again', obscure: true, onSubmitted: (_) => _submit()),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFAA0000)))),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: RetroButton(isDefault: true, onPressed: _busy ? null : _submit, child: Text(_busy ? 'Creating…' : 'Sign Up')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Buddy list "Invite a Friend": makes a share link.
Future<void> showInviteDialog(BuildContext context) {
  return showRetroDialog<void>(context, title: 'Invite a Friend', builder: (ctx) => const _InviteBody());
}

class _InviteBody extends StatefulWidget {
  const _InviteBody();
  @override
  State<_InviteBody> createState() => _InviteBodyState();
}

class _InviteBodyState extends State<_InviteBody> {
  String? _link;
  String? _note;
  String? _error;
  bool _busy = false;

  Future<void> _make(bool household) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final inv = await context.read<AppState>().createInvite(household: household);
      setState(() {
        _link = inv.link;
        _note = household
            ? 'Household link: up to ${inv.usesLeft} people can join with it.'
            : 'Works once.';
        if (inv.expires != null) _note = '$_note Expires ${inv.expires!.toLocal().toString().substring(0, 10)}.';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Text('Send this link to a friend. It installs the app and points it at this server.'),
      const SizedBox(height: 8),
      if (_link == null) ...[
        RetroButton(autofocus: true, onPressed: _busy ? null : () => _make(false), child: const Text('Make an invite link')),
        const SizedBox(height: 4),
        RetroButton(onPressed: _busy ? null : () => _make(true), child: const Text('Make a household link')),
      ] else ...[
        Sunken(padding: const EdgeInsets.all(8), child: SelectableText(_link!)),
        if (_note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_note!, style: const TextStyle(fontSize: 12))),
        const SizedBox(height: 6),
        RetroButton(
          autofocus: true,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _link!));
            setState(() => _note = 'Copied! Paste it in a text or email.');
          },
          child: const Text('Copy Link'),
        ),
      ],
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFAA0000)))),
    ]);
  }
}
