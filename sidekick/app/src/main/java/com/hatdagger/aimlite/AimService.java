package com.hatdagger.aimlite;

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

/**
 * Runs while you're signed on so Android doesn't close AIM in the background.
 * Holds Wi-Fi awake (the Sidekick turns Wi-Fi off when the screen sleeps) and
 * reconnects as soon as the network comes back.
 */
public final class AimService extends Service {
    private WifiManager.WifiLock wifiLock;
    private PowerManager.WakeLock wakeLock;

    private final BroadcastReceiver netChanged = new BroadcastReceiver() {
        @Override
        public void onReceive(Context c, Intent i) {
            ConnectivityManager cm = (ConnectivityManager) c.getSystemService(Context.CONNECTIVITY_SERVICE);
            NetworkInfo ni = cm == null ? null : cm.getActiveNetworkInfo();
            AimApp app = AimApp.get();
            if (ni != null && ni.isConnected() && app.client != null) app.client.retryNow();
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        registerReceiver(netChanged, new IntentFilter(ConnectivityManager.CONNECTIVITY_ACTION));
        WifiManager wm = (WifiManager) getSystemService(Context.WIFI_SERVICE);
        if (wm != null) {
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL, "aim");
            wifiLock.acquire();
        }
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (pm != null) {
            // Keeps the keep-alive and incoming messages flowing with the screen off.
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "aim");
            wakeLock.acquire();
        }
        startForeground(Notifier.ONGOING, AimApp.get().notifier().ongoing());
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
        if (wifiLock != null && wifiLock.isHeld()) wifiLock.release();
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        stopForeground(true);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
