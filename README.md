# Tonarm (`harbour-tonarm`)

Inoffizieller SailfishOS-Client für [Music Assistant](https://www.music-assistant.io/).
Silica-QML, spricht die WebSocket-API des MA-Servers direkt an.

Nicht mit dem Music-Assistant-Projekt verbunden. Der Name "Music Assistant"
gehört dessen Urhebern; diese App heisst deshalb Tonarm.

**Stand: Ausbaustufe 1** (v0.4) -- Fernbedienung. Bibliothek, Suche und
Warteschlange folgen; der Ausbauplan steht in [`KONZEPT.md`](KONZEPT.md).

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
qml/pages/PlayersPage.qml          Startseite: die Player der Anlage
qml/pages/NowPlayingPage.qml       Cover, Titel, Transport, Lautstärke
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
