package com.hatdagger.aimlite;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.net.wifi.WifiManager;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.SystemClock;

/**
 * Runs while you're signed on so Android doesn't close AIM in the background.
 *
 * Battery: with the screen on, the Sidekick stays awake and messages are
 * instant. With the screen off it's allowed to sleep; Wi-Fi stays connected
 * (the Sidekick would otherwise turn it off), so a message coming in can
 * still wake it, and every 30 minutes an alarm wakes it to check the link is
 * alive, reconnect if not, and send anything waiting.
 */
public final class AimService extends Service {
    /** How often to check in while the screen is off. */
    static final long CHECK_IN_EVERY = AlarmManager.INTERVAL_HALF_HOUR;

    private WifiManager.WifiLock wifiLock;
    private PowerManager.WakeLock screenOnLock;
    private PendingIntent checkInAlarm;

    private final BroadcastReceiver netChanged = new BroadcastReceiver() {
        @Override
        public void onReceive(Context c, Intent i) {
            ConnectivityManager cm = (ConnectivityManager) c.getSystemService(Context.CONNECTIVITY_SERVICE);
            NetworkInfo ni = cm == null ? null : cm.getActiveNetworkInfo();
            AimApp app = AimApp.get();
            if (ni != null && ni.isConnected() && app.client != null) {
                app.stayAwake(60000); // long enough to reconnect
                app.client.retryNow();
            }
        }
    };

    private final BroadcastReceiver screen = new BroadcastReceiver() {
        @Override
        public void onReceive(Context c, Intent i) {
            if (Intent.ACTION_SCREEN_ON.equals(i.getAction())) screenOn();
            else screenOff();
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        registerReceiver(netChanged, new IntentFilter(ConnectivityManager.CONNECTIVITY_ACTION));
        IntentFilter f = new IntentFilter(Intent.ACTION_SCREEN_ON);
        f.addAction(Intent.ACTION_SCREEN_OFF);
        registerReceiver(screen, f);
        WifiManager wm = (WifiManager) getSystemService(Context.WIFI_SERVICE);
        if (wm != null) {
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL, "aim");
            wifiLock.setReferenceCounted(false);
            wifiLock.acquire();
        }
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (pm != null) {
            screenOnLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "aim-screen-on");
            screenOnLock.setReferenceCounted(false);
        }
        Intent alarm = new Intent(this, CheckInReceiver.class);
        checkInAlarm = PendingIntent.getBroadcast(this, 0, alarm, 0);
        startForeground(Notifier.ONGOING, AimApp.get().notifier().ongoing());
        if (pm == null || pm.isScreenOn()) screenOn();
        else screenOff();
    }

    /** Screen on: stay awake, stop the timer, and make sure we're really connected. */
    private void screenOn() {
        alarms().cancel(checkInAlarm);
        if (screenOnLock != null) screenOnLock.acquire();
        CheckInReceiver.checkInSoon(this);
    }

    /** Screen off: let the Sidekick sleep and check in every half hour. */
    private void screenOff() {
        alarms().setInexactRepeating(AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + CHECK_IN_EVERY, CHECK_IN_EVERY, checkInAlarm);
        if (screenOnLock != null && screenOnLock.isHeld()) screenOnLock.release();
    }

    private AlarmManager alarms() {
        return (AlarmManager) getSystemService(Context.ALARM_SERVICE);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // Android restarted us after closing the app: sign back on, or stop.
        AimApp app = AimApp.get();
        if (!app.signedOn() && !app.autoSignOn()) {
            stopSelf();
            return START_NOT_STICKY;
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        unregisterReceiver(netChanged);
        unregisterReceiver(screen);
        alarms().cancel(checkInAlarm);
        if (wifiLock != null && wifiLock.isHeld()) wifiLock.release();
        if (screenOnLock != null && screenOnLock.isHeld()) screenOnLock.release();
        stopForeground(true);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
