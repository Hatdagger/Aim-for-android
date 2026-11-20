import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../app/history.dart';
import '../app/input_mode.dart';
import '../app/settings.dart';
import '../oscar/aim_html.dart';
import '../oscar/bytes.dart';
import '../oscar/client.dart';
import 'profile_screen.dart';
import 'retro.dart';
import 'color_picker.dart';
import 'retro_text_field.dart';
import 't9_phone.dart';
import 'keyboard_picker.dart';
import 'wallpaper.dart';

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
      titleActions: [
        _titleIcon(Icons.format_color_text, 'My text colours', _pickColors),
        const SizedBox(width: 3),
        _titleIcon(Icons.wallpaper, 'Wallpaper (only you see it)', _pickWallpaper),
        const SizedBox(width: 3),
        _titleIcon(Icons.keyboard, 'Keyboard for this chat', _pickKeyboard),
        const SizedBox(width: 4),
      ],
      padding: const EdgeInsets.all(4),
      // Short windows (phones and handhelds held sideways) get a slim layout:
      // AIM buttons as small icons in the header, Send beside the message box.
      child: LayoutBuilder(builder: (ctx, box) {
        // Judge the height without the on-screen keyboard: otherwise opening
        // the keyboard would switch layouts, rebuild the message box and close
        // the keyboard again.
        final compact = box.maxHeight + MediaQuery.viewInsetsOf(context).bottom < 520;
        return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            _compactHeader(app, conv.displayName, key, online, warnPct > 0 ? '$status · Warning $warnPct%' : status)
          else
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
              padding: EdgeInsets.zero,
              child: Stack(fit: StackFit.expand, children: [
                ChatWallpaper(spec: context.watch<AppSettings>().wallpaperFor(widget.screenName)),
                ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(6),
                itemCount: lines.length + (conv.typing == 2 ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == lines.length) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        color: const Color(0xCCFFFFFF),
                        child: Text('${conv.displayName} is typing…',
                            style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF404040))),
                      ),
                    );
                  }
                  return _bubble(app, lines[i]);
                },
              ),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          if (compact)
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _inputField(conv.displayName, maxLines: 2)),
              const SizedBox(width: 4),
              RetroButton(
                minWidth: 64,
                minHeight: 40,
                isDefault: true,
                onPressed: _send,
                child: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ])
          else ...[
            _inputField(conv.displayName),
            const SizedBox(height: 4),
            _actionBar(app, conv.displayName),
          ],
        ],
      );
      }),
    );
  }

  /// Keeps the message box (and its keyboard focus) the same widget when the
  /// layout changes between slim and full.
  final _inputKey = GlobalKey(debugLabel: 'message box');

  Widget _inputField(String name, {int maxLines = 4}) => KeyedSubtree(key: _inputKey, child: RetroTextField(
        controller: _input,
        hint: 'Message $name',
        minLines: 1,
        maxLines: maxLines,
        enterSubmits: true,
        action: TextInputAction.send,
        doneLabel: 'Send',
        oskPreview: () => [
          for (final l in _app.conversationFor(widget.screenName).lines.reversed.take(5).toList().reversed)
            OskLine(l.mine ? 'me' : l.from, l.text, l.mine),
        ],
        oskPreviewListen: _app,
        oskChat: widget.screenName,
        onChanged: _onChanged,
        onSubmitted: (_) => _send(),
      ));

  /// One-line buddy header with AIM's Warn/Block/Add/Talk/Info as small icons.
  Widget _compactHeader(AppState app, String name, String key, bool online, String status) {
    final signedOn = app.link == LinkState.online;
    final blocked = app.isBlocked(widget.screenName);
    final buddy = app.isBuddy(widget.screenName);
    Widget icon(IconData i, String tip, VoidCallback? onPressed) => Tooltip(
          message: tip,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: RetroButton(
              minWidth: 34,
              minHeight: 32,
              padding: const EdgeInsets.all(3),
              semanticLabel: tip,
              onPressed: onPressed,
              child: Icon(i, size: 18, color: onPressed == null ? Retro.shadow : Colors.black),
            ),
          ),
        );
    return Row(children: [
      Expanded(
        child: RetroListTile(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => ProfileScreen(screenName: widget.screenName))),
          child: Row(children: [
            BuddyAvatar(bytes: app.buddyIcons[key], size: 26, dim: !online),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  TextSpan(text: '  $status', style: const TextStyle(fontSize: 11)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      ),
      icon(Icons.warning_amber_rounded, 'Warn', signedOn ? () => _warn(name) : null),
      icon(blocked ? Icons.lock_open : Icons.block, blocked ? 'Unblock' : 'Block',
          signedOn ? () => _block(name, !blocked) : null),
      icon(Icons.person_add_alt_1, 'Add Buddy', signedOn && !buddy ? () => _addBuddy(name) : null),
      icon(Icons.phone_in_talk, 'Talk (not available yet)', null),
      icon(Icons.info_outline, 'Get Info', () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ProfileScreen(screenName: widget.screenName)))),
    ]);
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

  Widget _titleIcon(IconData icon, String tip, VoidCallback onPressed) => Tooltip(
        message: tip,
        child: RetroButton(
          minWidth: 0,
          minHeight: 22,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          semanticLabel: tip,
          onPressed: onPressed,
          child: Icon(icon, size: 15),
        ),
      );

  Future<void> _pickWallpaper() async {
    final s = context.read<AppSettings>();
    final r = await pickWallpaper(context,
        current: s.wallpaperFor(widget.screenName), allowDefault: s.wallpaperOverride(widget.screenName) != null);
    if (r == null) return;
    s.setWallpaperFor(widget.screenName, r == '*' ? null : r);
  }

  Future<void> _pickKeyboard() async {
    final s = context.read<AppSettings>();
    final r = await pickKeyboard(context,
        style: s.phoneStyleFor(widget.screenName),
        kind: s.keyboardKindFor(widget.screenName),
        name: context.read<AppState>().conversationFor(widget.screenName).displayName,
        allowDefault: s.keyboardOverride(widget.screenName) != null);
    if (r == null) return;
    s.setKeyboardFor(widget.screenName, r.$1, kind: r.$2);
  }

  Future<void> _pickColors() async {
    final s = context.read<AppSettings>();
    await showRetroDialog<void>(context, title: 'My message colours', builder: (ctx) {
      return ListenableBuilder(
        listenable: s,
        builder: (ctx, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MessageColorsEditor(settings: s),
          const SizedBox(height: 8),
          RetroButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ]),
      );
    });
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
    final settings = context.read<AppSettings>();
    final useColors = mine || settings.showTheirColors;
    final bg = Color((useColors ? l.bg : null) ?? (mine ? 0xFFD6E4FF : 0xFFF4F4F4));
    final fg = Color((useColors ? l.fg : null) ?? (isDark(bg) ? 0xFFFFFFFF : 0xFF000000));
    final dark = isDark(bg);
    final nameColor = mine ? (dark ? const Color(0xFFFF8A8A) : Retro.myName) : (dark ? const Color(0xFF9DBBFF) : Retro.theirName);
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: bevel(color: bg, deep: false),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(
          '${l.from}${l.auto ? ' (Auto-response)' : ''}  $time',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: nameColor),
        ),
        const SizedBox(height: 2),
        SelectableText(l.text, style: TextStyle(fontSize: 15, color: fg)),
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
        Container(
          color: const Color(0xCCFFFFFF),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(label, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF404040))),
        ),
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

/// Preview plus "Text colour" / "Background" buttons for your own messages.
/// Used in the chat window and in Preferences.
class MessageColorsEditor extends StatelessWidget {
  final AppSettings settings;
  const MessageColorsEditor({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final bg = Color(s.myBackColor ?? 0xFFD6E4FF);
    final fg = Color(s.myTextColor ?? (isDark(bg) ? 0xFFFFFFFF : 0xFF000000));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: bevel(color: bg, deep: false),
        padding: const EdgeInsets.all(8),
        child: Text('This is how your messages look. Buddies on AIM see these colours too.',
            style: TextStyle(color: fg, fontSize: 15)),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: RetroButton(
            onPressed: () async {
              final c = await pickColor(context, title: 'Text colour', current: s.myTextColor);
              if (c != null) s.myTextColor = c == -1 ? null : c;
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 14, color: fg),
              const SizedBox(width: 6),
              const Text('Text colour'),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: RetroButton(
            onPressed: () async {
              final c = await pickColor(context, title: 'Background colour', current: s.myBackColor);
              if (c != null) s.myBackColor = c == -1 ? null : c;
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 14, decoration: BoxDecoration(color: bg, border: Border.all())),
              const SizedBox(width: 6),
              const Text('Background'),
            ]),
          ),
        ),
      ]),
      RetroCheckbox(
          value: s.showTheirColors,
          label: "Show the colours my buddies picked",
          onChanged: (v) => s.showTheirColors = v),
    ]);
  }
}
