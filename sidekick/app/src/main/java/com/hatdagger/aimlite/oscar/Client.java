package com.hatdagger.aimlite.oscar;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import com.hatdagger.aimlite.oscar.Models.Disconnect;
import com.hatdagger.aimlite.oscar.Models.EndKind;
import com.hatdagger.aimlite.oscar.Models.SendResult;
import com.hatdagger.aimlite.oscar.Models.UserInfo;

/**
 * Keeps one screen name signed on: reconnects when the link drops, holds
 * outgoing IMs until they can go, answers with the away message, and keeps
 * chat rooms joined. Listener calls come from background threads.
 */
public final class Client {

    public enum State { OFFLINE, CONNECTING, ONLINE, RECONNECTING, STOPPED }

    public enum OutStatus { QUEUED, SENDING, WAITING, SENT, FAILED, CANCELLED }

    public interface Listener {
        void onState(State state, String message);

        void onBuddyListChanged();

        void onBuddyArrived(UserInfo info);

        void onBuddyDeparted(String screenName);

        void onMessage(String from, String text, boolean autoResponse);

        void onTyping(String from, int state);

        void onOutbox(OutMsg m);

        void onInvite(Rooms.Invite invite);

        void onRoomOpened(Room r);

        void onRoomMembers(Room r, List<String> joined, List<String> left, boolean initial);

        void onRoomMessage(Room r, Rooms.Message m);

        void onRoomClosed(Room r);
    }

    public static final class OutMsg {
        public final long id;
        public final String to;
        public final String text;
        public volatile OutStatus status = OutStatus.QUEUED;
        public volatile String note;
        volatile long nextTry;

        OutMsg(long id, String to, String text) {
            this.id = id;
            this.to = to;
            this.text = text;
        }
    }

    /** A chat room we're in, or want to be in (it rejoins after a drop). */
    public static final class Room {
        public final String key;
        public volatile Rooms.RoomInfo info;
        volatile Rooms.Conn conn;
        volatile boolean wanted = true;
        int failures;
        boolean retryPending;

        Room(Rooms.RoomInfo info) {
            this.info = info;
            this.key = info.key();
        }

        public String name() {
            return info.name;
        }

        public boolean isOpen() {
            Rooms.Conn c = conn;
            return c != null && c.isOpen();
        }

        public List<String> members() {
            Rooms.Conn c = conn;
            return c == null ? new ArrayList<String>() : c.members();
        }
    }

    private static final long[] BACKOFF = {1000, 3000, 5000, 10000, 20000, 30000};

    public final String host;
    public final int port;
    public final String screenName;
    private final String password;
    private final Listener listener;
    private long[] backoff = BACKOFF;

    private volatile String profile = "";
    private volatile String away;
    private volatile Session session;
    private volatile State state = State.OFFLINE;
    private volatile String lastMessage;
    private volatile boolean want;
    private final Object wake = new Object();
    private boolean woken;
    private final ExecutorService net = Executors.newSingleThreadExecutor();
    private final Timer timer = new Timer("aim-client", true);
    private final List<OutMsg> outbox = new ArrayList<OutMsg>();
    private final Map<String, Long> lastAutoReply = new HashMap<String, Long>();
    private final Map<String, Room> rooms = new LinkedHashMap<String, Room>();
    private long idSeq;
    private boolean pumpQueued;

    public Client(String host, int port, String screenName, String password, Listener listener) {
        this.host = host;
        this.port = port;
        this.screenName = screenName;
        this.password = password;
        this.listener = listener;
    }

    public void setBackoffForTests(long[] b) {
        backoff = b;
    }

    public State state() {
        return state;
    }

    public String lastMessage() {
        return lastMessage;
    }

    public Session session() {
        return session;
    }

    public boolean isOnline() {
        Session s = session;
        return state == State.ONLINE && s != null && s.isOnline();
    }

    public String myName() {
        Session s = session;
        return s == null ? screenName : s.formattedName;
    }

    public boolean isAway() {
        String a = away;
        return a != null && a.length() > 0;
    }

    public String awayMessage() {
        return away;
    }

    private void setState(State s, String msg) {
        state = s;
        lastMessage = msg;
        listener.onState(s, msg);
    }

    // ------------------------------------------------------------- lifecycle

    public synchronized void start() {
        if (want) return;
        want = true;
        Thread t = new Thread(new Runnable() {
            public void run() {
                runLoop();
            }
        }, "aim-link");
        t.setDaemon(true);
        t.start();
    }

    /**
     * The phone woke up (screen on, or the half-hourly check-in): make sure
     * we're really connected, reconnect if not, and send anything waiting.
     * Blocking; returns true if the link was alive.
     */
    public boolean checkIn(long timeoutMs) {
        if (!want) return true;
        Session s = session;
        if (s == null || state != State.ONLINE || !s.isOnline()) {
            retryNow();
            return false;
        }
        if (s.ping(timeoutMs)) {
            schedulePump(0);
            return true;
        }
        // Dead without anyone noticing (the router forgot us, Wi-Fi blipped):
        // drop it so the normal reconnect starts straight away.
        s.debugDrop();
        retryNow();
        return false;
    }

    /** Skip the remaining wait and reconnect now (network came back, app opened). */
    public void retryNow() {
        synchronized (wake) {
            woken = true;
            wake.notifyAll();
        }
    }

    private void runLoop() {
        int attempt = 0;
        while (want) {
            setState(attempt == 0 ? State.CONNECTING : State.RECONNECTING, lastMessage);
            final CountDownLatch over = new CountDownLatch(1);
            final Disconnect[] why = new Disconnect[1];
            Session s = new Session(host, port, screenName, password, new SessionEvents(over, why));
            session = s;
            Disconnect result;
            try {
                s.signOn(profile, away);
                attempt = 0;
                setState(State.ONLINE, null);
                schedulePump(0);
                rejoinRooms();
                over.await();
                result = why[0] != null ? why[0] : new Disconnect(EndKind.NETWORK, "Connection lost");
            } catch (Disconnect d) {
                result = d;
                s.debugDrop();
            } catch (IOException e) {
                s.debugDrop();
                result = new Disconnect(EndKind.NETWORK, friendly(e));
            } catch (InterruptedException e) {
                result = new Disconnect(EndKind.NETWORK, "Interrupted");
            } catch (RuntimeException e) {
                s.debugDrop();
                result = new Disconnect(EndKind.SERVER_ERROR, "Unexpected reply from the server");
            }
            synchronized (outbox) {
                for (OutMsg m : outbox) if (m.status == OutStatus.SENDING) m.status = OutStatus.QUEUED;
            }
            if (!want || result.kind == EndKind.SIGNED_OFF) break;
            if (result.kind == EndKind.BAD_PASSWORD || result.kind == EndKind.ELSEWHERE) {
                want = false;
                setState(State.STOPPED, result.getMessage());
                return;
            }
            long delay = backoff[Math.min(attempt, backoff.length - 1)];
            if (result.kind == EndKind.RATE_LIMITED && delay < 60000) delay = 60000;
            attempt++;
            setState(State.RECONNECTING, result.getMessage());
            synchronized (wake) {
                woken = false;
                long until = System.currentTimeMillis() + delay;
                while (!woken && want) {
                    long left = until - System.currentTimeMillis();
                    if (left <= 0) break;
                    try {
                        wake.wait(left);
                    } catch (InterruptedException e) {
                        break;
                    }
                }
            }
        }
        if (state != State.STOPPED) setState(State.OFFLINE, null);
    }

    private static String friendly(IOException e) {
        String m = String.valueOf(e.getMessage());
        if (e instanceof java.net.ConnectException || e instanceof java.net.UnknownHostException
                || e instanceof java.net.SocketTimeoutException || m.contains("refused")) {
            return "Can't reach the server";
        }
        return m;
    }

    private final class SessionEvents implements Session.Events {
        final CountDownLatch over;
        final Disconnect[] why;

        SessionEvents(CountDownLatch over, Disconnect[] why) {
            this.over = over;
            this.why = why;
        }

        public void onBuddyListChanged() {
            listener.onBuddyListChanged();
        }

        public void onBuddyArrived(UserInfo info) {
            String k = Bytes.normalizeSn(info.screenName);
            boolean any = false;
            synchronized (outbox) {
                for (OutMsg m : outbox) {
                    if (m.status == OutStatus.WAITING && Bytes.normalizeSn(m.to).equals(k)) {
                        m.status = OutStatus.QUEUED;
                        m.note = null;
                        m.nextTry = 0;
                        any = true;
                    }
                }
            }
            listener.onBuddyArrived(info);
            if (any) schedulePump(0);
        }

        public void onBuddyDeparted(String sn) {
            listener.onBuddyDeparted(sn);
        }

        public void onMessage(String from, String text, boolean auto) {
            listener.onMessage(from, text, auto);
            if (isAway() && !auto) autoReply(from);
        }

        public void onTyping(String from, int st) {
            listener.onTyping(from, st);
        }

        public void onRoomInvite(Rooms.Invite invite) {
            listener.onInvite(invite);
        }

        public void onEnded(Disconnect d) {
            why[0] = d;
            over.countDown();
        }
    }

    /** Signs off on purpose: pending IMs are cancelled, rooms are left. */
    public void signOff() {
        want = false;
        retryNow();
        synchronized (rooms) {
            for (Room r : rooms.values()) r.wanted = false;
            rooms.clear();
        }
        Session s = session;
        if (s != null) s.signOff();
        synchronized (outbox) {
            for (OutMsg m : outbox) m.status = OutStatus.CANCELLED;
            outbox.clear();
        }
        setState(State.OFFLINE, null);
    }

    public void shutdown() {
        signOff();
        net.shutdown();
        timer.cancel();
    }

    /** Drops the network link without signing off (tests). */
    public void debugDrop() {
        Session s = session;
        if (s != null) s.debugDrop();
    }

    // ------------------------------------------------------------- away / profile

    private void autoReply(final String to) {
        String k = Bytes.normalizeSn(to);
        long now = System.currentTimeMillis();
        synchronized (lastAutoReply) {
            Long last = lastAutoReply.get(k);
            if (last != null && now - last < 5 * 60 * 1000) return;
            lastAutoReply.put(k, now);
        }
        final String text = away;
        net.execute(new Runnable() {
            public void run() {
                Session s = session;
                if (s == null || !s.isOnline() || text == null) return;
                try {
                    s.sendIm(to, text, true);
                } catch (IOException ignored) {
                }
            }
        });
    }

    /** null or empty = back. */
    public void setAway(String text) {
        away = text == null || text.length() == 0 ? null : text;
        if (away == null) {
            synchronized (lastAutoReply) {
                lastAutoReply.clear();
            }
        }
        pushLocate();
    }

    public void setProfile(String text) {
        profile = text == null ? "" : text;
        pushLocate();
    }

    private void pushLocate() {
        net.execute(new Runnable() {
            public void run() {
                Session s = session;
                if (s != null && s.isOnline()) {
                    try {
                        s.setLocate(profile, away);
                    } catch (IOException ignored) {
                    }
                }
            }
        });
    }

    // ------------------------------------------------------------- IMs

    public OutMsg send(String to, String text) {
        OutMsg m;
        synchronized (outbox) {
            m = new OutMsg(++idSeq, to, text);
            outbox.add(m);
        }
        listener.onOutbox(m);
        schedulePump(0);
        return m;
    }

    public void cancel(long id) {
        synchronized (outbox) {
            for (OutMsg m : outbox) {
                if (m.id == id && m.status != OutStatus.SENDING) {
                    m.status = OutStatus.CANCELLED;
                    outbox.remove(m);
                    listener.onOutbox(m);
                    return;
                }
            }
        }
    }

    public void retry(long id) {
        synchronized (outbox) {
            for (OutMsg m : outbox) {
                if (m.id == id && m.status == OutStatus.FAILED) {
                    m.status = OutStatus.QUEUED;
                    m.note = null;
                    listener.onOutbox(m);
                }
            }
        }
        schedulePump(0);
    }

    public int pendingCount() {
        synchronized (outbox) {
            return outbox.size();
        }
    }

    private void schedulePump(long delay) {
        timer.schedule(new TimerTask() {
            public void run() {
                synchronized (outbox) {
                    if (pumpQueued) return;
                    pumpQueued = true;
                }
                net.execute(new Runnable() {
                    public void run() {
                        synchronized (outbox) {
                            pumpQueued = false;
                        }
                        pump();
                    }
                });
            }
        }, Math.max(0, delay));
    }

    private void pump() {
        while (true) {
            Session s = session;
            if (s == null || !s.isOnline() || state != State.ONLINE) return;
            long now = System.currentTimeMillis();
            OutMsg next = null;
            long soonest = Long.MAX_VALUE;
            synchronized (outbox) {
                for (OutMsg m : outbox) {
                    if (m.status == OutStatus.WAITING && m.nextTry > 0 && now >= m.nextTry) m.status = OutStatus.QUEUED;
                    if (m.status == OutStatus.QUEUED && now >= m.nextTry) {
                        if (next == null) next = m;
                    } else if ((m.status == OutStatus.QUEUED || m.status == OutStatus.WAITING) && m.nextTry > 0) {
                        soonest = Math.min(soonest, m.nextTry);
                    }
                }
                if (next != null) next.status = OutStatus.SENDING;
            }
            if (next == null) {
                if (soonest != Long.MAX_VALUE) schedulePump(soonest - now + 50);
                return;
            }
            listener.onOutbox(next);
            SendResult r;
            try {
                r = s.sendIm(next.to, next.text, false);
            } catch (IOException e) {
                r = SendResult.FAILED;
            }
            if (next.status == OutStatus.CANCELLED) continue;
            synchronized (outbox) {
                switch (r) {
                    case DELIVERED:
                        next.status = OutStatus.SENT;
                        next.note = null;
                        outbox.remove(next);
                        break;
                    case OFFLINE:
                        next.status = OutStatus.WAITING;
                        next.note = "Will send when " + next.to + " signs on";
                        next.nextTry = System.currentTimeMillis() + 120000;
                        break;
                    case RATE_LIMITED:
                        next.status = OutStatus.QUEUED;
                        next.note = "Slowing down (server rate limit)";
                        next.nextTry = System.currentTimeMillis() + 5000;
                        break;
                    default:
                        if (s.isOnline()) {
                            next.status = OutStatus.FAILED;
                            next.note = "Not delivered";
                        } else {
                            next.status = OutStatus.QUEUED;
                        }
                }
            }
            listener.onOutbox(next);
        }
    }

    // ------------------------------------------------------------- buddy list

    public void addBuddy(String sn) throws IOException {
        Session s = requireOnline();
        s.addBuddy(sn, "Buddies");
    }

    public void removeBuddy(String sn) throws IOException {
        requireOnline().removeBuddy(sn);
    }

    private Session requireOnline() throws IOException {
        Session s = session;
        if (s == null || !s.isOnline()) throw new IOException("Not signed on");
        return s;
    }

    // ------------------------------------------------------------- chat rooms

    public List<Room> rooms() {
        synchronized (rooms) {
            return new ArrayList<Room>(rooms.values());
        }
    }

    public Room room(String key) {
        synchronized (rooms) {
            return rooms.get(key);
        }
    }

    /** Goes into the room called [name], making it if needed. Blocking. */
    public Room joinRoom(String name) throws IOException {
        Session s = requireOnline();
        String clean = Rooms.cleanName(name);
        if (clean.length() == 0) throw new IOException("Type a room name (letters and numbers).");
        return enter(s.findOrCreateRoom(clean));
    }

    /** Goes into the room a buddy invited us to. Blocking. */
    public Room acceptInvite(Rooms.Invite inv) throws IOException {
        requireOnline();
        return enter(inv.room);
    }

    public void declineInvite(final Rooms.Invite inv) {
        net.execute(new Runnable() {
            public void run() {
                Session s = session;
                if (s == null || !s.isOnline()) return;
                try {
                    s.declineRoomInvite(inv);
                } catch (IOException ignored) {
                }
            }
        });
    }

    private Room enter(Rooms.RoomInfo info) throws IOException {
        Room r;
        synchronized (rooms) {
            r = rooms.get(info.key());
            if (r == null) {
                r = new Room(info);
                rooms.put(r.key, r);
            }
            r.wanted = true;
            r.failures = 0;
        }
        connectRoom(r);
        return r;
    }

    private void connectRoom(final Room r) throws IOException {
        synchronized (r) {
            if (r.isOpen()) return;
            Session s = requireOnline();
            Rooms.Conn c = s.joinRoom(r.info, new Rooms.Listener() {
                public void onMembers(Rooms.Conn conn, List<String> joined, List<String> left, boolean initial) {
                    if (r.conn == conn || r.conn == null) listener.onRoomMembers(r, joined, left, initial);
                }

                public void onMessage(Rooms.Conn conn, Rooms.Message m) {
                    listener.onRoomMessage(r, m);
                }

                public void onClosed(Rooms.Conn conn, String reason) {
                    if (r.conn != conn) return;
                    r.conn = null;
                    if (r.wanted) {
                        listener.onRoomClosed(r);
                        scheduleRoomRetry(r);
                    }
                }
            });
            if (!r.wanted) {
                c.leave();
                return;
            }
            r.conn = c;
            r.info = c.info;
            r.failures = 0;
        }
        listener.onRoomOpened(r);
    }

    /** A room dropped while the main link stayed up: try again shortly. */
    private void scheduleRoomRetry(final Room r) {
        synchronized (r) {
            if (!want || !r.wanted || r.retryPending || r.failures >= 6) return;
            r.retryPending = true;
            long delay = backoff[Math.min(r.failures, backoff.length - 1)];
            r.failures++;
            timer.schedule(new TimerTask() {
                public void run() {
                    net.execute(new Runnable() {
                        public void run() {
                            synchronized (r) {
                                r.retryPending = false;
                            }
                            if (!r.wanted || r.isOpen() || !isOnline()) return;
                            try {
                                connectRoom(r);
                            } catch (IOException e) {
                                scheduleRoomRetry(r);
                            }
                        }
                    });
                }
            }, delay);
        }
    }

    private void rejoinRooms() {
        for (final Room r : rooms()) {
            synchronized (r) {
                r.failures = 0;
            }
            net.execute(new Runnable() {
                public void run() {
                    if (!r.wanted || r.isOpen()) return;
                    try {
                        connectRoom(r);
                    } catch (IOException e) {
                        scheduleRoomRetry(r);
                    }
                }
            });
        }
    }

    public void leaveRoom(String key) {
        final Room r;
        synchronized (rooms) {
            r = rooms.remove(key);
        }
        if (r == null) return;
        r.wanted = false;
        final Rooms.Conn c = r.conn;
        r.conn = null;
        if (c != null) {
            net.execute(new Runnable() {
                public void run() {
                    c.leave();
                }
            });
        }
    }

    /** Says [text] in the room. False when the room isn't connected now. */
    public boolean sendToRoom(String key, String text) {
        Room r = room(key);
        Rooms.Conn c = r == null ? null : r.conn;
        if (c == null || !c.isOpen()) return false;
        try {
            c.send(text);
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    /** Invites buddies; returns the ones it couldn't reach. Blocking. */
    public List<String> inviteToRoom(String key, List<String> who, String message) throws IOException {
        Session s = requireOnline();
        Room r = room(key);
        if (r == null) throw new IOException("You're not in that room");
        List<String> failed = new ArrayList<String>();
        for (String sn : who) {
            try {
                if (s.sendRoomInvite(sn, r.info, message) != SendResult.DELIVERED) failed.add(sn);
            } catch (IOException e) {
                failed.add(sn);
            }
        }
        return failed;
    }

    /** Runs [task] on the network thread (for the app's blocking calls). */
    public void runOnNetwork(Runnable task) {
        net.execute(task);
    }
}
