package com.hatdagger.aimlite;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;

import com.hatdagger.aimlite.oscar.Client;

import java.lang.reflect.Method;

/**
 * Status-bar notifications the Android 2.2 way. setLatestEventInfo is gone
 * from today's SDK but is what Android 2.2 has, so it's called by name.
 */
public final class Notifier {
    static final int ONGOING = 1;
    static final int MESSAGES = 2;

    private final Context ctx;
    private final NotificationManager nm;
    private String lastTicker;

    Notifier(Context ctx) {
        this.ctx = ctx;
        this.nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
    }

    private PendingIntent openApp() {
        Intent i = new Intent(ctx, BuddyListActivity.class);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(ctx, 0, i, PendingIntent.FLAG_UPDATE_CURRENT);
    }

    static Notification build(Context ctx, String ticker, String title, String text, PendingIntent pi) {
        Notification n = new Notification();
        n.icon = R.drawable.icon;
        n.tickerText = ticker;
        n.when = System.currentTimeMillis();
        n.contentIntent = pi;
        try {
            Method m = Notification.class.getMethod("setLatestEventInfo", Context.class, CharSequence.class,
                    CharSequence.class, PendingIntent.class);
            m.invoke(n, ctx, title, text, pi);
        } catch (Exception ignored) {
            // Not on Android 2.2: the ticker still shows.
        }
        return n;
    }

    /** The "Signed on as ..." notification that keeps AIM running. */
    Notification ongoing() {
        AimApp app = AimApp.get();
        String text;
        if (app.state == Client.State.ONLINE) {
            text = app.client != null && app.client.isAway() ? "Away" : "Online";
        } else if (app.state == Client.State.STOPPED) {
            text = "Signed off";
        } else {
            text = "Reconnecting...";
        }
        Notification n = build(ctx, null, "AIM Lite: " + app.myName(), text, openApp());
        n.flags |= Notification.FLAG_ONGOING_EVENT | Notification.FLAG_NO_CLEAR;
        return n;
    }

    /** A new IM or invite while AIM isn't on screen. */
    void message(String from, String text) {
        AimApp app = AimApp.get();
        if (app.isVisible() && app.openConv != null) {
            // Someone else is talking while you're in a chat: a short buzz is enough.
            vibrate();
            return;
        }
        int n = app.totalUnread();
        String ticker = from + ": " + text;
        lastTicker = ticker;
        Notification note = build(ctx, ticker, n <= 1 ? from : n + " new messages", text, openApp());
        note.defaults |= Notification.DEFAULT_SOUND | Notification.DEFAULT_VIBRATE;
        note.flags |= Notification.FLAG_AUTO_CANCEL | Notification.FLAG_SHOW_LIGHTS;
        note.ledARGB = 0xffffcc00;
        note.ledOnMS = 300;
        note.ledOffMS = 2000;
        note.number = n;
        nm.notify(MESSAGES, note);
    }

    private void vibrate() {
        try {
            android.os.Vibrator v = (android.os.Vibrator) ctx.getSystemService(Context.VIBRATOR_SERVICE);
            if (v != null) v.vibrate(80);
        } catch (Exception ignored) {
        }
    }

    /** Keeps the status bar in step: clears read messages, updates the ongoing line. */
    void refresh() {
        AimApp app = AimApp.get();
        if (app.totalUnread() == 0) nm.cancel(MESSAGES);
        if (app.signedOn()) nm.notify(ONGOING, ongoing());
    }

    void clearMessages() {
        nm.cancel(MESSAGES);
        nm.cancel(ONGOING);
        lastTicker = null;
    }
}
