import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../oscar/aim_html.dart';
import '../oscar/client.dart';
import 'profile_screen.dart';
import 'retro.dart';
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
        Text(showCount ? '$name ($on/$total)' : '$name ($total)', style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
    );
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

  void _addBuddyDialog(AppState app) {
    final sn = TextEditingController();
    final group = TextEditingController(text: 'Buddies');
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
