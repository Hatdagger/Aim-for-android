import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../oscar/aim_html.dart';
import '../oscar/client.dart';
import '../oscar/models.dart';
import 'profile_screen.dart';
import 'retro.dart';
import 'update_button.dart';
import 'retro_text_field.dart';
import 'settings_screen.dart';
import 'sign_up.dart';

/// The buddy list window. [onOpenChat] decides whether a chat opens in a
/// side window (wide screens) or as a new page (phones).
class BuddyListPane extends StatefulWidget {
  final void Function(String screenName) onOpenChat;
  const BuddyListPane({super.key, required this.onOpenChat});

  @override
  State<BuddyListPane> createState() => _BuddyListPaneState();
}

class _BuddyListPaneState extends State<BuddyListPane> {
  int _tab = 0; // 0 buddies, 1 chats
  final Set<String> _collapsed = {};

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
          Row(children: [
            Expanded(child: _tabButton('Buddies', 0)),
            const SizedBox(width: 4),
            Expanded(child: _tabButton(app.totalUnread > 0 ? 'Chats (${app.totalUnread})' : 'Chats', 1)),
          ]),
          const SizedBox(height: 4),
          Expanded(
            child: Sunken(
              child: FocusTraversalGroup(child: _tab == 0 ? _buddies(app) : _chats(app)),
            ),
          ),
          const SizedBox(height: 4),
          _toolbar(app),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int i) => RetroButton(
        onPressed: () => setState(() => _tab = i),
        minWidth: 0,
        child: Text(label, style: TextStyle(fontWeight: _tab == i ? FontWeight.bold : FontWeight.normal)),
      );

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
    for (final (name, buddies) in groups) {
      final on = buddies.where((b) => b.online).toList();
      offline.addAll(buddies.where((b) => !b.online));
      children.add(_groupHeader(name, on.length, buddies.length, autofocus: first));
      first = false;
      if (!_collapsed.contains(name)) {
        for (final b in on) {
          children.add(_buddyRow(app, b));
        }
      }
    }
    if (offline.isNotEmpty) {
      children.add(_groupHeader('Offline', 0, offline.length, autofocus: false, showCount: false));
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

  Widget _groupHeader(String name, int on, int total, {required bool autofocus, bool showCount = true}) {
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

  Widget _buddyRow(AppState app, BuddyView b) {
    return RetroListTile(
      onTap: () => widget.onOpenChat(b.screenName),
      onLongPress: () => _buddyMenu(app, b.screenName),
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
                color: b.online ? null : Retro.shadow,
              ),
            ),
          ),
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
            onPressed: () => _buddyMenu(app, b.screenName),
            icon: const Icon(Icons.more_vert),
          ),
        ]),
      ),
    );
  }

  String _idle(int m) => m < 60 ? '(${m}m)' : '(${m ~/ 60}h)';

  Widget _chats(AppState app) {
    final convs = app.conversations.values.toList()
      ..sort((a, b) {
        final ta = a.lines.isEmpty ? DateTime(2000) : a.lines.last.time;
        final tb = b.lines.isEmpty ? DateTime(2000) : b.lines.last.time;
        return tb.compareTo(ta);
      });
    if (convs.isEmpty) {
      return const Padding(padding: EdgeInsets.all(12), child: Text('No conversations yet.'));
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (var i = 0; i < convs.length; i++)
          RetroListTile(
            autofocus: i == 0,
            onTap: () => widget.onOpenChat(convs[i].displayName),
            onLongPress: () => app.closeConversation(convs[i].key),
            child: Row(children: [
              BuddyAvatar(bytes: app.buddyIcons[convs[i].key], size: 34, dim: !app.isBuddyOnline(convs[i].displayName)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(convs[i].displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (convs[i].lines.isNotEmpty)
                    Text(
                      '${convs[i].lines.last.mine ? 'You: ' : ''}${convs[i].lines.last.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ]),
              ),
              if (convs[i].unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  color: Retro.myName,
                  child: Text('${convs[i].unread}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
      ],
    );
  }

  Widget _toolbar(AppState app) {
    return Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
      RetroButton(minWidth: 0, onPressed: () => _awayDialog(app), child: const Text('Away')),
      RetroButton(minWidth: 0, onPressed: () => _addBuddyDialog(app), child: const Text('Add')),
      RetroButton(minWidth: 0, onPressed: () => _newGroup(app), child: const Text('New Group')),
      RetroButton(minWidth: 0, onPressed: () => showInviteDialog(context), child: const Text('Invite')),
      RetroButton(
        minWidth: 0,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ProfileScreen(screenName: app.myScreenName, isMe: true))),
        child: const Text('My Info'),
      ),
      RetroButton(
        minWidth: 0,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        child: const Icon(Icons.settings),
      ),
      RetroButton(minWidth: 0, onPressed: () => _confirmSignOff(app), child: const Text('Sign Off')),
    ]);
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

  void _addBuddyDialog(AppState app, {String? group0}) {
    final sn = TextEditingController();
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
