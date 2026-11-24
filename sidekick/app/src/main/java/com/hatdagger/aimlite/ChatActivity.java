package com.hatdagger.aimlite;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.format.DateFormat;
import android.text.style.ForegroundColorSpan;
import android.text.style.StyleSpan;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;

import com.hatdagger.aimlite.oscar.Client;

import java.util.Date;
import java.util.List;

/**
 * An IM or chat room window: the conversation on top, the message box at the
 * bottom. Enter on the Sidekick keyboard sends; Shift+Enter (or Alt+Enter)
 * starts a new line.
 */
abstract class ChatActivity extends Activity {
    protected AimApp app;
    protected TextView title, sub, banner;
    protected EditText input;
    private ListView list;
    private List<AimApp.Line> lines;
    private int lastCount = -1;
    private final Adapter adapter = new Adapter();
    private final Runnable refresh = new Runnable() {
        public void run() {
            update();
        }
    };

    /** The lines to show (null when the chat is gone). */
    protected abstract List<AimApp.Line> lines();

    protected abstract String titleText();

    /** The line under the title (status, or who's in the room). */
    protected abstract String subText();

    protected abstract void send(String text);

    protected abstract void onOpened();

    protected abstract void onClosed();

    protected void onSubTapped() {}

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        app = AimApp.get();
        LinearLayout root = Ui.column(this);
        title = Ui.titleBar(this, "");
        root.addView(title, Ui.fill());
        sub = Ui.label(this, "");
        int p = Ui.dp(this, 4);
        sub.setPadding(p * 2, p, p * 2, p);
        sub.setSingleLine(true);
        sub.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                onSubTapped();
            }
        });
        root.addView(sub, Ui.fill());
        banner = Ui.banner(this);
        root.addView(banner, Ui.fill());

        list = new ListView(this);
        list.setBackgroundColor(Color.WHITE);
        list.setCacheColorHint(Color.WHITE);
        list.setDivider(null);
        list.setTranscriptMode(ListView.TRANSCRIPT_MODE_ALWAYS_SCROLL);
        list.setStackFromBottom(true);
        list.setAdapter(adapter);
        list.setFocusable(false); // the keyboard types into the message box, not the list
        root.addView(list, Ui.grow());

        LinearLayout bottom = Ui.row(this);
        input = new EditText(this);
        input.setHint("Type a message");
        input.setMaxLines(3);
        input.setImeOptions(EditorInfo.IME_ACTION_SEND | EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        input.setOnEditorActionListener(new TextView.OnEditorActionListener() {
            public boolean onEditorAction(TextView v, int id, KeyEvent e) {
                if (id == EditorInfo.IME_ACTION_SEND || e == null || e.getAction() == KeyEvent.ACTION_DOWN) {
                    doSend();
                }
                return true;
            }
        });
        input.setOnKeyListener(new View.OnKeyListener() {
            public boolean onKey(View v, int code, KeyEvent e) {
                if (code != KeyEvent.KEYCODE_ENTER) return false;
                if (e.isShiftPressed() || e.isAltPressed()) {
                    if (e.getAction() == KeyEvent.ACTION_DOWN) input.getText().insert(input.getSelectionStart(), "\n");
                    return true;
                }
                if (e.getAction() == KeyEvent.ACTION_DOWN) doSend();
                return true;
            }
        });
        bottom.addView(input, Ui.weight(1));
        Button send = Ui.button(this, "Send");
        send.setTypeface(Typeface.DEFAULT_BOLD);
        send.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                doSend();
            }
        });
        bottom.addView(send);
        root.addView(bottom, Ui.fill());
        setContentView(root);
    }

    private void doSend() {
        String t = input.getText().toString();
        if (t.trim().length() == 0) return;
        send(t);
        input.setText("");
    }

    @Override
    protected void onResume() {
        super.onResume();
        onOpened();
        app.observe(refresh);
        app.setVisible(true);
        update();
        input.requestFocus();
    }

    @Override
    protected void onPause() {
        app.unobserve(refresh);
        onClosed();
        app.setVisible(false);
        super.onPause();
    }

    protected void update() {
        lines = lines();
        if (lines == null) {
            finish();
            return;
        }
        title.setText(titleText());
        String s = subText();
        sub.setText(s == null ? "" : s);
        sub.setVisibility(s == null ? View.GONE : View.VISIBLE);
        String note = null;
        if (app.state != Client.State.ONLINE) {
            note = "Not connected. Messages will go out when the connection comes back.";
        }
        String extra = bannerText();
        if (extra != null) note = extra;
        banner.setText(note == null ? "" : note);
        banner.setVisibility(note == null ? View.GONE : View.VISIBLE);
        adapter.notifyDataSetChanged();
        if (lines.size() != lastCount) {
            lastCount = lines.size();
            list.setSelection(Math.max(0, lines.size() - 1));
        }
    }

    protected String bannerText() {
        return null;
    }

    private final class Adapter extends BaseAdapter {
        public int getCount() {
            return lines == null ? 0 : lines.size();
        }

        public Object getItem(int i) {
            return lines.get(i);
        }

        public long getItemId(int i) {
            return i;
        }

        @Override
        public boolean isEnabled(int i) {
            return false;
        }

        @Override
        public boolean areAllItemsEnabled() {
            return false;
        }

        public View getView(int i, View v, ViewGroup parent) {
            TextView t = v instanceof TextView ? (TextView) v : new TextView(ChatActivity.this);
            AimApp.Line l = lines.get(i);
            int p = Ui.dp(ChatActivity.this, 4);
            t.setPadding(p * 2, p, p * 2, p);
            if (l.system) {
                t.setText(l.text);
                t.setTextSize(13);
                t.setTextColor(0xFF606060);
                t.setTypeface(Typeface.defaultFromStyle(Typeface.ITALIC));
                t.setBackgroundColor(Color.WHITE);
                return t;
            }
            SpannableStringBuilder sb = new SpannableStringBuilder();
            String time = DateFormat.getTimeFormat(ChatActivity.this).format(new Date(l.time));
            String name = l.from + (l.auto ? " (Auto-response)" : "") + " (" + time + "): ";
            sb.append(name);
            sb.setSpan(new ForegroundColorSpan(l.mine ? Ui.MY_NAME : Ui.THEIR_NAME), 0, name.length(),
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            sb.setSpan(new StyleSpan(Typeface.BOLD), 0, name.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            sb.append(l.text);
            if (l.pending != null) {
                String st;
                switch (l.pending.status) {
                    case WAITING:
                        st = l.pending.note != null ? l.pending.note : "waiting for them to sign on";
                        break;
                    case FAILED:
                        st = "not delivered";
                        break;
                    default:
                        st = app.state == Client.State.ONLINE ? "sending..." : "waiting for connection";
                }
                int start = sb.length();
                sb.append("  [").append(st).append("]");
                sb.setSpan(new ForegroundColorSpan(0xFF808080), start, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
            t.setText(sb);
            t.setTextSize(16);
            t.setTextColor(Color.BLACK);
            t.setTypeface(Typeface.DEFAULT);
            t.setBackgroundColor(l.mine ? 0xFFEEF3FF : Color.WHITE);
            return t;
        }
    }
}
