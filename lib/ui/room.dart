import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../app/history.dart';
import '../app/input_mode.dart';
import '../app/settings.dart';
import '../oscar/bytes.dart';
import '../oscar/client.dart';
import 'color_picker.dart';
import 'keyboard_picker.dart';
import 'profile_screen.dart';
import 'retro.dart';
import 'retro_text_field.dart';
import 't9_phone.dart';
import 'wallpaper.dart';

/// One chat room ("Buddy Chat"): everyone's messages, who's here, and a
/// message box with the room's own keyboard and wallpaper.
class RoomPane extends StatefulWidget {
  final String roomKey;
  final VoidCallback? onClose;

  /// Opens a one-to-one IM with someone in the room.
  final void Function(String screenName)? onOpenChat;
  const RoomPane({super.key, required this.roomKey, this.onClose, this.onOpenChat});

  @override
  State<RoomPane> createState() => _RoomPaneState();
}

class _RoomPaneState extends State<RoomPane> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputKey = GlobalKey(debugLabel: 'room message box');
  int _lastCount = -1;
  late final AppState _app;
  late final InputMode _mode;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _mode = context.read<InputMode>();
    _mode.pushHandler(_onPad);
    WidgetsBinding.instance.addPostFrameCallback((_) => _app.openRoomChat(widget.roomKey));
  }

  @override
  void dispose() {
    _mode.removeHandler(_onPad);
    if (_app.openRoom == widget.roomKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _app.openRoomChat(null));
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

  void _send() {
    final t = _input.text;
    if (t.trim().isEmpty) return;
    _app.sendToRoom(widget.roomKey, t);
    _input.clear();
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
    final room = app.rooms[widget.roomKey];
    if (room == null) {
      return RetroWindow(
        title: 'Chat Room',
        onClose: widget.onClose,
        child: const Center(child: Text('You left this room.')),
      );
    }
    final lines = room.lines;
    if (lines.length != _lastCount) {
      _lastCount = lines.length;
      _scrollToEnd();
    }
    final members = room.members;
    return RetroWindow(
      title: '${room.name} - Chat Room',
      onClose: widget.onClose,
      titleActions: [
        _titleIcon(Icons.person_add_alt_1, 'Invite buddies', () => showRoomInviteDialog(context, room)),
        const SizedBox(width: 3),
        _titleIcon(Icons.wallpaper, 'Wallpaper (only you see it)', () => _pickWallpaper(room)),
        const SizedBox(width: 3),
        _titleIcon(Icons.keyboard, 'Keyboard for this room', () => _pickKeyboard(room)),
        const SizedBox(width: 3),
        _titleIcon(Icons.logout, 'Leave the room', () => _leave(room)),
        const SizedBox(width: 4),
      ],
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(builder: (ctx, box) {
        final side = box.maxWidth >= 600;
        final compact = box.maxHeight + MediaQuery.viewInsetsOf(context).bottom < 520;
        final messages = Sunken(
          padding: EdgeInsets.zero,
          child: Stack(fit: StackFit.expand, children: [
            ChatWallpaper(spec: context.watch<AppSettings>().wallpaperFor(room.settingsKey)),
            ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(6),
              itemCount: lines.length,
              itemBuilder: (ctx, i) => _line(lines[i]),
            ),
          ]),
        );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!room.isOpen)
            Container(
              decoration: bevel(sunken: true, color: const Color(0xFFFFE0A0)),
              padding: const EdgeInsets.all(6),
              child: Text(app.link == LinkState.online
                  ? 'Joining the room…'
                  : 'Not connected. You\'ll rejoin the room when the connection comes back.'),
            ),
          if (!side) _memberStrip(members),
          const SizedBox(height: 4),
          Expanded(
            child: side
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: messages),
                    const SizedBox(width: 4),
                    SizedBox(width: 170, child: _memberList(members)),
                  ])
                : messages,
          ),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: KeyedSubtree(
                key: _inputKey,
                child: RetroTextField(
                  controller: _input,
                  hint: 'Say something to the room',
                  minLines: 1,
                  maxLines: compact ? 2 : 4,
                  enterSubmits: true,
                  action: TextInputAction.send,
                  doneLabel: 'Send',
                  oskPreview: () => [
                    for (final l in (_app.rooms[widget.roomKey]?.lines ?? const <ChatLine>[])
                        .where((l) => !l.system)
                        .toList()
                        .reversed
                        .take(5)
                        .toList()
                        .reversed)
                      OskLine(l.mine ? 'me' : l.from, l.text, l.mine),
                  ],
                  oskPreviewListen: _app,
                  oskChat: room.settingsKey,
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 4),
            RetroButton(
              minWidth: 64,
              minHeight: compact ? 40 : 48,
              isDefault: true,
              onPressed: _send,
              child: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]),
        ]);
      }),
    );
  }

  // ---------------------------------------------------------------- people

  /// Phones: one line naming who's here; tap it for the full list.
  Widget _memberStrip(List<String> members) => RetroListTile(
        onTap: () => _membersDialog(members),
        child: Row(children: [
          const Icon(Icons.groups, size: 20),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              members.isEmpty ? 'Nobody here yet' : '${members.length} here: ${members.join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ]),
      );

  /// Wide windows: the people list beside the messages, like AIM.
  Widget _memberList(List<String> members) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text('${members.length} in room', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: Sunken(
            child: ListView(padding: EdgeInsets.zero, children: [
              for (final m in members)
                RetroListTile(
                  onTap: () => _personMenu(m),
                  child: Row(children: [
                    BuddyAvatar(bytes: _app.buddyIcons[normalizeSn(m)], size: 22),
                    const SizedBox(width: 6),
                    Expanded(child: Text(m, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ]),
          ),
        ),
      ]);

  void _membersDialog(List<String> members) {
    showRetroDialog<void>(context, title: 'In this room', builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (members.isEmpty) const Text('Nobody here yet.'),
        for (final m in members)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RetroButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _personMenu(m);
              },
              child: Text(m),
            ),
          ),
        RetroButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
      ]);
    });
  }

  void _personMenu(String sn) {
    final me = normalizeSn(_app.myScreenName) == normalizeSn(sn);
    showRetroDialog<void>(context, title: sn, builder: (ctx) {
      Widget b(String label, VoidCallback f, {bool autofocus = false}) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RetroButton(
              autofocus: autofocus,
              onPressed: () {
                Navigator.of(ctx).pop();
                f();
              },
              child: Text(label),
            ),
          );
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!me && widget.onOpenChat != null) b('Send Message', () => widget.onOpenChat!(sn), autofocus: true),
        b('Get Info', () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ProfileScreen(screenName: sn, isMe: me)))),
        RetroButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
      ]);
    });
  }

  // ---------------------------------------------------------------- title bar

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

  Future<void> _pickWallpaper(RoomChat room) async {
    final s = context.read<AppSettings>();
    final r = await pickWallpaper(context,
        current: s.wallpaperFor(room.settingsKey), allowDefault: s.wallpaperOverride(room.settingsKey) != null);
    if (r == null) return;
    s.setWallpaperFor(room.settingsKey, r == '*' ? null : r);
  }

  Future<void> _pickKeyboard(RoomChat room) async {
    final s = context.read<AppSettings>();
    final r = await pickKeyboard(context,
        style: s.phoneStyleFor(room.settingsKey),
        kind: s.keyboardKindFor(room.settingsKey),
        name: room.name,
        allowDefault: s.keyboardOverride(room.settingsKey) != null);
    if (r == null) return;
    s.setKeyboardFor(room.settingsKey, r.$1, kind: r.$2);
  }

  Future<void> _leave(RoomChat room) async {
    final ok = await showRetroDialog<bool>(context, title: 'Leave ${room.name}', builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Leave this chat room? You can come back with Chat on your Buddy List, or if someone invites you again.'),
        const SizedBox(height: 10),
        RetroButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        const SizedBox(height: 6),
        RetroButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
      ]);
    });
    if (ok != true || !mounted) return;
    widget.onClose?.call();
    await _app.leaveRoom(room.key);
  }

  // ---------------------------------------------------------------- messages

  Widget _line(ChatLine l) {
    if (l.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          color: const Color(0xCCFFFFFF),
          child: Text(l.text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF404040))),
        ),
      );
    }
    final mine = l.mine;
    final time = TimeOfDay.fromDateTime(l.time).format(context);
    final settings = context.read<AppSettings>();
    final useColors = mine || settings.showTheirColors;
    final bg = Color((useColors ? l.bg : null) ?? (mine ? 0xFFD6E4FF : 0xFFF4F4F4));
    final fg = Color((useColors ? l.fg : null) ?? (isDark(bg) ? 0xFFFFFFFF : 0xFF000000));
    final dark = isDark(bg);
    final nameColor =
        mine ? (dark ? const Color(0xFFFF8A8A) : Retro.myName) : (dark ? const Color(0xFF9DBBFF) : Retro.theirName);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
        decoration: bevel(color: bg, deep: false),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${l.from}  $time', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: nameColor)),
          const SizedBox(height: 2),
          SelectableText(l.text, style: TextStyle(fontSize: 15, color: fg)),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ dialogs

/// Picks online buddies to invite into [room] and sends the invites.
Future<void> showRoomInviteDialog(BuildContext context, RoomChat room) async {
  final app = context.read<AppState>();
  final picked = await pickBuddiesToInvite(context, title: 'Invite to ${room.name}', exclude: room.members);
  if (picked == null || picked.$1.isEmpty || !context.mounted) return;
  try {
    final failed = await app.inviteToRoom(room.key, picked.$1, picked.$2);
    if (failed.isNotEmpty && context.mounted) {
      showRetroMessage(context, 'Invite', 'Couldn\'t reach ${failed.join(', ')}.');
    }
  } catch (e) {
    if (context.mounted) showRetroMessage(context, 'Invite', '$e'.replaceFirst('Exception: ', ''));
  }
}

/// Online buddies to tick, plus an invite message. Null when cancelled.
Future<(List<String>, String)?> pickBuddiesToInvite(BuildContext context,
    {required String title, List<String> exclude = const []}) {
  final app = context.read<AppState>();
  final skip = {...exclude.map(normalizeSn), normalizeSn(app.myScreenName)};
  final online = <String>[
    for (final (_, bs) in app.buddyGroups)
      for (final b in bs)
        if (b.online && !skip.contains(normalizeSn(b.screenName))) b.screenName,
  ];
  final chosen = <String>{};
  final msg = TextEditingController(text: 'Join me in this Buddy Chat.');
  return showRetroDialog<(List<String>, String)>(context, title: title, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, setState) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(online.isEmpty ? 'None of your buddies are online right now.' : 'Buddies to invite:'),
        const SizedBox(height: 4),
        if (online.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final b in online)
                  RetroCheckbox(
                    value: chosen.contains(b),
                    label: b,
                    onChanged: (v) => setState(() => v ? chosen.add(b) : chosen.remove(b)),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 6),
        RetroTextField(controller: msg, hint: 'Invitation message'),
        const SizedBox(height: 8),
        RetroButton(
          isDefault: true,
          onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, (chosen.toList(), msg.text)),
          child: const Text('Send Invite'),
        ),
        const SizedBox(height: 6),
        RetroButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ]);
    });
  });
}
