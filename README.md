# Tonarm (`harbour-tonarm`)

Inoffizieller SailfishOS-Client für [Music Assistant](https://www.music-assistant.io/).
Silica-QML, spricht die WebSocket-API des MA-Servers direkt an.

Nicht mit dem Music-Assistant-Projekt verbunden. Der Name "Music Assistant"
gehört dessen Urhebern; diese App heisst deshalb Tonarm.

**Stand: Ausbaustufe 4** (v0.14) -- Fernbedienung, Bibliothek, Suche,
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
  Netzschalter, falls der Player einen hat
- **Bibliothek**: Interpreten, Alben, Titel, Playlists und Radio mit Anzahl,
  seitenweise nachgeladen und je Liste durchsuchbar; Album- und
  Interpretenseiten mit Cover, Playlists mit ihren Titeln
- **Suche** über alle Medientypen auf einer Seite, nach Typ gruppiert
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
- **Optionale Benachrichtigung** bei Titelwechsel (standardmässig aus)

Die App verlangt dafür die **Audio**-Berechtigung, obwohl sie kein Audio
ausgibt: auf SailfishOS ist das die Berechtigung, die das Anmelden eines
MPRIS-Dienstes erlaubt ("show audio controls on lockscreen"). Der
Berechtigungsdialog nennt sie dem Nutzer gegenüber allerdings "Audio
aufzeichnen und abspielen" -- einen feineren Weg gibt es nicht.
- **Live-Aktualisierung** per Server-Events (`player_updated`, `queue_updated`,
  `queue_time_updated`) statt durch Nachfragen; zwischen zwei Meldungen zählt
  die Spielzeit lokal weiter
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
src/credentials.{h,cpp}            Sailfish Secrets (aus harbour-hacontrol übernommen)
src/harbour-tonarm.cpp             nur QML laden + Credentials als Kontext-Property
qml/harbour-tonarm.qml             Wurzelfenster, hält Verbindung und Zustand
qml/components/MassConnection.qml  WebSocket, Handshake, Kommandos, Events, Reconnect
qml/components/PlayerStore.qml     Player und Warteschlangen, per Events aktuell
qml/lib/MassApi.js                 URL-Ableitung, Nachrichtenbau, /info-Probe
qml/lib/MassModels.js              Fähigkeiten, Spielzeit, Now-Playing-Aufbereitung
qml/components/MediaListItem.qml   Bibliothekszeile samt Abspiel-Kontextmenü
qml/components/StatusToast.qml     kurze Rückmeldung am unteren Rand
qml/components/MprisBridge.qml     MPRIS-Dienst für Sperrbildschirm/Medientasten
qml/components/TrackNotifier.qml   optionale Meldung bei Titelwechsel
qml/pages/PlayersPage.qml          Startseite: die Player der Anlage
qml/pages/NowPlayingPage.qml       Cover, Titel, Transport, Lautstärke
qml/pages/LibraryPage.qml          Einstieg: Medientypen mit Anzahl
qml/pages/MediaListPage.qml        seitenweise Liste je Medientyp, durchsuchbar
qml/pages/AlbumPage.qml            Album mit Titelliste
qml/pages/ArtistPage.qml           Interpret mit Alben
qml/pages/PlaylistPage.qml         Playlist mit Titeln
qml/pages/SearchPage.qml           Suche über alle Medientypen
qml/pages/QueuePage.qml            Warteschlange ansehen und bearbeiten
qml/pages/SavePlaylistDialog.qml   Name für die gespeicherte Warteschlange
qml/pages/PlayerPickerPage.qml     Player auswählen (Ziel oder Übergabe)
qml/pages/SettingsPage.qml         Adresse, Token, Erreichbarkeitstest, Serverangaben
qml/cover/CoverPage.qml            Verbindungszustand (ab Stufe 4: laufendes Stück)
```

## Sprache

Die Quelltext-Strings sind deutsch; `translations/harbour-tonarm-en.ts` ist für
die englische Fassung vorgesehen und noch leer. Vor einer Veröffentlichung im
Harbour-Store sollte das gedreht werden (englische Quelle, deutsche
Übersetzung) -- bis dahin zeigt die App auf englischen Geräten deutsche Texte.

## Lizenz

MIT, siehe [`LICENSE`](LICENSE).
