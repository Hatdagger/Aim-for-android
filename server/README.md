# AIM Server app

A separate app (not shipped with the client) that runs
[Open OSCAR Server](https://github.com/mk6i/open-oscar-server) for you, with a
control panel in your web browser, invite links and sign-ups for the AIM client.
Spec: [`../docs/SERVER_SPEC.md`](../docs/SERVER_SPEC.md).

Download: the **server-latest** release — `aim-server-windows.zip` or
`aim-server-linux.tar.gz` (Steam Deck: Desktop Mode). Both include Open OSCAR
Server v0.25.0. See `README-app.txt` for the owner's quick start.

## How it fits together
```
internet / home Wi-Fi ──► TCP 5190 (this app's router)
                            ├─ '*' or silence → Open OSCAR Server
                            │     home-network client → LAN listener   (127.0.0.1:15190, tells clients "LAN-IP:5190")
                            │     internet client     → WAN listener   (127.0.0.1:15191, tells clients "public-IP:5190")
                            ├─ TLS     → account API: POST /api/v1/signup, /api/v1/invites
                            └─ HTTP    → invite pages /i/CODE and downloads with invite.json
control panel ──► 127.0.0.1:8190 (this computer only)
Open OSCAR Server management API ──► 127.0.0.1:15192 (never exposed)
```
- AIM clients often wait for the server to speak first, so a connection that
  stays silent for 0.8 s is treated as AIM. The AIM for Android client speaks
  first, so it never waits.
- Password checks for `/api/v1/invites` do a real AIM 5.x MD5 sign-on against the
  server and stop before signing on.
- UPnP opens 5190 on the router while running (renewed every 20 min, removed on
  Stop). The app warns about CGNAT (router's address ≠ public address) and public
  address changes; a dynamic DNS name can be set in Settings.
- Sign-up limits per 24 h (IP / device / inviter / 10-minute bursts) flag or ban as
  in the spec. Trusted IPs/devices skip limits.

## Files (data folder "AIM Server Data" next to the program)
`settings.json`, `state.json` (invites, sign-ups, bans, trusted), `oscar.sqlite`
(Open OSCAR Server's database), `settings.env` (rewritten on each start),
`tls-cert.pem`/`tls-key.pem`, `panel-token`, `clients/` (cached client builds).

## Developing
Go 1.22+, standard library only.
```
go test ./...                                   # unit tests
OSCAR_BIN=/path/to/open_oscar_server go test ./...   # + live tests
go run . -data /tmp/aimdata -oscar /path/to/open_oscar_server
```
Flags: `-data`, `-oscar`, `-start`, `-no-browser`, `-port`, `-panel-port`, `-offline`.
