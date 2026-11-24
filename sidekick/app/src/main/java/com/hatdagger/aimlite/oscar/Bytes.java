package com.hatdagger.aimlite.oscar;

import java.io.ByteArrayOutputStream;
import java.io.UnsupportedEncodingException;
import java.util.ArrayList;
import java.util.List;

/** Big-endian byte helpers and TLVs (OSCAR's building blocks). Plain Java, Android 2.2 safe. */
public final class Bytes {
    private Bytes() {}

    public static byte[] utf8(String s) {
        try {
            return s.getBytes("UTF-8");
        } catch (UnsupportedEncodingException e) {
            throw new RuntimeException(e);
        }
    }

    public static String utf8(byte[] b) {
        try {
            return new String(b, "UTF-8");
        } catch (UnsupportedEncodingException e) {
            throw new RuntimeException(e);
        }
    }

    public static String latin1(byte[] b) {
        char[] c = new char[b.length];
        for (int i = 0; i < b.length; i++) c[i] = (char) (b[i] & 0xff);
        return new String(c);
    }

    public static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) {
            String h = Integer.toHexString(x & 0xff);
            if (h.length() < 2) sb.append('0');
            sb.append(h);
        }
        return sb.toString();
    }

    public static byte[] unhex(String s) {
        byte[] out = new byte[s.length() / 2];
        for (int i = 0; i < out.length; i++) {
            out[i] = (byte) Integer.parseInt(s.substring(i * 2, i * 2 + 2), 16);
        }
        return out;
    }

    public static boolean isAscii(String s) {
        for (int i = 0; i < s.length(); i++) if (s.charAt(i) >= 128) return false;
        return true;
    }

    /** Screen names compare without spaces or case. */
    public static String normalizeSn(String sn) {
        return sn.replace(" ", "").toLowerCase();
    }

    public static byte[] copy(byte[] b, int from, int to) {
        byte[] out = new byte[to - from];
        System.arraycopy(b, from, out, 0, out.length);
        return out;
    }

    // ------------------------------------------------------------------ writer

    public static final class Writer {
        private final ByteArrayOutputStream b = new ByteArrayOutputStream();

        public Writer u8(int v) {
            b.write(v & 0xff);
            return this;
        }

        public Writer u16(int v) {
            b.write((v >> 8) & 0xff);
            b.write(v & 0xff);
            return this;
        }

        public Writer u32(long v) {
            b.write((int) ((v >> 24) & 0xff));
            b.write((int) ((v >> 16) & 0xff));
            b.write((int) ((v >> 8) & 0xff));
            b.write((int) (v & 0xff));
            return this;
        }

        public Writer bytes(byte[] d) {
            b.write(d, 0, d.length);
            return this;
        }

        /** u8 length-prefixed ASCII string (screen names, cookies). */
        public Writer str8(String s) {
            byte[] e = asciiSafe(s);
            u8(e.length);
            return bytes(e);
        }

        public Writer tlv(int type, byte[] data) {
            u16(type);
            u16(data.length);
            return bytes(data);
        }

        public Writer tlvStr(int type, String s) {
            return tlv(type, utf8(s));
        }

        public Writer tlvU8(int type, int v) {
            return tlv(type, new byte[] {(byte) v});
        }

        public Writer tlvU16(int type, int v) {
            return tlv(type, new byte[] {(byte) (v >> 8), (byte) v});
        }

        public Writer tlvU32(int type, long v) {
            return tlv(type, new byte[] {(byte) (v >> 24), (byte) (v >> 16), (byte) (v >> 8), (byte) v});
        }

        public int size() {
            return b.size();
        }

        public byte[] toBytes() {
            return b.toByteArray();
        }

        private static byte[] asciiSafe(String s) {
            byte[] out = new byte[s.length()];
            for (int i = 0; i < s.length(); i++) {
                char c = s.charAt(i);
                out[i] = (byte) (c < 128 ? c : '?');
            }
            return out;
        }
    }

    // ------------------------------------------------------------------ reader

    public static final class Reader {
        public final byte[] d;
        public int pos;
        public final int end;

        public Reader(byte[] d) {
            this(d, 0, d.length);
        }

        public Reader(byte[] d, int pos, int end) {
            this.d = d;
            this.pos = pos;
            this.end = end;
        }

        public int remaining() {
            return end - pos;
        }

        private void need(int n) {
            if (pos + n > end) throw new IndexOutOfBoundsException("need " + n + " bytes, have " + remaining());
        }

        public int u8() {
            need(1);
            return d[pos++] & 0xff;
        }

        public int u16() {
            need(2);
            int v = ((d[pos] & 0xff) << 8) | (d[pos + 1] & 0xff);
            pos += 2;
            return v;
        }

        public long u32() {
            need(4);
            long v = ((long) (d[pos] & 0xff) << 24) | ((d[pos + 1] & 0xff) << 16) | ((d[pos + 2] & 0xff) << 8)
                    | (d[pos + 3] & 0xff);
            pos += 4;
            return v;
        }

        public byte[] bytes(int n) {
            need(n);
            byte[] out = copy(d, pos, pos + n);
            pos += n;
            return out;
        }

        public byte[] rest() {
            return bytes(remaining());
        }

        public String str8() {
            return latin1(bytes(u8()));
        }

        /** TLVs until the end (count &lt; 0) or [count] of them. */
        public Tlvs tlvs(int count) {
            List<Tlv> list = new ArrayList<Tlv>();
            while (remaining() >= 4 && (count < 0 || list.size() < count)) {
                int t = u16();
                int l = u16();
                if (l > remaining()) break;
                list.add(new Tlv(t, bytes(l)));
            }
            return new Tlvs(list);
        }

        public Tlvs tlvs() {
            return tlvs(-1);
        }
    }

    public static final class Tlv {
        public final int type;
        public final byte[] value;

        public Tlv(int type, byte[] value) {
            this.type = type;
            this.value = value;
        }

        public int u16() {
            return value.length < 2 ? 0 : ((value[0] & 0xff) << 8) | (value[1] & 0xff);
        }

        public long u32() {
            return value.length < 4 ? 0 : new Reader(value).u32();
        }

        public String str() {
            return utf8(value);
        }

        public Reader reader() {
            return new Reader(value);
        }
    }

    public static final class Tlvs {
        public final List<Tlv> items;

        public Tlvs(List<Tlv> items) {
            this.items = items;
        }

        public Tlv get(int type) {
            for (Tlv t : items) if (t.type == type) return t;
            return null;
        }

        public boolean has(int type) {
            return get(type) != null;
        }
    }
}
