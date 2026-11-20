import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../oscar/bytes.dart';
import 'buddy_list.dart';
import 'chat.dart';
import 'retro.dart';

/// Signed-on layout. Wide screens (tablets, Steam Deck, ROG Ally, desktop)
/// show the buddy list and the open chat as windows on the teal desktop;
/// phones show one full-screen window at a time.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String? _wideChat;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth >= 820;
      // Wide layout: Back closes the open chat first, then leaves as usual.
      return PopScope(
        canPop: !wide || _wideChat == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _wideChat != null) {
            setState(() => _wideChat = null);
            context.read<AppState>().openConversation(null);
          }
        },
        child: Scaffold(
        body: SafeArea(
          child: Container(
            color: Retro.desktop,
            padding: EdgeInsets.all(wide ? 12 : 0),
            child: wide ? _wide(context) : BuddyListPane(onOpenChat: (sn) => _openNarrow(context, sn)),
          ),
        ),
      ),
      );
    });
  }

  Widget _wide(BuildContext context) {
    final app = context.watch<AppState>();
    final chat = _wideChat;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 330,
        child: FocusTraversalGroup(child: BuddyListPane(onOpenChat: (sn) => setState(() => _wideChat = sn))),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: chat == null
            ? Center(
                child: Text(
                  app.totalUnread > 0 ? 'You have new messages — look for the red alerts in your Buddy List.' : 'Pick a buddy to start a conversation.',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              )
            : FocusTraversalGroup(
                child: ChatPane(
                  key: ValueKey(normalizeSn(chat)),
                  screenName: chat,
                  onClose: () {
                    setState(() => _wideChat = null);
                    app.openConversation(null);
                  },
                ),
              ),
      ),
    ]);
  }

  void _openNarrow(BuildContext context, String sn) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        body: SafeArea(
          child: Container(
            color: Retro.desktop,
            child: ChatPane(screenName: sn, onClose: () => Navigator.of(ctx).pop()),
          ),
        ),
      ),
    ));
  }
}
