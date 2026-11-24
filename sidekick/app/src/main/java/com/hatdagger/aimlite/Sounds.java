package com.hatdagger.aimlite;

import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.net.Uri;
import android.os.Handler;

import java.io.File;
import java.io.FileOutputStream;
import java.util.Random;

/**
 * AIM-style sounds, made in code (the app ships no sound files and none of
 * AOL's recordings): a door creaking open when a buddy signs on, creaking shut
 * when one leaves, a bell for a new IM, a soft blip when you send.
 */
final class Sounds {
    enum Kind { DOOR_OPEN, DOOR_CLOSE, IM_IN, IM_OUT }

    private static final int RATE = 22050;
    private final Context ctx;
    private final Handler main = new Handler();
    private final short[][] made = new short[Kind.values().length][];

    Sounds(Context ctx) {
        this.ctx = ctx;
    }

    boolean on() {
        return AimApp.get().prefs().getBoolean("sounds", true);
    }

    void setOn(boolean on) {
        AimApp.get().prefs().edit().putBoolean("sounds", on).commit();
    }

    void play(Kind k) {
        if (!on()) return;
        try {
            short[] pcm = pcm(k);
            int bytes = pcm.length * 2;
            int min = AudioTrack.getMinBufferSize(RATE, AudioFormat.CHANNEL_CONFIGURATION_MONO,
                    AudioFormat.ENCODING_PCM_16BIT);
            final AudioTrack t = new AudioTrack(AudioManager.STREAM_NOTIFICATION, RATE,
                    AudioFormat.CHANNEL_CONFIGURATION_MONO, AudioFormat.ENCODING_PCM_16BIT,
                    Math.max(bytes, min), AudioTrack.MODE_STATIC);
            t.write(pcm, 0, pcm.length);
            t.play();
            main.postDelayed(new Runnable() {
                public void run() {
                    try {
                        t.stop();
                    } catch (Exception ignored) {
                    }
                    t.release();
                }
            }, pcm.length * 1000L / RATE + 300);
        } catch (Exception ignored) {
            // A sound is a nicety; never let it get in the way of a message.
        }
    }

    /** The new-IM bell as a file, for the status bar notification. */
    Uri imSoundFile() {
        File f = new File(ctx.getFilesDir(), "im_in.wav");
        if (!f.exists()) {
            try {
                // The notification is played by Android itself, which must be able to read it.
                @SuppressWarnings("deprecation")
                FileOutputStream out = ctx.openFileOutput("im_in.wav", Context.MODE_WORLD_READABLE);
                out.write(wav(pcm(Kind.IM_IN)));
                out.close();
            } catch (Exception e) {
                return null;
            }
        }
        return Uri.fromFile(f);
    }

    private synchronized short[] pcm(Kind k) {
        if (made[k.ordinal()] == null) {
            switch (k) {
                case DOOR_OPEN:
                    made[k.ordinal()] = door(true);
                    break;
                case DOOR_CLOSE:
                    made[k.ordinal()] = door(false);
                    break;
                case IM_IN:
                    made[k.ordinal()] = bell();
                    break;
                default:
                    made[k.ordinal()] = blip();
            }
        }
        return made[k.ordinal()];
    }

    // ------------------------------------------------------------------ the sounds

    /** A wooden door: a creak that rises (opening) or falls then thuds (closing). */
    private static short[] door(boolean opening) {
        int creakLen = (int) (RATE * 0.42);
        int thudLen = opening ? 0 : (int) (RATE * 0.22);
        float[] out = new float[creakLen + thudLen + RATE / 20];
        Random rnd = new Random(7);
        double phase = 0;
        for (int i = 0; i < creakLen; i++) {
            double t = (double) i / creakLen;
            double f = opening ? 260 + 420 * t * t : 640 - 400 * t;
            f *= 1 + 0.06 * Math.sin(2 * Math.PI * 23 * i / RATE); // the hinge wobbles
            phase += f / RATE;
            // A creak is a buzz of tiny clicks: a sawtooth, roughened with a bit of noise.
            double saw = 2 * (phase - Math.floor(phase)) - 1;
            double env = Math.sin(Math.PI * Math.min(1, t * 1.15)) * (0.55 + 0.45 * Math.sin(2 * Math.PI * 9 * i / RATE));
            out[i] = (float) ((saw * 0.5 + (rnd.nextDouble() - 0.5) * 0.25) * env * 0.5);
        }
        smooth(out, 0, creakLen, 0.35f); // take the edge off the buzz
        for (int i = 0; i < thudLen; i++) {
            double t = (double) i / RATE;
            double env = Math.exp(-t * 28);
            out[creakLen + i] += (float) ((Math.sin(2 * Math.PI * 85 * t) + 0.4 * Math.sin(2 * Math.PI * 170 * t)
                    + (rnd.nextDouble() - 0.5) * 0.3 * Math.exp(-t * 90)) * env * 0.8);
        }
        return toPcm(out);
    }

    /** The new-IM bell: two bright, quick strikes. */
    private static short[] bell() {
        float[] out = new float[(int) (RATE * 0.75)];
        strike(out, 0, 1318.5, 0.55f);
        strike(out, (int) (RATE * 0.085), 1760.0, 0.6f);
        return toPcm(out);
    }

    private static void strike(float[] out, int start, double f, float vol) {
        double[] partials = {1, 2.76, 5.4, 8.93};
        double[] amps = {1, 0.45, 0.22, 0.1};
        double[] decay = {5, 9, 14, 20};
        for (int i = start; i < out.length; i++) {
            double t = (double) (i - start) / RATE;
            double attack = Math.min(1, t * 400);
            double s = 0;
            for (int p = 0; p < partials.length; p++) {
                s += amps[p] * Math.exp(-t * decay[p]) * Math.sin(2 * Math.PI * f * partials[p] * t);
            }
            out[i] += (float) (s * attack * vol * 0.45);
        }
    }

    /** Sending: a short soft blip that rises. */
    private static short[] blip() {
        int n = (int) (RATE * 0.11);
        float[] out = new float[n];
        double phase = 0;
        for (int i = 0; i < n; i++) {
            double t = (double) i / n;
            phase += (520 + 680 * t) / RATE;
            double env = Math.sin(Math.PI * t);
            out[i] = (float) (Math.sin(2 * Math.PI * phase) * env * env * 0.45);
        }
        return toPcm(out);
    }

    private static void smooth(float[] a, int from, int to, float k) {
        float prev = 0;
        for (int i = from; i < to; i++) {
            prev += k * (a[i] - prev);
            a[i] = prev;
        }
    }

    private static short[] toPcm(float[] f) {
        short[] s = new short[f.length];
        int fade = Math.min(f.length, RATE / 200);
        for (int i = 0; i < f.length; i++) {
            float v = f[i];
            if (i >= f.length - fade) v *= (float) (f.length - i) / fade;
            v = Math.max(-1f, Math.min(1f, v));
            s[i] = (short) (v * 30000);
        }
        return s;
    }

    private static byte[] wav(short[] pcm) {
        int data = pcm.length * 2;
        byte[] b = new byte[44 + data];
        put(b, 0, "RIFF");
        le32(b, 4, 36 + data);
        put(b, 8, "WAVEfmt ");
        le32(b, 16, 16);
        le16(b, 20, 1);
        le16(b, 22, 1);
        le32(b, 24, RATE);
        le32(b, 28, RATE * 2);
        le16(b, 32, 2);
        le16(b, 34, 16);
        put(b, 36, "data");
        le32(b, 40, data);
        for (int i = 0; i < pcm.length; i++) le16(b, 44 + i * 2, pcm[i]);
        return b;
    }

    private static void put(byte[] b, int at, String s) {
        for (int i = 0; i < s.length(); i++) b[at + i] = (byte) s.charAt(i);
    }

    private static void le16(byte[] b, int at, int v) {
        b[at] = (byte) v;
        b[at + 1] = (byte) (v >> 8);
    }

    private static void le32(byte[] b, int at, int v) {
        le16(b, at, v);
        le16(b, at + 2, v >> 16);
    }
}
