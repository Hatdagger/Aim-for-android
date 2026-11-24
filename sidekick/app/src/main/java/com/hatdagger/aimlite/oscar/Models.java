package com.hatdagger.aimlite.oscar;

import java.util.ArrayList;
import java.util.List;

/** Small data types shared by the session and the app. */
public final class Models {
    private Models() {}

    public static final class UserInfo {
        public final String screenName;
        public final int warningLevel;
        public final int userClass;
        public final int idleMinutes;
        /** Buddy icon id (MD5 of the picture), if they have one. */
        public final byte[] iconHash;
        public final int iconFlags;
        /** Seconds since 1970 when they signed on (0 if not sent). */
        public final long onlineSince;
        /** True on the update that says they just signed on (not a status change). */
        public boolean justArrived;

        UserInfo(String sn, int warn, int cls, int idle, byte[] iconHash, int iconFlags, long onlineSince) {
            screenName = sn;
            warningLevel = warn;
            userClass = cls;
            idleMinutes = idle;
            this.iconHash = iconHash;
            this.iconFlags = iconFlags;
            this.onlineSince = onlineSince;
        }

        public boolean isAway() {
            return (userClass & 0x0020) != 0;
        }

        public static UserInfo read(Bytes.Reader r) {
            String sn = r.str8();
            int warn = r.u16();
            int count = r.u16();
            Bytes.Tlvs t = r.tlvs(count);
            Bytes.Tlv cls = t.get(0x01);
            int c = cls == null ? 0 : cls.u16();
            Bytes.Tlv status = t.get(0x06);
            if (status != null && (status.u32() & 0x0001) != 0) c |= 0x0020;
            Bytes.Tlv idle = t.get(0x04);
            byte[] hash = null;
            int flags = 0;
            Bytes.Tlv bart = t.get(0x1d);
            if (bart != null) {
                try {
                    Bytes.Reader br = bart.reader();
                    while (br.remaining() >= 4) {
                        int type = br.u16();
                        int f = br.u8();
                        int len = br.u8();
                        byte[] data = br.bytes(len);
                        if (type == 0x0001 && len > 0) {
                            hash = data;
                            flags = f;
                        }
                    }
                } catch (RuntimeException ignored) {
                }
            }
            Bytes.Tlv since = t.get(0x03);
            return new UserInfo(sn, warn, c, idle == null ? 0 : idle.u16(), hash, flags,
                    since == null ? 0 : since.u32());
        }
    }

    public static final class FeedbagItem {
        public static final int BUDDY = 0, GROUP = 1, PERMIT = 2, DENY = 3, PDINFO = 4;

        public String name;
        public final int groupId;
        public final int itemId;
        public final int classId;
        public List<Bytes.Tlv> attrs;

        public FeedbagItem(String name, int groupId, int itemId, int classId, List<Bytes.Tlv> attrs) {
            this.name = name;
            this.groupId = groupId;
            this.itemId = itemId;
            this.classId = classId;
            this.attrs = attrs;
        }

        /** Child ids of a group (TLV 0xC8), in display order. */
        public List<Integer> order() {
            List<Integer> out = new ArrayList<Integer>();
            for (Bytes.Tlv t : attrs) {
                if (t.type == 0xc8) {
                    Bytes.Reader r = t.reader();
                    while (r.remaining() >= 2) out.add(r.u16());
                }
            }
            return out;
        }

        public void setOrder(List<Integer> ids) {
            Bytes.Writer w = new Bytes.Writer();
            for (int id : ids) w.u16(id);
            List<Bytes.Tlv> n = new ArrayList<Bytes.Tlv>();
            for (Bytes.Tlv t : attrs) if (t.type != 0xc8) n.add(t);
            n.add(new Bytes.Tlv(0xc8, w.toBytes()));
            attrs = n;
        }

        public static FeedbagItem read(Bytes.Reader r) {
            int nl = r.u16();
            String name = Bytes.utf8(r.bytes(nl));
            int gid = r.u16();
            int iid = r.u16();
            int cls = r.u16();
            int al = r.u16();
            Bytes.Reader ar = new Bytes.Reader(r.d, r.pos, r.pos + al);
            r.pos += al;
            return new FeedbagItem(name, gid, iid, cls, new ArrayList<Bytes.Tlv>(ar.tlvs().items));
        }

        public void write(Bytes.Writer w) {
            byte[] n = Bytes.utf8(name);
            w.u16(n.length).bytes(n).u16(groupId).u16(itemId).u16(classId);
            Bytes.Writer a = new Bytes.Writer();
            for (Bytes.Tlv t : attrs) a.tlv(t.type, t.value);
            byte[] ab = a.toBytes();
            w.u16(ab.length).bytes(ab);
        }
    }

    public static final class BuddyGroup {
        public final String name;
        public final int groupId;
        public final List<String> buddies;

        BuddyGroup(String name, int groupId, List<String> buddies) {
            this.name = name;
            this.groupId = groupId;
            this.buddies = buddies;
        }
    }

    public enum SendResult { DELIVERED, OFFLINE, RATE_LIMITED, FAILED }

    public enum EndKind { NETWORK, BAD_PASSWORD, ELSEWHERE, RATE_LIMITED, SERVER_ERROR, SIGNED_OFF }

    /** Why a sign-on failed or a session ended. */
    public static final class Disconnect extends java.io.IOException {
        public final EndKind kind;

        public Disconnect(EndKind kind, String message) {
            super(message);
            this.kind = kind;
        }
    }
}
