# Tonarm (`harbour-tonarm`)

Inoffizieller SailfishOS-Client für [Music Assistant](https://www.music-assistant.io/).
Silica-QML, spricht die WebSocket-API des MA-Servers direkt an.

Nicht mit dem Music-Assistant-Projekt verbunden. Der Name "Music Assistant"
gehört dessen Urhebern; diese App heisst deshalb Tonarm.

**Stand: Ausbaustufe 4** (v0.16) -- Fernbedienung, Bibliothek, Suche,
Warteschlange und Sperrbildschirm-Steuerung. Der Ausbauplan steht in
[`KONZEPT.md`](KONZEPT.md).

Auf einem Jolla Phone (2026) gegen einen echten Music-Assistant-Server
verifiziert; besteht `sfdk check` (harbour und rpmlint, je ohne Befund).

Baut sauber für `SailfishOS-5.1.0.11-{armv7hl,aarch64}`, besteht `sfdk check`
(harbour und rpmlint, je ohne Befund) und läuft auf einem Jolla Phone (2026)
gegen einen echten Server.

## Was die App kann

- **Player-Liste**: alle Player der Anlage mit dem, was gerade läuft,
  Fortschrittsbalken und Play/Pause direkt in der Zeile; nicht verfügbare
  Player bleiben sichtbar, aber ausgegraut
- **Now Playing** je Player: Cover, Titel/Interpret/Album, Fortschrittsregler
  zum Springen, Weiter/Zurück, Lautstärke, Stummschaltung -- und einen
  Netzschalter, falls der Player einen hat. Bei Radio steht "Live" statt
  eines Reglers; bei Hörbüchern und Podcast-Folgen gibt es das aktuelle
  Kapitel, Sprünge um -15 s / +30 s, das Tempo, und Weiter/Zurück springen
  zwischen Kapiteln. Im Pulley-Menü: **Songtext**, mitlaufend mit
  hervorgehobener Zeile (Tippen springt dorthin), und ein **Einschlaftimer**
  (15–90 Minuten oder bis Titel-/Kapitelende; läuft auf dem Server)
- **Bibliothek**: Interpreten, Alben, Titel, Playlists, Radio, Podcasts und
  Hörbücher mit Anzahl, seitenweise nachgeladen und je Liste durchsuchbar;
  Album- und Interpretenseiten mit Cover, Playlists mit ihren Titeln,
  Podcasts mit ihren Folgen; dazu "Zuletzt gehört" und "Weiterhören"
  (angefangene Hörbücher und Podcast-Folgen)
- **Hörbuchseite**: Autoren, Sprecher, Fortschritt, Weiterhören oder von vorn,
  als beendet bzw. nicht begonnen markieren, und die Kapitel -- läuft das
  Buch, ist das aktuelle markiert und ein Tippen springt dorthin
- **Suche** über alle Medientypen auf einer Seite, nach Typ gruppiert --
  überall oder nur in der Bibliothek; Treffer eines Streaming-Dienstes nennen
  ihn ("Apple Music · Interpret")
- **Abspielen aus jeder Liste** per Kontextmenü (jetzt spielen, als Nächstes,
  anhängen); auf welchem Player das landet, wählt man einmal aus
- **Warteschlange**: sehen, was noch kommt, per Tippen dorthin springen,
  Einträge verschieben oder entfernen; zufällige Reihenfolge, Überblenden und
  Wiederholen; an einen anderen Player übergeben, als Playlist speichern oder
  leeren
- **Cover-Page** mit laufendem Titel, Albumbild und Play/Pause -- bedienbar,
  ohne die App zu öffnen
- **Sperrbildschirm und Medientasten** über MPRIS: Titel, Interpret, Album,
  Cover und Spielzeit werden dorthin gespiegelt, und von dort lassen sich
  Play/Pause, Weiter, Zurück, Springen und Lautstärke bedienen -- gesteuert
  wird dabei der entfernte Player, die App gibt selbst kein Audio aus
- **Favoriten**: im Kontextmenü jeder Bibliothekszeile setzen oder entfernen,
  als Stern in der Liste sichtbar, und jede Liste lässt sich auf "Nur
  Favoriten" umstellen
- **Lautsprecher gruppieren**: mehrere Lautsprecher synchron zusammenschalten,
  mit gemeinsamer Lautstärke und einem Regler je Lautsprecher -- angeboten
  werden nur die, die der Server tatsächlich synchronisieren kann
- **Lautstärke folgt dem Finger**: sie ändert sich schon beim Ziehen, und der
  Regler springt danach nicht zurück
- **Optionale Benachrichtigung** bei Titelwechsel (standardmässig aus)
- **Demomodus** (Einstellungen): ein erfundener Server mit fünf Räumen, Musik,
  Radio, einem Hörbuch und einem Podcast — zum Ausprobieren ohne eigenen
  Server

Die App verlangt dafür die **Audio**-Berechtigung, obwohl sie kein Audio
ausgibt: auf SailfishOS ist das die Berechtigung, die das Anmelden eines
MPRIS-Dienstes erlaubt ("show audio controls on lockscreen"). Der
Berechtigungsdialog nennt sie dem Nutzer gegenüber allerdings "Audio
aufzeichnen und abspielen" -- einen feineren Weg gibt es nicht.
- **Live-Aktualisierung** per Server-Events (`player_updated`, `queue_updated`,
  `queue_time_updated`) statt durch Nachfragen; zwischen zwei Meldungen zählt
  die Spielzeit lokal weiter. Nach der Rückkehr aus dem Hintergrund prüft die
  App die Verbindung und lädt nach, was verpasst sein kann
- **Zweite Adresse für unterwegs** (VPN, Tailscale, Reverse-Proxy): die App
  versucht zuerst die Heimadresse, eine halbe Sekunde später die andere, und
  nimmt, was zuerst antwortet
- **Cover bleiben auf dem Gerät** (höchstens 100 MB) und kommen nach einem
  Neustart nicht wieder über das Netz
- Serveradresse und Zugriffstoken verschlüsselt über Sailfish Secrets
  (`src/credentials.{h,cpp}`), Erreichbarkeitstest gegen `GET /info`
- WebSocket-Verbindung mit `ServerInfo`/`auth`-Handshake, automatischer
  Reconnect mit wachsendem Abstand, Warnung bei inkompatibler Schema-Version

## Voraussetzungen

- Ein erreichbarer Music-Assistant-Server im lokalen Netz (Standardport 8095).
  Läuft er als Home-Assistant-App, ist das die Adresse des HA-Rechners -- die
  App benutzt das Host-Netz, eine Portfreigabe ist nicht nötig. Nicht die
  Ingress-Adresse aus der HA-Oberfläche verwenden.
- Ein Long-Lived Access Token, in der MA-Oberfläche unter
  Einstellungen → Profil erzeugt. Für die späteren Ausbaustufen braucht es
  mindestens die Scopes `LIBRARY_READ`, `QUEUES_READ` und `QUEUES_CONTROL`;
  ein Token mit der Rolle `admin` deckt alles ab.

Der konkret vermessene Zielserver dieses Projekts ist in
[`KONZEPT.md`](KONZEPT.md) Abschnitt 12 dokumentiert.

## Bauen

`sfdk config` gilt nur für die laufende Shell-Sitzung -- Konfiguration und
Kommando müssen verkettet werden, sonst greift die globale Voreinstellung
(die zeigt hier auf ein fremdes Projekt):

```sh
sfdk config target=SailfishOS-5.1.0.11-armv7hl \
  && sfdk config specfile=rpm/harbour-tonarm.spec \
  && sfdk build
```

Das Paket landet in `RPMS/`. Icons werden nicht automatisch erzeugt; nach
Änderungen am Motiv:

```sh
python3 icons/source/generate-icon.py   # braucht python3-cairo
```

## Aufbau

```
src/credentials.{h,cpp}            Sailfish Secrets: Adresse, Token, Adresse unterwegs
src/covercache.{h,cpp}             Cover-Zwischenspeicher auf der Platte (QNetworkDiskCache)
src/harbour-tonarm.cpp             QML laden, Cache-Fabrik, Kontext-Properties
qml/harbour-tonarm.qml             Wurzelfenster: Verbindung (echt oder Demo) und Zustand
qml/components/MassConnection.qml  WebSocket(s), Handshake, Kommandos, Events, Reconnect,
                                   Heim-/Unterwegs-Adresse im Wettlauf
qml/components/DemoConnection.qml  Demomodus: Music-Assistant-Server im Speicher
qml/components/PlayerStore.qml     Player und Warteschlangen, per Events aktuell; Kommandos
qml/components/VolumeSlider.qml    Lautstärke live beim Ziehen, ohne Zurückspringen
qml/components/MediaListItem.qml   Bibliothekszeile samt Abspiel-Kontextmenü
qml/components/StatusToast.qml     kurze Rückmeldung am unteren Rand
qml/components/MprisBridge.qml     MPRIS-Dienst für Sperrbildschirm/Medientasten
qml/components/TrackNotifier.qml   optionale Meldung bei Titelwechsel
qml/lib/MassApi.js                 URL-Ableitung, Nachrichtenbau, /info-Probe
qml/lib/MassModels.js              Fähigkeiten, Spielzeit, Now Playing, Kapitel, Gruppen
qml/lib/Navigate.js                wohin ein angetipptes Medienobjekt führt
qml/lib/DemoData.js                erfundener Bestand des Demomodus
qml/demo/art/                      Cover des Demomodus (store/generate-demo-art.py)
qml/pages/PlayersPage.qml          Startseite: die Player der Anlage
qml/pages/NowPlayingPage.qml       Cover, Titel, Transport, Lautstärke; Radio, Kapitel, Tempo
qml/pages/LibraryPage.qml          Einstieg: Medientypen mit Anzahl
qml/pages/MediaListPage.qml        seitenweise Liste je Medientyp, durchsuchbar
qml/pages/RecentlyPlayedPage.qml   Zuletzt gehört / Weiterhören
qml/pages/AlbumPage.qml            Album mit Titelliste
qml/pages/ArtistPage.qml           Interpret mit Alben
qml/pages/PlaylistPage.qml         Playlist mit Titeln
qml/pages/PodcastPage.qml          Podcast mit Folgen
qml/pages/AudiobookPage.qml        Hörbuch: Fortschritt, Weiterhören, Kapitel
qml/pages/LyricsPage.qml           Songtext, mitlaufend
qml/pages/SleepTimerPage.qml       Einschlaftimer
qml/pages/SearchPage.qml           Suche über alle Medientypen, überall oder nur Bibliothek
qml/pages/QueuePage.qml            Warteschlange ansehen und bearbeiten
qml/pages/GroupPage.qml            Lautsprecher zusammenschalten, Einzellautstärken
qml/pages/SavePlaylistDialog.qml   Name für die gespeicherte Warteschlange
qml/pages/PlayerPickerPage.qml     Player auswählen (Ziel oder Übergabe)
qml/pages/SettingsPage.qml         Adressen, Token, Tests, Demo, Anzeige, Cache, Serverangaben
qml/cover/CoverPage.qml            laufendes Stück mit Play/Pause und Weiter
scripts/ma-probe.mjs               den Server befragen, bevor QML entsteht
```

## Den Server befragen

`scripts/ma-probe.mjs` (Node 22+) zeigt, welche Kommandos der Server kennt und
wie seine Antworten tatsächlich aussehen -- Feldnamen vom echten Server, nicht
aus der Dokumentation. Zugangsdaten stehen in `.env` im Projektverzeichnis
(`MA_URL=…`, `MA_TOKEN=…`; steht in `.gitignore`).

```sh
node scripts/ma-probe.mjs                          # Übersicht: Server, Player, Bibliothek
node scripts/ma-probe.mjs --find playback_speed    # Kommandos suchen (ohne Token)
node scripts/ma-probe.mjs music/audiobooks/library_items '{"limit":1}'
node scripts/ma-probe.mjs --events 20              # 20 s Ereignisse mitschneiden
```

Lange Listen werden gekürzt (`--full` zeigt alles). Achtung: Das Skript führt
jedes Kommando aus, auch schreibende wie `player_queues/play_media`.

## Sprache

Deutsch und Englisch. Die Quelltext-Strings sind deutsch, Englisch liegt als
vollständige Übersetzung in `translations/harbour-tonarm-en.ts` (284 von 284
Einträgen) und wird beim Bauen zu `harbour-tonarm-en.qm` übersetzt.

## Store-Material

`store/` enthält Icon, Cover, Zusammenfassung und Beschreibung auf Deutsch und
Englisch, Bildschirmfotos und eine README, die Feld für Feld dem
Harbour-Einreichungsformular folgt.

## Lizenz

MIT, siehe [`LICENSE`](LICENSE).
