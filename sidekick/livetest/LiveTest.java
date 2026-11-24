import com.hatdagger.aimlite.oscar.Bytes;
import com.hatdagger.aimlite.oscar.Client;
import com.hatdagger.aimlite.oscar.Models;
import com.hatdagger.aimlite.oscar.Rooms;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * End-to-end check of the Sidekick app's AIM code against a running Open
 * OSCAR Server. Usage: java LiveTest host:port (accounts alice, bob, carol with
 * password "password1" must exist). Exits non-zero on the first failure.
 */
public final class LiveTest {
    static String host;
    static int port;

    /** Records everything a client hears, for the test to wait on. */
    static final class Probe implements Client.Listener {
        final String name;
        final BlockingQueue<Object[]> q = new LinkedBlockingQueue<Object[]>();

        Probe(String n) {
            name = n;
        }

        void put(Object... e) {
            q.add(e);
        }

        public void onState(Client.State s, String m) { put("state", s, m); }
        public void onBuddyListChanged() { put("list"); }
        public void onBuddyArrived(Models.UserInfo i) { put("arrived", i.screenName); }
        public void onBuddyDeparted(String sn) { put("departed", sn); }
        public void onMessage(String from, String text, boolean auto) { put("im", from, text, auto); }
        public void onTyping(String from, int st) { put("typing", from, st); }
        public void onOutbox(Client.OutMsg m) { put("outbox", m.status); }
        public void onInvite(Rooms.Invite inv) { put("invite", inv); }
        public void onRoomOpened(Client.Room r) { put("roomOpened", r.key); }
        public void onRoomMembers(Client.Room r, List<String> j, List<String> l, boolean init) {
            put("members", r.key, j, l, init);
        }
        public void onRoomMessage(Client.Room r, Rooms.Message m) { put("roomMsg", r.key, m.from, m.text); }
        public void onRoomClosed(Client.Room r) { put("roomClosed", r.key); }

        interface Match {
            boolean ok(Object[] e);
        }

        Object[] await(String what, Match m) throws Exception {
            long until = System.currentTimeMillis() + 30000;
            while (true) {
                long left = until - System.currentTimeMillis();
                Object[] e = left <= 0 ? null : q.poll(left, TimeUnit.MILLISECONDS);
                if (e == null) throw new AssertionError(name + ": timed out waiting for " + what);
                if (m.ok(e)) return e;
            }
        }

        Object[] await(final String kind) throws Exception {
            return await(kind, new Match() {
                public boolean ok(Object[] e) {
                    return e[0].equals(kind);
                }
            });
        }

        void drain() {
            q.clear();
        }
    }

    static Client client(String sn, String pw, Probe p) {
        Client c = new Client(host, port, sn, pw, p);
        c.setBackoffForTests(new long[] {300, 1000});
        return c;
    }

    static void online(Client c, Probe p) throws Exception {
        p.await("online", new Probe.Match() {
            public boolean ok(Object[] e) {
                if (e[0].equals("state") && e[1] == Client.State.STOPPED) throw new AssertionError("stopped: " + e[2]);
                return e[0].equals("state") && e[1] == Client.State.ONLINE;
            }
        });
    }

    static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
        System.out.println("  ok: " + what);
    }

    public static void main(String[] args) throws Exception {
        String[] hp = args[0].split(":");
        host = hp[0];
        port = Integer.parseInt(hp[1]);

        System.out.println("wrong password stops");
        Probe bad = new Probe("bad");
        Client badc = client("carol", "nope-nope", bad);
        badc.start();
        bad.await("stopped", new Probe.Match() {
            public boolean ok(Object[] e) {
                if (e[0].equals("state") && e[1] == Client.State.ONLINE) throw new AssertionError("signed on with a bad password");
                return e[0].equals("state") && e[1] == Client.State.STOPPED;
            }
        });
        check(true, "bad password -> stopped");
        badc.shutdown();

        System.out.println("sign on, buddy list, IMs");
        Probe pa = new Probe("alice"), pb = new Probe("bob");
        Client a = client("alice", "password1", pa), b = client("bob", "password1", pb);
        a.start();
        b.start();
        online(a, pa);
        online(b, pb);
        if (!a.session().isBuddy("bob")) a.addBuddy("bob");
        check(a.session().isBuddy("bob"), "alice has bob on her list");
        boolean found = false;
        for (Models.BuddyGroup g : a.session().groups()) for (String n : g.buddies) if (Bytes.normalizeSn(n).equals("bob")) found = true;
        check(found, "bob is in one of alice's groups");

        pb.drain();
        a.send("bob", "hello <bob> & co");
        Object[] im = pb.await("im");
        check(im[2].equals("hello <bob> & co"), "bob got alice's IM: " + im[2]);
        pa.drain();
        b.send("alice", "unicode ☕ ok");
        im = pa.await("im");
        check(im[2].equals("unicode ☕ ok"), "alice got unicode: " + im[2]);

        System.out.println("away auto-reply");
        a.setAway("gone fishing");
        Thread.sleep(500);
        pb.drain();
        b.send("alice", "you there?");
        im = pb.await("auto-reply", new Probe.Match() {
            public boolean ok(Object[] e) {
                return e[0].equals("im") && Boolean.TRUE.equals(e[3]);
            }
        });
        check(((String) im[2]).contains("gone fishing"), "bob got the away message");
        a.setAway(null);

        System.out.println("reconnect delivers queued IMs");
        a.debugDrop();
        a.send("bob", "sent while reconnecting");
        im = pb.await("queued im", new Probe.Match() {
            public boolean ok(Object[] e) {
                return e[0].equals("im") && "sent while reconnecting".equals(e[2]);
            }
        });
        check(true, "queued IM arrived after reconnect");

        System.out.println("chat rooms");
        Probe pc = new Probe("carol");
        Client c = client("carol", "password1", pc);
        c.start();
        online(c, pc);
        String name = "Sidekick Room " + (System.currentTimeMillis() % 100000);
        Client.Room ra = a.joinRoom(name);
        check(ra.isOpen() && ra.name().equals(name), "alice made the room " + ra.name());
        pc.drain();
        List<String> failed = a.inviteToRoom(ra.key, Arrays.asList("carol"), "come in");
        check(failed.isEmpty(), "invite sent");
        Rooms.Invite inv = (Rooms.Invite) pc.await("invite")[1];
        check(inv.message.equals("come in") && inv.room.key().equals(ra.key), "carol got the invite");

        pa.drain();
        Client.Room rc = c.acceptInvite(inv);
        pa.await("carol arrives", new Probe.Match() {
            public boolean ok(Object[] e) {
                return e[0].equals("members") && ((List<?>) e[2]).toString().toLowerCase().contains("carol");
            }
        });
        check(rc.isOpen(), "carol is in the room");
        Thread.sleep(300);
        List<String> norm = new ArrayList<String>();
        for (String m : ra.members()) norm.add(Bytes.normalizeSn(m));
        check(norm.contains("alice") && norm.contains("carol"), "members: " + ra.members());

        pc.drain();
        check(a.sendToRoom(ra.key, "hi carol ☕"), "alice says hi");
        Object[] rm = pc.await("roomMsg");
        check(rm[3].equals("hi carol ☕") && Bytes.normalizeSn((String) rm[2]).equals("alice"), "carol heard: " + rm[3]);
        pa.drain();
        check(c.sendToRoom(rc.key, "hey alice"), "carol answers");
        rm = pa.await("roomMsg");
        check(rm[3].equals("hey alice"), "alice heard: " + rm[3]);

        System.out.println("room rejoins after a dropped link");
        pc.drain();
        c.debugDrop();
        pc.await("roomOpened");
        check(rc.isOpen(), "carol is back in the room");
        pc.drain();
        a.sendToRoom(ra.key, "welcome back");
        rm = pc.await("roomMsg");
        check(rm[3].equals("welcome back"), "carol hears the room again");

        pa.drain();
        c.leaveRoom(rc.key);
        pa.await("carol leaves", new Probe.Match() {
            public boolean ok(Object[] e) {
                return e[0].equals("members") && ((List<?>) e[3]).toString().toLowerCase().contains("carol");
            }
        });
        check(c.rooms().isEmpty(), "carol left");

        System.out.println("check-in after sleep");
        check(a.checkIn(15000), "alice's link answers a ping");
        check(a.isOnline(), "alice still online after the check-in");

        System.out.println("get info");
        b.setProfile("bob's profile ☕");
        b.setAway("back soon");
        Thread.sleep(800);
        com.hatdagger.aimlite.oscar.Session.Profile info = a.session().getProfile("bob");
        check(info.profile != null && info.profile.contains("bob's profile"), "bob's profile: " + info.profile);
        check(info.away != null && info.away.contains("back soon"), "bob's away message: " + info.away);
        check(info.user != null && Bytes.normalizeSn(info.user.screenName).equals("bob"), "info is about bob");
        b.setAway(null);
        try {
            a.session().getProfile("nobody" + System.currentTimeMillis());
            check(false, "info for a missing user should fail");
        } catch (java.io.IOException e) {
            check(true, "info for a missing user fails: " + e.getMessage());
        }

        System.out.println("buddy icon service");
        byte[] fakeHash = new byte[16];
        new java.util.Random().nextBytes(fakeHash);
        try {
            byte[] got = a.session().fetchBuddyIcon("bob", fakeHash, 1);
            check(got == null || got.length > 0, "unknown icon -> " + (got == null ? "none" : got.length + " bytes"));
        } catch (java.io.IOException e) {
            check(!(e instanceof com.hatdagger.aimlite.oscar.Flap.ConnectionClosed), "icon service said: " + e.getMessage());
        }
        check(a.checkIn(15000), "alice's link is fine after asking for an icon");

        a.shutdown();
        b.shutdown();
        c.shutdown();
        System.out.println("ALL PASSED");
        System.exit(0);
    }
}
