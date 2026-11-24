package com.hatdagger.aimlite.oscar;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

/** Chat rooms ("Buddy Chat"): room ids, messages, invites and a room's own connection. */
public final class Rooms {
    private Rooms() {}

    /** AIM capability for chat rooms; invites carry it. */
    public static final byte[] CAP_CHAT = Bytes.unhex("748f2420628711d18222444553540000");
    public static final int PRIVATE_EXCHANGE = 4;

    public static final class RoomInfo {
        public final int exchange;
        public final String cookie;
        public final int instance;
        public final String name;

        public RoomInfo(int exchange, String cookie, int instance, String name) {
            this.exchange = exchange;
            this.cookie = cookie;
            this.instance = instance;
            this.name = name;
        }

        public String key() {
            return cookie.toLowerCase();
        }

        public byte[] ref() {
            return new Bytes.Writer().u16(exchange).str8(cookie).u16(instance).toBytes();
        }

        public static RoomInfo readRef(Bytes.Reader r) {
            int ex = r.u16();
            String c = r.str8();
            int in = r.u16();
            return new RoomInfo(ex, c, in, nameFromCookie(c));
        }

        public static RoomInfo readFull(Bytes.Reader r) {
            int ex = r.u16();
            String c = r.str8();
            int in = r.u16();
            String name = nameFromCookie(c);
            if (r.remaining() >= 3) {
                r.u8(); // detail level
                int count = r.u16();
                Bytes.Tlvs t = r.tlvs(count);
                Bytes.Tlv n = t.get(0x00d3);
                if (n == null) n = t.get(0x006a);
                if (n != null && n.value.length > 0) name = n.str();
            }
            return new RoomInfo(ex, c, in, name);
        }

        /** Cookies look like "4-0-Room Name"; the name is the last part. */
        public static String nameFromCookie(String cookie) {
            String[] p = cookie.split("-", 3);
            if (p.length == 3) {
                try {
                    Integer.parseInt(p[0]);
                    Integer.parseInt(p[1]);
                    return p[2];
                } catch (NumberFormatException ignored) {
                }
            }
            return cookie;
        }
    }

    /** Room names travel as plain ASCII. */
    public static String cleanName(String name) {
        String s = name.trim().replaceAll("[^\\x20-\\x7e]", "").replaceAll("\\s+", " ");
        return s.length() > 64 ? s.substring(0, 64).trim() : s;
    }

    public static final class Message {
        public final String from;
        public final String text;

        Message(String from, String text) {
            this.from = from;
            this.text = text;
        }
    }

    public static byte[] encodeMessage(String text, Random rnd) {
        Object[] enc = AimText.encode(AimText.toHtml(text));
        int cs = (Integer) enc[0];
        byte[] body = (byte[]) enc[1];
        byte[] info = new Bytes.Writer().tlv(0x0001, body)
                .tlvStr(0x0002, cs == 2 ? "unicode-2-0" : "us-ascii")
                .tlvStr(0x0003, "en").toBytes();
        byte[] cookie = new byte[8];
        rnd.nextBytes(cookie);
        return new Bytes.Writer().bytes(cookie).u16(3).tlv(0x0001, new byte[0]).tlv(0x0005, info).toBytes();
    }

    public static Message parseMessage(byte[] data) {
        Bytes.Reader r = new Bytes.Reader(data);
        if (r.remaining() < 10) return null;
        r.bytes(8);
        r.u16();
        Bytes.Tlvs t = r.tlvs();
        Bytes.Tlv info = t.get(0x0005);
        if (info == null) return null;
        Bytes.Tlv sender = t.get(0x0003);
        String from = sender == null ? "" : Models.UserInfo.read(sender.reader()).screenName;
        Bytes.Tlvs it = info.reader().tlvs();
        Bytes.Tlv text = it.get(0x0001);
        if (text == null) return null;
        Bytes.Tlv cs = it.get(0x0002);
        String html = AimText.decode(AimText.charsetCode(cs == null ? "" : cs.str()), text.value);
        return new Message(from, AimText.toText(html));
    }

    // ------------------------------------------------------------------ invites

    public static final class Invite {
        public final String from;
        public final RoomInfo room;
        public final String message;
        public final byte[] cookie;

        Invite(String from, RoomInfo room, String message, byte[] cookie) {
            this.from = from;
            this.room = room;
            this.message = message;
            this.cookie = cookie;
        }
    }

    /** Reads a rendezvous payload (ICBM ch2 TLV 5). Null unless it's a chat invite. */
    public static Invite parseInvite(String from, byte[] rdv) {
        try {
            Bytes.Reader r = new Bytes.Reader(rdv);
            int type = r.u16();
            byte[] cookie = r.bytes(8);
            byte[] cap = r.bytes(16);
            if (type != 0 || !Bytes.hex(cap).equals(Bytes.hex(CAP_CHAT))) return null;
            Bytes.Tlvs t = r.tlvs();
            Bytes.Tlv ref = t.get(0x2711);
            if (ref == null) return null;
            RoomInfo room = RoomInfo.readRef(ref.reader());
            Bytes.Tlv msg = t.get(0x000c);
            Bytes.Tlv cs = t.get(0x000d);
            String text = msg == null ? ""
                    : AimText.toText(AimText.decode(AimText.charsetCode(cs == null ? "" : cs.str()), msg.value));
            return new Invite(from, room, text, cookie);
        } catch (RuntimeException e) {
            return null;
        }
    }

    public static byte[] encodeInvite(byte[] cookie, RoomInfo room, String message) {
        return new Bytes.Writer().u16(0).bytes(cookie).bytes(CAP_CHAT)
                .tlvU16(0x000a, 1)
                .tlv(0x000f, new byte[0])
                .tlvStr(0x000c, message)
                .tlvStr(0x000d, Bytes.isAscii(message) ? "us-ascii" : "utf-8")
                .tlvStr(0x000e, "en")
                .tlv(0x2711, room.ref())
                .toBytes();
    }

    public static byte[] encodeDecline(byte[] cookie) {
        return new Bytes.Writer().u16(1).bytes(cookie).bytes(CAP_CHAT).tlvU16(0x000b, 1).toBytes();
    }

    // ------------------------------------------------------------------ connection

    public interface Listener {
        /** [initial] is the list we got on joining. */
        void onMembers(Conn room, List<String> joined, List<String> left, boolean initial);

        void onMessage(Conn room, Message m);

        void onClosed(Conn room, String reason);
    }

    /** One open room: its own connection to the server's chat service. */
    public static final class Conn implements Flap.Listener {
        public volatile RoomInfo info;
        private final Flap flap;
        private final Listener listener;
        private final Map<String, String> members = new HashMap<String, String>();
        private boolean gotList;
        private final Random rnd = new Random();
        private volatile boolean closedSent;

        Conn(RoomInfo info, Flap flap, Listener listener) {
            this.info = info;
            this.flap = flap;
            this.listener = listener;
        }

        public boolean isOpen() {
            return !flap.isClosed();
        }

        /** Who's in the room, sorted. */
        public List<String> members() {
            List<String> out;
            synchronized (members) {
                out = new ArrayList<String>(members.values());
            }
            Collections.sort(out, new Comparator<String>() {
                public int compare(String a, String b) {
                    return a.toLowerCase().compareTo(b.toLowerCase());
                }
            });
            return out;
        }

        public void onSnac(Flap.Snac s) {
            if (s.family != 0x000e) return;
            Bytes.Reader r = s.reader();
            switch (s.subtype) {
                case 0x0002: {
                    RoomInfo n = RoomInfo.readFull(r);
                    if (!n.name.equals(info.name)) info = new RoomInfo(info.exchange, info.cookie, info.instance, n.name);
                    break;
                }
                case 0x0003: {
                    List<String> joined = new ArrayList<String>();
                    while (r.remaining() > 0) {
                        Models.UserInfo u = Models.UserInfo.read(r);
                        synchronized (members) {
                            members.put(Bytes.normalizeSn(u.screenName), u.screenName);
                        }
                        joined.add(u.screenName);
                    }
                    boolean initial = !gotList;
                    gotList = true;
                    listener.onMembers(this, joined, new ArrayList<String>(), initial);
                    break;
                }
                case 0x0004: {
                    List<String> left = new ArrayList<String>();
                    while (r.remaining() > 0) {
                        Models.UserInfo u = Models.UserInfo.read(r);
                        synchronized (members) {
                            members.remove(Bytes.normalizeSn(u.screenName));
                        }
                        left.add(u.screenName);
                    }
                    listener.onMembers(this, new ArrayList<String>(), left, false);
                    break;
                }
                case 0x0006: {
                    Message m = parseMessage(s.data);
                    if (m != null) listener.onMessage(this, m);
                    break;
                }
                default:
                    break;
            }
        }

        public void onFrame(int channel, byte[] data) {}

        public void onClosed(String reason) {
            synchronized (this) {
                if (closedSent) return;
                closedSent = true;
            }
            listener.onClosed(this, reason);
        }

        public void send(String text) throws IOException {
            flap.sendSnac(0x000e, 0x0005, encodeMessage(text, rnd));
        }

        public void leave() {
            flap.close();
        }

        public void kill() {
            flap.kill();
        }

        void ready(int[][] families) throws IOException {
            flap.setListener(this);
            Session.serviceReady(flap, families);
        }
    }
}
