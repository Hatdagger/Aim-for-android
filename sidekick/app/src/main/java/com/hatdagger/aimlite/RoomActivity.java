package com.hatdagger.aimlite;

import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.view.Menu;
import android.view.MenuItem;
import android.widget.EditText;
import android.widget.LinearLayout;

import com.hatdagger.aimlite.oscar.Bytes;
import com.hatdagger.aimlite.oscar.Client;

import java.util.ArrayList;
import java.util.List;

/** A chat room window: everyone's messages, who's here (tap the line), invite and leave. */
public final class RoomActivity extends ChatActivity {

    private String key() {
        return getIntent().getStringExtra("key");
    }

    private AimApp.RoomChat room() {
        return app.rooms.get(key());
    }

    @Override
    protected List<AimApp.Line> lines() {
        AimApp.RoomChat r = room();
        return r == null ? null : r.lines;
    }

    @Override
    protected String titleText() {
        return room().name() + " - Chat Room";
    }

    @Override
    protected String subText() {
        List<String> m = room().room.members();
        return m.isEmpty() ? "Nobody here yet" : m.size() + " here: " + AimApp.join(m) + "  (tap for options)";
    }

    @Override
    protected String bannerText() {
        AimApp.RoomChat r = room();
        if (r != null && !r.isOpen()) {
            return app.state == Client.State.ONLINE ? "Joining the room..."
                    : "Not connected. You'll rejoin the room when the connection comes back.";
        }
        return null;
    }

    @Override
    protected void send(String text) {
        app.sendToRoom(key(), text);
    }

    @Override
    protected void onOpened() {
        app.openRoom = key();
        AimApp.RoomChat r = room();
        if (r != null) r.unread = 0;
    }

    @Override
    protected void onClosed() {
        if (key().equals(app.openRoom)) app.openRoom = null;
    }

    /** Tap the member line: pick someone to IM. */
    @Override
    protected void onSubTapped() {
        AimApp.RoomChat r = room();
        if (r == null) return;
        final List<String> people = new ArrayList<String>();
        String me = Bytes.normalizeSn(app.myName());
        for (String s : r.room.members()) if (!Bytes.normalizeSn(s).equals(me)) people.add(s);
        if (people.isEmpty()) {
            Ui.message(this, "In this room", "Just you so far. Use Menu > Invite to bring buddies in.");
            return;
        }
        new AlertDialog.Builder(this).setTitle("Send an IM to...")
                .setItems(people.toArray(new String[0]), new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        Intent i = new Intent(RoomActivity.this, ImActivity.class);
                        i.putExtra("sn", people.get(w));
                        startActivity(i);
                    }
                }).show();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu m) {
        m.add(0, 1, 0, "Invite Buddies");
        m.add(0, 2, 0, "Leave Room");
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == 1) {
            inviteDialog();
            return true;
        }
        if (item.getItemId() == 2) {
            new AlertDialog.Builder(this).setTitle("Leave " + room().name() + "?")
                    .setPositiveButton("Leave", new DialogInterface.OnClickListener() {
                        public void onClick(DialogInterface d, int w) {
                            app.leaveRoom(key());
                            finish();
                        }
                    })
                    .setNegativeButton("Stay", null).show();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    private void inviteDialog() {
        List<String> here = new ArrayList<String>();
        for (String s : room().room.members()) here.add(Bytes.normalizeSn(s));
        final List<String> online = new ArrayList<String>();
        for (String s : app.onlineBuddies()) if (!here.contains(Bytes.normalizeSn(s))) online.add(s);
        if (online.isEmpty()) {
            Ui.message(this, "Invite", "None of your buddies are online right now.");
            return;
        }
        final boolean[] picked = new boolean[online.size()];
        new AlertDialog.Builder(this).setTitle("Invite to " + room().name())
                .setMultiChoiceItems(online.toArray(new String[0]), picked,
                        new DialogInterface.OnMultiChoiceClickListener() {
                            public void onClick(DialogInterface d, int w, boolean on) {
                                picked[w] = on;
                            }
                        })
                .setPositiveButton("Next", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        List<String> who = new ArrayList<String>();
                        for (int i = 0; i < picked.length; i++) if (picked[i]) who.add(online.get(i));
                        if (!who.isEmpty()) inviteMessage(who);
                    }
                })
                .setNegativeButton("Cancel", null).show();
    }

    private void inviteMessage(final List<String> who) {
        final EditText e = Ui.field(this, "Invitation message", false);
        e.setText("Join me in this Buddy Chat.");
        LinearLayout wrap = new LinearLayout(this);
        wrap.addView(e, Ui.fill());
        new AlertDialog.Builder(this).setTitle("Invite " + AimApp.join(who)).setView(wrap)
                .setPositiveButton("Send Invite", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        app.inviteToRoom(key(), who, e.getText().toString(), new AimApp.Done<List<String>>() {
                            public void ok(List<String> failed) {
                                if (!failed.isEmpty()) {
                                    Ui.message(RoomActivity.this, "Invite", "Couldn't reach " + AimApp.join(failed) + ".");
                                }
                            }

                            public void failed(String m) {
                                Ui.message(RoomActivity.this, "Invite", m);
                            }
                        });
                    }
                })
                .setNegativeButton("Cancel", null).show();
    }
}
