package com.hatdagger.aimlite;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;

import com.hatdagger.aimlite.oscar.Bytes;
import com.hatdagger.aimlite.oscar.Client;
import com.hatdagger.aimlite.oscar.Models;
import com.hatdagger.aimlite.oscar.Rooms;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** The Buddy List: chat rooms and invites, then your groups, then offline buddies. */
public final class BuddyListActivity extends Activity {

    /** One line in the list. */
    private static final class Row {
        static final int HEADER = 0, BUDDY = 1, ROOM = 2, INVITE = 3, NOTE = 4;
        final int kind;
        final String text;
        final String key;
        final Object data;
        final boolean dim;
        final int unread;

        Row(int kind, String text, String key, Object data, boolean dim, int unread) {
            this.kind = kind;
            this.text = text;
            this.key = key;
            this.data = data;
            this.dim = dim;
            this.unread = unread;
        }
    }

    private AimApp app;
    private TextView title, banner;
    private Button back;
    private ListView list;
    private LinearLayout middle, bar;
    private final List<Row> rows = new ArrayList<Row>();
    private final Set<String> collapsed = new HashSet<String>();
    private final Adapter adapter = new Adapter();
    private final Runnable refresh = new Runnable() {
        public void run() {
            update();
        }
    };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        app = AimApp.get();
        LinearLayout root = Ui.column(this);
        title = Ui.titleBar(this, "Buddy List");
        root.addView(title, Ui.fill());

        LinearLayout bannerRow = Ui.row(this);
        bannerRow.setBackgroundColor(0xFFFFE0A0);
        banner = Ui.banner(this);
        bannerRow.addView(banner, Ui.weight(1));
        back = Ui.button(this, "I'm Back");
        back.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                app.setAway(null);
            }
        });
        bannerRow.addView(back);
        root.addView(bannerRow, Ui.fill());

        list = new ListView(this);
        list.setBackgroundColor(Color.WHITE);
        list.setCacheColorHint(Color.WHITE);
        list.setAdapter(adapter);
        // The trackball: draw the selected row ourselves (navy bar, white text) instead of
        // Android's highlight, which the white rows would cover up.
        list.setSelector(new android.graphics.drawable.ColorDrawable(0));
        list.setItemsCanFocus(false);
        list.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            public void onItemSelected(AdapterView<?> p, View v, int pos, long id) {
                repaintRows();
            }

            public void onNothingSelected(AdapterView<?> p) {
                repaintRows();
            }
        });
        list.getViewTreeObserver().addOnTouchModeChangeListener(new android.view.ViewTreeObserver.OnTouchModeChangeListener() {
            public void onTouchModeChanged(boolean touch) {
                repaintRows();
            }
        });
        list.setOnFocusChangeListener(new View.OnFocusChangeListener() {
            public void onFocusChange(View v, boolean has) {
                repaintRows();
            }
        });
        list.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            public void onItemClick(AdapterView<?> p, View v, int pos, long id) {
                tap(rows.get(pos));
            }
        });
        list.setOnItemLongClickListener(new AdapterView.OnItemLongClickListener() {
            public boolean onItemLongClick(AdapterView<?> p, View v, int pos, long id) {
                return longTap(rows.get(pos));
            }
        });
        middle = new LinearLayout(this);
        middle.addView(list);
        root.addView(middle, Ui.grow());

        // AIM's strip of buttons: under the list upright, down the right side sideways.
        bar = Ui.row(this);
        bar.setBackgroundColor(Ui.FACE);
        bar.addView(picto(R.drawable.ic_bar_im, "IM", new View.OnClickListener() {
            public void onClick(View v) {
                Ui.ask(BuddyListActivity.this, "Send Instant Message", "Screen name", "", new Ui.OnText() {
                    public void text(String s) {
                        openIm(s);
                    }
                });
            }
        }));
        bar.addView(picto(R.drawable.ic_bar_chat, "Chat", new View.OnClickListener() {
            public void onClick(View v) {
                chatDialog();
            }
        }));
        bar.addView(picto(R.drawable.ic_bar_info, "Info", new View.OnClickListener() {
            public void onClick(View v) {
                profileDialog();
            }
        }));
        bar.addView(picto(R.drawable.ic_bar_away, "Away", new View.OnClickListener() {
            public void onClick(View v) {
                awayDialog();
            }
        }));
        bar.addView(picto(R.drawable.ic_bar_setup, "Setup", new View.OnClickListener() {
            public void onClick(View v) {
                setupMenu();
            }
        }));
        middle.addView(bar);
        arrange(getResources().getConfiguration().orientation);
        setContentView(root);
    }

    /** Buttons below the list when upright, in a column on the right when sideways. */
    private void arrange(int orientation) {
        boolean wide = orientation == Configuration.ORIENTATION_LANDSCAPE;
        middle.setOrientation(wide ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        bar.setOrientation(wide ? LinearLayout.VERTICAL : LinearLayout.HORIZONTAL);
        list.setLayoutParams(wide
                ? new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.FILL_PARENT, 1f)
                : new LinearLayout.LayoutParams(ViewGroup.LayoutParams.FILL_PARENT, 0, 1f));
        bar.setLayoutParams(wide
                ? new LinearLayout.LayoutParams(Ui.dp(this, 72), ViewGroup.LayoutParams.FILL_PARENT)
                : new LinearLayout.LayoutParams(ViewGroup.LayoutParams.FILL_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        for (int i = 0; i < bar.getChildCount(); i++) {
            bar.getChildAt(i).setLayoutParams(wide
                    ? new LinearLayout.LayoutParams(ViewGroup.LayoutParams.FILL_PARENT, 0, 1f)
                    : new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        }
    }

    /** The keyboard sliding open or shut turns the screen without restarting this window. */
    @Override
    public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c);
        arrange(c.orientation);
    }

    /** One picture button, like the main app's: the picture with its name under it. */
    private View picto(int image, String label, View.OnClickListener l) {
        LinearLayout v = Ui.column(this);
        v.setGravity(Gravity.CENTER);
        v.setBackgroundDrawable(Ui.selectable(this));
        int p = Ui.dp(this, 3);
        v.setPadding(p, p, p, p);
        ImageView img = new ImageView(this);
        img.setImageResource(image);
        v.addView(img);
        TextView t = Ui.label(this, label);
        t.setTextSize(12);
        t.setGravity(Gravity.CENTER);
        v.addView(t);
        v.setClickable(true);
        v.setFocusable(true);
        v.setOnClickListener(l);
        return v;
    }

    /** Setup: the things that don't need their own button. */
    private void setupMenu() {
        new AlertDialog.Builder(this).setTitle("Setup")
                .setItems(new String[] {"Add Buddy",
                        app.sounds().on() ? "Sounds: On (tap to turn off)" : "Sounds: Off (tap to turn on)",
                        HomeMode.isOn(this) ? "Leave Home Screen Mode" : "Make AIM the Home Screen",
                        "Sign Off"}, new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        if (w == 0) addDialog("");
                        else if (w == 1) {
                            boolean on = !app.sounds().on();
                            app.sounds().setOn(on);
                            if (on) app.sounds().play(Sounds.Kind.IM_IN);
                        } else if (w == 2) HomeMode.fromSetup(BuddyListActivity.this);
                        else confirmSignOff();
                    }
                }).show();
    }

    private void confirmSignOff() {
        new AlertDialog.Builder(this).setTitle("Sign off?")
                .setPositiveButton("Sign Off", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        app.signOff();
                    }
                })
                .setNegativeButton("Cancel", null).show();
    }

    @Override
    protected void onResume() {
        super.onResume();
        app.openConv = null;
        app.openRoom = null;
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

    /** Back hides AIM like Home does; you stay signed on. Sign off is in the menu. */
    @Override
    public boolean onKeyDown(int code, KeyEvent e) {
        if (code == KeyEvent.KEYCODE_BACK) {
            // As the home screen there's nothing behind AIM to go back to.
            if (!HomeMode.isOn(this)) moveTaskToBack(true);
            return true;
        }
        return super.onKeyDown(code, e);
    }

    // ---------------------------------------------------------------- building the list

    private void update() {
        if (app.client == null || app.state == Client.State.OFFLINE) {
            startActivity(new Intent(this, SignOnActivity.class));
            finish();
            return;
        }
        title.setText(app.myName() + "'s Buddy List");
        String note = null;
        boolean showBack = false;
        switch (app.state) {
            case CONNECTING:
            case RECONNECTING:
                note = "Reconnecting... messages you send will go out when the connection is back.";
                break;
            case STOPPED:
                note = (app.stateMessage == null ? "Signed off." : app.stateMessage) + " Use Menu > Sign Off.";
                break;
            default:
                if (app.client.isAway()) {
                    note = "Away: " + app.client.awayMessage();
                    showBack = true;
                }
        }
        banner.setText(note == null ? "" : note);
        ((View) banner.getParent()).setVisibility(note == null ? View.GONE : View.VISIBLE);
        back.setVisibility(showBack ? View.VISIBLE : View.GONE);

        rows.clear();
        // Chat rooms and invites first.
        if (!app.rooms.isEmpty() || !app.invites.isEmpty()) {
            int unread = app.invites.size();
            for (AimApp.RoomChat r : app.rooms.values()) unread += r.unread;
            header("Chat Rooms", "(" + (app.rooms.size() + app.invites.size()) + ")", unread);
            if (!collapsed.contains("Chat Rooms")) {
                for (Rooms.Invite inv : app.invites) {
                    rows.add(new Row(Row.INVITE, inv.from + " invited you to " + inv.room.name, null, inv, false, 1));
                }
                for (AimApp.RoomChat r : app.rooms.values()) {
                    String t = r.name() + (r.isOpen() ? "  (" + r.room.members().size() + ")" : "  (joining)");
                    rows.add(new Row(Row.ROOM, t, r.key, r, !r.isOpen(), r.unread));
                }
            }
        }

        List<Models.BuddyGroup> groups = app.groups();
        Set<String> known = new HashSet<String>();
        for (Models.BuddyGroup g : groups) for (String s : g.buddies) known.add(Bytes.normalizeSn(s));

        // People who messaged you but aren't on your list.
        List<AimApp.Conv> strangers = new ArrayList<AimApp.Conv>();
        for (AimApp.Conv c : app.convs.values()) if (!known.contains(c.key)) strangers.add(c);
        if (!strangers.isEmpty()) {
            int unread = 0;
            for (AimApp.Conv c : strangers) unread += c.unread;
            header("Not on My List", "(" + strangers.size() + ")", unread);
            if (!collapsed.contains("Not on My List")) {
                for (AimApp.Conv c : strangers) {
                    rows.add(new Row(Row.BUDDY, c.name, c.key, c.name, app.onlineInfo(c.name) == null, c.unread));
                }
            }
        }

        List<String> offline = new ArrayList<String>();
        int offlineUnread = 0;
        for (Models.BuddyGroup g : groups) {
            List<Row> on = new ArrayList<Row>();
            int unread = 0;
            for (String s : g.buddies) {
                Models.UserInfo u = app.onlineInfo(s);
                AimApp.Conv c = app.convs.get(Bytes.normalizeSn(s));
                int n = c == null ? 0 : c.unread;
                unread += n;
                if (u == null) {
                    offline.add(s);
                    offlineUnread += n;
                    continue;
                }
                String t = u.screenName;
                if (u.isAway()) t += "  (away)";
                if (u.idleMinutes > 0) t += u.idleMinutes < 60 ? "  (" + u.idleMinutes + "m)" : "  (" + (u.idleMinutes / 60) + "h)";
                on.add(new Row(Row.BUDDY, t, Bytes.normalizeSn(s), u.screenName, u.isAway() || u.idleMinutes > 0, n));
            }
            header(g.name, "(" + on.size() + "/" + g.buddies.size() + ")", unread);
            if (!collapsed.contains(g.name)) rows.addAll(on);
        }
        if (!offline.isEmpty()) {
            header("Offline", "(" + offline.size() + ")", offlineUnread);
            if (!collapsed.contains("Offline")) {
                for (String s : offline) {
                    AimApp.Conv c = app.convs.get(Bytes.normalizeSn(s));
                    rows.add(new Row(Row.BUDDY, s, Bytes.normalizeSn(s), s, true, c == null ? 0 : c.unread));
                }
            }
        }
        if (rows.isEmpty()) {
            rows.add(new Row(Row.NOTE, app.state == Client.State.ONLINE ? "No buddies yet. Press Add to add one."
                    : "Signing on...", null, null, true, 0));
        }
        adapter.notifyDataSetChanged();
    }

    private void header(String name, String count, int unread) {
        boolean c = collapsed.contains(name);
        rows.add(new Row(Row.HEADER, (c ? "+ " : "- ") + name + " " + count, name, null, false, c ? unread : 0));
    }

    /** Redraws the rows on screen so the highlight follows the trackball. */
    private void repaintRows() {
        int first = list.getFirstVisiblePosition();
        for (int j = 0; j < list.getChildCount(); j++) {
            int pos = first + j;
            if (pos < rows.size()) adapter.getView(pos, list.getChildAt(j), list);
        }
    }

    private boolean isSelected(int pos) {
        return !list.isInTouchMode() && list.hasFocus() && pos == list.getSelectedItemPosition();
    }

    private final class Adapter extends BaseAdapter {
        public int getCount() {
            return rows.size();
        }

        public Object getItem(int i) {
            return rows.get(i);
        }

        public long getItemId(int i) {
            return i;
        }

        @Override
        public int getViewTypeCount() {
            return 1;
        }

        public View getView(int i, View v, ViewGroup parent) {
            TextView t = v instanceof TextView ? (TextView) v : new TextView(BuddyListActivity.this);
            Row r = rows.get(i);
            int pad = Ui.dp(BuddyListActivity.this, 6);
            String text = r.text + (r.unread > 0 ? "   [" + r.unread + " new]" : "");
            t.setText(text);
            t.setTextSize(r.kind == Row.HEADER ? 15 : 17);
            t.setPadding(r.kind == Row.HEADER || r.kind == Row.NOTE ? pad : pad * 4, pad, pad, pad);
            t.setTypeface(r.kind == Row.HEADER || r.unread > 0 || r.kind == Row.INVITE ? Typeface.DEFAULT_BOLD
                    : Typeface.DEFAULT);
            int color = Color.BLACK;
            if (r.kind == Row.INVITE || r.unread > 0) color = 0xFFC00000;
            else if (r.kind == Row.ROOM) color = r.dim ? 0xFF808080 : 0xFF5A2DA0;
            else if (r.dim) color = 0xFF808080;
            boolean sel = isSelected(i);
            t.setTextColor(sel ? Color.WHITE : color);
            t.setBackgroundColor(sel ? Ui.SELECTED : r.kind == Row.HEADER ? 0xFFE8E4DC : Color.WHITE);
            android.graphics.drawable.Drawable icon = r.kind == Row.BUDDY && app.onlineInfo((String) r.data) != null
                    ? app.icons.icon((String) r.data, 26) : null;
            t.setCompoundDrawables(icon, null, null, null);
            t.setCompoundDrawablePadding(Ui.dp(BuddyListActivity.this, 6));
            if (icon != null) t.setPadding(pad * 2, pad / 2, pad, pad / 2);
            return t;
        }
    }

    // ---------------------------------------------------------------- taps

    private void tap(Row r) {
        switch (r.kind) {
            case Row.HEADER:
                if (!collapsed.remove(r.key)) collapsed.add(r.key);
                update();
                break;
            case Row.BUDDY:
                openIm((String) r.data);
                break;
            case Row.ROOM:
                openRoom(r.key);
                break;
            case Row.INVITE:
                inviteDialog((Rooms.Invite) r.data);
                break;
            default:
                break;
        }
    }

    private boolean longTap(final Row r) {
        if (r.kind == Row.BUDDY) {
            final String sn = (String) r.data;
            final boolean buddy = app.isBuddy(sn);
            final AimApp.Conv conv = app.convs.get(Bytes.normalizeSn(sn));
            List<String> opts = new ArrayList<String>();
            opts.add("Send Message");
            opts.add("Get Info");
            opts.add(buddy ? "Remove from Buddy List" : "Add to Buddy List");
            if (conv != null) opts.add("Close conversation");
            new AlertDialog.Builder(this).setTitle(sn)
                    .setItems(opts.toArray(new String[0]), new DialogInterface.OnClickListener() {
                        public void onClick(DialogInterface d, int w) {
                            if (w == 0) openIm(sn);
                            else if (w == 1) Ui.getInfo(BuddyListActivity.this, sn);
                            else if (w == 2 && buddy) removeBuddy(sn);
                            else if (w == 2) addDialog(sn);
                            else if (w == 3 && conv != null) app.closeConv(conv.key);
                        }
                    }).show();
            return true;
        }
        if (r.kind == Row.ROOM) {
            final String key = r.key;
            new AlertDialog.Builder(this).setTitle(((AimApp.RoomChat) r.data).name())
                    .setItems(new String[] {"Open", "Leave the room"}, new DialogInterface.OnClickListener() {
                        public void onClick(DialogInterface d, int w) {
                            if (w == 0) openRoom(key);
                            else app.leaveRoom(key);
                        }
                    }).show();
            return true;
        }
        return false;
    }

    private void openIm(String sn) {
        Intent i = new Intent(this, ImActivity.class);
        i.putExtra("sn", sn);
        startActivity(i);
    }

    private void openRoom(String key) {
        Intent i = new Intent(this, RoomActivity.class);
        i.putExtra("key", key);
        startActivity(i);
    }

    // ---------------------------------------------------------------- dialogs

    private void addDialog(String initial) {
        Ui.ask(this, "Add Buddy", "Screen name", initial, new Ui.OnText() {
            public void text(final String s) {
                app.addBuddy(s, new AimApp.Done<Void>() {
                    public void ok(Void v) {
                        Ui.message(BuddyListActivity.this, "Add Buddy", s + " was added to your Buddies group.");
                    }

                    public void failed(String m) {
                        Ui.message(BuddyListActivity.this, "Add Buddy", "Couldn't add " + s + ": " + m);
                    }
                });
            }
        });
    }

    private void removeBuddy(final String sn) {
        new AlertDialog.Builder(this).setTitle("Remove " + sn + "?")
                .setPositiveButton("Remove", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        app.removeBuddy(sn, new AimApp.Done<Void>() {
                            public void ok(Void v) {}

                            public void failed(String m) {
                                Ui.message(BuddyListActivity.this, "Remove Buddy", m);
                            }
                        });
                    }
                })
                .setNegativeButton("Cancel", null).show();
    }

    private void awayDialog() {
        if (app.client != null && app.client.isAway()) {
            app.setAway(null);
            return;
        }
        String saved = app.prefs().getString("away", "I'm away from my Sidekick right now.");
        Ui.ask(this, "Away Message", "Away message", saved, new Ui.OnText() {
            public void text(String s) {
                app.prefs().edit().putString("away", s).commit();
                app.setAway(s);
            }
        });
    }

    /** Chat: name a room (new or existing); a new room offers to invite buddies. */
    private void chatDialog() {
        if (app.state != Client.State.ONLINE) {
            Ui.message(this, "Chat", "Chat rooms need a connection. Try again once you're signed on.");
            return;
        }
        String def = app.myName().replace(" ", "") + "Chat" + (100 + (int) (System.currentTimeMillis() % 900));
        Ui.ask(this, "Chat Room", "Room name (new or existing)", def, new Ui.OnText() {
            public void text(String name) {
                app.joinRoom(name, new AimApp.Done<String>() {
                    public void ok(String key) {
                        openRoom(key);
                    }

                    public void failed(String m) {
                        Ui.message(BuddyListActivity.this, "Chat", m);
                    }
                });
            }
        });
    }

    private void inviteDialog(final Rooms.Invite inv) {
        String msg = inv.from + " invited you to the chat room \"" + inv.room.name + "\"."
                + (inv.message.length() > 0 ? "\n\n\"" + inv.message + "\"" : "");
        new AlertDialog.Builder(this).setTitle("Buddy Chat Invitation").setMessage(msg)
                .setPositiveButton("Join", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        app.acceptInvite(inv, new AimApp.Done<String>() {
                            public void ok(String key) {
                                openRoom(key);
                            }

                            public void failed(String m) {
                                Ui.message(BuddyListActivity.this, "Chat", m);
                            }
                        });
                    }
                })
                .setNeutralButton("Later", null)
                .setNegativeButton("No thanks", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        app.declineInvite(inv);
                    }
                }).show();
    }

    // ---------------------------------------------------------------- menu key

    @Override
    public boolean onCreateOptionsMenu(Menu m) {
        m.add(0, 1, 0, "Send IM");
        m.add(0, 2, 0, "Chat Room");
        m.add(0, 3, 0, "Away");
        m.add(0, 4, 0, "Add Buddy");
        m.add(0, 5, 0, "My Info");
        m.add(0, 6, 0, "Sign Off");
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        switch (item.getItemId()) {
            case 1:
                Ui.ask(this, "Send Instant Message", "Screen name", "", new Ui.OnText() {
                    public void text(String s) {
                        openIm(s);
                    }
                });
                return true;
            case 2:
                chatDialog();
                return true;
            case 3:
                awayDialog();
                return true;
            case 4:
                addDialog("");
                return true;
            case 5:
                profileDialog();
                return true;
            case 6:
                confirmSignOff();
                return true;
            default:
                return super.onOptionsItemSelected(item);
        }
    }

    private void profileDialog() {
        final EditText e = new EditText(this);
        e.setMinLines(3);
        e.setText(app.prefs().getString("profile", ""));
        new AlertDialog.Builder(this).setTitle("My Profile").setView(e)
                .setPositiveButton("Save", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        String p = e.getText().toString();
                        app.prefs().edit().putString("profile", p).commit();
                        if (app.client != null) app.client.setProfile(p);
                    }
                })
                .setNegativeButton("Cancel", null).show();
    }
}
