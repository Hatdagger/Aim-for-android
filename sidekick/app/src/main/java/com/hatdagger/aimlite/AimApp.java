package com.hatdagger.aimlite;

import android.app.Application;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;

import com.hatdagger.aimlite.oscar.Bytes;
import com.hatdagger.aimlite.oscar.Client;
import com.hatdagger.aimlite.oscar.Models;
import com.hatdagger.aimlite.oscar.Rooms;
import com.hatdagger.aimlite.oscar.Session;

import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The app's state: the signed-on client, conversations, rooms and invites.
 * Everything here is touched on the main thread only; network callbacks are
 * posted over. Screens register as observers and redraw on [changed].
 */
public final class AimApp extends Application {

    private static AimApp instance;

    public static AimApp get() {
        return instance;
    }

    // ------------------------------------------------------------------ model

    public static final class Line {
        public final String from;
        public final String text;
        public final long time;
        public final boolean mine;
        public final boolean system;
        public final boolean auto;
        public Client.OutMsg pending;

        Line(String from, String text, boolean mine, boolean system, boolean auto) {
            this.from = from;
            this.text = text;
            this.time = System.currentTimeMillis();
            this.mine = mine;
            this.system = system;
            this.auto = auto;
        }
    }

    public static final class Conv {
        public final String key;
        public String name;
        public final List<Line> lines = new ArrayList<Line>();
        public int unread;
        public int typing;

        Conv(String key, String name) {
            this.key = key;
            this.name = name;
        }
    }

    public static final class RoomChat {
        public final String key;
        public Client.Room room;
        public final List<Line> lines = new ArrayList<Line>();
        public int unread;
        boolean wasOpen;

        RoomChat(Client.Room r) {
            key = r.key;
            room = r;
        }

        public String name() {
            return room.name();
        }

        public boolean isOpen() {
            return room.isOpen();
        }
    }

    public interface Done<T> {
        void ok(T result);

        void failed(String message);
    }

    // ------------------------------------------------------------------ state

    public Client client;
    public Client.State state = Client.State.OFFLINE;
    public String stateMessage;
    public boolean everOnline;
    public final Map<String, Conv> convs = new LinkedHashMap<String, Conv>();
    public final Map<String, RoomChat> rooms = new LinkedHashMap<String, RoomChat>();
    public final List<Rooms.Invite> invites = new ArrayList<Rooms.Invite>();
    public String openConv;
    public String openRoom;
    private int visible;
    private final List<Runnable> observers = new ArrayList<Runnable>();
    private Handler main;
    private Notifier notifier;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        main = new Handler();
        notifier = new Notifier(this);
    }

    public SharedPreferences prefs() {
        return getSharedPreferences("aim", Context.MODE_PRIVATE);
    }

    public Notifier notifier() {
        return notifier;
    }

    public void observe(Runnable r) {
        if (!observers.contains(r)) observers.add(r);
    }

    public void unobserve(Runnable r) {
        observers.remove(r);
    }

    public void changed() {
        for (Runnable r : new ArrayList<Runnable>(observers)) r.run();
        notifier.refresh();
    }

    /** A screen came to the front (or left it). */
    public void setVisible(boolean v) {
        visible += v ? 1 : -1;
        if (visible < 0) visible = 0;
        if (v && client != null) client.retryNow();
        notifier.refresh();
    }

    public boolean isVisible() {
        return visible > 0;
    }

    public boolean signedOn() {
        return client != null && state != Client.State.OFFLINE && state != Client.State.STOPPED;
    }

    public String myName() {
        return client == null ? prefs().getString("sn", "") : client.myName();
    }

    void post(Runnable r) {
        main.post(r);
    }

    // ------------------------------------------------------------------ sign on / off

    public void signOn(String server, String sn, String pw) {
        signOffQuietly();
        String[] hp = Session.parseServer(server);
        int port;
        try {
            port = Integer.parseInt(hp[1]);
        } catch (NumberFormatException e) {
            port = 5190;
        }
        convs.clear();
        rooms.clear();
        invites.clear();
        everOnline = false;
        stateMessage = null;
        client = new Client(hp[0], port, sn, pw, new Events());
        client.setProfile(prefs().getString("profile", ""));
        state = Client.State.CONNECTING;
        client.start();
        startService(new Intent(this, AimService.class));
        changed();
    }

    /** Signs on with the saved account if "sign on automatically" is set. */
    public boolean autoSignOn() {
        SharedPreferences p = prefs();
        String server = p.getString("server", "");
        String sn = p.getString("sn", "");
        String pw = p.getString("pw", "");
        if (!p.getBoolean("autoLogin", false) || server.length() == 0 || sn.length() == 0 || pw.length() == 0) {
            return false;
        }
        signOn(server, sn, pw);
        return true;
    }

    private void signOffQuietly() {
        Client c = client;
        client = null;
        if (c != null) {
            final Client old = c;
            new Thread(new Runnable() {
                public void run() {
                    old.shutdown();
                }
            }).start();
        }
    }

    public void signOff() {
        signOffQuietly();
        state = Client.State.OFFLINE;
        convs.clear();
        rooms.clear();
        invites.clear();
        openConv = null;
        openRoom = null;
        prefs().edit().putBoolean("autoLogin", false).commit();
        stopService(new Intent(this, AimService.class));
        notifier.clearMessages();
        changed();
    }

    // ------------------------------------------------------------------ events from the client

    private final class Events implements Client.Listener {
        private boolean mine(final Runnable r) {
            final Client me = client;
            post(new Runnable() {
                public void run() {
                    if (client == me && me != null) {
                        r.run();
                        changed();
                    }
                }
            });
            return true;
        }

        public void onState(final Client.State s, final String m) {
            mine(new Runnable() {
                public void run() {
                    state = s;
                    stateMessage = m;
                    if (s == Client.State.ONLINE) everOnline = true;
                }
            });
        }

        public void onBuddyListChanged() {
            mine(new Runnable() {
                public void run() {}
            });
        }

        public void onBuddyArrived(Models.UserInfo info) {
            onBuddyListChanged();
        }

        public void onBuddyDeparted(String sn) {
            onBuddyListChanged();
        }

        public void onMessage(final String from, final String text, final boolean auto) {
            mine(new Runnable() {
                public void run() {
                    Conv c = conv(from);
                    c.name = from;
                    c.typing = 0;
                    c.lines.add(new Line(from, text, false, false, auto));
                    boolean viewing = isVisible() && c.key.equals(openConv);
                    if (!viewing) {
                        c.unread++;
                        notifier.message(from, text);
                    }
                }
            });
        }

        public void onTyping(final String from, final int st) {
            mine(new Runnable() {
                public void run() {
                    Conv c = convs.get(Bytes.normalizeSn(from));
                    if (c != null) c.typing = st;
                }
            });
        }

        public void onOutbox(Client.OutMsg m) {
            mine(new Runnable() {
                public void run() {
                    for (Conv c : convs.values()) {
                        for (int i = c.lines.size() - 1; i >= 0; i--) {
                            Line l = c.lines.get(i);
                            if (l.pending == null) continue;
                            if (l.pending.status == Client.OutStatus.SENT) l.pending = null;
                            else if (l.pending.status == Client.OutStatus.CANCELLED) c.lines.remove(i);
                        }
                    }
                }
            });
        }

        public void onInvite(final Rooms.Invite inv) {
            mine(new Runnable() {
                public void run() {
                    RoomChat already = rooms.get(inv.room.key());
                    if (already != null && already.isOpen()) return;
                    for (int i = invites.size() - 1; i >= 0; i--) {
                        Rooms.Invite o = invites.get(i);
                        if (o.room.key().equals(inv.room.key())) invites.remove(i);
                    }
                    invites.add(0, inv);
                    notifier.message(inv.from, "invited you to the chat room \"" + inv.room.name + "\"");
                }
            });
        }

        public void onRoomOpened(final Client.Room r) {
            mine(new Runnable() {
                public void run() {
                    RoomChat rc = roomChat(r);
                    if (!rc.wasOpen) note(rc, rc.lines.isEmpty() ? "You are in \"" + rc.name() + "\"." : "Back in the room.");
                    rc.wasOpen = true;
                }
            });
        }

        public void onRoomMembers(final Client.Room r, final List<String> joined, final List<String> left,
                final boolean initial) {
            mine(new Runnable() {
                public void run() {
                    RoomChat rc = rooms.get(r.key);
                    if (rc == null || initial) return;
                    String me = Bytes.normalizeSn(myName());
                    for (String sn : joined) if (!Bytes.normalizeSn(sn).equals(me)) note(rc, sn + " entered the room.");
                    for (String sn : left) if (!Bytes.normalizeSn(sn).equals(me)) note(rc, sn + " left the room.");
                }
            });
        }

        public void onRoomMessage(final Client.Room r, final Rooms.Message m) {
            mine(new Runnable() {
                public void run() {
                    RoomChat rc = rooms.get(r.key);
                    if (rc == null || Bytes.normalizeSn(m.from).equals(Bytes.normalizeSn(myName()))) return;
                    rc.lines.add(new Line(m.from, m.text, false, false, false));
                    if (!(isVisible() && rc.key.equals(openRoom))) rc.unread++;
                }
            });
        }

        public void onRoomClosed(final Client.Room r) {
            mine(new Runnable() {
                public void run() {
                    RoomChat rc = rooms.get(r.key);
                    if (rc == null) return;
                    if (rc.wasOpen && state == Client.State.ONLINE) note(rc, "Lost the connection to the room. Rejoining...");
                    rc.wasOpen = false;
                }
            });
        }
    }

    // ------------------------------------------------------------------ IMs

    public Conv conv(String sn) {
        String k = Bytes.normalizeSn(sn);
        Conv c = convs.get(k);
        if (c == null) {
            c = new Conv(k, sn);
            convs.put(k, c);
        }
        return c;
    }

    public void sendIm(String to, String text) {
        String t = text.trim();
        if (client == null || t.length() == 0) return;
        Conv c = conv(to);
        Line l = new Line(myName(), t, true, false, false);
        l.pending = client.send(to, t);
        c.lines.add(l);
        changed();
    }

    public void closeConv(String key) {
        convs.remove(key);
        changed();
    }

    public Models.UserInfo onlineInfo(String sn) {
        Client c = client;
        Session s = c == null ? null : c.session();
        return s == null ? null : s.onlineInfo(sn);
    }

    public List<Models.BuddyGroup> groups() {
        Client c = client;
        Session s = c == null ? null : c.session();
        return s == null ? new ArrayList<Models.BuddyGroup>() : s.groups();
    }

    public boolean isBuddy(String sn) {
        Client c = client;
        Session s = c == null ? null : c.session();
        return s != null && s.isBuddy(sn);
    }

    public List<String> onlineBuddies() {
        List<String> out = new ArrayList<String>();
        for (Models.BuddyGroup g : groups()) {
            for (String b : g.buddies) {
                Models.UserInfo u = onlineInfo(b);
                if (u != null && !out.contains(u.screenName)) out.add(u.screenName);
            }
        }
        return out;
    }

    public void setAway(String text) {
        if (client != null) client.setAway(text);
        changed();
    }

    public int totalUnread() {
        int n = invites.size();
        for (Conv c : convs.values()) n += c.unread;
        for (RoomChat r : rooms.values()) n += r.unread;
        return n;
    }

    // ------------------------------------------------------------------ blocking work, off the main thread

    private interface Work<T> {
        T run(Client c) throws IOException;
    }

    private <T> void background(final Work<T> work, final Done<T> done) {
        final Client c = client;
        if (c == null) {
            done.failed("Not signed on");
            return;
        }
        c.runOnNetwork(new Runnable() {
            public void run() {
                try {
                    final T r = work.run(c);
                    post(new Runnable() {
                        public void run() {
                            done.ok(r);
                            changed();
                        }
                    });
                } catch (final IOException e) {
                    post(new Runnable() {
                        public void run() {
                            done.failed(e.getMessage() == null ? "Something went wrong" : e.getMessage());
                        }
                    });
                }
            }
        });
    }

    public void addBuddy(final String sn, Done<Void> done) {
        background(new Work<Void>() {
            public Void run(Client c) throws IOException {
                c.addBuddy(sn);
                return null;
            }
        }, done);
    }

    public void removeBuddy(final String sn, Done<Void> done) {
        background(new Work<Void>() {
            public Void run(Client c) throws IOException {
                c.removeBuddy(sn);
                return null;
            }
        }, done);
    }

    // ------------------------------------------------------------------ chat rooms

    RoomChat roomChat(Client.Room r) {
        RoomChat rc = rooms.get(r.key);
        if (rc == null) {
            rc = new RoomChat(r);
            rooms.put(r.key, rc);
        }
        rc.room = r;
        return rc;
    }

    void note(RoomChat rc, String text) {
        rc.lines.add(new Line("", text, false, true, false));
    }

    private void dropInvites(String key) {
        for (int i = invites.size() - 1; i >= 0; i--) if (invites.get(i).room.key().equals(key)) invites.remove(i);
    }

    public void joinRoom(final String name, final Done<String> done) {
        background(new Work<Client.Room>() {
            public Client.Room run(Client c) throws IOException {
                return c.joinRoom(name);
            }
        }, new Done<Client.Room>() {
            public void ok(Client.Room r) {
                roomChat(r);
                dropInvites(r.key);
                done.ok(r.key);
            }

            public void failed(String m) {
                done.failed(m);
            }
        });
    }

    public void acceptInvite(final Rooms.Invite inv, final Done<String> done) {
        background(new Work<Client.Room>() {
            public Client.Room run(Client c) throws IOException {
                return c.acceptInvite(inv);
            }
        }, new Done<Client.Room>() {
            public void ok(Client.Room r) {
                roomChat(r);
                dropInvites(r.key);
                done.ok(r.key);
            }

            public void failed(String m) {
                done.failed(m);
            }
        });
    }

    public void declineInvite(Rooms.Invite inv) {
        invites.remove(inv);
        if (client != null) client.declineInvite(inv);
        changed();
    }

    public void inviteToRoom(final String key, final List<String> who, final String message, final Done<List<String>> done) {
        final String text = message.trim().length() == 0 ? "Join me in this Buddy Chat." : message.trim();
        background(new Work<List<String>>() {
            public List<String> run(Client c) throws IOException {
                return c.inviteToRoom(key, who, text);
            }
        }, new Done<List<String>>() {
            public void ok(List<String> failed) {
                RoomChat rc = rooms.get(key);
                List<String> sent = new ArrayList<String>(who);
                sent.removeAll(failed);
                if (rc != null && !sent.isEmpty()) note(rc, "Invited " + join(sent) + ".");
                done.ok(failed);
            }

            public void failed(String m) {
                done.failed(m);
            }
        });
    }

    public void leaveRoom(String key) {
        rooms.remove(key);
        if (key.equals(openRoom)) openRoom = null;
        if (client != null) client.leaveRoom(key);
        changed();
    }

    public void sendToRoom(String key, String text) {
        RoomChat rc = rooms.get(key);
        String t = text.trim();
        if (rc == null || t.length() == 0) return;
        if (client != null && client.sendToRoom(key, t)) {
            rc.lines.add(new Line(myName(), t, true, false, false));
        } else {
            note(rc, "Not sent: not connected to the room right now.");
        }
        changed();
    }

    public static String join(List<String> l) {
        StringBuilder sb = new StringBuilder();
        for (String s : l) {
            if (sb.length() > 0) sb.append(", ");
            sb.append(s);
        }
        return sb.toString();
    }
}
