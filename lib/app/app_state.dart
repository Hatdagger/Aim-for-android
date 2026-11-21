import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../oscar/aim_html.dart';
import '../oscar/bytes.dart';
import '../oscar/client.dart';
import '../oscar/direct_connect.dart';
import '../oscar/odc.dart';
import '../oscar/models.dart';
import '../oscar/session.dart';
import '../oscar/signup_api.dart';
import 'invite.dart';
import 'history.dart';
import 'icons.dart';
import 'input_mode.dart';
import 'platform_bridge.dart';
import 'settings.dart';
import 'sounds.dart';

class Conversation {
  final String key;
  String displayName;
  final List<ChatLine> lines = [];
  int unread = 0;
  int typing = 0; // 0 none, 1 paused, 2 typing
  Conversation(this.key, this.displayName);
}

class BuddyView {
  final String screenName;
  final bool online;
  final bool away;
  final int idleMinutes;
  final Uint8List? icon;
  BuddyView(this.screenName, this.online, this.away, this.idleMinutes, this.icon);
}

class AppState extends ChangeNotifier {
  final AppSettings settings;
  final InputMode input;
  final SoundEngine sounds;
  final IconCache icons = IconCache();
  final HistoryStore history = HistoryStore();

  AppState(this.settings, this.input) : sounds = SoundEngine(settings) {
    void syncStyle() {
      OutgoingStyle.textColor = settings.myTextColor;
      OutgoingStyle.backColor = settings.myBackColor;
    }

    syncStyle();
    settings.addListener(syncStyle);
    settings.addListener(() => client?.direct.allowIncoming = settings.allowDirectConnect);
    // Screens watch AppState; redraw them whenever a setting changes so what
    // they show always matches the settings in use.
    settings.addListener(notifyListeners);
    inbox.incoming.listen((inv) {
      pendingInvite = inv;
      notifyListeners();
    });
  }

  final InviteInbox inbox = InviteInbox();

  /// An invite link that opened or was found by the app, waiting for sign-up.
  Invite? pendingInvite;

  Future<void> checkForInvite({bool clipboard = true}) async {
    final inv = await inbox.initial() ?? (clipboard ? await inbox.fromClipboard() : null);
    if (inv != null) {
      pendingInvite = inv;
      notifyListeners();
    }
  }

  void dismissInvite() {
    pendingInvite = null;
    notifyListeners();
  }

  SignupApi _api(String server, {String? fingerprint}) =>
      SignupApi(ServerConfig.parse(server), pinnedFingerprint: fingerprint ?? settings.certFor(server));

  void _rememberCert(String server, SignupApi api) {
    final fp = api.lastFingerprint;
    if (fp != null && settings.certFor(server) == null) settings.setCertFor(server, fp);
  }

  /// Creates an account from an invite, then signs straight on.
  Future<void> signUpWithInvite(Invite inv, String screenName, String password) async {
    final api = _api(inv.server, fingerprint: inv.fingerprint);
    await api.signUp(inviteCode: inv.code, screenName: screenName, password: password, deviceId: await deviceId());
    _rememberCert(inv.server, api);
    pendingInvite = null;
    settings.setupDone = true;
    await signOn(server: inv.server, screenName: screenName, password: password, savePassword: true, autoLogin: true);
  }

  Future<CreatedInvite> createInvite({bool household = false}) async {
    final c = client;
    if (c == null) throw const SignupError('Sign on first');
    final server = c.server.toString();
    final api = _api(server);
    final inv = await api.createInvite(
        screenName: c.screenName, password: c.password, deviceId: await deviceId(), household: household);
    _rememberCert(server, api);
    return inv;
  }

  AimClient? client;
  StreamSubscription<ClientEvent>? _sub;
  final Map<String, Conversation> conversations = {};
  final Map<String, Uint8List> _buddyIconHash = {};
  final Map<String, Uint8List> buddyIcons = {};
  String? openChat; // normalized screen name being viewed
  bool foreground = true;
  bool awayIsAuto = false;
  int _backgroundUnread = 0;
  DateTime? _onlineSince;
  bool _iconUploaded = false;
  String? signOnError;

  /// True once this sign-on has reached the server at least once; until then
  /// the sign-on window stays up (showing retries).
  bool everOnline = false;

  LinkState get link => client?.state ?? LinkState.offline;
  String? get linkMessage => client?.lastMessage;
  bool get signedOn => client != null && link != LinkState.offline && link != LinkState.stopped;
  String get myScreenName => client?.session?.formattedScreenName ?? client?.screenName ?? '';
  bool get isAway => client?.isAway ?? false;
  String? get awayMessage => client?.awayHtml;

  // --------------------------------------------------------------- sign on

  Future<void> signOn({
    required String server,
    required String screenName,
    required String password,
    required bool savePassword,
    required bool autoLogin,
  }) async {
    signOnError = null;
    everOnline = false;
    settings.server = server;
    await settings.rememberAccount(screenName, password, savePassword: savePassword, autoLogin: autoLogin);
    await _disposeClient();
    final c = AimClient(
      server: ServerConfig.parse(server),
      screenName: screenName,
      password: password,
      profileHtml: textToAimHtml(settings.profileFor(screenName)),
      fixLoopbackRedirects: settings.fixLoopbackRedirects,
      publicIp: () => _api(server).myIp(),
    );
    c.direct.allowIncoming = settings.allowDirectConnect;
    client = c;
    _iconUploaded = false;
    conversations.clear();
    if (settings.historyEnabled) {
      try {
        final all = await history.loadAll(screenName);
        for (final e in all.entries) {
          final conv = Conversation(normalizeSn(e.key), e.key);
          conv.lines.addAll(e.value);
          conversations[conv.key] = conv;
        }
      } catch (_) {}
    }
    _sub = c.events.listen(_onClientEvent);
    c.start();
    unawaited(PlatformBridge.requestNotificationPermission());
    notifyListeners();
  }

  Future<void> tryAutoLogin() async {
    final acct = settings.autoLoginAccount;
    if (acct == null || settings.server.isEmpty) return;
    final pw = await settings.passwordFor(acct.screenName);
    if (pw == null) return;
    await signOn(
        server: settings.server,
        screenName: acct.screenName,
        password: pw,
        savePassword: true,
        autoLogin: true);
  }

  /// Manual sign-off: ends the session, cancels pending messages and clears
  /// history. (A dropped connection is not a sign-off.)
  Future<void> signOff() async {
    _awayTimer?.cancel();
    _awayTimer = null;
    final c = client;
    final owner = c?.screenName;
    await c?.signOff();
    await _disposeClient();
    if (owner != null) {
      try {
        await history.clear(owner);
      } catch (_) {}
    }
    conversations.clear();
    buddyIcons.clear();
    _buddyIconHash.clear();
    directProgress.clear();
    openChat = null;
    everOnline = false;
    awayIsAuto = false;
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    _backgroundUnread = 0;
    await PlatformBridge.clearUnread();
    await PlatformBridge.stopKeepAlive();
    notifyListeners();
  }

  Future<void> _disposeClient() async {
    await _sub?.cancel();
    _sub = null;
    client = null;
  }

  // --------------------------------------------------------------- events

  void _onClientEvent(ClientEvent e) {
    switch (e) {
      case LinkStateChanged(:final state, :final message):
        _onLink(state, message);
      case OutboxChanged(:final message):
        _onOutbox(message);
      case SessionEvent(:final event):
        _onSession(event);
      case DirectConnectEvent(:final event):
        _onDirect(event);
    }
    notifyListeners();
  }

  void _onLink(LinkState s, String? message) {
    switch (s) {
      case LinkState.online:
        everOnline = true;
        _onlineSince = DateTime.now();
        PlatformBridge.startKeepAlive('Signed on as $myScreenName');
        if (Platform.isAndroid && !settings.askedBackground) {
          // First sign-on: ask Android not to put AIM to sleep in the background.
          settings.askedBackground = true;
          PlatformBridge.requestBackgroundRunning();
        }
        _uploadOwnIcon();
      case LinkState.reconnecting:
        PlatformBridge.startKeepAlive('Reconnecting…');
      case LinkState.stopped:
        signOnError = message;
        PlatformBridge.stopKeepAlive();
      case LinkState.offline:
        PlatformBridge.stopKeepAlive();
      case LinkState.connecting:
        break;
    }
  }

  bool get _inInitialBurst =>
      _onlineSince == null || DateTime.now().difference(_onlineSince!) < const Duration(seconds: 4);

  void _onSession(OscarEvent ev) {
    switch (ev) {
      case BuddyArrived(:final info):
        final key = normalizeSn(info.screenName);
        final wasOnline = _wasOnline.contains(key);
        _wasOnline.add(key);
        if (!wasOnline && !_inInitialBurst) sounds.play(SoundEvent.buddyIn);
        final h = info.iconHash;
        if (h != null) _maybeFetchIcon(info.screenName, h);
      case BuddyDeparted(:final screenName):
        final key = normalizeSn(screenName);
        if (_wasOnline.remove(key)) sounds.play(SoundEvent.buddyOut);
      case MessageReceived(:final message):
        _onIncoming(message);
      case TypingChanged(:final screenName, :final state):
        final c = conversations[normalizeSn(screenName)];
        if (c != null) c.typing = state;
      case BuddyListChanged():
      case SelfInfoChanged():
      case RendezvousReceived():
        break;
    }
  }

  final Set<String> _wasOnline = {};

  Conversation conversationFor(String sn) {
    final key = normalizeSn(sn);
    return conversations.putIfAbsent(key, () => Conversation(key, sn));
  }

  void _onIncoming(IncomingMessage m) {
    final (fg, bg) = aimHtmlColors(m.html);
    _addIncoming(m.from, ChatLine(m.from, m.text, m.time, mine: false, auto: m.autoResponse, fg: fg, bg: bg));
  }

  void _addIncoming(String from, ChatLine line) {
    final conv = conversationFor(from);
    final first = conv.lines.where((l) => !l.system).isEmpty;
    conv.displayName = from;
    conv.typing = 0;
    conv.lines.add(line);
    _persist(conv, line);
    _alert(conv, first: first);
  }

  void _alert(Conversation conv, {bool first = false}) {
    final viewing = foreground && openChat == conv.key;
    if (!viewing) conv.unread++;
    if (foreground) {
      sounds.play(first ? SoundEvent.firstIm : SoundEvent.imReceived);
    } else {
      _backgroundUnread++;
      PlatformBridge.showUnread(_backgroundUnread);
    }
  }

  void _onOutbox(OutgoingMessage m) {
    for (final conv in conversations.values) {
      for (final l in conv.lines) {
        if (l.pendingId == m.id) {
          if (m.status == OutboxStatus.sent) {
            l.pendingId = null;
            _persist(conv, l);
            sounds.play(SoundEvent.imSent);
          } else if (m.status == OutboxStatus.cancelled) {
            conv.lines.remove(l);
          }
          return;
        }
      }
    }
  }

  // --------------------------------------------------------------- direct connect

  /// Bytes of a picture arriving now, per buddy: (got, total).
  final Map<String, (int, int)> directProgress = {};

  DirectLink? directLink(String sn) => client?.direct.linkFor(sn);
  bool directOpen(String sn) => client?.direct.isOpen(sn) ?? false;

  final Set<String> _directWasOpen = {};

  void _note(String sn, String text) {
    final conv = conversationFor(sn);
    final line = ChatLine('', text, DateTime.now(), mine: false, system: true);
    conv.lines.add(line);
  }

  void _onDirect(DirectEvent e) {
    switch (e) {
      case DirectStateChanged(:final link, :final state):
        final key = normalizeSn(link.peer);
        final conv = conversationFor(link.peer);
        switch (state) {
          case DirectState.invited:
            _alert(conv);
          case DirectState.connected:
            _directWasOpen.add(key);
            _note(link.peer, 'Direct Connect with ${conv.displayName} is open. Pictures go straight between you.');
            sounds.play(SoundEvent.buddyIn);
          case DirectState.failed:
            _note(link.peer, 'Direct Connect failed.');
          case DirectState.declined:
            _note(link.peer, '${conv.displayName} declined Direct Connect.');
          case DirectState.closed:
            directProgress.remove(key);
            if (_directWasOpen.remove(key)) _note(link.peer, 'Direct Connect closed.');
          case DirectState.inviting:
          case DirectState.connecting:
            break;
        }
      case DirectMessageIn(:final from, :final message):
        directProgress.remove(normalizeSn(from));
        unawaited(_onDirectMessage(from, message));
      case DirectTypingIn(:final from, :final state):
        final c = conversations[normalizeSn(from)];
        if (c != null) c.typing = state;
      case DirectProgress(:final from, :final got, :final total):
        final key = normalizeSn(from);
        if (got >= total) {
          directProgress.remove(key);
        } else {
          directProgress[key] = (got, total);
        }
    }
  }

  Future<void> _onDirectMessage(String from, DirectMessage m) async {
    final owner = client?.screenName;
    if (owner == null) return;
    final paths = <String>[];
    for (final im in m.images.take(20)) {
      try {
        paths.add(await history.savePicture(owner, im.data));
      } catch (_) {}
    }
    if (m.text.isEmpty && paths.isEmpty) return;
    final (fg, bg) = aimHtmlColors(m.html);
    _addIncoming(from,
        ChatLine(from, m.text, DateTime.now(), mine: false, auto: m.autoResponse, fg: fg, bg: bg, images: paths));
    notifyListeners();
  }

  Future<void> directInvite(String sn) async {
    final c = client;
    if (c == null) return;
    conversationFor(sn);
    final f = c.direct.invite(sn);
    notifyListeners();
    await f;
  }

  Future<void> directAccept(String sn) async => client?.direct.accept(sn);
  Future<void> directDecline(String sn) async => client?.direct.decline(sn);
  Future<void> directClose(String sn) async => client?.direct.close(sn);

  /// Sends a picture over the open Direct Connect. [bytes] is already sized
  /// for sending (see pictures.dart).
  Future<void> sendPicture(String to, Uint8List bytes, {String text = ''}) async {
    final c = client;
    if (c == null || !c.direct.isOpen(to)) throw Exception('Direct Connect is not open');
    final path = await history.savePicture(c.screenName, bytes);
    final conv = conversationFor(to);
    final line = ChatLine(myScreenName, text, DateTime.now(),
        mine: true, fg: settings.myTextColor, bg: settings.myBackColor, images: [path]);
    conv.lines.add(line);
    notifyListeners();
    final ext = pictureExtension(bytes);
    try {
      await c.direct.send(to, text, images: [OdcImage(1, bytes, name: 'picture$ext')]);
      _persist(conv, line);
      sounds.play(SoundEvent.imSent);
    } catch (_) {
      conv.lines.remove(line);
      _note(to, 'Picture not sent: Direct Connect closed.');
    }
    notifyListeners();
  }

  OutgoingMessage? pending(String id) => client?.outbox.where((m) => m.id == id).firstOrNull;

  void _persist(Conversation c, ChatLine l) {
    if (!settings.historyEnabled || client == null || l.pendingId != null) return;
    history.append(client!.screenName, c.displayName, l).catchError((_) {});
  }

  // --------------------------------------------------------------- actions

  void send(String to, String text) {
    final c = client;
    if (c == null || text.trim().isEmpty) return;
    if (c.direct.isOpen(to)) {
      unawaited(_sendDirect(c, to, text.trim()));
      return;
    }
    _sendViaServer(c, to, text);
  }

  /// While Direct Connect is open, messages go over it (like AIM does). If it
  /// dropped, the message goes through the server instead.
  Future<void> _sendDirect(AimClient c, String to, String text) async {
    final conv = conversationFor(to);
    final line = ChatLine(myScreenName, text, DateTime.now(),
        mine: true, fg: settings.myTextColor, bg: settings.myBackColor);
    conv.lines.add(line);
    notifyListeners();
    try {
      await c.direct.send(to, text);
      _persist(conv, line);
      sounds.play(SoundEvent.imSent);
    } catch (_) {
      conv.lines.remove(line);
      _sendViaServer(c, to, text);
    }
    notifyListeners();
  }

  void _sendViaServer(AimClient c, String to, String text) {
    final conv = conversationFor(to);
    final m = c.send(to, text.trim());
    conv.lines.add(ChatLine(myScreenName, text.trim(), DateTime.now(),
        mine: true, pendingId: m.id, fg: settings.myTextColor, bg: settings.myBackColor));
    notifyListeners();
  }

  void cancelPending(String id) {
    client?.cancel(id);
    notifyListeners();
  }

  void retryPending(String id) {
    client?.retry(id);
    notifyListeners();
  }

  void typing(String to, int state) {
    final c = client;
    if (c == null) return;
    if (c.direct.isOpen(to)) {
      c.direct.sendTyping(to, state);
    } else {
      c.session?.sendTyping(to, state);
    }
  }

  void openConversation(String? sn) {
    openChat = sn == null ? null : normalizeSn(sn);
    if (sn != null) conversationFor(sn).unread = 0;
    notifyListeners();
  }

  void closeConversation(String key) {
    conversations.remove(key);
    if (openChat == key) openChat = null;
    notifyListeners();
  }

  void setAway(String? text, {bool auto = false}) {
    client?.setAway(text == null || text.isEmpty ? null : textToAimHtml(text));
    awayIsAuto = auto && text != null;
    notifyListeners();
  }

  void setProfile(String text) {
    settings.setProfileFor(myScreenName, text);
    client?.setProfile(textToAimHtml(text));
    notifyListeners();
  }

  Future<ProfileInfo> profileOf(String sn) async {
    final s = client?.session;
    if (s == null || !s.isOnline) throw Exception('Not signed on');
    return s.getProfile(sn);
  }

  Future<void> addBuddy(String sn, String group) async {
    await client?.session?.addBuddy(sn, group.isEmpty ? 'Buddies' : group);
    notifyListeners();
  }

  Future<void> removeBuddy(String sn) async {
    await client?.session?.removeBuddy(sn);
    notifyListeners();
  }

  // Buddy list editing. Each throws a readable message if it can't be done.
  Future<void> _edit(Future<void> Function(OscarSession s) f) async {
    final s = client?.session;
    if (s == null || !s.isOnline) throw Exception('Not signed on');
    await f(s);
    notifyListeners();
  }

  /// Groups with their ids, in list order (for editing).
  List<BuddyGroup> get rawGroups => client?.session?.groups ?? const [];

  Future<void> addGroup(String name) => _edit((s) => s.addGroup(name));
  Future<void> renameGroup(int gid, String name) => _edit((s) => s.renameGroup(gid, name));
  Future<void> removeGroup(int gid, {int? moveTo}) => _edit((s) => s.removeGroup(gid, moveTo: moveTo));
  Future<void> moveBuddy(String sn, int toGid) => _edit((s) => s.moveBuddy(sn, toGid));
  Future<void> moveGroup(int gid, int delta) => _edit((s) => s.moveGroup(gid, delta));
  Future<void> moveBuddyWithinGroup(String sn, int delta) => _edit((s) => s.moveBuddyWithinGroup(sn, delta));

  bool isBlocked(String sn) => client?.session?.isBlocked(sn) ?? false;
  bool isBuddy(String sn) => client?.session?.isBuddy(sn) ?? false;

  Future<void> setBlocked(String sn, bool blocked) async {
    final s = client?.session;
    if (s == null || !s.isOnline) throw Exception('Not signed on');
    blocked ? await s.block(sn) : await s.unblock(sn);
    notifyListeners();
  }

  /// Returns the buddy's new warning level (percent).
  Future<int> warn(String sn, {bool anonymous = false}) async {
    final s = client?.session;
    if (s == null || !s.isOnline) throw Exception('Not signed on');
    return s.warn(sn, anonymous: anonymous);
  }

  // --------------------------------------------------------------- icons

  Uint8List? get myIcon {
    final p = settings.iconPathFor(client?.screenName ?? settings.lastScreenName ?? '');
    if (p == null) return null;
    final f = File(p);
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  Future<void> setMyIcon(Uint8List bytes) async {
    final sn = client?.screenName ?? settings.lastScreenName;
    if (sn == null) return;
    final path = await icons.saveOwn(sn, bytes);
    settings.setIconPathFor(sn, path);
    _iconUploaded = false;
    await _uploadOwnIcon();
    notifyListeners();
  }

  Future<void> _uploadOwnIcon() async {
    if (_iconUploaded) return;
    final s = client?.session;
    final bytes = myIcon;
    if (s == null || bytes == null || !s.isOnline) return;
    _iconUploaded = true;
    try {
      await s.setBuddyIcon(bytes);
    } catch (_) {
      _iconUploaded = false;
    }
  }

  Future<void> _maybeFetchIcon(String sn, Uint8List hash) async {
    final key = normalizeSn(sn);
    final prev = _buddyIconHash[key];
    if (prev != null && hex(prev) == hex(hash) && buddyIcons.containsKey(key)) return;
    _buddyIconHash[key] = hash;
    final cached = await icons.get(hash);
    if (cached != null) {
      buddyIcons[key] = cached;
      notifyListeners();
      return;
    }
    try {
      final bytes = await client?.session?.fetchBuddyIcon(sn, hash);
      if (bytes != null) {
        buddyIcons[key] = bytes;
        await icons.put(hash, bytes);
        notifyListeners();
      }
    } catch (_) {}
  }

  // --------------------------------------------------------------- buddy list view

  List<(String, List<BuddyView>)> get buddyGroups {
    final s = client?.session;
    if (s == null) return const [];
    return s.groups.map((g) {
      final views = g.buddies.map((b) {
        final info = s.online[normalizeSn(b)];
        return BuddyView(info?.screenName ?? b, info != null, info?.isAway ?? false, info?.idleMinutes ?? 0,
            buddyIcons[normalizeSn(b)]);
      }).toList();
      views.sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.screenName.toLowerCase().compareTo(b.screenName.toLowerCase());
      });
      return (g.name, views);
    }).toList();
  }

  bool isBuddyOnline(String sn) => client?.session?.online.containsKey(normalizeSn(sn)) ?? false;

  // --------------------------------------------------------------- lifecycle

  Timer? _awayTimer;

  void setForeground(bool fg) {
    if (foreground == fg) return;
    foreground = fg;
    sounds.foreground = fg;
    _awayTimer?.cancel();
    _awayTimer = null;
    if (fg) {
      _backgroundUnread = 0;
      PlatformBridge.clearUnread();
      if (openChat != null) conversations[openChat!]?.unread = 0;
      if (awayIsAuto) setAway(null);
      client?.retryNow();
    } else {
      // Only go away once the app has stayed closed for a while (10 minutes
      // by default), so a quick look at another app doesn't flip you away.
      if (settings.autoAway && client != null && !isAway) {
        _awayTimer = Timer(Duration(minutes: settings.autoAwayMinutes), () {
          _awayTimer = null;
          if (!foreground && settings.autoAway && client != null && !isAway) {
            setAway(settings.autoAwayMessage, auto: true);
          }
        });
      }
    }
    notifyListeners();
  }

  int get totalUnread => conversations.values.fold(0, (a, c) => a + c.unread);
}
