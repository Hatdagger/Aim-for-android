package com.hatdagger.aimlite;

import android.app.AlertDialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.InputType;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Small helpers for building the classic-AIM-looking screens in code. */
final class Ui {
    private Ui() {}

    static final int FACE = 0xFFD4D0C8;
    static final int TITLE = 0xFF0A246A;
    static final int YELLOW = 0xFFFFCC00;
    static final int MY_NAME = 0xFFC00000;
    static final int THEIR_NAME = 0xFF0000C0;

    /** The trackball highlight on a button: pale blue with a navy frame (pressed: darker). */
    static android.graphics.drawable.Drawable selectable(Context c) {
        android.graphics.drawable.StateListDrawable d = new android.graphics.drawable.StateListDrawable();
        int w = dp(c, 2);
        android.graphics.drawable.GradientDrawable pressed = new android.graphics.drawable.GradientDrawable();
        pressed.setColor(0xFF9DB8EC);
        pressed.setStroke(w, TITLE);
        pressed.setCornerRadius(dp(c, 3));
        android.graphics.drawable.GradientDrawable focused = new android.graphics.drawable.GradientDrawable();
        focused.setColor(0xFFD6E2FA);
        focused.setStroke(w, TITLE);
        focused.setCornerRadius(dp(c, 3));
        d.addState(new int[] {android.R.attr.state_pressed}, pressed);
        d.addState(new int[] {android.R.attr.state_focused}, focused);
        d.addState(new int[0], new android.graphics.drawable.ColorDrawable(0));
        return d;
    }

    /** Selected row in a list: AIM's navy bar with white text. */
    static final int SELECTED = TITLE;

    static int dp(Context c, int v) {
        return (int) (v * c.getResources().getDisplayMetrics().density + 0.5f);
    }

    static LinearLayout.LayoutParams fill() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.FILL_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    static LinearLayout.LayoutParams weight(float w) {
        return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, w);
    }

    static LinearLayout.LayoutParams grow() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.FILL_PARENT, 0, 1f);
    }

    static LinearLayout column(Context c) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setBackgroundColor(FACE);
        return l;
    }

    static LinearLayout row(Context c) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.HORIZONTAL);
        l.setGravity(Gravity.CENTER_VERTICAL);
        return l;
    }

    /** The blue window title bar. */
    static TextView titleBar(Context c, String text) {
        TextView t = new TextView(c);
        t.setText(text);
        t.setBackgroundColor(TITLE);
        t.setTextColor(Color.WHITE);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextSize(16);
        t.setSingleLine(true);
        int p = dp(c, 6);
        t.setPadding(p, p, p, p);
        return t;
    }

    static TextView label(Context c, String text) {
        TextView t = new TextView(c);
        t.setText(text);
        t.setTextColor(Color.BLACK);
        t.setTextSize(14);
        return t;
    }

    /** A yellow-on-amber strip for "reconnecting" and similar notes. */
    static TextView banner(Context c) {
        TextView t = label(c, "");
        t.setBackgroundColor(0xFFFFE0A0);
        int p = dp(c, 5);
        t.setPadding(p, p, p, p);
        return t;
    }

    static Button button(Context c, String text) {
        Button b = new Button(c);
        b.setText(text);
        b.setTextSize(14);
        return b;
    }

    static EditText field(Context c, String hint, boolean password) {
        EditText e = new EditText(c);
        e.setHint(hint);
        e.setSingleLine(true);
        if (password) {
            e.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        } else {
            e.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        }
        return e;
    }

    static void message(Context c, String title, String text) {
        new AlertDialog.Builder(c).setTitle(title).setMessage(text).setPositiveButton("OK", null).show();
    }

    /** Get Info: their icon, status, away message and profile. */
    static void getInfo(final android.app.Activity a, final String sn) {
        final android.app.ProgressDialog wait = android.app.ProgressDialog.show(a, sn, "Getting info...", true, true);
        AimApp.get().getInfo(sn, new AimApp.Done<com.hatdagger.aimlite.oscar.Session.Profile>() {
            public void ok(com.hatdagger.aimlite.oscar.Session.Profile p) {
                wait.dismiss();
                if (a.isFinishing()) return;
                StringBuilder sb = new StringBuilder();
                com.hatdagger.aimlite.oscar.Models.UserInfo u = p.user;
                if (u != null) {
                    String st = u.isAway() ? "Away" : u.idleMinutes > 0 ? "Idle " + idle(u.idleMinutes) : "Online";
                    sb.append("Status: ").append(st).append('\n');
                    if (u.onlineSince > 0) {
                        long mins = (System.currentTimeMillis() / 1000 - u.onlineSince) / 60;
                        if (mins >= 0) sb.append("Online for: ").append(idle((int) mins)).append('\n');
                    }
                    if (u.warningLevel > 0) sb.append("Warning level: ").append(Math.round(u.warningLevel / 10.0)).append("%\n");
                }
                if (p.away != null && p.away.trim().length() > 0) sb.append("\nAway message:\n").append(p.away.trim()).append('\n');
                sb.append("\nProfile:\n").append(p.profile == null || p.profile.trim().length() == 0
                        ? "(no profile)" : p.profile.trim());
                TextView t = label(a, sb.toString());
                int pad = dp(a, 10);
                t.setPadding(pad, pad, pad, pad);
                android.widget.ScrollView sv = new android.widget.ScrollView(a);
                sv.setBackgroundColor(Color.WHITE);
                sv.addView(t);
                AlertDialog.Builder b = new AlertDialog.Builder(a).setTitle(p.screenName).setView(sv)
                        .setPositiveButton("OK", null);
                android.graphics.drawable.Drawable icon = AimApp.get().icons.icon(p.screenName, 32);
                if (icon != null) b.setIcon(icon);
                b.show();
            }

            public void failed(String m) {
                wait.dismiss();
                if (!a.isFinishing()) message(a, "Get Info", m);
            }
        });
    }

    static String idle(int mins) {
        if (mins < 60) return mins + " min";
        if (mins < 60 * 24) return (mins / 60) + " hr " + (mins % 60) + " min";
        return (mins / (60 * 24)) + " days";
    }

    interface OnText {
        void text(String s);
    }

    /** One-line question ("Screen name?"). */
    static void ask(Context c, String title, String hint, String initial, final OnText ok) {
        final EditText e = field(c, hint, false);
        e.setText(initial);
        e.setSelection(e.getText().length());
        new AlertDialog.Builder(c).setTitle(title).setView(e)
                .setPositiveButton("OK", new android.content.DialogInterface.OnClickListener() {
                    public void onClick(android.content.DialogInterface d, int w) {
                        String s = e.getText().toString().trim();
                        if (s.length() > 0) ok.text(s);
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }
}
