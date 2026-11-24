package com.hatdagger.aimlite;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import com.hatdagger.aimlite.oscar.Client;

/**
 * The half-hourly alarm while the screen is off. Keeps the Sidekick awake just
 * long enough to check the link, reconnect if needed and send what's waiting,
 * then lets it sleep again.
 */
public final class CheckInReceiver extends BroadcastReceiver {
    /** At most this long awake per check-in. */
    private static final long AWAKE_FOR = 60000;

    @Override
    public void onReceive(Context c, Intent i) {
        checkInSoon(c);
    }

    static void checkInSoon(Context c) {
        final AimApp app = AimApp.get();
        final Client client = app.client;
        if (client == null) return;
        app.stayAwake(AWAKE_FOR);
        Thread t = new Thread(new Runnable() {
            public void run() {
                client.checkIn(15000);
                // Reconnecting: give it a chance to finish while we're awake.
                long until = System.currentTimeMillis() + AWAKE_FOR - 5000;
                while (System.currentTimeMillis() < until && app.client == client
                        && client.state() != Client.State.ONLINE && client.state() != Client.State.STOPPED
                        && client.state() != Client.State.OFFLINE) {
                    try {
                        Thread.sleep(500);
                    } catch (InterruptedException e) {
                        break;
                    }
                }
                // A moment for queued messages to go out and replies to come in.
                try {
                    Thread.sleep(3000);
                } catch (InterruptedException ignored) {
                }
                app.letSleep();
            }
        }, "aim-check-in");
        t.setDaemon(true);
        t.start();
    }
}
