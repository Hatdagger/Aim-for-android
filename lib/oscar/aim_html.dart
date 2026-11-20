import 'dart:convert';
import 'dart:typed_data';

/// AIM sends messages as a small subset of HTML. This turns that into plain
/// text for the chat view, and plain text back into AIM-compatible HTML.
String htmlToText(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  s = s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  s = s.replaceAll('&amp;', '&');
  return s.trim();
}

String escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String textToAimHtml(String text) {
  final body = escapeHtml(text).replaceAll('\r\n', '\n').replaceAll('\n', '<BR>');
  return '<HTML><BODY BGCOLOR="#ffffff"><FONT LANG="0">$body</FONT></BODY></HTML>';
}

bool isAscii(String s) => s.codeUnits.every((c) => c < 128);

/// Encodes text for an ICBM text fragment. Returns (charset, bytes).
(int, Uint8List) encodeImText(String html) {
  if (isAscii(html)) return (0x0000, Uint8List.fromList(ascii.encode(html)));
  final units = html.codeUnits; // UTF-16 code units
  final out = Uint8List(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    out[i * 2] = (units[i] >> 8) & 0xff;
    out[i * 2 + 1] = units[i] & 0xff;
  }
  return (0x0002, out);
}

String decodeImText(int charset, List<int> bytes) {
  if (charset == 0x0002) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }
  if (charset == 0x0003) return latin1.decode(bytes);
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}
