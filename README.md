# AIM for Android (and Linux, Windows)

An old-school AIM client with modern behaviour, for servers running
[Open OSCAR Server](https://github.com/mk6i/open-oscar-server).

- Classic look: grey bevelled windows on a teal desktop, the classic sounds
  (imported from your own AIM 5.1 installer — none are included).
- Stays connected: reconnects automatically after drops; messages you send while
  offline (or to a buddy who is offline) wait and go out later. You can cancel them.
- Goes Away automatically when the app is in the background.
- Notifications only say "You have N new AIM messages" — no names, no previews.
- Buddy icons (48×48, ≤7 KB, picked from your gallery, you choose the crop), profiles,
  away messages, typing indicator.
- Controller support (Steam Deck, ROG Ally, XInput, Android pads) with a T9 phone
  keypad that docks beside the chat — predictive or multi-tap, in several phone styles.
- Gadget keyboards: a wide flip phone that opens sideways to a keyboard, a glowing console
  keyboard under a tube TV that switches on like a CRT, a thumb-keyboard "pocket mail" phone,
  a click-wheel music player whose keyboard slides up over the wheel, and a green-screen
  handheld that boots with a beeeep and pops up a name-entry style letter box (arrows / D-pad
  move the ▶). Key clicks and flip/slide/boot sounds are made in code (Prefs can turn them off).
- Invite links: "Get a Screen Name" with an invite from a friend.
- Optional chat history (off by default, cleared when you sign off).

## Download
Builds are posted to the **Releases** page (`latest`) by GitHub Actions on every push:
`aim-android.apk`, `aim-windows.zip`, `aim-linux.tar.gz`.

## Building yourself
```
flutter create --project-name aim_for_android --org com.hatdagger --platforms android,linux,windows .
python3 tool/setup_platforms.py
flutter build apk      # or: flutter build linux / flutter build windows
```

## Layout
- `lib/oscar/` — OSCAR protocol (FLAP/SNAC, sign-on, buddy list, IMs, profiles, icons),
  the reconnecting client with outbox, and the sign-up API client. Pure Dart.
- `lib/importer/` — unpacks the sounds from `aim513036.exe` (Wise → Cabinet/LZX → AOL .mld).
- `lib/app/` — app state, settings, sounds, T9 engine, controller input, Android bridge.
- `lib/ui/` — screens and retro widgets.
- `android_overlay/` — Kotlin foreground service, notifications and link handling.
- `server/` — the **AIM Server app** (separate download, `server-latest` release): runs Open OSCAR
  Server with a browser control panel, one port, UPnP, invite links and sign-ups. See `server/README.md`.
- `docs/SERVER_SPEC.md` — the server app's spec and its invite/sign-up API.

The T9 word list (`assets/t9_words.txt`) is derived from SCOWL; see `assets/t9_words_LICENSE.txt`.
AIM and AOL are trademarks of their owners; this project is not affiliated with them.
