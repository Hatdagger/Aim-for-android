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
