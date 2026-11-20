AIM Server
==========

Runs your own AIM server for the AIM for Android / Windows / Linux app.

START
  Windows: double-click aim-server.exe
  Linux / Steam Deck (Desktop Mode): double-click aim-server (or run ./aim-server)

The control panel opens in your web browser (http://127.0.0.1:8190).
Press Start. To open the panel again later, run aim-server again.
To shut everything down, press "Quit" in the panel.

FIRST TIME
  1. Accounts tab: make your own screen name.
  2. Invites tab: make an invite and send the link. "Household" works for several people.
  3. People open the link, download the app and pick a screen name.

THE ONE PORT
  Everything (AIM, sign-ups, invite pages) uses TCP port 5190.
  The app asks your router to open it (UPnP). If that fails, the Server tab tells
  you exactly what to forward in your router's settings.
  Windows may ask whether to allow aim-server.exe through the firewall:
  tick "Private networks" (and "Public" only if you know you need it).

YOUR DATA
  Kept in the "AIM Server Data" folder next to the program: accounts database
  (oscar.sqlite), invites (state.json), settings and the server's certificate.
  Back up that folder to keep everything. Don't share it.

Includes Open OSCAR Server by mk6i (MIT licence, see LICENSE-open-oscar-server.txt).
AIM and AOL are trademarks of their owners; this project is not affiliated with them.
