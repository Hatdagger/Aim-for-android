package com.hatdagger.aimlite;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;

import com.hatdagger.aimlite.oscar.Bytes;
import com.hatdagger.aimlite.oscar.Client;
import com.hatdagger.aimlite.oscar.Models;
import com.hatdagger.aimlite.oscar.Session;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Buddies' icons: downloaded once from the server's icon service, kept on the
 * phone by picture id, so a buddy who keeps the same icon costs nothing next
 * time. Main thread only, except the download itself.
 */
final class BuddyIcons {
    private final Context ctx;
    private final File dir;
    /** Buddy (normalised) -> picture id. */
    private final Map<String, String> whose = new HashMap<String, String>();
    /** Picture id -> picture. */
    private final Map<String, Bitmap> pictures = new HashMap<String, Bitmap>();
    private final Set<String> fetching = new HashSet<String>();
    private final Set<String> failed = new HashSet<String>();
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    BuddyIcons(Context ctx) {
        this.ctx = ctx;
        dir = new File(ctx.getCacheDir(), "icons");
        dir.mkdirs();
    }

    /** A buddy signed on or changed: note their icon and fetch it if we don't have it. */
    void wanted(Models.UserInfo u) {
        String k = Bytes.normalizeSn(u.screenName);
        // A 1-byte or blank id means "no icon".
        if (u.iconHash == null || u.iconHash.length < 4) {
            whose.remove(k);
            return;
        }
        final String id = hex(u.iconHash);
        whose.put(k, id);
        if (pictures.containsKey(id) || fetching.contains(id) || failed.contains(id)) return;
        final File f = new File(dir, id);
        if (f.exists()) {
            Bitmap b = decode(read(f));
            if (b != null) {
                pictures.put(id, b);
                return;
            }
        }
        final AimApp app = AimApp.get();
        final Client c = app.client;
        if (c == null) return;
        final String sn = u.screenName;
        final byte[] hash = u.iconHash;
        final int flags = u.iconFlags;
        fetching.add(id);
        worker.execute(new Runnable() {
            public void run() {
                byte[] data = null;
                try {
                    Session s = c.session();
                    if (s != null && s.isOnline()) data = s.fetchBuddyIcon(sn, hash, flags);
                } catch (Exception ignored) {
                }
                final byte[] got = data;
                final Bitmap pic = got == null ? null : decode(got);
                if (pic != null) write(f, got);
                app.post(new Runnable() {
                    public void run() {
                        fetching.remove(id);
                        if (pic != null) pictures.put(id, pic);
                        else failed.add(id); // don't keep asking for a broken one this session
                        app.changed();
                    }
                });
            }
        });
    }

    /** The buddy's icon at [sizeDp], or null. */
    Drawable icon(String sn, int sizeDp) {
        String id = whose.get(Bytes.normalizeSn(sn));
        Bitmap b = id == null ? null : pictures.get(id);
        if (b == null) return null;
        int px = Ui.dp(ctx, sizeDp);
        BitmapDrawable d = new BitmapDrawable(ctx.getResources(), b);
        d.setBounds(0, 0, px, px);
        return d;
    }

    void clear() {
        whose.clear();
        failed.clear();
    }

    private static Bitmap decode(byte[] data) {
        if (data == null) return null;
        try {
            return BitmapFactory.decodeByteArray(data, 0, data.length);
        } catch (Throwable e) {
            return null;
        }
    }

    private static byte[] read(File f) {
        try {
            FileInputStream in = new FileInputStream(f);
            byte[] b = new byte[(int) f.length()];
            int n = 0;
            while (n < b.length) {
                int r = in.read(b, n, b.length - n);
                if (r < 0) break;
                n += r;
            }
            in.close();
            return b;
        } catch (Exception e) {
            return null;
        }
    }

    private static void write(File f, byte[] b) {
        try {
            FileOutputStream out = new FileOutputStream(f);
            out.write(b);
            out.close();
        } catch (Exception ignored) {
        }
    }

    private static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x & 0xff));
        return sb.toString();
    }
}
