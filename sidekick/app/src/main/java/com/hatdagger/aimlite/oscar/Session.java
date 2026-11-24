package com.hatdagger.aimlite.oscar;

import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;

import com.hatdagger.aimlite.oscar.Models.BuddyGroup;
import com.hatdagger.aimlite.oscar.Models.Disconnect;
import com.hatdagger.aimlite.oscar.Models.EndKind;
import com.hatdagger.aimlite.oscar.Models.FeedbagItem;
import com.hatdagger.aimlite.oscar.Models.SendResult;
import com.hatdagger.aimlite.oscar.Models.UserInfo;

/**
 * One signed-on OSCAR session (the same protocol the main app speaks), written
 * for Android 2.2: blocking calls, so run them off the UI thread.
 */
public final class Session {

    /** What the server tells us without being asked. Called on a network thread. */
    public interface Events {
        void onBuddyListChanged();

        void onBuddyArrived(UserInfo info);

        void onBuddyDeparted(String screenName);

        void onMessage(String from, String text, boolean autoResponse);

        void onTyping(String from, int state);

        void onRoomInvite(Rooms.Invite invite);

        void onEnded(Disconnect why);
    }

    private static final String CLIENT_ID = "AOL Instant Messenger, version 5.1.3036/WIN32";
    private static final String MD5_SALT = "AOL Instant Messenger (SM)";
    private static final int[][] BOS_FAMILIES = {{1, 4}, {2, 1}, {3, 1}, {4, 1}, {9, 1}, {0x13, 4}};

    private static final byte[][] CAPS = {
            Bytes.unhex("0946134e4c7f11d18222444553540000"), // unicode messages
            Rooms.CAP_CHAT,
    };

    public final String host;
    public final int port;
    public final String screenName;
    private final String password;
    private final Events events;
    private final Random rnd = new Random();

    private volatile Flap bos;
    private Flap nav;
    private final Object navLock = new Object();
    private final Set<Rooms.Conn> rooms = new HashSet<Rooms.Conn>();
    private volatile boolean ended;
    private volatile boolean signingOff;
    public volatile String formattedName;

    /** Buddy list items (guarded by this). */
    private final List<FeedbagItem> feedbag = new ArrayList<FeedbagItem>();
    /** Who's online, by normalised name (guarded by this). */
    private final Map<String, UserInfo> online = new HashMap<String, UserInfo>();

    public Session(String host, int port, String screenName, String password, Events events) {
        this.host = host;
        this.port = port;
        this.screenName = screenName;
        this.password = password;
        this.events = events;
        this.formattedName = screenName;
    }

    /** "host:port" or "host" (port 5190). */
    public static String[] parseServer(String s) {
        String t = s.trim().replaceFirst("^[a-zA-Z]+://", "");
        int i = t.lastIndexOf(':');
        if (i > 0 && t.indexOf(':') == i) return new String[] {t.substring(0, i), t.substring(i + 1)};
        return new String[] {t, "5190"};
    }

    public boolean isOnline() {
        Flap b = bos;
        return b != null && !b.isClosed() && !ended;
    }

    // ---------------------------------------------------------------- sign on

    public void signOn(String profileText, String awayText) throws IOException {
        Object[] auth = authenticate();
        String[] addr = (String[]) auth[0];
        Opened o = connectService(addr[0], Integer.parseInt(addr[1]), (byte[]) auth[1]);
        Flap b = o.flap;
        bos = b;
        try {
            setupBos(o, profileText, awayText);
        } catch (IOException e) {
            b.kill();
            throw e;
        }
    }

    private Object[] authenticate() throws IOException {
        Flap auth = Flap.connect(host, port);
        try {
            // Speak first (the AIM Server app routes connections by their first
            // byte), then take the greeting.
            Flap.Waiter greet = auth.expectFrame(1);
            auth.send(1, new Bytes.Writer().u32(1).toBytes());
            try {
                greet.awaitFrame(10000);
            } catch (Flap.TimeoutIOException ignored) {
                // some servers never greet
            }
            byte[] chal = new Bytes.Writer().tlvStr(0x0001, screenName).tlv(0x004b, new byte[0])
                    .tlv(0x005a, new byte[0]).toBytes();
            Flap.Waiter kw = auth.expect(-1, 0x17, 0x07, 0x17, 0x03, 0x17, 0x01);
            auth.sendSnac(0x17, 0x06, chal);
            Flap.Snac keyReply = kw.await(20000);
            if (keyReply.subtype != 0x07) throw loginError(keyReply);
            Bytes.Reader kr = keyReply.reader();
            byte[] key = kr.bytes(kr.u16());

            byte[] pwMd5 = md5(Bytes.utf8(password));
            byte[] salt = Bytes.utf8(MD5_SALT);
            byte[] all = new byte[key.length + pwMd5.length + salt.length];
            System.arraycopy(key, 0, all, 0, key.length);
            System.arraycopy(pwMd5, 0, all, key.length, pwMd5.length);
            System.arraycopy(salt, 0, all, key.length + pwMd5.length, salt.length);
            byte[] hash = md5(all);

            byte[] login = new Bytes.Writer()
                    .tlvStr(0x0001, screenName)
                    .tlvStr(0x0003, CLIENT_ID)
                    .tlv(0x0025, hash)
                    .tlv(0x004c, new byte[0])
                    .tlvU16(0x0016, 0x0109)
                    .tlvU16(0x0017, 5)
                    .tlvU16(0x0018, 1)
                    .tlvU16(0x0019, 0)
                    .tlvU16(0x001a, 3036)
                    .tlvU32(0x0014, 0xd2)
                    .tlvStr(0x000f, "en")
                    .tlvStr(0x000e, "us")
                    .tlvU8(0x004a, 1)
                    .toBytes();
            Flap.Waiter lw = auth.expect(-1, 0x17, 0x03, 0x17, 0x01);
            auth.sendSnac(0x17, 0x02, login);
            Flap.Snac reply = lw.await(20000);
            if (reply.subtype != 0x03) throw loginError(reply);
            Bytes.Tlvs t = reply.reader().tlvs();
            Bytes.Tlv err = t.get(0x0008);
            if (err != null) throw authError(err.u16());
            Bytes.Tlv a = t.get(0x0005);
            Bytes.Tlv c = t.get(0x0006);
            if (a == null || c == null) throw new Disconnect(EndKind.SERVER_ERROR, "Server did not send a BOS address");
            Bytes.Tlv sn = t.get(0x0001);
            if (sn != null) formattedName = sn.str();
            return new Object[] {redirect(a.str()), c.value};
        } finally {
            auth.close();
        }
    }

    private static byte[] md5(byte[] b) {
        try {
            return MessageDigest.getInstance("MD5").digest(b);
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }

    /** If the server sends us to a loopback address, use the address the user typed. */
    private String[] redirect(String addr) {
        String[] r = parseServer(addr);
        if (r[1].length() == 0) r[1] = String.valueOf(port);
        if (isLoop(r[0]) && !isLoop(host)) r[0] = host;
        return r;
    }

    private static boolean isLoop(String h) {
        return h.equals("localhost") || h.startsWith("127.") || h.equals("0.0.0.0") || h.equals("::1") || h.equals("::");
    }

    private Disconnect loginError(Flap.Snac s) {
        if (s.subtype == 0x01) {
            int code = s.data.length >= 2 ? ((s.data[0] & 0xff) << 8) | (s.data[1] & 0xff) : 0;
            return new Disconnect(EndKind.SERVER_ERROR, "Sign-on error 0x" + Integer.toHexString(code));
        }
        Bytes.Tlv c = s.reader().tlvs().get(0x0008);
        return authError(c == null ? 0 : c.u16());
    }

    private Disconnect authError(int code) {
        switch (code) {
            case 0x01: case 0x04: case 0x05:
                return new Disconnect(EndKind.BAD_PASSWORD, "Incorrect screen name or password.");
            case 0x11:
                return new Disconnect(EndKind.BAD_PASSWORD, "This account is suspended.");
            case 0x18: case 0x1d:
                return new Disconnect(EndKind.RATE_LIMITED, "Connecting too frequently. Waiting before trying again.");
            default:
                return new Disconnect(EndKind.SERVER_ERROR, "Sign-on failed (error 0x" + Integer.toHexString(code) + ").");
        }
    }

    /** A just-opened service connection and the "host online" reply we're waiting for. */
    private static final class Opened {
        final Flap flap;
        final Flap.Waiter online;

        Opened(Flap f, Flap.Waiter o) {
            flap = f;
            online = o;
        }
    }

    private Opened connectService(String h, int p, byte[] cookie) throws IOException {
        Flap c;
        try {
            c = Flap.connect(h, p);
        } catch (IOException e) {
            if (h.equals(host)) throw e;
            c = Flap.connect(host, p);
        }
        Flap.Waiter greet = c.expectFrame(1);
        // Listen for "host online" before saying hello so it can't slip past.
        Flap.Waiter online = c.expect(-1, 0x01, 0x03);
        c.send(1, new Bytes.Writer().u32(1).tlv(0x0006, cookie).toBytes());
        try {
            greet.awaitFrame(10000);
        } catch (Flap.TimeoutIOException ignored) {
        }
        return new Opened(c, online);
    }

    /** Host online -> versions -> rate limits. */
    private static void negotiate(Opened o, int[][] families) throws IOException {
        Flap c = o.flap;
        o.online.await(20000);
        Bytes.Writer v = new Bytes.Writer();
        for (int[] f : families) v.u16(f[0]).u16(f[1]);
        Flap.Waiter vw = c.expect(-1, 0x01, 0x18);
        c.sendSnac(0x01, 0x17, v.toBytes());
        vw.await(20000);
        Flap.Waiter rw = c.expect(-1, 0x01, 0x07);
        c.sendSnac(0x01, 0x06, new byte[0]);
        Flap.Snac rates = rw.await(20000);
        Bytes.Reader rr = rates.reader();
        int n = rr.remaining() >= 2 ? rr.u16() : 0;
        Bytes.Writer ack = new Bytes.Writer();
        for (int i = 1; i <= n; i++) ack.u16(i);
        c.sendSnac(0x01, 0x08, ack.toBytes());
    }

    static void serviceReady(Flap c, int[][] families) throws IOException {
        Bytes.Writer ready = new Bytes.Writer();
        for (int[] f : families) ready.u16(f[0]).u16(f[1]).u16(0x0110).u16(0x08e5);
        c.sendSnac(0x01, 0x02, ready.toBytes());
        c.startKeepAlive();
    }

    private void setupBos(Opened o, String profileText, String awayText) throws IOException {
        final Flap b = o.flap;
        Flap.Waiter online = o.online;
        b.setListener(new Flap.Listener() {
            public void onSnac(Flap.Snac s) {
                dispatch(s);
            }

            public void onFrame(int channel, byte[] data) {
                if (channel == 4) onSignOffFrame(data);
            }

            public void onClosed(String reason) {
                end(signingOff ? new Disconnect(EndKind.SIGNED_OFF, "Signed off")
                        : new Disconnect(EndKind.NETWORK, "Connection lost (" + reason + ")"));
            }
        });
        online.await(20000);
        Bytes.Writer v = new Bytes.Writer();
        for (int[] f : BOS_FAMILIES) v.u16(f[0]).u16(f[1]);
        Flap.Waiter vw = b.expect(-1, 0x01, 0x18);
        b.sendSnac(0x01, 0x17, v.toBytes());
        vw.await(20000);
        Flap.Waiter rw = b.expect(-1, 0x01, 0x07);
        b.sendSnac(0x01, 0x06, new byte[0]);
        Bytes.Reader rr = rw.await(20000).reader();
        int n = rr.remaining() >= 2 ? rr.u16() : 0;
        Bytes.Writer ack = new Bytes.Writer();
        for (int i = 1; i <= n; i++) ack.u16(i);
        b.sendSnac(0x01, 0x08, ack.toBytes());

        b.sendSnac(0x01, 0x0e, new byte[0]); // self info
        b.sendSnac(0x13, 0x02, new byte[0]);
        loadFeedbag(b);
        b.sendSnac(0x13, 0x07, new byte[0]); // activate

        b.sendSnac(0x02, 0x02, new byte[0]);
        b.sendSnac(0x02, 0x04, locateInfo(profileText, awayText));
        b.sendSnac(0x03, 0x02, new byte[0]);
        b.sendSnac(0x04, 0x04, new byte[0]);
        b.sendSnac(0x04, 0x02, new Bytes.Writer().u16(0).u32(0x0b).u16(8000).u16(999).u16(999).u32(0).toBytes());
        b.sendSnac(0x09, 0x02, new byte[0]);
        Bytes.Writer ready = new Bytes.Writer();
        for (int[] f : BOS_FAMILIES) ready.u16(f[0]).u16(f[1]).u16(0x0110).u16(0x08e5);
        b.sendSnac(0x01, 0x02, ready.toBytes());
        b.startKeepAlive();
    }

    private void loadFeedbag(Flap b) throws IOException {
        synchronized (this) {
            feedbag.clear();
        }
        Flap.Waiter w = b.expect(-1, 0x13, 0x06, 0x13, 0x0f);
        b.sendSnac(0x13, 0x04, new byte[0]);
        Flap.Snac s = w.await(20000);
        while (s.subtype != 0x0f) {
            Bytes.Reader r = s.reader();
            r.u8();
            int count = r.u16();
            synchronized (this) {
                for (int i = 0; i < count; i++) feedbag.add(FeedbagItem.read(r));
            }
            if (!s.moreFollows()) break;
            w = b.expect(-1, 0x13, 0x06);
            s = w.await(20000);
        }
        events.onBuddyListChanged();
    }

    private static byte[] locateInfo(String profileText, String awayText) {
        Bytes.Writer caps = new Bytes.Writer();
        for (byte[] c : CAPS) caps.bytes(c);
        return new Bytes.Writer()
                .tlvStr(0x0001, "text/aolrtf; charset=\"us-ascii\"")
                .tlvStr(0x0002, profileText == null ? "" : AimText.toHtml(profileText))
                .tlvStr(0x0003, "text/aolrtf; charset=\"us-ascii\"")
                .tlvStr(0x0004, awayText == null || awayText.length() == 0 ? "" : AimText.toHtml(awayText))
                .tlv(0x0005, caps.toBytes())
                .toBytes();
    }

    // ---------------------------------------------------------------- incoming

    private void dispatch(Flap.Snac s) {
        Bytes.Reader r = s.reader();
        if (s.family == 0x03 && s.subtype == 0x0b) {
            while (r.remaining() > 0) {
                UserInfo u = UserInfo.read(r);
                synchronized (this) {
                    online.put(Bytes.normalizeSn(u.screenName), u);
                }
                events.onBuddyArrived(u);
            }
        } else if (s.family == 0x03 && s.subtype == 0x0c) {
            while (r.remaining() > 0) {
                UserInfo u = UserInfo.read(r);
                synchronized (this) {
                    online.remove(Bytes.normalizeSn(u.screenName));
                }
                events.onBuddyDeparted(u.screenName);
            }
        } else if (s.family == 0x04 && s.subtype == 0x07) {
            onIcbm(r);
        } else if (s.family == 0x04 && s.subtype == 0x14) {
            r.bytes(8);
            r.u16();
            String sn = r.str8();
            events.onTyping(sn, r.u16());
        } else if (s.family == 0x01 && s.subtype == 0x0f) {
            formattedName = UserInfo.read(r).screenName;
        } else if (s.family == 0x13 && (s.subtype == 0x08 || s.subtype == 0x09 || s.subtype == 0x0a)) {
            List<FeedbagItem> items = new ArrayList<FeedbagItem>();
            while (r.remaining() > 0) items.add(FeedbagItem.read(r));
            synchronized (this) {
                for (FeedbagItem it : items) {
                    removeMatching(it);
                    if (s.subtype != 0x0a) feedbag.add(it);
                }
            }
            events.onBuddyListChanged();
        }
    }

    private void removeMatching(FeedbagItem it) {
        for (int i = feedbag.size() - 1; i >= 0; i--) {
            FeedbagItem e = feedbag.get(i);
            if (e.groupId == it.groupId && e.itemId == it.itemId && e.classId == it.classId) feedbag.remove(i);
        }
    }

    private void onIcbm(Bytes.Reader r) {
        r.bytes(8);
        int channel = r.u16();
        UserInfo info = UserInfo.read(r);
        Bytes.Tlvs tlvs = r.tlvs();
        if (channel == 2) {
            Bytes.Tlv data = tlvs.get(0x0005);
            if (data == null) return;
            Rooms.Invite inv = Rooms.parseInvite(info.screenName, data.value);
            if (inv != null) events.onRoomInvite(inv);
            return;
        }
        if (channel != 1) return;
        Bytes.Tlv msg = tlvs.get(0x0002);
        if (msg == null) return;
        Bytes.Reader mr = msg.reader();
        StringBuilder html = new StringBuilder();
        while (mr.remaining() >= 4) {
            int id = mr.u8();
            mr.u8();
            int len = mr.u16();
            byte[] frag = mr.bytes(Math.min(len, mr.remaining()));
            if (id == 0x01 && frag.length >= 4) {
                Bytes.Reader fr = new Bytes.Reader(frag);
                int cs = fr.u16();
                fr.u16();
                html.append(AimText.decode(cs, fr.rest()));
            }
        }
        events.onMessage(info.screenName, AimText.toText(html.toString()), tlvs.has(0x0004));
    }

    private void onSignOffFrame(byte[] data) {
        Bytes.Tlv code = new Bytes.Reader(data).tlvs().get(0x0009);
        if (code != null && code.u16() == 0x0001) {
            end(new Disconnect(EndKind.ELSEWHERE,
                    "You were signed off because this screen name signed on somewhere else."));
        } else if (!signingOff) {
            end(new Disconnect(EndKind.NETWORK, "Server ended the session"));
        }
        Flap b = bos;
        if (b != null) b.kill();
    }

    private void end(Disconnect d) {
        synchronized (this) {
            if (ended) return;
            ended = true;
        }
        killServices();
        events.onEnded(d);
    }

    private void killServices() {
        List<Rooms.Conn> rs;
        synchronized (rooms) {
            rs = new ArrayList<Rooms.Conn>(rooms);
            rooms.clear();
        }
        for (Rooms.Conn c : rs) c.kill();
        synchronized (navLock) {
            if (nav != null) nav.kill();
            nav = null;
        }
    }

    // ---------------------------------------------------------------- buddy list

    public synchronized List<BuddyGroup> groups() {
        FeedbagItem root = null;
        List<FeedbagItem> gs = new ArrayList<FeedbagItem>();
        for (FeedbagItem i : feedbag) {
            if (i.classId != FeedbagItem.GROUP) continue;
            if (i.groupId == 0) root = i;
            else gs.add(i);
        }
        final List<Integer> order = root == null ? new ArrayList<Integer>() : root.order();
        Collections.sort(gs, new Comparator<FeedbagItem>() {
            public int compare(FeedbagItem a, FeedbagItem b) {
                return rank(order, a.groupId) - rank(order, b.groupId);
            }
        });
        List<BuddyGroup> out = new ArrayList<BuddyGroup>();
        for (FeedbagItem g : gs) {
            List<FeedbagItem> members = new ArrayList<FeedbagItem>();
            for (FeedbagItem i : feedbag) if (i.classId == FeedbagItem.BUDDY && i.groupId == g.groupId) members.add(i);
            final List<Integer> ord = g.order();
            Collections.sort(members, new Comparator<FeedbagItem>() {
                public int compare(FeedbagItem a, FeedbagItem b) {
                    return rank(ord, a.itemId) - rank(ord, b.itemId);
                }
            });
            List<String> names = new ArrayList<String>();
            for (FeedbagItem m : members) names.add(m.name);
            out.add(new BuddyGroup(g.name, g.groupId, names));
        }
        return out;
    }

    private static int rank(List<Integer> order, int id) {
        int i = order.indexOf(id);
        return i < 0 ? 9999 : i;
    }

    public synchronized UserInfo onlineInfo(String sn) {
        return online.get(Bytes.normalizeSn(sn));
    }

    public synchronized boolean isBuddy(String sn) {
        String k = Bytes.normalizeSn(sn);
        for (FeedbagItem i : feedbag) if (i.classId == FeedbagItem.BUDDY && Bytes.normalizeSn(i.name).equals(k)) return true;
        return false;
    }

    private synchronized int freeId(int groupId, int classFilter) {
        while (true) {
            int id = 1 + rnd.nextInt(0x7ffe);
            boolean used = false;
            for (FeedbagItem i : feedbag) {
                if (classFilter >= 0 ? (i.classId == classFilter && i.groupId == id)
                        : (i.groupId == groupId && i.itemId == id)) {
                    used = true;
                    break;
                }
            }
            if (!used) return id;
        }
    }

    private static byte[] items(FeedbagItem... list) {
        Bytes.Writer w = new Bytes.Writer();
        for (FeedbagItem i : list) i.write(w);
        return w.toBytes();
    }

    /** One buddy list edit: start, the changes, end, then the server's answer. */
    private void feedbagEdit(byte[][] snacs, int[] subtypes) throws IOException {
        Flap b = requireBos();
        b.sendSnac(0x13, 0x11, new byte[0]);
        Flap.Waiter ackW = b.expect(-1, 0x13, 0x0e);
        for (int i = 0; i < snacs.length; i++) b.sendSnac(0x13, subtypes[i], snacs[i]);
        b.sendSnac(0x13, 0x12, new byte[0]);
        Bytes.Reader r = ackW.await(20000).reader();
        while (r.remaining() >= 2) {
            int code = r.u16();
            if (code != 0) throw new IOException("Buddy list change rejected (code " + code + ")");
        }
    }

    public void addBuddy(String sn, String groupName) throws IOException {
        FeedbagItem group = null;
        synchronized (this) {
            for (FeedbagItem i : feedbag) {
                if (i.classId == FeedbagItem.GROUP && i.groupId != 0 && i.name.equalsIgnoreCase(groupName)) group = i;
            }
        }
        if (group == null) {
            addGroup(groupName);
            synchronized (this) {
                for (FeedbagItem i : feedbag) {
                    if (i.classId == FeedbagItem.GROUP && i.groupId != 0 && i.name.equals(groupName)) group = i;
                }
            }
            if (group == null) throw new IOException("Couldn't make the group " + groupName);
        }
        int iid = freeId(group.groupId, -1);
        FeedbagItem buddy = new FeedbagItem(sn, group.groupId, iid, FeedbagItem.BUDDY, new ArrayList<Bytes.Tlv>());
        List<Integer> ord = group.order();
        ord.add(iid);
        group.setOrder(ord);
        feedbagEdit(new byte[][] {items(buddy), items(group)}, new int[] {0x08, 0x09});
        synchronized (this) {
            feedbag.add(buddy);
        }
        events.onBuddyListChanged();
    }

    public void addGroup(String name) throws IOException {
        int gid = freeId(0, FeedbagItem.GROUP);
        List<Bytes.Tlv> attrs = new ArrayList<Bytes.Tlv>();
        attrs.add(new Bytes.Tlv(0xc8, new byte[0]));
        FeedbagItem group = new FeedbagItem(name, gid, 0, FeedbagItem.GROUP, attrs);
        FeedbagItem root = null;
        synchronized (this) {
            for (FeedbagItem i : feedbag) if (i.classId == FeedbagItem.GROUP && i.groupId == 0) root = i;
        }
        boolean createRoot = root == null;
        if (root == null) root = new FeedbagItem("", 0, 0, FeedbagItem.GROUP, new ArrayList<Bytes.Tlv>());
        List<Integer> ord = root.order();
        ord.add(gid);
        root.setOrder(ord);
        feedbagEdit(new byte[][] {items(group), items(root)}, new int[] {0x08, createRoot ? 0x08 : 0x09});
        synchronized (this) {
            feedbag.add(group);
            if (createRoot) feedbag.add(root);
        }
    }

    public void removeBuddy(String sn) throws IOException {
        String k = Bytes.normalizeSn(sn);
        List<FeedbagItem> found = new ArrayList<FeedbagItem>();
        synchronized (this) {
            for (FeedbagItem i : feedbag) {
                if (i.classId == FeedbagItem.BUDDY && Bytes.normalizeSn(i.name).equals(k)) found.add(i);
            }
        }
        if (found.isEmpty()) return;
        List<byte[]> snacs = new ArrayList<byte[]>();
        List<Integer> subs = new ArrayList<Integer>();
        snacs.add(items(found.toArray(new FeedbagItem[0])));
        subs.add(0x0a);
        for (FeedbagItem it : found) {
            FeedbagItem g = null;
            synchronized (this) {
                for (FeedbagItem i : feedbag) if (i.classId == FeedbagItem.GROUP && i.groupId == it.groupId) g = i;
            }
            if (g != null) {
                List<Integer> ord = g.order();
                ord.remove(Integer.valueOf(it.itemId));
                g.setOrder(ord);
                snacs.add(items(g));
                subs.add(0x09);
            }
        }
        int[] subArr = new int[subs.size()];
        for (int i = 0; i < subArr.length; i++) subArr[i] = subs.get(i);
        feedbagEdit(snacs.toArray(new byte[0][]), subArr);
        synchronized (this) {
            feedbag.removeAll(found);
        }
        events.onBuddyListChanged();
    }

    // ---------------------------------------------------------------- messaging

    private Flap requireBos() throws IOException {
        Flap b = bos;
        if (b == null || b.isClosed()) throw new Flap.ConnectionClosed("not signed on");
        return b;
    }

    public SendResult sendIm(String to, String text, boolean autoResponse) throws IOException {
        Flap b = requireBos();
        byte[] cookie = new byte[8];
        rnd.nextBytes(cookie);
        Object[] enc = AimText.encode(AimText.toHtml(text));
        byte[] body = (byte[]) enc[1];
        byte[] frags = new Bytes.Writer()
                .u8(0x05).u8(0x01).u16(1).u8(0x01)
                .u8(0x01).u8(0x01).u16(body.length + 4).u16((Integer) enc[0]).u16(0).bytes(body)
                .toBytes();
        Bytes.Writer w = new Bytes.Writer().bytes(cookie).u16(1).str8(to).tlv(0x0002, frags);
        if (autoResponse) {
            w.tlv(0x0004, new byte[0]);
            b.sendSnac(0x04, 0x06, w.toBytes());
            return SendResult.DELIVERED;
        }
        w.tlv(0x0003, new byte[0]);
        return sendAndCheck(b, w.toBytes());
    }

    private SendResult sendAndCheck(Flap b, byte[] body) throws IOException {
        long id = b.nextReqId();
        Flap.Waiter w = b.expect(id, 0x04, 0x0c, 0x04, 0x01);
        b.sendSnac(0x04, 0x06, body, id);
        try {
            Flap.Snac reply = w.await(15000);
            if (reply.subtype == 0x0c) return SendResult.DELIVERED;
            int code = reply.data.length >= 2 ? ((reply.data[0] & 0xff) << 8) | (reply.data[1] & 0xff) : 0;
            if (code == 0x04) return SendResult.OFFLINE;
            if (code == 0x02 || code == 0x03) return SendResult.RATE_LIMITED;
            return SendResult.FAILED;
        } catch (Flap.TimeoutIOException e) {
            return isOnline() ? SendResult.DELIVERED : SendResult.FAILED;
        } catch (Flap.ConnectionClosed e) {
            return SendResult.FAILED;
        }
    }

    private SendResult sendRendezvous(String to, byte[] cookie, byte[] data) throws IOException {
        Flap b = requireBos();
        byte[] body = new Bytes.Writer().bytes(cookie).u16(2).str8(to).tlv(0x0005, data).tlv(0x0003, new byte[0])
                .toBytes();
        return sendAndCheck(b, body);
    }

    public void sendTyping(String to, int state) {
        Flap b = bos;
        if (b == null || b.isClosed()) return;
        try {
            b.sendSnac(0x04, 0x14, new Bytes.Writer().bytes(new byte[8]).u16(1).str8(to).u16(state).toBytes());
        } catch (IOException ignored) {
        }
    }

    /** Profile and away message; empty away = back. */
    public void setLocate(String profileText, String awayText) throws IOException {
        requireBos().sendSnac(0x02, 0x04, locateInfo(profileText, awayText));
    }

    // ---------------------------------------------------------------- services / chat rooms

    /** Asks the main connection for another service and does its handshake. */
    private Flap openService(int family, int[][] families, byte[] roomRef) throws IOException {
        Flap b = requireBos();
        long id = b.nextReqId();
        Flap.Waiter w = b.expect(id, 0x01, 0x05, 0x01, 0x01);
        Bytes.Writer req = new Bytes.Writer().u16(family);
        if (roomRef != null) req.tlv(0x0001, roomRef);
        b.sendSnac(0x01, 0x04, req.toBytes(), id);
        Flap.Snac s = w.await(20000);
        if (s.subtype != 0x05) throw new IOException("unavailable");
        Bytes.Tlvs t = s.reader().tlvs();
        Bytes.Tlv a = t.get(0x0005), c = t.get(0x0006);
        if (a == null || c == null) throw new IOException("unavailable");
        String[] addr = redirect(a.str());
        Opened o = connectService(addr[0], Integer.parseInt(addr[1]), c.value);
        Flap f = o.flap;
        try {
            negotiate(o, families);
        } catch (IOException e) {
            f.kill();
            throw e;
        }
        return f;
    }

    private static final int[][] NAV_FAMILIES = {{1, 4}, {0x0d, 1}};
    private static final int[][] CHAT_FAMILIES = {{1, 4}, {0x0e, 1}};

    private Flap navConn() throws IOException {
        synchronized (navLock) {
            if (nav != null && !nav.isClosed()) return nav;
            Flap f;
            try {
                f = openService(0x0d, NAV_FAMILIES, null);
            } catch (Flap.ConnectionClosed e) {
                throw e;
            } catch (IOException e) {
                throw new IOException("This server doesn't have chat rooms.");
            }
            serviceReady(f, NAV_FAMILIES);
            nav = f;
            return f;
        }
    }

    /** Finds the room called [name], making it if nobody has. */
    public Rooms.RoomInfo findOrCreateRoom(String name) throws IOException {
        Flap c = navConn();
        long id = c.nextReqId();
        Flap.Waiter w = c.expect(id, 0x0d, 0x09, 0x0d, 0x01);
        byte[] body = new Bytes.Writer().u16(Rooms.PRIVATE_EXCHANGE).str8("create").u16(0xffff).u8(1).u16(3)
                .tlvStr(0x00d3, name).tlvStr(0x00d6, "us-ascii").tlvStr(0x00d7, "en").toBytes();
        c.sendSnac(0x0d, 0x08, body, id);
        Flap.Snac s = w.await(20000);
        Bytes.Tlv info = s.subtype == 0x09 ? s.reader().tlvs().get(0x0004) : null;
        if (info == null) throw new IOException("The server couldn't open the room \"" + name + "\".");
        return Rooms.RoomInfo.readFull(info.reader());
    }

    /** Goes into [room]; everything that happens there goes to [listener]. */
    public Rooms.Conn joinRoom(Rooms.RoomInfo room, final Rooms.Listener listener) throws IOException {
        Flap f;
        try {
            f = openService(0x0e, CHAT_FAMILIES, room.ref());
        } catch (Flap.ConnectionClosed e) {
            throw e;
        } catch (IOException e) {
            throw new IOException("That room is gone or the server won't let you in.");
        }
        final Rooms.Conn[] holder = new Rooms.Conn[1];
        Rooms.Conn conn = new Rooms.Conn(room, f, new Rooms.Listener() {
            public void onMembers(Rooms.Conn r, List<String> joined, List<String> left, boolean initial) {
                listener.onMembers(r, joined, left, initial);
            }

            public void onMessage(Rooms.Conn r, Rooms.Message m) {
                listener.onMessage(r, m);
            }

            public void onClosed(Rooms.Conn r, String reason) {
                synchronized (rooms) {
                    rooms.remove(holder[0]);
                }
                listener.onClosed(r, reason);
            }
        });
        holder[0] = conn;
        synchronized (rooms) {
            if (ended) {
                f.kill();
                throw new Flap.ConnectionClosed("signed off");
            }
            rooms.add(conn);
        }
        conn.ready(CHAT_FAMILIES);
        return conn;
    }

    public SendResult sendRoomInvite(String to, Rooms.RoomInfo room, String message) throws IOException {
        byte[] cookie = new byte[8];
        rnd.nextBytes(cookie);
        return sendRendezvous(to, cookie, Rooms.encodeInvite(cookie, room, message));
    }

    public void declineRoomInvite(Rooms.Invite inv) throws IOException {
        sendRendezvous(inv.from, inv.cookie, Rooms.encodeDecline(inv.cookie));
    }

    // ---------------------------------------------------------------- sign off

    public void signOff() {
        signingOff = true;
        List<Rooms.Conn> rs;
        synchronized (rooms) {
            rs = new ArrayList<Rooms.Conn>(rooms);
        }
        for (Rooms.Conn c : rs) c.leave();
        synchronized (navLock) {
            if (nav != null) nav.close();
        }
        Flap b = bos;
        if (b != null) b.close();
        end(new Disconnect(EndKind.SIGNED_OFF, "Signed off"));
    }

    /** Drops every connection without signing off (tests / simulated loss). */
    public void debugDrop() {
        killServices();
        Flap b = bos;
        if (b != null) b.kill();
    }
}
