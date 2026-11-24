package com.hatdagger.aimlite.oscar;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;

/** AIM's message HTML and character sets. */
public final class AimText {
    private AimText() {}

    public static String escape(String t) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < t.length(); i++) {
            char c = t.charAt(i);
            switch (c) {
                case '&': sb.append("&amp;"); break;
                case '<': sb.append("&lt;"); break;
                case '>': sb.append("&gt;"); break;
                case '"': sb.append("&quot;"); break;
                case '\r': break;
                case '\n': sb.append("<BR>"); break;
                default: sb.append(c);
            }
        }
        return sb.toString();
    }

    /** Plain text to the HTML AIM clients send. */
    public static String toHtml(String text) {
        return "<HTML><BODY BGCOLOR=\"#ffffff\"><FONT LANG=\"0\">" + escape(text) + "</FONT></BODY></HTML>";
    }

    /** AIM HTML to plain text (line breaks kept, tags dropped, entities decoded). */
    public static String toText(String html) {
        String s = html.replaceAll("(?i)<br\\s*/?>", "\n").replaceAll("(?i)</p>", "\n");
        s = s.replaceAll("<[^>]*>", "");
        StringBuilder sb = new StringBuilder();
        int i = 0;
        while (i < s.length()) {
            char c = s.charAt(i);
            if (c == '&') {
                int semi = s.indexOf(';', i);
                if (semi > i && semi - i <= 8) {
                    String ent = s.substring(i + 1, semi);
                    String rep = entity(ent);
                    if (rep != null) {
                        sb.append(rep);
                        i = semi + 1;
                        continue;
                    }
                }
            }
            sb.append(c);
            i++;
        }
        return sb.toString().trim();
    }

    private static String entity(String e) {
        String l = e.toLowerCase();
        if (l.equals("amp")) return "&";
        if (l.equals("lt")) return "<";
        if (l.equals("gt")) return ">";
        if (l.equals("quot")) return "\"";
        if (l.equals("apos")) return "'";
        if (l.equals("nbsp")) return " ";
        try {
            if (l.startsWith("#x")) return String.valueOf((char) Integer.parseInt(l.substring(2), 16));
            if (l.startsWith("#")) return String.valueOf((char) Integer.parseInt(l.substring(1)));
        } catch (NumberFormatException ignored) {
        }
        return null;
    }

    /** Charset code 0 = ASCII, 2 = UTF-16BE ("unicode"), 3 = Latin-1. Returns {code, bytes}. */
    public static Object[] encode(String html) {
        if (Bytes.isAscii(html)) return new Object[] {0, Bytes.utf8(html)};
        byte[] out = new byte[html.length() * 2];
        for (int i = 0; i < html.length(); i++) {
            char c = html.charAt(i);
            out[i * 2] = (byte) (c >> 8);
            out[i * 2 + 1] = (byte) c;
        }
        return new Object[] {2, out};
    }

    public static String decode(int charset, byte[] b) {
        if (charset == 2) {
            char[] c = new char[b.length / 2];
            for (int i = 0; i < c.length; i++) c[i] = (char) (((b[i * 2] & 0xff) << 8) | (b[i * 2 + 1] & 0xff));
            return new String(c);
        }
        if (charset == 3) return Bytes.latin1(b);
        try {
            return Charset.forName("UTF-8").newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(b)).toString();
        } catch (CharacterCodingException e) {
            return Bytes.latin1(b);
        }
    }

    /** Charset name (as chat rooms and invites give it) to a code for [decode]. */
    public static int charsetCode(String name) {
        String n = name == null ? "" : name.toLowerCase();
        if (n.contains("unicode") || n.contains("utf-16") || n.contains("ucs")) return 2;
        if (n.contains("8859") || n.contains("latin")) return 3;
        return 0;
    }
}
