package com.hatdagger.aimlite.oscar;

import java.io.DataInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.Timer;
import java.util.TimerTask;

/** One FLAP connection: a reader thread, blocking request/reply helpers, keep-alive. */
public final class Flap {

    public static final class Snac {
        public final int family;
        public final int subtype;
        public final int flags;
        public final long reqId;
        public final byte[] data;

        Snac(int family, int subtype, int flags, long reqId, byte[] data) {
            this.family = family;
            this.subtype = subtype;
            this.flags = flags;
            this.reqId = reqId;
            this.data = data;
        }

        public Bytes.Reader reader() {
            return new Bytes.Reader(data);
        }

        public boolean moreFollows() {
            return (flags & 0x0001) != 0;
        }

        static Snac parse(byte[] raw) {
            Bytes.Reader r = new Bytes.Reader(raw);
            int fam = r.u16();
            int sub = r.u16();
            int flags = r.u16();
            long req = r.u32();
            if ((flags & 0x8000) != 0 && r.remaining() >= 2) {
                int skip = r.u16();
                if (skip <= r.remaining()) r.pos += skip;
            }
            return new Snac(fam, sub, flags, req, r.rest());
        }
    }

    public interface Listener {
        void onSnac(Snac s);

        void onFrame(int channel, byte[] data);

        void onClosed(String reason);
    }

    /** Something to wait for: a SNAC (family/subtype pairs, optional request id) or a frame channel. */
    public final class Waiter {
        final int[] wanted;
        final long reqId;
        final int channel;
        private Object result;
        private boolean done;

        Waiter(int[] wanted, long reqId, int channel) {
            this.wanted = wanted;
            this.reqId = reqId;
            this.channel = channel;
        }

        synchronized boolean offer(Object o) {
            if (done) return false;
            result = o;
            done = true;
            notifyAll();
            return true;
        }

        /** Waits up to [ms]; throws on timeout or when the connection closes. */
        public Snac await(long ms) throws IOException {
            Object r = awaitAny(ms);
            if (r instanceof Snac) return (Snac) r;
            throw new IOException("unexpected reply");
        }

        public byte[] awaitFrame(long ms) throws IOException {
            Object r = awaitAny(ms);
            if (r instanceof byte[]) return (byte[]) r;
            throw new IOException("unexpected reply");
        }

        private Object awaitAny(long ms) throws IOException {
            long until = System.currentTimeMillis() + ms;
            synchronized (this) {
                while (!done) {
                    long left = until - System.currentTimeMillis();
                    if (left <= 0) break;
                    try {
                        wait(left);
                    } catch (InterruptedException e) {
                        break;
                    }
                }
                if (!done) {
                    done = true;
                    removeWaiter(this);
                    throw new TimeoutIOException("Timed out waiting for the server");
                }
            }
            if (result instanceof ClosedMarker) throw new ConnectionClosed(((ClosedMarker) result).reason);
            return result;
        }
    }

    public static class TimeoutIOException extends IOException {
        public TimeoutIOException(String m) {
            super(m);
        }
    }

    public static class ConnectionClosed extends IOException {
        public ConnectionClosed(String m) {
            super("Connection closed: " + m);
        }
    }

    private static final class ClosedMarker {
        final String reason;

        ClosedMarker(String r) {
            reason = r;
        }
    }

    private final Socket socket;
    private final DataInputStream in;
    private final OutputStream out;
    private final Object writeLock = new Object();
    private final List<Waiter> waiters = new ArrayList<Waiter>();
    private volatile Listener listener;
    private volatile boolean closed;
    private String closeReason;
    private int seq = new Random().nextInt(0x7fff);
    private long nextReq = 1 + new Random().nextInt(0x7fff);
    private Timer keepAlive;

    private Flap(Socket s) throws IOException {
        socket = s;
        in = new DataInputStream(s.getInputStream());
        out = s.getOutputStream();
        Thread t = new Thread(new Runnable() {
            public void run() {
                readLoop();
            }
        }, "flap-" + s.getPort());
        t.setDaemon(true);
        t.start();
    }

    public static Flap connect(String host, int port) throws IOException {
        Socket s = new Socket();
        s.connect(new InetSocketAddress(host, port), 15000);
        s.setTcpNoDelay(true);
        return new Flap(s);
    }

    public void setListener(Listener l) {
        listener = l;
        if (closed && l != null) l.onClosed(closeReason);
    }

    public boolean isClosed() {
        return closed;
    }

    public String localHost() {
        try {
            return socket.getLocalAddress().getHostAddress();
        } catch (Exception e) {
            return null;
        }
    }

    public synchronized long nextReqId() {
        nextReq = (nextReq + 1) & 0x7fffffffL;
        return nextReq;
    }

    // ---------------------------------------------------------------- reading

    private void readLoop() {
        String reason = "connection lost";
        try {
            while (true) {
                int star = in.readUnsignedByte();
                if (star != 0x2a) throw new IOException("bad FLAP start byte");
                int channel = in.readUnsignedByte();
                in.readUnsignedShort(); // seq
                int len = in.readUnsignedShort();
                byte[] data = new byte[len];
                in.readFully(data);
                if (channel == 2) {
                    Snac s;
                    try {
                        s = Snac.parse(data);
                    } catch (RuntimeException e) {
                        continue;
                    }
                    if (!deliverSnac(s)) {
                        Listener l = listener;
                        if (l != null) {
                            try {
                                l.onSnac(s);
                            } catch (RuntimeException e) {
                                // one bad packet shouldn't end the session
                            }
                        }
                    }
                } else {
                    if (!deliverFrame(channel, data)) {
                        Listener l = listener;
                        if (l != null) l.onFrame(channel, data);
                    }
                }
            }
        } catch (IOException e) {
            if (!closed) reason = "connection lost";
        }
        finish(reason);
    }

    private boolean deliverSnac(Snac s) {
        synchronized (waiters) {
            for (int i = 0; i < waiters.size(); i++) {
                Waiter w = waiters.get(i);
                if (w.wanted == null) continue;
                if (w.reqId >= 0 && s.reqId != w.reqId && s.subtype != 0x01) continue;
                for (int k = 0; k + 1 < w.wanted.length; k += 2) {
                    if (s.family == w.wanted[k] && s.subtype == w.wanted[k + 1]) {
                        waiters.remove(i);
                        w.offer(s);
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private boolean deliverFrame(int channel, byte[] data) {
        synchronized (waiters) {
            for (int i = 0; i < waiters.size(); i++) {
                Waiter w = waiters.get(i);
                if (w.wanted == null && w.channel == channel) {
                    waiters.remove(i);
                    w.offer(data);
                    return true;
                }
            }
        }
        return false;
    }

    void removeWaiter(Waiter w) {
        synchronized (waiters) {
            waiters.remove(w);
        }
    }

    /** Register BEFORE sending the request. pairs = family, subtype, family, subtype... */
    public Waiter expect(long reqId, int... pairs) throws IOException {
        Waiter w = new Waiter(pairs, reqId, -1);
        synchronized (waiters) {
            if (closed) throw new ConnectionClosed(closeReason);
            waiters.add(w);
        }
        return w;
    }

    public Waiter expectFrame(int channel) throws IOException {
        Waiter w = new Waiter(null, -1, channel);
        synchronized (waiters) {
            if (closed) throw new ConnectionClosed(closeReason);
            waiters.add(w);
        }
        return w;
    }

    // ---------------------------------------------------------------- writing

    public void send(int channel, byte[] data) throws IOException {
        synchronized (writeLock) {
            if (closed) throw new ConnectionClosed(closeReason);
            seq = (seq + 1) & 0xffff;
            byte[] head = new byte[] {0x2a, (byte) channel, (byte) (seq >> 8), (byte) seq,
                    (byte) (data.length >> 8), (byte) data.length};
            try {
                out.write(head);
                out.write(data);
                out.flush();
            } catch (IOException e) {
                finish("connection lost");
                throw e;
            }
        }
    }

    public long sendSnac(int family, int subtype, byte[] data) throws IOException {
        return sendSnac(family, subtype, data, nextReqId());
    }

    public long sendSnac(int family, int subtype, byte[] data, long reqId) throws IOException {
        Bytes.Writer w = new Bytes.Writer().u16(family).u16(subtype).u16(0).u32(reqId).bytes(data);
        send(2, w.toBytes());
        return reqId;
    }

    public void startKeepAlive() {
        synchronized (writeLock) {
            if (keepAlive != null || closed) return;
            keepAlive = new Timer("flap-keepalive", true);
        }
        keepAlive.schedule(new TimerTask() {
            public void run() {
                try {
                    send(5, new byte[0]);
                } catch (IOException e) {
                    cancel();
                }
            }
        }, 50000, 50000);
    }

    // ---------------------------------------------------------------- closing

    private void finish(String reason) {
        List<Waiter> pending;
        synchronized (waiters) {
            if (closed) return;
            closed = true;
            closeReason = reason;
            pending = new ArrayList<Waiter>(waiters);
            waiters.clear();
        }
        Timer k = keepAlive;
        if (k != null) k.cancel();
        try {
            socket.close();
        } catch (IOException ignored) {
        }
        for (Waiter w : pending) w.offer(new ClosedMarker(reason));
        Listener l = listener;
        if (l != null) l.onClosed(reason);
    }

    /** Polite sign-off (channel 4), then close. */
    public void close() {
        if (closed) return;
        try {
            send(4, new byte[0]);
        } catch (IOException ignored) {
        }
        finish("closed by client");
    }

    /** Drop the link without signing off (tests). */
    public void kill() {
        finish("killed");
    }
}
