# TODO: lessons from the iOS app

Findings from [Tonarm for iOS](https://github.com/silly82/Tonarm) (SwiftUI, same Music Assistant API, same server MA 2.10.4, schema 65) that apply to this Sailfish client. Checked against the code of v0.18 on 2026-09-27; each item says what is here today. Ordered by value for effort. Sections 1 and 4 are done in v0.20 (KONZEPT section 24), section 2 in v0.21 (section 25), section 3 in v0.22 (section 26).

## 1. Bugs and gaps that are cheap to close

- [x] **Now playing artwork over another address.** `current_media.image_url` is an absolute URL built from the server's own LAN `base_url` (`MassModels.js`, `nowPlaying()`). Connected through VPN/Tailscale or a reverse proxy, the cover on Now Playing, the cover page and MPRIS then points at an address the phone cannot reach. Fix: keep everything from `/imageproxy` onward and put the active `baseUrl` (scheme, host, port, base path) in front (Tonarm: `ImageURL.rebased`). Library images are not affected; they are built from `baseUrl` already.
- [x] **Back from the background / after sleep.** Nothing reacts to `Qt.application.state` yet. On `Qt.ApplicationActive`: send `info` with a short timeout (3 s). No answer: close the socket and reconnect at once (the state may still say "ready" while the socket is dead). Answer: reload players and queues (and an open queue page), because events were missed. Also reset the backoff, so a return does not wait out a 60 s retry.
- [x] **Radio in Now Playing.** While a station plays, MA 2.10.4 sends the stream title (ICY) as `title`, the station as `artist`, its entry (e.g. "Radio SRF 3 (AAC 192)") as `album` and `duration` null (checked on a speaker, 2026-09-27). Today the progress slider already hides (duration 0), but the album line repeats the station. Detect live media (`current_media.media_type === "radio"`, or the queue item's), show "Live" instead of the slider, drop the repeated album line, hide shuffle/repeat on the queue page for it.
- [x] **`device_name` in `auth`.** Send `device_name` next to `token` and `locale` (e.g. "Tonarm (Sailfish)"), so the server lists the client by name.
- [x] **Delayed connection error.** Show a connection problem only after about 1.5 s, so quick reconnects do not flash; keep "not connected" command errors quiet while the status already explains them; a tap on the status reconnects at once (no backoff).

## 2. Volume and groups

- [x] **Volume live while dragging.** Today both sliders (Now Playing, `GroupPage`) send only `onReleased`. Tonarm: while dragging, send the latest value at most every 150 ms plus the final one on release; the slider keeps its own value until the server reports it (±1) or 3 s pass (no snapping back); volume commands per player go out in order (chain them, do not fire in parallel). Checked live: a burst of levels ends on the last one.
- [x] **Individual volumes in a group.** `GroupPage` has the group volume only. Add one slider per member (leader first), each sending `players/cmd/volume_set` for that speaker. Fixed group players (MA player type `group`) get them too.
- [x] **Document group volume semantics.** `group_volume` in MA 2.10.4 (`set_group_volume`) scales the members from a snapshot of their levels: down proportionally, up each toward 100 by the same share (30/10 at group 15 gives 15/5). A leader leaving its group: the remaining member takes over the queue and keeps playing after a few seconds. Both checked live; worth a line in `KONZEPT.md`.

## 3. Search and library

- [x] **Search scope.** `music/search` takes `library_only` (bool). Offer "Library" and "Everywhere" (streaming providers included); today the app always searches both (the placeholder says so) and cannot narrow it.
- [x] **Name the streaming service.** Load `providers` once per connect and put the service in front of the subtitle for items outside the library ("Apple Music · Artist").
- [x] **Two-line titles** in `MediaListItem` and the queue instead of fade truncation (Tonarm did this after its UI tours; long titles often differ only at the end).

## 4. Audiobooks and podcasts (bigger)

Today an audiobook plays from the context menu only. The API facts from Tonarm (built and unit-tested there, not yet run against a real audiobook provider):

- [x] **Detail page:** `music/audiobooks/get`; authors, narrators, progress from `resume_position_ms` and `fully_played` (Bool; 0/1 for podcast episodes); chapters in `metadata.chapters` (`position`, `name`, `start`, `end`, seconds of the book).
- [x] **Resume / from start:** the server resumes a started book on play, so "from start" first sends `music/mark_unplayed`. `music/mark_played` / `mark_unplayed` take `media_item` exactly as the server sent it.
- [x] **Now Playing for spoken content** (audiobook, podcast episode): back 15 s / forward 30 s instead of shuffle/repeat; next/previous jump chapters as seeks (previous within 5 s of a chapter start goes to the chapter before); current chapter shown; speed via `player_queues/set_playback_speed` (`queue_id`, `speed`), only where the queue reports `playback_speed`. MPRIS next/previous should follow the same chapter logic.
- [x] **Continue listening:** `music/in_progress_items(limit)` as an entry on `RecentlyPlayedPage` or the library page.

## 5. Remote access

- [ ] **Second ("away") address with fallback.** Tonarm keeps home and away address of the same server (away e.g. `http://<host>.<tailnet>.ts.net:8095`) and tries them staggered: the last one that worked starts at once, the next 0.5 s later, the first `ServerInfo` wins, the other socket is closed. At home the LAN answers in milliseconds, so the away address is never touched. After a network change start over with the home address. On Sailfish: two `WebSocket` objects in `MassConnection`, credentials entry `harbour-tonarm-awayUrl`; network change from `Qt.application.state` plus reconnect is enough to start with. Needs the artwork rebase from section 1.
- [ ] **MA's own WebRTC remote access stays a non-goal.** Tonarm proved it works (Remote ID, signaling server, `http_proxy` data channel for artwork, DTLS fingerprint check), but it needs libwebrtc, which is neither in Harbour's allowed libraries nor reasonable to ship in an RPM. VPN/Tailscale remains the way (KONZEPT section 2 stands).

## 6. Store, tests, tooling

- [ ] **Demo mode.** Tonarm has an in-memory MA server (four made-up rooms, library, groups, an audiobook, radio) behind the same transport interface. Here it would be a `DemoConnection.qml` with the same API as `MassConnection` (`sendCommand`, `serverEvent`, `ready`). It solves what `store/README.md` leaves open: screenshots of the player list, Now Playing and the queue without showing the rooms of the flat. Also a first look for people without a server.
- [ ] **Artwork disk cache.** The image proxy answers with `Cache-Control: max-age` of a year. QML's `Image` caches in memory only; a `QQmlNetworkAccessManagerFactory` with a `QNetworkDiskCache` (in the app's cache directory, e.g. 100 MB) in `harbour-tonarm.cpp` keeps covers across starts and saves mobile data. Check Harbour: `QNetworkDiskCache` is part of Qt5Network, so it should pass.
- [ ] **Server probe script.** Take over `scripts/ma-probe.mjs` from Tonarm (connect, hello, auth, `players/all`; token from `.env`, gitignored) for checking API shapes before writing QML, the discipline from KONZEPT sections 12 and 15.
- [ ] **Previous restarts the track** a few seconds in (server behaviour, checked live): no code change, but MPRIS and the button should not try to be smarter.

Not applicable: Siri/App Intents, keyboard shortcuts and menu bar, iPhone Duo fold layout, iPad grids, Dynamic Type (Silica scales with the theme), TestFlight.

---

# TODO: Erkenntnisse aus der iOS-App (Deutsch)

Befunde aus [Tonarm für iOS](https://github.com/silly82/Tonarm) (SwiftUI, dieselbe Music-Assistant-API, derselbe Server MA 2.10.4, Schema 65), die auf diesen Sailfish-Client passen. Am 27.9.2026 gegen den Code von v0.18 geprüft; jeder Punkt sagt, was hier heute steht. Sortiert nach Nutzen pro Aufwand. Abschnitte 1 und 4 sind in v0.20 erledigt (KONZEPT Abschnitt 24), Abschnitt 2 in v0.21 (Abschnitt 25), Abschnitt 3 in v0.22 (Abschnitt 26).

## 1. Fehler und Lücken, die sich billig schliessen lassen

- [x] **Now-Playing-Cover über eine andere Adresse.** `current_media.image_url` ist eine absolute Adresse, gebaut aus der eigenen LAN-`base_url` des Servers (`MassModels.js`, `nowPlaying()`). Über VPN/Tailscale oder einen Reverse-Proxy zeigt das Cover auf Now Playing, der Cover-Page und in MPRIS dann auf eine Adresse, die das Telefon nicht erreicht. Lösung: alles ab `/imageproxy` behalten und die aktive `baseUrl` (Schema, Host, Port, Basispfad) davorsetzen (Tonarm: `ImageURL.rebased`). Bibliotheksbilder sind nicht betroffen, die werden bereits aus `baseUrl` gebaut.
- [x] **Rückkehr aus dem Hintergrund / nach dem Schlafen.** Auf `Qt.application.state` reagiert noch nichts. Bei `Qt.ApplicationActive`: `info` mit kurzer Frist (3 s) schicken. Keine Antwort: Socket schliessen und sofort neu verbinden (der Zustand kann noch "ready" sagen, während der Socket tot ist). Antwort: Player und Warteschlangen (und eine offene Warteschlangen-Seite) neu laden, weil Ereignisse verpasst wurden. Ausserdem den Backoff zurücksetzen, damit eine Rückkehr nicht einen 60-s-Versuch abwartet.
- [x] **Radio in Now Playing.** Während ein Sender läuft, schickt MA 2.10.4 den Stream-Titel (ICY) als `title`, den Sender als `artist`, dessen Eintrag (z. B. "Radio SRF 3 (AAC 192)") als `album` und `duration` null (an einem Lautsprecher geprüft, 27.9.2026). Der Fortschrittsregler verschwindet heute schon (Dauer 0), aber die Albumzeile wiederholt den Sender. Live-Medien erkennen (`current_media.media_type === "radio"` oder das des Queue-Eintrags), "Live" statt des Reglers zeigen, die doppelte Albumzeile weglassen, Zufall/Wiederholen auf der Warteschlangen-Seite dafür ausblenden.
- [x] **`device_name` bei `auth`.** Neben `token` und `locale` auch `device_name` schicken (z. B. "Tonarm (Sailfish)"), damit der Server den Client beim Namen führt.
- [x] **Verbindungsfehler verzögert zeigen.** Ein Verbindungsproblem erst nach etwa 1,5 s anzeigen, damit kurze Neuverbindungen nicht aufblitzen; Kommandofehler "nicht verbunden" still lassen, solange der Status das schon erklärt; Tippen auf den Status verbindet sofort neu (ohne Backoff).

## 2. Lautstärke und Gruppen

- [x] **Lautstärke live beim Ziehen.** Heute senden beide Regler (Now Playing, `GroupPage`) nur bei `onReleased`. Tonarm: beim Ziehen den jeweils letzten Wert höchstens alle 150 ms senden, beim Loslassen den Endwert; der Regler behält seinen Wert, bis der Server ihn meldet (±1) oder 3 s vergehen (kein Zurückspringen); Lautstärkebefehle pro Player gehen in Reihenfolge raus (verketten, nicht parallel feuern). Live geprüft: eine Folge von Werten endet auf dem letzten.
- [x] **Einzellautstärken in einer Gruppe.** `GroupPage` hat nur die Gruppenlautstärke. Pro Mitglied einen Regler ergänzen (Anführer zuerst), jeder schickt `players/cmd/volume_set` für seinen Lautsprecher. Feste Gruppen-Player (MA-Playertyp `group`) bekommen sie auch.
- [x] **Semantik der Gruppenlautstärke festhalten.** `group_volume` skaliert in MA 2.10.4 (`set_group_volume`) die Mitglieder ausgehend von einer Momentaufnahme ihrer Werte: nach unten proportional, nach oben jedes um denselben Anteil Richtung 100 (30/10 bei Gruppe 15 ergibt 15/5). Verlässt der Anführer die Gruppe, übernimmt das verbleibende Mitglied die Warteschlange und spielt nach einigen Sekunden weiter. Beides live geprüft; eine Zeile in `KONZEPT.md` wert.

## 3. Suche und Bibliothek

- [x] **Suchbereich.** `music/search` nimmt `library_only` (bool). "Bibliothek" und "Überall" (inkl. Streaming-Anbieter) anbieten; heute sucht die App immer in beidem (der Platzhalter sagt es) und lässt sich nicht einschränken.
- [x] **Streaming-Dienst nennen.** `providers` einmal pro Verbindung laden und bei Einträgen ausserhalb der Bibliothek den Dienst vor die Unterzeile setzen ("Apple Music · Interpret").
- [x] **Zweizeilige Titel** in `MediaListItem` und der Warteschlange statt Ausblenden (in Tonarm nach den UI-Durchgängen umgesetzt; lange Titel unterscheiden sich oft erst am Ende).

## 4. Hörbücher und Podcasts (grösser)

Heute spielt ein Hörbuch nur über das Kontextmenü. Die API-Fakten aus Tonarm (dort gebaut und mit Unit-Tests geprüft, noch nicht gegen einen echten Hörbuch-Anbieter gelaufen):

- [x] **Detailseite:** `music/audiobooks/get`; Autoren, Sprecher, Fortschritt aus `resume_position_ms` und `fully_played` (Bool; bei Podcast-Folgen 0/1); Kapitel in `metadata.chapters` (`position`, `name`, `start`, `end`, Sekunden im Buch).
- [x] **Weiterhören / Von vorn:** Der Server setzt ein begonnenes Buch beim Abspielen fort, "Von vorn" schickt deshalb zuerst `music/mark_unplayed`. `music/mark_played` / `mark_unplayed` nehmen `media_item` genau so, wie der Server es geschickt hat.
- [x] **Now Playing für Gesprochenes** (Hörbuch, Podcast-Folge): −15 s / +30 s statt Zufall/Wiederholen; Weiter/Zurück springen per Seek zwischen Kapiteln (Zurück innerhalb 5 s nach Kapitelbeginn geht ins vorherige); aktuelles Kapitel anzeigen; Tempo über `player_queues/set_playback_speed` (`queue_id`, `speed`), nur wo die Queue `playback_speed` meldet. MPRIS-Weiter/Zurück sollte derselben Kapitel-Logik folgen.
- [x] **Weiterhören-Liste:** `music/in_progress_items(limit)` als Eintrag auf `RecentlyPlayedPage` oder der Bibliotheksseite.

## 5. Fernzugriff

- [ ] **Zweite Adresse ("unterwegs") mit Rückfall.** Tonarm hält Heim- und Unterwegs-Adresse desselben Servers (unterwegs z. B. `http://<host>.<tailnet>.ts.net:8095`) und probiert sie gestaffelt: die zuletzt funktionierende startet sofort, die nächste 0,5 s später, das erste `ServerInfo` gewinnt, der andere Socket wird geschlossen. Zu Hause antwortet das LAN in Millisekunden, die Unterwegs-Adresse wird also nie angefasst. Nach einem Netzwechsel wieder mit der Heimadresse beginnen. Auf Sailfish: zwei `WebSocket`-Objekte in `MassConnection`, Secrets-Eintrag `harbour-tonarm-awayUrl`; als Netzwechsel genügt für den Anfang `Qt.application.state` plus Reconnect. Braucht die Cover-Umschreibung aus Abschnitt 1.
- [ ] **MAs eigener WebRTC-Fernzugriff bleibt Nicht-Ziel.** Tonarm hat gezeigt, dass er funktioniert (Remote-ID, Signaling-Server, `http_proxy`-Datenkanal für Cover, Prüfung des DTLS-Fingerabdrucks), aber er braucht libwebrtc, das weder zu Harbours erlaubten Bibliotheken gehört noch sinnvoll in ein RPM passt. VPN/Tailscale bleibt der Weg (KONZEPT Abschnitt 2 gilt weiter).

## 6. Store, Tests, Werkzeuge

- [ ] **Demomodus.** Tonarm hat einen MA-Server im Speicher (vier erfundene Räume, Bibliothek, Gruppen, ein Hörbuch, Radio) hinter derselben Transport-Schnittstelle. Hier wäre das ein `DemoConnection.qml` mit derselben API wie `MassConnection` (`sendCommand`, `serverEvent`, `ready`). Das löst, was `store/README.md` offen lässt: Bildschirmfotos von Player-Liste, Now Playing und Warteschlange, ohne die Räume der Wohnung zu zeigen. Dazu ein erster Blick für Leute ohne Server.
- [ ] **Cover-Cache auf der Platte.** Der Bildproxy antwortet mit `Cache-Control: max-age` von einem Jahr. QMLs `Image` cacht nur im Speicher; eine `QQmlNetworkAccessManagerFactory` mit `QNetworkDiskCache` (im Cache-Verzeichnis der App, z. B. 100 MB) in `harbour-tonarm.cpp` behält Cover über Neustarts und spart Mobilfunkdaten. Harbour prüfen: `QNetworkDiskCache` gehört zu Qt5Network, sollte also durchgehen.
- [ ] **Server-Probe-Skript.** `scripts/ma-probe.mjs` aus Tonarm übernehmen (verbinden, hello, auth, `players/all`; Token aus `.env`, gitignored), um API-Formen zu prüfen, bevor QML entsteht -- die Disziplin aus KONZEPT Abschnitt 12 und 15.
- [ ] **Zurück startet den Titel neu**, wenn er schon einige Sekunden läuft (Serververhalten, live geprüft): keine Codeänderung, aber MPRIS und der Knopf sollten nicht klüger sein wollen.

Nicht übertragbar: Siri/App Intents, Tastenkürzel und Menüleiste, Falz-Layout des iPhone Duo, iPad-Raster, Dynamic Type (Silica skaliert mit dem Theme), TestFlight.
