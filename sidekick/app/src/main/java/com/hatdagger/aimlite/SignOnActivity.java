package com.hatdagger.aimlite;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.hatdagger.aimlite.oscar.Client;

/** Sign On window: server, screen name, password. Laid out for the sideways screen. */
public final class SignOnActivity extends Activity {
    private EditText server, sn, pw;
    private CheckBox savePw, auto;
    private TextView status;
    private Button go;
    private AimApp app;
    private final Runnable refresh = new Runnable() {
        public void run() {
            update();
        }
    };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        app = AimApp.get();
        SharedPreferences p = app.prefs();

        LinearLayout root = Ui.column(this);
        root.addView(Ui.titleBar(this, "Sign On"), Ui.fill());

        // Landscape: logo on the left, the form on the right.
        LinearLayout body = Ui.row(this);
        body.setGravity(Gravity.TOP);
        int pad = Ui.dp(this, 8);
        body.setPadding(pad, pad, pad, pad);

        LinearLayout logo = Ui.column(this);
        logo.setGravity(Gravity.CENTER_HORIZONTAL);
        ImageView icon = new ImageView(this);
        icon.setImageResource(R.drawable.icon);
        logo.addView(icon);
        TextView name = Ui.label(this, "AIM Lite");
        name.setTypeface(Typeface.DEFAULT_BOLD);
        name.setTextSize(20);
        name.setGravity(Gravity.CENTER);
        logo.addView(name);
        TextView sub = Ui.label(this, "for the Sidekick");
        sub.setGravity(Gravity.CENTER);
        logo.addView(sub);
        body.addView(logo, new LinearLayout.LayoutParams(Ui.dp(this, 130), LinearLayout.LayoutParams.WRAP_CONTENT));

        LinearLayout form = Ui.column(this);
        form.addView(Ui.label(this, "Server"));
        server = Ui.field(this, "server address (e.g. 192.168.1.20:5190)", false);
        server.setText(p.getString("server", ""));
        form.addView(server, Ui.fill());
        LinearLayout names = Ui.row(this);
        LinearLayout snCol = Ui.column(this);
        snCol.addView(Ui.label(this, "Screen Name"));
        sn = Ui.field(this, "screen name", false);
        sn.setText(p.getString("sn", ""));
        snCol.addView(sn, Ui.fill());
        LinearLayout pwCol = Ui.column(this);
        pwCol.addView(Ui.label(this, "Password"));
        pw = Ui.field(this, "password", true);
        pw.setText(p.getString("pw", ""));
        pw.setImeOptions(EditorInfo.IME_ACTION_GO);
        pw.setOnEditorActionListener(new TextView.OnEditorActionListener() {
            public boolean onEditorAction(TextView v, int id, KeyEvent e) {
                signOn();
                return true;
            }
        });
        pwCol.addView(pw, Ui.fill());
        names.addView(snCol, Ui.weight(1));
        names.addView(pwCol, Ui.weight(1));
        form.addView(names, Ui.fill());

        LinearLayout opts = Ui.row(this);
        savePw = new CheckBox(this);
        savePw.setText("Save password");
        savePw.setTextColor(Color.BLACK);
        savePw.setChecked(p.getBoolean("savePw", true));
        auto = new CheckBox(this);
        auto.setText("Auto sign on");
        auto.setTextColor(Color.BLACK);
        auto.setChecked(p.getBoolean("autoLogin", false));
        opts.addView(savePw);
        opts.addView(auto);
        go = Ui.button(this, "Sign On");
        go.setTypeface(Typeface.DEFAULT_BOLD);
        go.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                signOn();
            }
        });
        opts.addView(new View(this), Ui.weight(1));
        opts.addView(go, new LinearLayout.LayoutParams(Ui.dp(this, 120), LinearLayout.LayoutParams.WRAP_CONTENT));
        form.addView(opts, Ui.fill());

        status = Ui.label(this, "");
        form.addView(status, Ui.fill());
        body.addView(form, Ui.weight(1));

        ScrollView scroll = new ScrollView(this);
        scroll.addView(body);
        root.addView(scroll, Ui.grow());
        setContentView(root);

        // Opened from the launcher while already signed on: go to the list.
        if (app.signedOn() && app.everOnline) {
            openBuddyList();
            return;
        }
        if (b == null && !app.signedOn() && app.autoSignOn()) update();
    }

    private void signOn() {
        String s = server.getText().toString().trim();
        String n = sn.getText().toString().trim();
        String w = pw.getText().toString();
        if (s.length() == 0 || n.length() == 0 || w.length() == 0) {
            status.setText("Fill in the server, your screen name and password.");
            return;
        }
        app.prefs().edit()
                .putString("server", s)
                .putString("sn", n)
                .putString("pw", savePw.isChecked() ? w : "")
                .putBoolean("savePw", savePw.isChecked())
                .putBoolean("autoLogin", auto.isChecked() && savePw.isChecked())
                .commit();
        app.signOn(s, n, w);
    }

    private void update() {
        if (app.client == null) {
            go.setEnabled(true);
            if (app.state == Client.State.STOPPED && app.stateMessage != null) status.setText(app.stateMessage);
            return;
        }
        switch (app.state) {
            case ONLINE:
                openBuddyList();
                return;
            case STOPPED:
                status.setText(app.stateMessage == null ? "Signed off." : app.stateMessage);
                go.setEnabled(true);
                return;
            case CONNECTING:
                status.setText("Connecting...");
                go.setEnabled(false);
                return;
            case RECONNECTING:
                status.setText("Trying again... " + (app.stateMessage == null ? "" : "(" + app.stateMessage + ")"));
                go.setEnabled(true);
                return;
            default:
                go.setEnabled(true);
        }
    }

    private void openBuddyList() {
        startActivity(new Intent(this, BuddyListActivity.class));
        finish();
    }

    /** As the home screen, Back has nowhere to go; Menu > Leave Home Screen Mode does. */
    @Override
    public boolean onKeyDown(int code, KeyEvent e) {
        if (code == KeyEvent.KEYCODE_BACK && HomeMode.isOn(this)) return true;
        return super.onKeyDown(code, e);
    }

    @Override
    public boolean onCreateOptionsMenu(Menu m) {
        m.add(0, 1, 0, "Leave Home Screen Mode");
        return true;
    }

    @Override
    public boolean onPrepareOptionsMenu(Menu m) {
        return HomeMode.isOn(this);
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == 1) {
            HomeMode.fromSetup(this);
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    @Override
    protected void onResume() {
        super.onResume();
        app.observe(refresh);
        app.setVisible(true);
        update();
    }

    @Override
    protected void onPause() {
        app.unobserve(refresh);
        app.setVisible(false);
        super.onPause();
    }
}
