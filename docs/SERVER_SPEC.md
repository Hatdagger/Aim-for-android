# AIM Server app — spec (separate app, not shipped with the client)

A desktop app (Windows/Linux) wrapping **Open OSCAR Server** (MIT, by mk6i) with a
simple GUI, plus the invite/sign-up service the client talks to.

## GUI
- Start / Stop server. Writes `settings.env`, runs the server binary, shows its log.
- **Addresses panel**: local IP(s), public IP (from the router over UPnP, else a
  what's-my-IP lookup), and the port to forward: **TCP 5190** only.
  Never forward the management API (8080).
- **UPnP**: "Open port automatically" (AddPortMapping 5190/TCP), renew while
  running, remove on stop. On failure show manual router steps with the exact IP/port.
- **Checks**: CGNAT (router's external IP ≠ public IP → warn port forwarding can't
  work), UPnP disabled, public IP changed since last run. Later: dynamic DNS.
- Listeners: configure OSCAR advertised addresses for both LAN and WAN.
- Accounts: add / delete / reset password (management API `POST /user` etc.).
- Online users and chat rooms; "Require passwords" (`DISABLE_AUTH=false`) on by default.
- **Invites**: invite tree (who invited whom), active codes, revoke.
- **Needs review / Banned** lists with Approve, Unban, Trust buttons.
- **Trusted households**: mark an IP or device id as trusted (skips limits,
  still recorded in the invite tree).

## One port: 5190
The app listens on 5190 itself and routes each new connection by its first byte:

| First byte | Meaning | Route to |
|---|---|---|
| `0x2A` (`*`) | OSCAR FLAP | Open OSCAR Server (internal port) |
| `0x16` | TLS ClientHello | Account API (HTTPS, below) |
| `G`/`H`/`P` | Plain HTTP | Invite landing pages and downloads |

The TLS certificate is self-signed and generated on first run. Its SHA-256
fingerprint (of the DER certificate, lowercase hex) goes in every invite link so
clients can pin it.

## Invite links
```
http://HOST:5190/i/CODE#fp=SHA256HEX&by=InviterName
aim://invite?server=HOST:5190&code=CODE&fp=SHA256HEX&by=InviterName
```
- `GET /i/CODE` → landing page: who invited you, which server, download buttons
  (Android APK, Windows zip, Linux tarball), an "Open in AIM" button (the `aim://`
  link), and JavaScript that copies the invite link to the clipboard when a
  download button is tapped (the Android client checks the clipboard on first run).
- `GET /i/CODE/windows.zip` and `/i/CODE/linux.tar.gz`: the client build with an
  `invite.json` added next to the executable:
  `{"server":"HOST:5190","code":"CODE","fp":"…","by":"Inviter"}`
  The client reads it on first launch, then ignores it.
- `GET /i/CODE/android.apk`: the client APK (clipboard handoff, see above).
- Client builds come from the client repo's GitHub "latest" release, cached by the server app.

Code kinds: **single** (1 use, expires in 7 days) and **household** (N uses,
default 8, expires in 30 days). Codes look like `7KQ2-M9XD` (no 0/O/1/I).

## Account API (HTTPS on 5190, JSON)
All requests include `device_id`, a random id generated once per install.
The server also records the caller's IP.

`POST /api/v1/signup`
```json
{"invite_code":"7KQ2-M9XD","screen_name":"New Kid","password":"secret12","device_id":"…"}
```
→ `200 {"ok":true}` or `4xx {"error":"message for the user","code":"…"}`
codes: `invalid_invite`, `invite_used`, `invite_expired`, `name_taken`,
`name_invalid`, `password_weak`, `rate_limited`, `banned`.

`POST /api/v1/invites` (auth: the user's own screen name + password)
```json
{"screen_name":"Hatdagger","password":"…","device_id":"…","kind":"single"}
```
→ `200 {"code":"7KQ2-M9XD","link":"http://HOST:5190/i/7KQ2-M9XD#fp=…&by=Hatdagger","uses_left":1,"expires_at":"2026-11-27T19:00:00Z"}`

## Abuse limits (defaults, all adjustable; tuned for big households)
| Same… | Allowed / 24 h | Flag for review | Auto-ban |
|---|---|---|---|
| IP address | 12 accounts | 13+ | 25+ |
| Device id | 8 accounts | 9+ | 15+ |
| Inviter | 10 invites used | 11+ | 20+ |
| Any of the above in 10 min | — | 6+ | 10+ |

- Flag: the new accounts work but appear in **Needs review**.
- Auto-ban: the device id and IP can't sign up, the inviter can't create codes,
  and accounts created in the burst are suspended until reviewed.
- Trusted IPs/devices skip the limits.
- Device ids can be reset by reinstalling, so the three signals are combined.
