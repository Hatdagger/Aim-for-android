import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../oscar/bytes.dart';

class ChatLine {
  final String from;
  final String text;
  final DateTime time;
  final bool mine;
  final bool auto;

  /// Colours the sender picked (ARGB), or null for the default look.
  final int? fg;
  final int? bg;

  /// Outbox id while the message is still pending, otherwise null.
  String? pendingId;

  ChatLine(this.from, this.text, this.time,
      {required this.mine, this.auto = false, this.pendingId, this.fg, this.bg});

  Map<String, dynamic> toJson() =>
      {
        'f': from,
        't': text,
        'at': time.millisecondsSinceEpoch,
        'm': mine,
        if (auto) 'a': true,
        if (fg != null) 'fg': fg,
        if (bg != null) 'bg': bg,
      };

  static ChatLine fromJson(Map<String, dynamic> j) => ChatLine(
        j['f'] as String,
        j['t'] as String,
        DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        mine: j['m'] as bool,
        auto: j['a'] as bool? ?? false,
        fg: j['fg'] as int?,
        bg: j['bg'] as int?,
      );
}

/// Optional on-device chat history (off by default). Cleared on sign-off.
class HistoryStore {
  Future<Directory> _dir(String owner) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}history${Platform.pathSeparator}${normalizeSn(owner)}');
    await d.create(recursive: true);
    return d;
  }

  String _fileName(String buddy) =>
      '${normalizeSn(buddy).replaceAll(RegExp(r'[^a-z0-9@._-]'), '_')}.jsonl';

  Future<void> append(String owner, String buddy, ChatLine line) async {
    final d = await _dir(owner);
    final f = File('${d.path}${Platform.pathSeparator}${_fileName(buddy)}');
    await f.writeAsString('${jsonEncode(line.toJson())}\n', mode: FileMode.append, flush: true);
  }

  Future<Map<String, List<ChatLine>>> loadAll(String owner) async {
    final d = await _dir(owner);
    final out = <String, List<ChatLine>>{};
    await for (final f in d.list()) {
      if (f is! File || !f.path.endsWith('.jsonl')) continue;
      final lines = <ChatLine>[];
      String? buddy;
      for (final l in await f.readAsLines()) {
        if (l.trim().isEmpty) continue;
        try {
          final c = ChatLine.fromJson(jsonDecode(l) as Map<String, dynamic>);
          lines.add(c);
          if (!c.mine) buddy = c.from;
        } catch (_) {}
      }
      final name = buddy ?? f.uri.pathSegments.last.replaceAll('.jsonl', '');
      out[name] = lines;
    }
    return out;
  }

  Future<void> clear(String owner) async {
    final d = await _dir(owner);
    if (await d.exists()) await d.delete(recursive: true);
  }
}
