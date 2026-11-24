import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../oscar/aim_html.dart';
import '../oscar/bytes.dart';
import '../oscar/client.dart';
import '../oscar/models.dart';
import '../oscar/chat_room.dart';
import 'profile_screen.dart';
import 'retro.dart';
import 'room.dart';
import 'update_button.dart';
import 'retro_text_field.dart';
import 'settings_screen.dart';
import 'sign_up.dart';

/// The buddy list window. [onOpenChat] decides whether a chat opens in a
/// side window (wide screens) or as a new page (phones).
class BuddyListPane extends StatefulWidget {
  final void Function(String screenName) onOpenChat;

  /// Opens a chat room window (by room key).
  final void Function(String roomKey) onOpenRoom;
  const BuddyListPane({super.key, required this.onOpenChat, required this.onOpenRoom});

  @override
  State<BuddyListPane> createState() => _BuddyListPaneState();
}

class _BuddyListPaneState extends State<BuddyListPane> {
  final Set<String> _collapsed = {};

  /// Messages waiting from [sn] (0 when none).
  int _unread(AppState app, String sn) => app.conversations[normalizeSn(sn)]?.unread ?? 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return RetroWindow(
      title: "${app.myScreenName}'s Buddy List",
      titleActions: const [UpdateButton(compact: true), SizedBox(width: 4)],
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusBar(app),
          const SizedBox(height: 4),
          Expanded(
            child: Sunken(
              child: FocusTraversalGroup(child: _buddies(app)),
            ),
          ),
          const SizedBox(height: 4),
          _toolbar(app),
        ],
      ),
    );
  }

  Widget _statusBar(AppState app) {
    String? text;
    Color bg = const Color(0xFFFFFFE1);
    switch (app.link) {
      case LinkState.reconnecting:
      case LinkState.connecting:
        text = 'Reconnecting… messages you send will go out when the connection is back.';
        bg = const Color(0xFFFFE0A0);
      case LinkState.online:
        if (app.isAway) text = 'Away: ${htmlToText(app.awayMessage ?? '')}';
      default:
        break;
    }
    if (text == null) return const SizedBox.shrink();
    return Container(
      decoration: bevel(sunken: true, color: bg),
      padding: const EdgeInsets.all(6),
      child: Row(children: [
        Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
        if (app.isAway && app.link == LinkState.online)
          RetroButton(minWidth: 0, onPressed: () => app.setAway(null), child: const Text("I'm Back")),
      ]),
    );
  }

  Widget _buddies(AppState app) {
    final groups = app.buddyGroups;
    final offline = <BuddyView>[];
    final children = <Widget>[];
    var first = true;

    // Chat rooms you're in and invites waiting, at the very top.
    if (app.rooms.isNotEmpty || app.roomInvites.isNotEmpty) {
      const name = 'Chat Rooms';
      final unread = app.roomInvites.length + app.rooms.values.fold(0, (a, r) => a + r.unread);
      children.add(_groupHeader(name, 0, app.rooms.length + app.roomInvites.length,
          autofocus: true, showCount: false, unread: unread));
      first = false;
      if (!_collapsed.contains(name)) {
        for (final inv in app.roomInvites) {
          children.add(_inviteRow(app, inv));
        }
        for (final r in app.rooms.values) {
          children.add(_roomRow(app, r));
        }
      }
    }

    // People who messaged you but are not on your Buddy List get their own
    // group at the top, so the one list is also the list of chats.
    final known = {for (final (_, bs) in groups) for (final b in bs) normalizeSn(b.screenName)};
    final strangers = app.conversations.values.where((c) => !known.contains(c.key)).toList()
      ..sort((a, b) => b.unread.compareTo(a.unread));
    if (strangers.isNotEmpty) {
      const name = 'Not on My List';
      children.add(_groupHeader(name, 0, strangers.length,
          autofocus: first, showCount: false, unread: strangers.fold(0, (a, c) => a + c.unread)));
      first = false;
      if (!_collapsed.contains(name)) {
        for (final c in strangers) {
          children.add(_buddyRow(
            app,
            BuddyView(c.displayName, app.isBuddyOnline(c.displayName), false, 0, app.buddyIcons[c.key]),
            onList: false,
          ));
        }
      }
    }

    for (final (name, buddies) in groups) {
      final on = buddies.where((b) => b.online).toList();
      offline.addAll(buddies.where((b) => !b.online));
      children.add(_groupHeader(name, on.length, buddies.length,
          autofocus: first, unread: buddies.fold(0, (a, b) => a + _unread(app, b.screenName))));
      first = false;
      if (!_collapsed.contains(name)) {
        for (final b in on) {
          children.add(_buddyRow(app, b));
        }
      }
    }
    if (offline.isNotEmpty) {
      children.add(_groupHeader('Offline', 0, offline.length,
          autofocus: false, showCount: false, unread: offline.fold(0, (a, b) => a + _unread(app, b.screenName))));
      if (!_collapsed.contains('Offline')) {
        for (final b in offline) {
          children.add(_buddyRow(app, b));
        }
      }
    }
    if (children.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.all(12),
        child: Text(app.link == LinkState.online ? 'No buddies yet. Use Add to add one.' : 'Signing on…'),
      ));
    }
    return ListView(padding: EdgeInsets.zero, children: children);
  }

  Widget _groupHeader(String name, int on, int total,
      {required bool autofocus, bool showCount = true, int unread = 0}) {
    final collapsed = _collapsed.contains(name);
    return RetroListTile(
      autofocus: autofocus,
      onTap: () => setState(() => collapsed ? _collapsed.remove(name) : _collapsed.add(name)),
      child: Row(children: [
        Icon(collapsed ? Icons.arrow_right : Icons.arrow_drop_down, size: 20),
        Expanded(
          child: Text(showCount ? '$name ($on/$total)' : '$name ($total)',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        // A closed group still shows that someone inside it is waiting.
        if (collapsed && unread > 0) Padding(padding: const EdgeInsets.only(right: 6), child: UnreadBadge(unread)),
        if (showCount)
          RetroButton(
            minWidth: 0,
            minHeight: 26,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            semanticLabel: 'Edit group $name',
            onPressed: () => _groupMenu(context.read<AppState>(), name),
            child: const Icon(Icons.edit, size: 15),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- editing

  Future<void> _try(String title, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) showRetroMessage(context, title, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<String?> _askName(String title, String label, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showRetroDialog<String>(context, title: title, builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(label),
        RetroTextField(controller: c, hint: label, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          RetroButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          const SizedBox(width: 6),
          RetroButton(isDefault: true, onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
        ]),
      ]);
    });
  }

  void _groupMenu(AppState app, String name) {
    final g = app.rawGroups.where((g) => g.name == name).firstOrNull;
    if (g == null) return;
    final all = app.rawGroups;
    final idx = all.indexWhere((x) => x.groupId == g.groupId);
    showRetroDialog<void>(context, title: 'Group: $name', builder: (ctx) {
      Widget b(String label, Future<void> Function() f, {bool enabled = true, bool autofocus = false}) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RetroButton(
              autofocus: autofocus,
              onPressed: enabled
                  ? () {
                      Navigator.pop(ctx);
                      f();
                    }
                  : null,
              child: Text(label),
            ),
          );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        b('Rename group…', autofocus: true, () async {
          final n = await _askName('Rename Group', 'New name', initial: name);
          if (n != null && n.isNotEmpty && n != name) await _try('Rename Group', () => app.renameGroup(g.groupId, n));
        }),
        b('Add a buddy to this group…', () async => _addBuddyDialog(app, group0: name)),
        b('Move group up', enabled: idx > 0, () => _try('Move Group', () => app.moveGroup(g.groupId, -1))),
        b('Move group down', enabled: idx < all.length - 1, () => _try('Move Group', () => app.moveGroup(g.groupId, 1))),
        b('New group…', () => _newGroup(app)),
        b('Delete group…', () => _deleteGroup(app, g)),
        RetroButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ]);
    });
  }

  Future<void> _newGroup(AppState app) async {
    final n = await _askName('New Group', 'Group name');
    if (n == null || n.isEmpty) return;
    if (app.rawGroups.any((g) => g.name.toLowerCase() == n.toLowerCase())) {
      if (mounted) showRetroMessage(context, 'New Group', 'You already have a group called $n.');
      return;
    }
    await _try('New Group', () => app.addGroup(n));
  }

  Future<void> _deleteGroup(AppState app, BuddyGroup g) async {
    final others = app.rawGroups.where((x) => x.groupId != g.groupId).toList();
    final choice = await showRetroDialog<int>(context, title: 'Delete ${g.name}', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(g.buddies.isEmpty
            ? 'Delete the empty group ${g.name}?'
            : '${g.name} has ${g.buddies.length} buddies. Where should they go?'),
        const SizedBox(height: 8),
        if (g.buddies.isNotEmpty)
          for (final o in others)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: RetroButton(onPressed: () => Navigator.pop(ctx, o.groupId), child: Text('Move them to ${o.name}')),
            ),
        RetroButton(
          onPressed: () => Navigator.pop(ctx, -1),
          child: Text(g.buddies.isEmpty ? 'Delete' : 'Delete the group and remove its buddies'),
        ),
        const SizedBox(height: 4),
        RetroButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ]);
    });
    if (choice == null) return;
    await _try('Delete Group', () => app.removeGroup(g.groupId, moveTo: choice == -1 ? null : choice));
  }

  Future<void> _moveBuddyTo(AppState app, String sn) async {
    final current = app.rawGroups.where((g) => g.buddies.any((b) => b.toLowerCase() == sn.toLowerCase())).firstOrNull;
    final choice = await showRetroDialog<int>(context, title: 'Move $sn', builder: (ctx) {
      return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Move to which group?'),
          const SizedBox(height: 6),
          for (final g in app.rawGroups)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: RetroButton(
                onPressed: g.groupId == current?.groupId ? null : () => Navigator.pop(ctx, g.groupId),
                child: Text(g.groupId == current?.groupId ? '${g.name} (now)' : g.name),
              ),
            ),
          RetroButton(onPressed: () => Navigator.pop(ctx, -1), child: const Text('New group…')),
          const SizedBox(height: 4),
          RetroButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ]),
      );
    });
    if (choice == null) return;
    var gid = choice;
    if (choice == -1) {
      final n = await _askName('New Group', 'Group name');
      if (n == null || n.isEmpty) return;
      await _try('New Group', () => app.addGroup(n));
      final made = app.rawGroups.where((g) => g.name == n).firstOrNull;
      if (made == null) return;
      gid = made.groupId;
    }
    await _try('Move Buddy', () => app.moveBuddy(sn, gid));
  }

  Widget _buddyRow(AppState app, BuddyView b, {bool onList = true}) {
    final unread = _unread(app, b.screenName);
    final menu = onList ? () => _buddyMenu(app, b.screenName) : () => _strangerMenu(app, b.screenName);
    return RetroListTile(
      onTap: () => widget.onOpenChat(b.screenName),
      onLongPress: menu,
      child: Padding(
        padding: const EdgeInsets.only(left: 18),
        child: Row(children: [
          BuddyAvatar(bytes: b.icon, size: 26, dim: !b.online || b.away),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              b.screenName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontStyle: b.away ? FontStyle.italic : FontStyle.normal,
                // New messages: the name goes big, heavy and black.
                fontWeight: unread > 0 ? FontWeight.w900 : FontWeight.normal,
                fontSize: unread > 0 ? 16 : null,
                color: b.online || unread > 0 ? null : Retro.shadow,
              ),
            ),
          ),
          if (unread > 0) Padding(padding: const EdgeInsets.only(left: 4), child: UnreadBadge(unread)),
          if (b.away) const Icon(Icons.description_outlined, size: 16),
          if (b.idleMinutes > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(_idle(b.idleMinutes), style: const TextStyle(fontSize: 12, color: Retro.shadow)),
            ),
          IconButton(
            tooltip: 'More for ${b.screenName}',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: menu,
            icon: const Icon(Icons.more_vert),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- chat rooms

  Widget _inviteRow(AppState app, RoomInvite inv) => RetroListTile(
        onTap: () => _inviteDialog(app, inv),
        child: Row(children: [
          const Icon(Icons.mark_email_unread, size: 22, color: Color(0xFFB00000)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${inv.from} invited you to ${inv.room.name}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const UnreadBadge(1),
        ]),
      );

  Widget _roomRow(AppState app, RoomChat r) => RetroListTile(
        onTap: () => widget.onOpenRoom(r.key),
        child: Row(children: [
          Icon(Icons.forum, size: 22, color: r.isOpen ? const Color(0xFF7A4FD0) : Retro.shadow),
          const SizedBox(width: 6),
          Expanded(
            child: Text(r.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: r.unread > 0 ? FontWeight.bold : FontWeight.normal)),
          ),
          Text(r.isOpen ? '(${r.members.length})' : '(joining)',
              style: const TextStyle(fontSize: 12, color: Retro.shadow)),
          if (r.unread > 0) Padding(padding: const EdgeInsets.only(left: 6), child: UnreadBadge(r.unread)),
          IconButton(
            tooltip: 'More for ${r.name}',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () => _roomMenu(app, r),
            icon: const Icon(Icons.more_vert),
          ),
        ]),
      );

  void _inviteDialog(AppState app, RoomInvite inv) {
    showRetroDialog<void>(context, title: 'Buddy Chat Invitation', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('${inv.from} invited you to the chat room "${inv.room.name}".',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        if (inv.message.isNotEmpty) ...[
          const SizedBox(height: 6),
          Sunken(padding: const EdgeInsets.all(6), child: Text(inv.message)),
        ],
        const SizedBox(height: 10),
        RetroButton(
          autofocus: true,
          isDefault: true,
          onPressed: () {
            Navigator.of(ctx).pop();
            _try('Chat', () async {
              final key = await app.acceptRoomInvite(inv);
              widget.onOpenRoom(key);
            });
          },
          child: const Text('Join'),
        ),
        const SizedBox(height: 4),
        RetroButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            app.declineRoomInvite(inv);
          },
          child: const Text('No thanks'),
        ),
        const SizedBox(height: 4),
        RetroButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Decide later')),
      ]);
    });
  }

  void _roomMenu(AppState app, RoomChat r) {
    showRetroDialog<void>(context, title: r.name, builder: (ctx) {
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
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        b('Open', () => widget.onOpenRoom(r.key), autofocus: true),
        b('Invite buddies…', () => showRoomInviteDialog(context, r)),
        b('Leave the room', () => app.leaveRoom(r.key)),
        RetroButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
      ]);
    });
  }

  /// Chat ▸ "Buddy Chat": name a room (new or existing) and invite buddies.
  Future<void> _chatDialog(AppState app) async {
    final name = TextEditingController(text: '${app.myScreenName.replaceAll(' ', '')}Chat${100 + DateTime.now().millisecond % 900}');
    final go = await showRetroDialog<bool>(context, title: 'Chat Room', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Type a room name. If the room already exists you join it; otherwise it\'s made for you.'),
        const SizedBox(height: 6),
        RetroTextField(controller: name, hint: 'Room name', autofocus: true, onSubmitted: (_) => Navigator.pop(ctx, true)),
        const SizedBox(height: 8),
        RetroButton(isDefault: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Go')),
        const SizedBox(height: 6),
        RetroButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ]);
    });
    if (go != true || !mounted) return;
    await _try('Chat', () async {
      final key = await app.joinRoom(name.text);
      if (!mounted) return;
      widget.onOpenRoom(key);
      final room = app.rooms[key];
      if (room != null && room.members.length <= 1 && mounted) {
        // A brand-new room: offer to invite people straight away, like AIM.
        await showRoomInviteDialog(context, room);
      }
    });
  }

  String _idle(int m) => m < 60 ? '(${m}m)' : '(${m ~/ 60}h)';

  /// Menu for someone who messaged you but is not on your Buddy List.
  void _strangerMenu(AppState app, String sn) {
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
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        b('Send Message', () => widget.onOpenChat(sn), autofocus: true),
        b('Get Info', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(screenName: sn)))),
        b('Add to Buddy List…', () => _addBuddyDialog(app, sn0: sn)),
        b('Close this conversation', () => app.closeConversation(normalizeSn(sn))),
        RetroButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
      ]);
    });
  }

  /// The classic AIM 5 strip of picture buttons under the list: one row,
  /// a picture with a small word under it.
  Widget _toolbar(AppState app) {
    return Container(
      decoration: bevel(),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: FocusTraversalGroup(
        child: Row(children: [
          Expanded(
            child: Pictogram(
              icon: Icons.chat_bubble,
              color: const Color(0xFFF2C230),
              label: 'IM',
              onTap: () => _sendIm(),
            ),
          ),
          Expanded(
            child: Pictogram(
              icon: Icons.forum,
              color: const Color(0xFF7A4FD0),
              label: 'Chat',
              onTap: () => app.link == LinkState.online
                  ? _chatDialog(app)
                  : showRetroMessage(context, 'Chat', 'Chat rooms need a connection. Try again once you\'re signed on.'),
            ),
          ),
          Expanded(
            child: Pictogram(
              icon: Icons.badge,
              color: const Color(0xFF3D7BD9),
              label: 'Info',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ProfileScreen(screenName: app.myScreenName, isMe: true))),
            ),
          ),
          Expanded(
            child: Pictogram(
              icon: Icons.sticky_note_2,
              color: const Color(0xFFE8B23A),
              label: 'Away',
              dropdown: true,
              onTap: () => _awayDialog(app),
            ),
          ),
          Expanded(
            child: Pictogram(
              icon: Icons.exposure,
              color: const Color(0xFF3DA33D),
              label: 'Setup',
              dropdown: true,
              onTap: () => _setupMenu(app),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _sendIm() async {
    final sn = await _askName('Send Instant Message', 'Screen name');
    if (sn != null && sn.isNotEmpty) widget.onOpenChat(sn);
  }

  /// Setup ▾: everything that used to be a row of buttons.
  void _setupMenu(AppState app) {
    showRetroDialog<void>(context, title: 'Setup', builder: (ctx) {
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
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        b('Add Buddy…', () => _addBuddyDialog(app), autofocus: true),
        b('New Group…', () => _newGroup(app)),
        b('Invite a Friend…', () => showInviteDialog(context)),
        b('Preferences…',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        b('Sign Off', () => _confirmSignOff(app)),
        RetroButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
      ]);
    });
  }

  void _buddyMenu(AppState app, String sn) {
    showRetroDialog<void>(context, title: sn, builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        RetroButton(
          autofocus: true,
          onPressed: () {
            Navigator.of(ctx).pop();
            widget.onOpenChat(sn);
          },
          child: const Text('Send Message'),
        ),
        const SizedBox(height: 4),
        RetroButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(screenName: sn)));
          },
          child: const Text('Get Info'),
        ),
        const SizedBox(height: 4),
        RetroButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            try {
              await app.removeBuddy(sn);
            } catch (e) {
              if (mounted) showRetroMessage(context, 'Remove Buddy', '$e');
            }
          },
          child: const Text('Remove from Buddy List'),
        ),
        const SizedBox(height: 4),
        RetroButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            _moveBuddyTo(app, sn);
          },
          child: const Text('Move to another group…'),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: RetroButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _try('Move Buddy', () => app.moveBuddyWithinGroup(sn, -1));
              },
              child: const Text('Move up'),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: RetroButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _try('Move Buddy', () => app.moveBuddyWithinGroup(sn, 1));
              },
              child: const Text('Move down'),
            ),
          ),
        ]),
      ]);
    });
  }

  void _awayDialog(AppState app) {
    final custom = TextEditingController();
    showRetroDialog<void>(context, title: 'Away Message', builder: (ctx) {
      final saved = app.settings.awayMessages;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < saved.length; i++) ...[
          RetroButton(
            autofocus: i == 0,
            onPressed: () {
              app.setAway(saved[i]);
              Navigator.of(ctx).pop();
            },
            child: Text(saved[i], textAlign: TextAlign.center),
          ),
          const SizedBox(height: 4),
        ],
        const Divider(),
        RetroTextField(controller: custom, hint: 'New away message', maxLines: 3),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          RetroButton(
            onPressed: () {
              final t = custom.text.trim();
              if (t.isEmpty) return;
              app.settings.awayMessages = [t, ...saved.where((s) => s != t)].take(8).toList();
              app.setAway(t);
              Navigator.of(ctx).pop();
            },
            child: const Text('Save & Go Away'),
          ),
        ]),
      ]);
    });
  }

  void _addBuddyDialog(AppState app, {String? group0, String? sn0}) {
    final sn = TextEditingController(text: sn0 ?? '');
    final group = TextEditingController(text: group0 ?? (app.rawGroups.firstOrNull?.name ?? 'Buddies'));
    showRetroDialog<void>(context, title: 'Add Buddy', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Screen name'),
        RetroTextField(controller: sn, hint: 'Screen name', autofocus: true),
        const SizedBox(height: 6),
        const Text('Group'),
        RetroTextField(controller: group, hint: 'Group'),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          RetroButton(
            isDefault: true,
            onPressed: () async {
              if (sn.text.trim().isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                await app.addBuddy(sn.text.trim(), group.text.trim());
              } catch (e) {
                if (mounted) showRetroMessage(context, 'Add Buddy', 'Could not add buddy: $e');
              }
            },
            child: const Text('Add'),
          ),
        ]),
      ]);
    });
  }

  void _confirmSignOff(AppState app) {
    showRetroDialog<void>(context, title: 'Sign Off', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(app.settings.historyEnabled
            ? 'Sign off? Unsent messages will be cancelled and saved chat history will be cleared.'
            : 'Sign off? Unsent messages will be cancelled.'),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          RetroButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          const SizedBox(width: 6),
          RetroButton(
            autofocus: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              app.signOff();
            },
            child: const Text('Sign Off'),
          ),
        ]),
      ]);
    });
  }
}

/// The red "new messages" alert shown beside a buddy's name: an envelope and
/// how many messages are waiting.
class UnreadBadge extends StatelessWidget {
  final int count;
  const UnreadBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count new ${count == 1 ? 'message' : 'messages'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Retro.myName,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mail, size: 14, color: Colors.white),
          const SizedBox(width: 3),
          Text(count > 99 ? '99+' : '$count',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
        ]),
      ),
    );
  }
}

/// One picture button in the bottom strip: a coloured picture with its name
/// under it, and a little ▾ when it opens a menu.
class Pictogram extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool dropdown;
  final VoidCallback onTap;
  const Pictogram({super.key, required this.icon, required this.color, required this.label, required this.onTap, this.dropdown = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: RetroListTile(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 30,
            child: Stack(clipBehavior: Clip.none, children: [
              // A dark outline behind the picture, like the old icons.
              Icon(icon, size: 30, color: Colors.black54),
              Positioned(left: 1, top: 1, child: Icon(icon, size: 28, color: color)),
              if (dropdown)
                const Positioned(right: -10, top: -6, child: Icon(Icons.arrow_drop_down, size: 18)),
            ]),
          ),
          const SizedBox(height: 1),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}
