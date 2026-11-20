import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../app/history.dart';
import '../app/input_mode.dart';
import '../oscar/aim_html.dart';
import '../oscar/bytes.dart';
import '../oscar/client.dart';
import 'profile_screen.dart';
import 'retro.dart';
import 'retro_text_field.dart';

/// One conversation, laid out like a texting app inside a classic IM window.
class ChatPane extends StatefulWidget {
  final String screenName;
  final VoidCallback? onClose;
  const ChatPane({super.key, required this.screenName, this.onClose});

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _typingTimer;
  int _sentTyping = 0;
  int _lastCount = -1;
  late final AppState _app;
  late final InputMode _mode;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _mode = context.read<InputMode>();
    _mode.pushHandler(_onPad);
    WidgetsBinding.instance.addPostFrameCallback((_) => _app.openConversation(widget.screenName));
  }

  @override
  void didUpdateWidget(ChatPane old) {
    super.didUpdateWidget(old);
    if (normalizeSn(old.screenName) != normalizeSn(widget.screenName)) {
      _input.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _app.openConversation(widget.screenName));
    }
  }

  @override
  void dispose() {
    _mode.removeHandler(_onPad);
    _typingTimer?.cancel();
    if (_sentTyping != 0) _app.typing(widget.screenName, 0);
    if (_app.openChat == normalizeSn(widget.screenName)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _app.openConversation(null));
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _onPad(PadAction a) {
    if (a == PadAction.start) {
      _send();
      return true;
    }
    return false;
  }

  void _onChanged(String t) {
    if (t.isEmpty) {
      if (_sentTyping != 0) _app.typing(widget.screenName, 0);
      _sentTyping = 0;
      return;
    }
    if (_sentTyping != 2) {
      _app.typing(widget.screenName, 2);
      _sentTyping = 2;
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _app.typing(widget.screenName, 1);
      _sentTyping = 1;
    });
  }

  void _send() {
    final t = _input.text;
    if (t.trim().isEmpty) return;
    _app.send(widget.screenName, t);
    _input.clear();
    _typingTimer?.cancel();
    _sentTyping = 0;
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final conv = app.conversationFor(widget.screenName);
    final key = normalizeSn(widget.screenName);
    final online = app.isBuddyOnline(widget.screenName);
    final info = app.client?.session?.online[key];
    final status = !online
        ? 'Offline — messages wait until they sign on'
        : (info?.isAway ?? false)
            ? 'Away'
            : (info != null && info.idleMinutes > 0 ? 'Idle ${info.idleMinutes} min' : 'Online');
    final warnPct = ((info?.warningLevel ?? 0) / 10).round();
    final lines = conv.lines;
    if (lines.length != _lastCount) {
      _lastCount = lines.length;
      _scrollToEnd();
    }
    return RetroWindow(
      title: '${conv.displayName} - Instant Message',
      onClose: widget.onClose,
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RetroListTile(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => ProfileScreen(screenName: widget.screenName))),
            child: Row(children: [
              BuddyAvatar(bytes: app.buddyIcons[key], size: 40, dim: !online),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(conv.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(warnPct > 0 ? '$status · Warning level $warnPct%' : status, style: const TextStyle(fontSize: 12)),
                ]),
              ),
              const Icon(Icons.info_outline),
            ]),
          ),
          if (app.link != LinkState.online)
            Container(
              decoration: bevel(sunken: true, color: const Color(0xFFFFE0A0)),
              padding: const EdgeInsets.all(6),
              child: const Text('Not connected. Your messages will be sent when the connection comes back.'),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: Sunken(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(6),
                itemCount: lines.length + (conv.typing == 2 ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == lines.length) {
                    return Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text('${conv.displayName} is typing…',
                          style: const TextStyle(fontStyle: FontStyle.italic, color: Retro.shadow)),
                    );
                  }
                  return _bubble(app, lines[i]);
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          RetroTextField(
            controller: _input,
            hint: 'Message ${conv.displayName}',
            minLines: 1,
            maxLines: 4,
            enterSubmits: true,
            action: TextInputAction.send,
            doneLabel: 'Send',
            onChanged: _onChanged,
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 4),
          _actionBar(app, conv.displayName),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- AIM button bar

  /// The row under the message box, like AIM 5:
  /// Warn · Block · Add Buddy · Talk · Get Info · Send.
  Widget _actionBar(AppState app, String name) {
    final signedOn = app.link == LinkState.online;
    final blocked = app.isBlocked(widget.screenName);
    final buddy = app.isBuddy(widget.screenName);
    return Row(children: [
      _barButton(Icons.warning_amber_rounded, 'Warn', signedOn ? () => _warn(name) : null),
      _barButton(blocked ? Icons.lock_open : Icons.block, blocked ? 'Unblock' : 'Block',
          signedOn ? () => _block(name, !blocked) : null),
      _barButton(Icons.person_add_alt_1, 'Add Buddy', signedOn && !buddy ? () => _addBuddy(name) : null),
      _barButton(Icons.phone_in_talk, 'Talk', null), // voice isn't supported (yet)
      _barButton(Icons.info_outline, 'Get Info', () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ProfileScreen(screenName: widget.screenName)))),
      const SizedBox(width: 4),
      RetroButton(
        minWidth: 64,
        minHeight: 48,
        isDefault: true,
        onPressed: _send,
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.send, size: 20),
          Text('Send', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    ]);
  }

  Widget _barButton(IconData icon, String label, VoidCallback? onPressed) {
    final color = onPressed == null ? Retro.shadow : Colors.black;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: RetroButton(
          minWidth: 0,
          minHeight: 48,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          semanticLabel: label,
          onPressed: onPressed,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: color),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: TextStyle(fontSize: 11, color: color)),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _warn(String name) async {
    final anon = await showRetroDialog<bool>(context, title: 'Warn $name', builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Warning $name raises their warning level and slows down how fast they can send messages. '
            'Use it on people who are bothering you.'),
        const SizedBox(height: 10),
        RetroButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Warn')),
        const SizedBox(height: 6),
        RetroButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Warn anonymously')),
        const SizedBox(height: 6),
        RetroButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ]);
    });
    if (anon == null || !mounted) return;
    try {
      final level = await _app.warn(widget.screenName, anonymous: anon);
      if (mounted) showRetroMessage(context, 'Warn', '$name has been warned. Their warning level is now $level%.');
    } catch (e) {
      if (mounted) showRetroMessage(context, 'Warn', '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _block(String name, bool block) async {
    if (block) {
      final ok = await showRetroDialog<bool>(context, title: 'Block $name', builder: (ctx) {
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$name won\'t be able to see when you\'re online or send you messages. You can unblock them here later.'),
          const SizedBox(height: 10),
          RetroButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Block')),
          const SizedBox(height: 6),
          RetroButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ]);
      });
      if (ok != true || !mounted) return;
    }
    try {
      await _app.setBlocked(widget.screenName, block);
    } catch (e) {
      if (mounted) showRetroMessage(context, block ? 'Block' : 'Unblock', '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _addBuddy(String name) async {
    try {
      await _app.addBuddy(widget.screenName, 'Buddies');
      if (mounted) showRetroMessage(context, 'Add Buddy', '$name was added to your Buddies group.');
    } catch (e) {
      if (mounted) showRetroMessage(context, 'Add Buddy', 'Could not add buddy: $e');
    }
  }

  Widget _bubble(AppState app, ChatLine l) {
    final pending = l.pendingId == null ? null : app.pending(l.pendingId!);
    final mine = l.mine;
    final time = TimeOfDay.fromDateTime(l.time).format(context);
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: bevel(color: mine ? const Color(0xFFD6E4FF) : const Color(0xFFF4F4F4), deep: false),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(
          '${l.from}${l.auto ? ' (Auto-response)' : ''}  $time',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: mine ? Retro.myName : Retro.theirName),
        ),
        const SizedBox(height: 2),
        SelectableText(l.text, style: const TextStyle(fontSize: 15)),
        if (pending != null) _pendingRow(app, pending),
      ]),
    );
    return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: bubble);
  }

  Widget _pendingRow(AppState app, OutgoingMessage m) {
    final label = switch (m.status) {
      OutboxStatus.queued => app.link == LinkState.online ? 'Sending…' : 'Waiting for connection',
      OutboxStatus.sending => 'Sending…',
      OutboxStatus.waitingForBuddy => m.note ?? 'Waiting for buddy to sign on',
      OutboxStatus.failed => m.note ?? 'Not delivered',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
        const Icon(Icons.schedule, size: 14, color: Retro.shadow),
        Text(label, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF404040))),
        if (m.status == OutboxStatus.failed)
          RetroButton(minWidth: 0, minHeight: 26, padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => app.retryPending(m.id), child: const Text('Retry', style: TextStyle(fontSize: 12))),
        if (m.status != OutboxStatus.sending)
          RetroButton(minWidth: 0, minHeight: 26, padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => app.cancelPending(m.id), child: const Text('Cancel', style: TextStyle(fontSize: 12))),
      ]),
    );
  }
}

String plainAway(String? html) => htmlToText(html ?? '');
