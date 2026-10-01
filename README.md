# Tonarm (`harbour-tonarm`)

Inoffizieller SailfishOS-Client für [Music Assistant](https://www.music-assistant.io/):
eine Fernbedienung für den eigenen Musikserver, ohne Cloud. Silica-QML, spricht
die WebSocket-API des Servers direkt an.

Nicht mit dem Music-Assistant-Projekt verbunden. Der Name "Music Assistant"
gehört dessen Urhebern; diese App heisst deshalb Tonarm.

**Stand: v0.32** (September 2026). Pakete für aarch64, armv7hl und i486 unter
[Releases](https://github.com/silly82/sailtonarm/releases); alle bestehen
`sfdk check` (harbour und rpmlint, je ohne Befund). Geprüft auf einem Jolla
Phone (2026) gegen einen echten Server (Music Assistant 2.10.4, Apple Music,
Overcast, RadioBrowser, Sonos/AirPlay). armv7hl und i486 bauen und bestehen die
Prüfung, sind aber nie auf echter Hardware gelaufen.

## Dokumentation

| Für wen | Datei |
|---|---|
| Nutzer, Deutsch | [`docs/BENUTZERHANDBUCH.md`](docs/BENUTZERHANDBUCH.md) |
| Users, English | [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md) |
| Developers (English): structure, server API, testing, release | [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) |
| Das ausführliche Entwicklungstagebuch (34 Abschnitte) | [`KONZEPT.md`](KONZEPT.md) |
| Was noch ansteht | [`TODO.md`](TODO.md) |
| Material für die Store-Einreichung | [`store/README.md`](store/README.md) |

## Was die App kann

**Fernbedienung**
- **Player-Liste**: alle Player der Anlage mit laufendem Titel, Fortschritt und
  Play/Pause in der Zeile; nicht verfügbare bleiben sichtbar, aber gedämpft
- **Läuft gerade** je Player: Cover, Titel, Fortschritt zum Springen,
  Weiter/Zurück, Lautstärke (folgt dem Finger, springt nicht zurück),
  Stummschaltung, Netzschalter falls vorhanden. Bei Radio "Live" statt
  Regler; bei Hörbüchern und Podcast-Folgen Kapitel, −15 s/+30 s und Tempo.
  Hintergrund in den **Farben des Covers** (abschaltbar)
- Im Pulley-Menü von "Läuft gerade": **Songtext** (mitlaufend, Tippen springt
  dorthin), **Einschlaftimer** (läuft auf dem Server), **Ähnliches abspielen**,
  **Zur Playlist hinzufügen**, Warteschlange
- **Warteschlange**: springen, verschieben, entfernen, Zufall, Überblenden,
  Wiederholen, an einen anderen Player übergeben, als Playlist speichern, leeren
- **Lautsprecher gruppieren** mit Gruppenlautstärke und Regler je Lautsprecher
- **Durchsage**: Text eingeben, der Server spricht ihn auf einem Lautsprecher
- **Cover-Page** (Play/Pause, Weiter bzw. +30 s bei Hörbüchern) und
  **Sperrbildschirm/Medientasten** über MPRIS -- gesteuert wird der entfernte
  Player, die App gibt selbst kein Audio aus

**Bibliothek**
- Interpreten, Alben, Titel, Playlists, Radio, Podcasts, Hörbücher -- mit
  Anzahl, seitenweise geladen, durchsuchbar, filterbar auf Favoriten; dazu
  **Zuletzt gehört** und **Weiterhören**
- **Suche** über alles, wahlweise nur in der Bibliothek; Treffer eines Dienstes
  nennen ihn
- **Interpretenseite** mit beliebten Titeln, Alben und ähnlichen Interpreten
- **Hörbuchseite** mit Fortschritt, Weiterhören/von vorn und Kapiteln
- **Podcasts** wie im Podcatcher: Datum, Stand ("neu", "43 % gehört"),
  Beschreibung, Tippen spielt ab
- **Pflegen**: Playlists bearbeiten (Titel hinzufügen/entfernen, neue anlegen),
  Treffer eines Dienstes in die Bibliothek aufnehmen oder entfernen, Sender
  aus dem weltweiten Verzeichnis oder per Stream-Adresse hinzufügen, Favoriten,
  als gehört markieren

**Verbindung und Alltag**
- Server-Ereignisse statt Nachfragen: Änderungen anderswo sind sofort sichtbar;
  nach der Rückkehr aus dem Hintergrund prüft die App die Verbindung
- **Zweite Adresse für unterwegs** (VPN, Tailscale, Reverse-Proxy): zuerst die
  Heimadresse, eine halbe Sekunde später die andere
- **Cover-Zwischenspeicher** auf dem Gerät (bis 100 MB) spart Mobilfunkdaten
- Adresse und Token verschlüsselt in Sailfish Secrets
- **Demomodus**: ein erfundener Server zum Ausprobieren ohne eigenen Server
- Deutsch und Englisch, Hochformat feststellbar

## Voraussetzungen

- Ein erreichbarer Music-Assistant-Server (Standardport 8095). Läuft er als
  Home-Assistant-App, ist das die Adresse des HA-Rechners, nicht die
  Ingress-Adresse aus der HA-Oberfläche.
- Ein langlebiges Zugriffstoken aus der Music-Assistant-Oberfläche
  (Einstellungen → Profil). Ein Token mit der Rolle `admin` deckt alles ab.

Die App verlangt die **Audio**-Berechtigung, obwohl sie kein Audio ausgibt: auf
SailfishOS ist das die Berechtigung, die das Anmelden eines MPRIS-Dienstes
(Sperrbildschirm) erlaubt. Der Berechtigungsdialog nennt sie trotzdem "Audio
aufzeichnen und abspielen" -- einen feineren Weg gibt es nicht.

## Bauen

`sfdk config` gilt nur für die laufende Shell-Sitzung -- Konfiguration und
Kommando müssen verkettet werden, sonst greift die globale Voreinstellung
(die zeigt hier auf ein fremdes Projekt):

```sh
sfdk config target=SailfishOS-5.1.0.11-aarch64 \
  && sfdk config specfile=rpm/harbour-tonarm.spec \
  && sfdk config no-fix-version \
  && sfdk build
```

Das Paket landet in `RPMS/`. **Vor jedem Wechsel der Architektur aufräumen**
(`rm -f harbour-tonarm *.o moc_*.cpp moc_*.h Makefile .qmake.stash`), sonst
landet still das Binary der vorigen Architektur im Paket. Der ganze Ablauf mit
Prüfung und Veröffentlichung steht (englisch) in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

Icons werden nicht automatisch erzeugt; nach Änderungen am Motiv:

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
qml/pages/ArtistPage.qml           Interpret: Titel, Alben, ähnliche Interpreten
qml/pages/PlaylistPage.qml         Playlist mit Titeln
qml/pages/PodcastPage.qml          Podcast mit Folgen (Datum, Stand)
qml/pages/EpisodePage.qml          Folge: Beschreibung, Datum, Weiterhören
qml/pages/PlaylistPickerPage.qml   Playlist wählen (oder neu anlegen) zum Hinzufügen
qml/pages/RadioSearchPage.qml      Sender im Verzeichnis suchen und aufnehmen
qml/pages/AddRadioDialog.qml       Sender per Stream-Adresse
qml/pages/AudiobookPage.qml        Hörbuch: Fortschritt, Weiterhören, Kapitel
qml/pages/LyricsPage.qml           Songtext, mitlaufend
qml/pages/SleepTimerPage.qml       Einschlaftimer
qml/pages/AnnouncementDialog.qml   Durchsage: Text, Gong, Lautstärke
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
vollständige Übersetzung in `translations/harbour-tonarm-en.ts` (393 von 393
Einträgen) und wird beim Bauen zu `harbour-tonarm-en.qm` übersetzt.

## Store-Material

`store/` enthält Icon, Cover, Zusammenfassung und Beschreibung auf Deutsch und
Englisch, Bildschirmfotos und eine README, die Feld für Feld dem
Harbour-Einreichungsformular folgt.

## Lizenz

MIT, siehe [`LICENSE`](LICENSE).
