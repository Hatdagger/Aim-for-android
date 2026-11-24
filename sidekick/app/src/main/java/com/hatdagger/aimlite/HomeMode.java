package com.hatdagger.aimlite;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.text.InputType;
import android.text.method.PasswordTransformationMethod;
import android.widget.EditText;
import android.widget.LinearLayout;

import java.security.MessageDigest;

/**
 * "AIM is the home screen": the Home key and turning the Sidekick on both
 * land in AIM. Leaving takes the PIN set when it was turned on.
 *
 * Android 2.2 has no real lockdown without root, so this keeps honest people
 * in AIM; it isn't a lock against someone who knows Android well.
 */
final class HomeMode {
    private HomeMode() {}

    private static final String ALIAS = "com.hatdagger.aimlite.HomeScreen";
    private static final int MAX_TRIES = 3;
    private static final long LOCKOUT_MS = 30000;
    private static int wrongTries;
    private static long lockedUntil;

    static boolean isOn(Context c) {
        return AimApp.get().prefs().getBoolean("homeMode", false);
    }

    /** Setup menu: turn it on (choose a PIN) or off (enter the PIN). */
    static void fromSetup(Activity a) {
        if (isOn(a)) askToLeave(a);
        else askToTurnOn(a);
    }

    private static EditText pinField(Context c, String hint) {
        EditText e = Ui.field(c, hint, false);
        e.setInputType(InputType.TYPE_CLASS_NUMBER);
        e.setTransformationMethod(PasswordTransformationMethod.getInstance());
        return e;
    }

    private static void askToTurnOn(final Activity a) {
        LinearLayout box = Ui.column(a);
        int p = Ui.dp(a, 8);
        box.setPadding(p, p, p, p);
        box.addView(Ui.label(a, "The Home key and turning the Sidekick on will open AIM. "
                + "Leaving AIM will need a PIN.\n\nChoose a PIN (4 to 8 numbers):"));
        final EditText pin = pinField(a, "PIN");
        final EditText again = pinField(a, "PIN again");
        box.addView(pin, Ui.fill());
        box.addView(again, Ui.fill());
        new AlertDialog.Builder(a).setTitle("Make AIM the Home Screen").setView(box)
                .setPositiveButton("Turn On", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        String one = pin.getText().toString();
                        if (one.length() < 4 || one.length() > 8) {
                            Ui.message(a, "Home Screen", "The PIN needs 4 to 8 numbers. Nothing was changed.");
                        } else if (!one.equals(again.getText().toString())) {
                            Ui.message(a, "Home Screen", "The two PINs didn't match. Nothing was changed.");
                        } else {
                            turnOn(a, one);
                        }
                    }
                })
                .setNegativeButton("Cancel", null).show();
    }

    private static void turnOn(final Activity a, String pin) {
        AimApp.get().prefs().edit().putBoolean("homeMode", true).putString("homePin", hash(pin)).commit();
        a.getPackageManager().setComponentEnabledSetting(new ComponentName(a, ALIAS),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP);
        new AlertDialog.Builder(a).setTitle("One last step")
                .setMessage("Android will now ask which Home screen to use.\n\n"
                        + "Tick \"Use by default for this action\", then pick AIM Lite.")
                .setPositiveButton("OK", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        goHome(a);
                    }
                }).show();
    }

    private static void askToLeave(final Activity a) {
        long wait = lockedUntil - System.currentTimeMillis();
        if (wait > 0) {
            Ui.message(a, "Leave AIM", "Too many wrong PINs. Try again in " + (wait / 1000 + 1) + " seconds.");
            return;
        }
        final EditText pin = pinField(a, "PIN");
        new AlertDialog.Builder(a).setTitle("Leave AIM").setMessage("Enter the PIN to turn off home screen mode.")
                .setView(pin)
                .setPositiveButton("Leave", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        SharedPreferences p = AimApp.get().prefs();
                        if (hash(pin.getText().toString()).equals(p.getString("homePin", ""))) {
                            wrongTries = 0;
                            turnOff(a);
                        } else if (++wrongTries >= MAX_TRIES) {
                            wrongTries = 0;
                            lockedUntil = System.currentTimeMillis() + LOCKOUT_MS;
                            Ui.message(a, "Leave AIM", "Wrong PIN. Try again in 30 seconds.");
                        } else {
                            Ui.message(a, "Leave AIM", "Wrong PIN.");
                        }
                    }
                })
                .setNegativeButton("Cancel", null).show();
    }

    private static void turnOff(Activity a) {
        AimApp.get().prefs().edit().putBoolean("homeMode", false).remove("homePin").commit();
        PackageManager pm = a.getPackageManager();
        pm.clearPackagePreferredActivities(a.getPackageName());
        pm.setComponentEnabledSetting(new ComponentName(a, ALIAS),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP);
        goHome(a);
    }

    private static void goHome(Activity a) {
        Intent i = new Intent(Intent.ACTION_MAIN);
        i.addCategory(Intent.CATEGORY_HOME);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            a.startActivity(i);
        } catch (Exception ignored) {
        }
    }

    private static String hash(String pin) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-1").digest(("aimlite-home:" + pin).getBytes("UTF-8"));
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format("%02x", b & 0xff));
            return sb.toString();
        } catch (Exception e) {
            return pin;
        }
    }
}
