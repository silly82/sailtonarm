# Tonarm – Entwicklung

Für alle, die an Tonarm weiterbauen. Dieses Dokument fasst zusammen, was in
[`../KONZEPT.md`](../KONZEPT.md) über 34 Abschnitte verteilt steht: den Aufbau
der App, was der Music-Assistant-Server **tatsächlich** liefert (gemessen,
nicht aus der Dokumentation), wie auf dem Gerät getestet wird, der
Release-Ablauf und die Stolperfallen. Bei Widersprüchen gilt KONZEPT.md; dort
steht jeweils, wann und wie etwas geprüft wurde.

Stand: v0.30, gemessen gegen Music Assistant 2.10.4 (API-Schema 65).

---

## 1. Aufbau

```
C++ (klein)                     QML/JS (fast alles)
─────────────                   ──────────────────────────────────────────────
Credentials  ─ Secrets ─┐       harbour-tonarm.qml  (Wurzel: wählt die Verbindung)
CoverCache   ─ Disk     │         ├─ MassConnection   echte WebSocket-Verbindung
 (NAM-Fabrik)           │         ├─ DemoConnection   Server im Speicher (Demo)
                        └──────▶  ├─ PlayerStore      Player, Queues, alle Kommandos
                                  ├─ MprisBridge      Sperrbildschirm
                                  └─ Seiten (pages/)  lesen Store, rufen Store
lib/MassApi.js     URL-Ableitung, Nachrichten, Fehlertexte
lib/MassModels.js  reine Rechenhilfen (Now Playing, Kapitel, LRC, Gruppen, …)
lib/Navigate.js    wohin ein Medienobjekt führt
lib/DemoData.js    erfundener Bestand
```

Grundsätze, die sich bewährt haben:

- **Eine Verbindung, per Property weitergereicht** (`mass: …`), kein
  QML-Singleton: die waren in diesem Setup unzuverlässig. `appWindow.mass` ist
  je nach Demomodus `MassConnection` oder `DemoConnection` -- beide haben
  dieselbe Schnittstelle (`sendCommand`, `serverEvent`, `authenticated`,
  `resynced`, `ready`, `activeBaseUrl`, …). Seiten wissen nicht, womit sie
  reden.
- **Kommandonamen stehen an genau einer Stelle**: `PlayerStore`. Seiten rufen
  Store-Funktionen; Ausnahmen sind reine Lese-Abfragen einer Seite
  (Albumtitel, Suche).
- **Zustand kommt vom Server.** Nach dem Laden tragen nur Server-Ereignisse
  (`player_updated`, `queue_updated`, `queue_time_updated`,
  `queue_items_updated`) Änderungen ein. Wo der Server kein Ereignis schickt
  (Favoriten, gehört-Markierung, Bibliothek), merkt sich die Zeile ihren Stand
  lokal (`favoriteOverride`, `playedOverride`, `libraryOverride`).
- **Regler nie an den Serverwert binden**, sonst springt der Griff unter dem
  Finger. Nachziehen nur, wenn niemand hält (`VolumeSlider`, Tempo).
- **Deutsch ist die Quellsprache**, Englisch die `.ts`. Deshalb keine
  `%n`-Pluralformen für deutsche Texte (die hülfen nur dem Englischen); die
  Einzahl steht ausdrücklich im Code ("1 Eintrag").
- Kommentare erklären das *Warum*, gern mit dem Befund, der dazu geführt hat.

---

## 2. Die Server-API, wie sie wirklich ist

Handshake: Socket öffnen → Server schickt `ServerInfo` → Client schickt
`auth {token, locale, device_name}` → Antwort → ab da Ereignisse. Grosse Listen
kommen in Stücken mit `partial: true`. Fehlercode 20 = Anmeldung nötig,
23 = Token ungültig (beide englisch, weil vor der Anmeldung).

Werkzeug zum Nachsehen: `scripts/ma-probe.mjs` (siehe README) und die
Befehlsliste `/api-docs/commands.json` bzw. das Schema `/api-docs/schemas.json`
des laufenden Servers -- beides ohne Token abrufbar.

### Player, Warteschlange, Lautstärke

| Befund | Folge |
|---|---|
| `player_queues/*` (Play, Weiter, Springen) prüfen keine `supported_features`, nur ob die Queue aktiv ist | Transport-Knöpfe nie an Features binden; Features nur für `players/cmd/*` |
| Queue-Feld `items` ist eine **Anzahl** | Einträge über `player_queues/items` holen |
| `move_item` nimmt `pos_shift` relativ; ein Sprung vor den laufenden Titel tut nichts, ohne Fehler | UI bietet nur ±1 und "ans Ende" |
| Gruppen stehen doppelt: `group_childs`/`group_members` beim Anführer, `synced_to`/`active_group` beim Mitglied, je nach Anbieter nur eine Hälfte | alle vier prüfen; Sonos listet den Anführer in den eigenen `group_childs` |
| `group_volume` skaliert nach unten im Verhältnis, nach oben Richtung 100; gemeldete Gruppenlautstärke folgt dem lautesten Mitglied | so auch im Demo-Server |
| Lautstärke parallel gesendet kann in falscher Reihenfolge ankommen | je Player seriell, nur neuester Wert nachgeschickt |
| Radio: ICY-Titel als `title`, Sender als `artist`, Sendereintrag als `album`, `duration` null | "Live", doppelte Albumzeile weg |
| `current_media.image_url` baut der Server aus **seiner** `base_url` | immer ab `/imageproxy` auf die verbundene Adresse umschreiben |
| Einschlaftimer: `players/sleep_timer/set(player_id, seconds)`, Ablauf am Player als `sleep_timer_expires_at` | läuft auf dem Server |
| Zurück startet nach einigen Sekunden den Titel neu | so lassen |

### Bibliothek und Medien

| Befund | Folge |
|---|---|
| `get_collection` ist kaputt (Fehler 999) | Inhalte über `album_tracks`, `artist_albums`, `playlist_tracks` |
| Bildkennung ist `proxy_id` aus `metadata.images[]` (nicht `path`); `?size=` nur aus {0,80,160,256,512,1024} | `MassApi.imageUrl()` rastet ein |
| Bildproxy: `Cache-Control: max-age` ein Jahr | Plattencache in C++ (`CoverCache`) |
| `music/search` schlüsselt Radio als `radio`, der Bibliothekspräfix heisst `radios`; `library_only` ist veraltet, `providers: ["library"]` | beides beachtet |
| Favoriten: `add_item(uri)` für alles, `remove_item(media_type, library_item_id)` nur für Bibliothekseinträge; kein Ereignis | Entfernen nur bei `provider === "library"` |
| `similar_tracks` liefert hier nur 2 Titel | "Ähnliches abspielen" = `play_media` mit `radio_mode: true` (Endless Mix; schaltet Shuffle ein) |
| `artist_tracks`: Dienst → beliebteste zuerst (langsam, >10 s), Bibliothek → alphabetisch | Abschnitt "Beliebte Titel" nur beim Dienst |
| Songtexte: `metadata/get_track_lyrics({track: volles media_item})` → `[einfach, lrc]`; hier nur LRC; erste Abfrage >30 s | 120 s Frist, LRC-Parser |
| `metadata/get_image_palette(image_id)` → sechs Farben `[r,g,b]`; bei Playlist-Bildern `null` | Verlauf nur mit Farbe |
| Playlists: `add_playlist_tracks`/`remove_playlist_tracks` sind Hintergrundaufgaben; `position` ab 1 | nach dem Entfernen neu laden |
| Apple Music kann Playlists bearbeiten, aber **nicht anlegen** (Fehler 3) | neue Playlists beim Anbieter `builtin` |
| `music/library/add_item(item: uri)` / `remove_item(media_type, id)`; Entfernen ist "destruktiv" (Album nimmt Titel mit) | Entfernen nur Titel/Alben/Sender, mit Rückgängig-Frist |
| Sender: Suche findet RadioBrowser; eigene Adresse über `builtin/add_radio(url, name)` | Sender-Suchseite |

### Hörbücher und Podcasts

| Befund | Folge |
|---|---|
| Kapitel in `metadata.chapters` (position, name, start, end in s), schon im Queue-Eintrag | kein Nachladen für "Läuft gerade" |
| Server setzt begonnene Bücher fort; "von vorn" = erst `mark_unplayed` | so umgesetzt |
| `mark_played`/`mark_unplayed` wollen `media_item` unverändert zurück | ganze Objekte durchreichen |
| `fully_played` ist bei Büchern Bool, bei Folgen 0/1 | `Models.isFullyPlayed()` |
| Tempo: `player_queues/set_playback_speed`, nur wo die Queue `playback_speed` meldet | Tempo-Auswahl nur dann |
| `in_progress_items` liefert schlanke Verweise ohne Fortschritt | kein Prozentwert in "Weiterhören" |
| Overcast-Abgleich: je Podcast ~10 Folgen, `metadata.release_date`, `description` (HTML); `mark_played` wird angenommen, **wirkt aber nicht** | nach dem Markieren nachlesen und ehrlich melden |

### Sonstiges

- Durchsage: `players/cmd/play_announcement(player_id, message, pre_announce,
  volume_level)`; Antwort erst nach dem Sprechen (~12–25 s). Der Server stellt
  die Lautstärke selbst zurück. Sonos meldet danach die AirPlay-Sitzung weiter
  als "playing".
- `streams/info` gibt es auf 2.10.4 nicht (nur dev-Zweig).
- Kein Ereignis für Favoriten, Bibliothek, gehört-Stand.

---

## 3. Sailfish-Eigenheiten

- **MPRIS** (`Amber.Mpris`): der Busname braucht die **Audio**-Berechtigung;
  `canControl`, `hasShuffle`, `hasLoopStatus` werden beim ersten `GetAll`
  eingefroren -- statisch `true` lassen; Zeiten in **Millisekunden**,
  Lautstärke 0..1; `mpris:trackid` muss ein D-Bus-Objektpfad sein.
- **Sailjail**: Cache nur unter `QStandardPaths::CacheLocation`
  (`~/.cache/<Organisation>/<App>`). Nach einem Update fragt das System
  unter Umständen erneut nach Secrets-Zugriff.
- **Silica**: kein `pop()` während einer Dialog-Animation -- bei Dialogen
  `acceptDestination` + `PageStackAction.Pop`. Kontextmenü-`MenuItem`s werden
  nach dem Schliessen zerstört: späte Rückrufe dürfen keine Seiten-ids mehr
  auflösen (vorher in lokale Variablen legen). Ein `SectionHeader` in einem
  `Loader` ragt rechts hinaus (in ein `Item` packen); ein `ListView.view`
  sieht bei Loader-Delegates der Loader, nicht die Zeile.
- `\u`-Escapes in QML-Strings mag der Parser nicht; `.pragma library`-Dateien
  können kein `qsTr`.
- Eine `QQmlNetworkAccessManagerFactory` muss vor dem ersten `setSource()`
  gesetzt werden.

---

## 4. Auf dem Gerät testen

Testgerät: Jolla Phone (2026), aarch64, per USB-Netz und SSH erreichbar
(`defaultuser@<telefon>`, `devel-su` für root). Das Telefon läuft dauerhaft
unter hoher Last (Load um 13) -- das prägt die Methode.

### Installieren und starten

```sh
scp RPMS/harbour-tonarm-X-1.aarch64.rpm defaultuser@<telefon>:/tmp/
ssh defaultuser@<telefon> "devel-su sh -c 'rpm -Uvh --force /tmp/harbour-tonarm-X-1.aarch64.rpm'"
# alte Instanz beenden (nur das Binary, nie "firejail"/"invoker" -- das trifft alle Apps):
ssh defaultuser@<telefon> 'for p in $(ps -o pid,args | grep "[/]usr/bin/harbour-tonarm$" | awk "{print \$1}"); do kill $p; done'
ssh defaultuser@<telefon> 'nohup invoker --type=silica-qt5 -s harbour-tonarm >/dev/null 2>&1 &'
```

### Logs

Das Journal auf dem Telefon hält wegen Kernel-Meldungen **nur etwa zwei
Minuten**. Logs der App deshalb während des Tests laufend einsammeln
(alle 3 s `journalctl _PID=<binary-pid> -o cat`, auf dem Rechner
zusammenführen). Die PID des Binarys, nicht die des `firejail`-Wrappers:
`ps -o pid,args | awk '$2=="/usr/bin/harbour-tonarm" && NF==2'`. BusyBox
kennt weder `timeout` noch `grep --line-buffered`.

### Bildschirmfotos

Über Lipstick per D-Bus, als root mit der Session-Bus-Adresse von
`defaultuser`; der Zielpfad muss **unter dem Home-Verzeichnis** liegen. Jedes
Bild mit eigenem Namen -- ein fehlgeschlagenes Foto liefert sonst still ein
altes gleichen Namens.

### Seiten prüfen ohne Touch (bevorzugt)

Ein **vorübergehender Timer in `harbour-tonarm.qml`** öffnet Seiten selbst
(`pageStack.push(...)`) und ruft dieselben Store-Funktionen wie die Knöpfe;
Ausgaben per `console.log` mit eindeutigem Präfix. Danach `git checkout` der
Datei und das saubere Paket **neu bauen und installieren**. So entstehen keine
verirrten Eingaben.

### Touch-Injektion (nur wenn nötig)

Rohe `input_event`s an das Touch-Gerät (Python auf dem Telefon, als root).
Wegen der Last kommen Tipper verspätet an und treffen die Seite, die sich
gerade öffnet. Regeln:

- **ein Tipper, 4–5 s warten, Kontrollbild**, dann entscheiden;
- Pulley-Züge in leeren Bereichen beginnen, nie über einer Listenzeile (sonst
  langer Druck → Kontextmenü);
- ein Tipper, der Wiedergabe auslöst, kann **über eine Minute** verzögert
  wirken -- mindestens 90 s warten und den Server prüfen, bevor man ihn für
  wirkungslos hält; nie wiederholen;
- im Demomodus sind Tipper ungefährlich.

### Echte Lautsprecher

- **Nur mit ausdrücklicher Zustimmung**, und die gilt nicht über eine lange
  Pause hinweg (Nachmittag ≠ Abend).
- Abspielen, Lautstärke, Wiederholen über **Home Assistant** steuern, nicht per
  Touch; leise (10–15 %), danach Ausgangszustand herstellen.
- Home Assistant kann veraltete Zustände zeigen; im Zweifel zählt, was die App
  zeigt. Sonos nach AirPlay-Nutzung über die AirPlay-Entität stoppen.
- Um zu beweisen, dass ein "Ende des Titels"-Timer gegriffen hat:
  *Wiederholen: ein Titel* einschalten, sonst endet die Warteschlange ohnehin.

### Schreibende Tests

Vorher fragen, was verändert werden darf; eigene Test-Objekte anlegen
("Tonarm Test"), nach jedem Schritt nachlesen, am Ende über Zähler
(`…/count`) prüfen, dass der Ausgangszustand wieder erreicht ist. Einen
abgebrochenen Test erst lesend prüfen, bevor man ihn wiederholt.

---

## 5. Bauen, prüfen, veröffentlichen

```sh
# je Architektur, jedes Mal vorher aufräumen:
for arch in aarch64 armv7hl i486; do
  rm -f harbour-tonarm *.o moc_*.cpp moc_*.h Makefile .qmake.stash RPMS/*.rpm
  sfdk config target=SailfishOS-5.1.0.11-$arch \
    && sfdk config specfile=rpm/harbour-tonarm.spec \
    && sfdk config no-fix-version \
    && sfdk build
  cp RPMS/harbour-tonarm-*-1.$arch.rpm <sammelordner>/
done
# prüfen:
sfdk check -s harbour,rpmlint <paket>        # erwartet: succeeded, 0/0/0
# Binary-Architektur im Paket (ELF e_machine: b7 aarch64, 28 arm, 03 x86):
rpm2cpio <paket> | cpio -id ./usr/bin/harbour-tonarm && od -An -tx1 -j18 -N2 usr/bin/harbour-tonarm
```

Checkliste je Version:

1. `qmllint` auf geänderte Dateien -- **auf die Ausgabe achten**: qmllint endet
   auch bei Syntaxfehlern mit Status 0.
2. Version und `%changelog` in `rpm/harbour-tonarm.spec` (deutsch).
3. Bauen; lupdate meldet neue Texte → in `translations/harbour-tonarm-en.ts`
   übersetzen, `type="unfinished"` entfernen (auch bei Einträgen, die lupdate
   aus anderem Kontext übernommen hat -- sonst verwirft `lrelease
   -nounfinished` sie). lupdate rät bei Mustern wie `%1:%2` manchmal falsch.
4. Auf dem Gerät prüfen (Abschnitt 4), Journal ohne Warnungen.
5. `KONZEPT.md` (neuer Abschnitt), README, ggf. TODO und Handbuch.
6. Commit mit Autor `Silvan Walker <siliwalker@gmail.com>`; **Leak-Prüfung**
   auf Diff *und* Metadaten: keine LAN-Adressen, Tailnet- oder Rechnernamen,
   Tokens (`git log --format='%ae %ce'`, Tagger).
7. Alle drei Architekturen bauen und prüfen, pushen, annotiertes Tag `vX.Y`,
   GitHub-Release mit den drei RPMs und zweisprachigen Notizen.

---

## 6. Wo was steht

| Thema | KONZEPT-Abschnitt |
|---|---|
| Ziele, Nicht-Ziele, Fernzugriff | 1–10 |
| Server vermessen, Build, erster Start | 12–14 |
| Stufen 1–4 (Fernbedienung, Bibliothek, Queue, MPRIS) | 15–19 |
| Favoriten, Gruppen, Englisch, Store | 20–22 |
| Hörbücher, Podcasts, Radio, Verbindung | 23–24 |
| Lautstärke live, Gruppen | 25 |
| Suche | 26 |
| Unterwegs-Adresse | 27 |
| Demomodus | 28 |
| Cover-Cache, Probe-Skript | 29 |
| Songtexte, Einschlaftimer | 30 |
| Ähnliches, Interpretenseite | 31 |
| Durchsage, Cover bei Hörbüchern | 32 |
| Podcasts wie im Podcatcher | 33 |
| Playlists, Bibliothek, Sender, Cover-Farben | 34 |

Das Konzept für Stufe 5 (Sendspin, das Telefon als Lautsprecher) liegt auf dem
Branch `sendspin-player` in `KONZEPT-ENDPOINT.md`.
