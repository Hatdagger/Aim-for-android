package com.hatdagger.aimlite;

import android.view.Menu;
import android.view.MenuItem;

import com.hatdagger.aimlite.oscar.Models;

import java.util.List;

/** A one-to-one Instant Message window. */
public final class ImActivity extends ChatActivity {
    private String sn;

    private String sn() {
        if (sn == null) sn = getIntent().getStringExtra("sn");
        return sn;
    }

    @Override
    protected List<AimApp.Line> lines() {
        return app.client == null ? null : app.conv(sn()).lines;
    }

    @Override
    protected String titleText() {
        return app.conv(sn()).name + " - Instant Message";
    }

    @Override
    protected String subText() {
        AimApp.Conv c = app.conv(sn());
        Models.UserInfo u = app.onlineInfo(sn());
        String s;
        if (u == null) s = "Offline - messages wait until they sign on";
        else if (u.isAway()) s = "Away";
        else if (u.idleMinutes > 0) s = "Idle " + u.idleMinutes + " min";
        else s = "Online";
        if (u != null && u.warningLevel > 0) s += " - Warning " + Math.round(u.warningLevel / 10.0) + "%";
        if (c.typing == 2) s += " - typing...";
        return s;
    }

    @Override
    protected android.graphics.drawable.Drawable subIcon() {
        return app.onlineInfo(sn()) == null ? null : app.icons.icon(sn(), 32);
    }

    @Override
    protected void onSubTapped() {
        Ui.getInfo(this, sn());
    }

    @Override
    protected void send(String text) {
        app.sendIm(sn(), text);
    }

    @Override
    protected void onOpened() {
        app.openConv = app.conv(sn()).key;
        app.conv(sn()).unread = 0;
    }

    @Override
    protected void onClosed() {
        if (app.conv(sn()).key.equals(app.openConv)) app.openConv = null;
    }

    @Override
    public boolean onCreateOptionsMenu(Menu m) {
        m.add(0, 1, 0, "Add Buddy");
        m.add(0, 2, 0, "Close conversation");
        m.add(0, 3, 0, "Get Info");
        return true;
    }

    @Override
    public boolean onPrepareOptionsMenu(Menu m) {
        m.findItem(1).setVisible(!app.isBuddy(sn()));
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == 1) {
            app.addBuddy(sn(), new AimApp.Done<Void>() {
                public void ok(Void v) {
                    Ui.message(ImActivity.this, "Add Buddy", sn() + " was added to your Buddies group.");
                }

                public void failed(String msg) {
                    Ui.message(ImActivity.this, "Add Buddy", msg);
                }
            });
            return true;
        }
        if (item.getItemId() == 3) {
            Ui.getInfo(this, sn());
            return true;
        }
        if (item.getItemId() == 2) {
            app.closeConv(app.conv(sn()).key);
            finish();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }
}
