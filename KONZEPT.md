# Konzept: Music-Assistant-Client für SailfishOS (Tonarm)

Stand: 2026-09-19 -- **Ausbaustufe 3 fertig** (v0.8), auf dem Telefon
bestätigt. Stufe 0 in Abschnitt 11, Zielserver vermessen in 12, Build und
Harbour-Prüfung in 13, erster Gerätestart in 14, Stufe 1 in 15, Cover-Page
und Stufe 2 in 16, Stufe 3 in 17. Als Nächstes: Stufe 4 (MPRIS, Hintergrund).

## 1. Ausgangslage und Ziel

[Music Assistant](https://www.music-assistant.io/) (MA) ist ein selbstgehosteter
Media-Library-/Multiroom-Server (Open Home Foundation, eng mit Home Assistant
verzahnt). Offizielle Clients: die Web-UI des Servers und die
[Mobile-App](https://github.com/music-assistant/mobile-app) (Kotlin
Multiplatform + Compose, Android/iOS). Ein SailfishOS-Client existiert nicht.

Ziel: ein nativer Silica-QML-Client, der die Rolle der offiziellen Mobile-App
übernimmt -- **Fernbedienung und Bibliotheks-Browser für den eigenen
MA-Server**. Kein 1:1-Nachbau der Compose-UI, sondern die gleichen Funktionen
in Sailfish-Idiomen (Pulley-Menüs, Seiten-Stack statt Bottom-Navigation,
Cover-Page, Events-View).

Direkter Vorläufer im eigenen Bestand: `sailhacontrol` (HA-Client, WebSocket +
Live-Events + Sailfish Secrets + BackgroundJob). Dessen Architektur ist
weitgehend übertragbar; Teile von `src/credentials.{h,cpp}` (Sailfish Secrets)
lassen sich direkt wiederverwenden.

**Name (entschieden 2026-09-19): Tonarm.** Verzeichnis `sailtonarm`,
RPM/Binary `harbour-tonarm`. Harbour-Regeln verbieten fremde Marken im
Anwendungsnamen, "Music Assistant" scheidet also aus; der Bezug steht in der
Paketbeschreibung. "Tonarm" passt ausserdem zur Rolle der Stufen 1-4: der
Tonarm steuert, was gespielt wird, ohne selbst die Platte zu sein.

## 2. Nicht-Ziele

- **Kein Waydroid/Alien-Dalvik-Betrieb der offiziellen App.** Funktioniert
  vermutlich, ist aber kein nativer Client.
- **Kein Port des KMP-Codes.** Kotlin/Compose-Multiplatform läuft nicht auf
  SFOS; die App wird neu in QML geschrieben, nur das Protokoll wird geteilt.
- **Kein Android-Auto-/CarPlay-Äquivalent**, keine Sprachassistenten-Anbindung.
- **Kein WebRTC-Remote-Access** (die offizielle App tunnelt Sendspin über
  WebRTC-DataChannels). Remote-Zugriff läuft, wenn überhaupt, über
  VPN/Reverse-Proxy -- gleiche Entscheidung wie in `sailhacontrol`.
- **Kein Server-Konfigurations-UI** (Provider einrichten, DSP, Player-Configs).
  Das bleibt der Web-UI vorbehalten; die App steuert, sie administriert nicht.

## 3. Serverseitige Schnittstelle

Recherchiert am 2026-09-19 im Serverquelltext (Branch `dev`) und anschliessend
**gegen die eigene Instanz verifiziert** -- siehe Abschnitt 12 für das, was
dabei anders war als im `dev`-Zweig.

Alles über HTTP/WebSocket auf **Port 8095** (Default):

| Pfad | Zweck |
|---|---|
| `GET /info` | `ServerInfoMessage` ohne Auth -- für Discovery/Versions-Check |
| `GET /ws` | WebSocket-API (Hauptkanal: Commands + Push-Events) |
| `POST /api` | dieselben Commands als JSON-RPC-Einzelaufruf (Bearer-Header) |
| `GET /imageproxy/<image_id>` | Cover-Art/Artwork |
| `GET /sendspin` | authentifizierter Proxy auf den Sendspin-Server (Port 8927) |

Weitere Ports: **8097** Stream-Server (Audio für Player), **8927** Sendspin.

**Handshake (`/ws`):** Server sendet sofort `ServerInfoMessage`
(`server_id`, `server_version`, `schema_version`,
`min_supported_schema_version`, `name`, `internal_url`, `external_url`,
`has_remote_access`, `status`). Der Client antwortet mit dem Sonderkommando
`auth` und einem Long-Lived Token (MA-UI → Settings → Profile). Erst nach
erfolgreicher Auth wird der Client automatisch auf Events abonniert.

**Nachrichtenformat:**

```jsonc
// Client → Server
{ "message_id": "17", "command": "players/all", "args": {} }
// Server → Client
{ "message_id": "17", "result": [ /* ... */ ], "partial": false }
{ "message_id": "17", "error_code": 6, "details": "..." }
// unaufgefordert: Events (MassEvent: event, object_id, data)
```

`partial: true` signalisiert gestückelte Antworten -- relevant für große
Bibliothekslisten und **muss** im Client behandelt werden (Teilergebnisse
sammeln, bis `partial: false` kommt).

**Kommandos** (aus `@api_command(...)` im Server-Quelltext; jedes hat einen
`required_scope`, der Token muss die passenden Scopes tragen):

- Player: `players/all`, `players/get`, `players/cmd/{play,pause,play_pause,stop,next,previous,seek,power,volume_set,volume_up,volume_down,volume_mute,shuffle,repeat,select_source}`, Gruppen: `players/cmd/{group,ungroup,set_members,group_volume}`, `players/create_group_player`, Sleeptimer: `players/sleep_timer/{get,set,clear}`
- Queues: `player_queues/{all,get,items,get_active_queue}`, `player_queues/play_media`, `player_queues/{play,pause,play_pause,stop,next,previous,seek,skip,resume,play_index,transfer}`, `player_queues/{shuffle,repeat,crossfade,autoplay,set_playback_speed}`, `player_queues/{move_item,move_item_end,delete_item,clear,save_as_playlist}`
- Musik: `music/search`, `music/browse`, `music/item_by_uri`, `music/recently_played_items`, `music/recently_added_tracks`, `music/in_progress_items`, `music/favorites/{add_item,remove_item}`, `music/sync`
- Bibliothek je Medientyp dynamisch registriert als
  `music/{artists,albums,tracks,playlists,radios,podcasts,audiobooks}/{count,library_items,get,get_collection}`
- Scopes: `LIBRARY_READ`, `LIBRARY_WRITE`, `QUEUES_READ`, `QUEUES_CONTROL`, ...

`player_queues/play_media(queue_id, media, option, start_item, shuffle, ...)`
ist der zentrale Abspiel-Einstieg; `media` nimmt URIs oder Item-Objekte,
`option` ist der Enqueue-Modus (play/replace/next/add).

## 4. Client-Architektur

Wie `sailhacontrol`: **reines QML + JS, kein C++-Bridge-Objekt** -- bis
Stufe 5. Die API ist JSON über WebSocket, `qt5-qtwebsockets` deckt das ab
(dort bereits im Einsatz und auf Hardware verifiziert).

```
qml/
  harbour-tonarm.qml               Wurzelfenster, hält die eine Verbindung
  components/MassConnection.qml    WebSocket, Handshake, Kommandos mit
                                   message_id-Zuordnung, partial-Zusammenbau,
                                   Event-Verteilung, Reconnect
  lib/MassApi.js                   zustandslos: URL-Ableitung, Nachrichtenbau,
                                   /info-Probe, Kompatibilitätsprüfung
  lib/MassModels.js                Normalisierung Player/Queue/MediaItem (ab Stufe 1)
  cover/CoverPage.qml              Verbindungszustand, ab Stufe 4 Now Playing
  pages/                           Players, NowPlaying, Library, Search, Queue,
                                   Artist/Album/Playlist-Detail, Settings
src/credentials.{h,cpp}            Sailfish Secrets (aus sailhacontrol übernommen)
```

Zentrale Designentscheidungen:

1. **Ein WebSocket, ein Zustandsobjekt.** Server-Push ist die einzige
   Wahrheitsquelle für Player/Queue-State; die UI pollt nie. Das Objekt lebt im
   Wurzelfenster und wird den Seiten per Property mitgegeben -- kein
   QML-Singleton (die brauchen eine `qmldir`-Datei und haben sich in diesem
   Setup als unzuverlässig erwiesen).
2. **Token in Sailfish Secrets**, nicht in `ConfigurationValue` --
   `sailhacontrol` hat das bereits durchlitten, der Code existiert.
3. **Cover-Art ohne Token, direkt in `Image.source`.** `/imageproxy/*` ist auf
   beiden Webservern registriert (`MetaDataController.post_setup()`) und
   verlangt keine Anmeldung -- am Zielserver auf Port 8095 *und* 8097 mit einem
   echten Bild geprüft (Abschnitt 12). Damit kommt QMLs `Image` an die Bilder,
   was mit `Authorization`-Header nicht ginge. Die ID ist `proxy_id` aus
   `metadata.images[]`, und in Listen immer mit `?size=` laden.
   `streams/info` wäre die sauberere Quelle für die Stream-Adresse, existiert
   auf 2.10.4 aber nicht -- bleibt die Ableitung `Port 8095 → 8097`.
4. **Schema-Version prüfen.** Die offizielle App unterstützt nur die aktuelle
   und die vorherige Server-Version. Der Client vergleicht
   `schema_version`/`min_supported_schema_version` aus `ServerInfo` und zeigt
   bei Inkompatibilität eine klare Meldung statt kryptischer Fehler.
   Referenzwerte aus `music_assistant/constants.py` (Branch `dev`, 2026-09-19):
   `API_SCHEMA_VERSION = 77`, `MIN_SCHEMA_VERSION = 28`.
5. **Grosse Listen kommen gestückelt.** Der Server schickt Ergebnisse von
   Async-Generatoren in Paketen zu je 500 Einträgen mit `partial: true`; erst
   die Nachricht ohne das Flag schliesst das Ergebnis ab. Das steckt in
   `MassConnection`, nicht in den Aufrufern.

## 5. UI-Abbildung: Compose-App → Silica

| Offizielle App | SailfishOS |
|---|---|
| Bottom-Navigation (Home/Library/Search/Settings) | Seiten-Stack; Einstiegsseite = Player-Liste, Rest über Pulley-Menü |
| Now-Playing-Sheet | eigene Seite, per Tap auf die Player-Zeile; zusätzlich Cover-Page |
| Material-3-Listen | `SilicaListView` + `ListItem`/`MenuItem`-Kontextmenüs |
| FAB / Overflow-Menüs | Pulley-Menü oben/unten, Long-Press-Kontextmenü |
| Queue-Reorder per Drag | Kontextmenü "nach oben/unten/an den Anfang" (`move_item`, `pos_shift`); Drag optional später |
| Mediennotification / Lockscreen | MPRIS (Stufe 4) |
| Android Auto / CarPlay | entfällt |

## 6. Ausbaustufen

### Stufe 0 -- Scaffold und Verbindung (v0.1) -- **implementiert, s. Abschnitt 11**

- Projektgerüst nach SFOS-Standardtemplate (`.pro`, `.desktop` mit
  `Permissions=Internet;Secrets;`, `rpm/*.spec`), Icons, Übersetzungs-Stub.
- `SettingsPage`: Serveradresse, Token (Sailfish Secrets), "Server erreichbar?"
  gegen `GET /info`.
- WebSocket-Verbindung inkl. `ServerInfo`/`auth`-Handshake, Reconnect mit
  wachsendem Abstand, Verbindungsstatus sichtbar in der UI.
- **Fertig, wenn** auf echter Hardware gegen einen echten MA-Server
  `players/all` ein Ergebnis liefert und ein Token-Neustart persistiert.
  → Code steht, **auf Hardware noch nicht verifiziert**.

### Stufe 1 -- Fernbedienung (v0.2 -- der eigentliche Kern)

Das ist die Stufe, die die App bereits nützlich macht.

- **Player-Liste** (`players/all` + Event `player_updated`): Name, Zustand,
  aktueller Titel, Lautstärke; ausgegraut wenn nicht verfügbar.
- **Now-Playing-Seite**: Cover, Titel/Artist/Album, Fortschrittsbalken
  (client-seitig interpoliert zwischen den Queue-Updates -- `elapsed_time`
  kommt nicht sekündlich), Play/Pause/Next/Prev/Seek, Lautstärke, Power.
- Kommandos: `player_queues/{play_pause,next,previous,seek}` bzw.
  `players/cmd/*`; Lautstärke `players/cmd/volume_set`.
- Aktiver Player wird gemerkt (`ConfigurationValue`), damit die App dort
  aufmacht, wo man zuletzt war.
- **Risiko:** Lautstärke-Slider und Live-Events können sich gegenseitig
  überschreiben -- Slider während der Benutzerinteraktion von eingehenden
  Events entkoppeln (in `sailhacontrol` schon einmal gelöst).

### Stufe 2 -- Bibliothek und Suche (v0.3)

- Bibliotheksseiten je Medientyp über
  `music/{artists,albums,tracks,playlists,radios}/library_items` mit
  `limit`/`offset` und inkrementellem Nachladen; `.../count` für die
  Kopfzeile.
- Detailseiten: Artist → Alben, Album → Tracks
  (`music/albums/get_collection` bzw. `music/item_by_uri`), Playlist → Tracks.
- **Suche** (`music/search`) über alle Medientypen, nach Typ gruppiert.
- Abspielen aus jeder Liste: `player_queues/play_media` mit Ziel-Queue =
  aktiver Player, `option` aus dem Kontextmenü (Jetzt spielen / Als
  Nächstes / Anhängen).
- Favoriten (`music/favorites/{add_item,remove_item}`).
- **Risiko:** Listengröße. `partial`-Antworten und Delegate-Recycling müssen
  sitzen, bevor jemand eine 20k-Track-Bibliothek öffnet. Bilder erst beim
  Sichtbarwerden laden.

### Stufe 3 -- Warteschlange (v0.4)

- Queue-Ansicht (`player_queues/items`, paginiert), aktuelles Item markiert,
  Sprung per `player_queues/play_index`.
- Bearbeiten: `move_item` / `move_item_end` / `delete_item` / `clear`,
  `save_as_playlist`.
- Modi: `shuffle`, `repeat`, `crossfade`, `autoplay`.
- **Übergabe an anderen Player** (`player_queues/transfer`) -- in der
  offiziellen App ein Kernfeature ("Musik folgt mir").
- Einfache Gruppen-Bedienung: `players/cmd/{group,ungroup,set_members}` plus
  `group_volume`. Dynamische Gruppen-Player anlegen/löschen optional.

### Stufe 4 -- Sailfish-Integration (v0.5)

Hier wird aus einem Fernbedienungs-Formular eine Sailfish-App:

- **Cover-Page**: Cover-Art als Hintergrund, Titel scrollend
  (`ScrollingLabel` aus `sailhacontrol` wiederverwendbar), Cover-Actions
  Play/Pause und Next.
- **MPRIS** (`Amber.Mpris`/`org.nemomobile.mpris`): der Sailfish-Lockscreen
  und die Medientasten steuern damit den *entfernten* Player. Metadaten und
  Position werden gespiegelt.
  **Zu prüfen:** ob SFOS einen MPRIS-Provider akzeptiert, der selbst kein
  lokales Audio ausgibt -- wenn der Lockscreen-Controller an eine aktive
  Audio-Policy gebunden ist, fällt das Feature bis Stufe 5 aus.
- **BackgroundJob** (`Nemo.KeepAlive`) + `org.nemomobile.notifications`:
  optionale Benachrichtigung bei Track-Wechsel; identisches Muster wie in
  `sailhacontrol`, inklusive des dort dokumentierten Sandbox-Verhaltens.
- **Discovery**: MA annonciert sich per mDNS (`_mass._tcp`). SFOS hat keinen
  QML-mDNS-Client -- entweder Avahi über D-Bus (`nemo-qml-plugin-dbus-qt5`,
  ohnehin schon Abhängigkeit) oder manueller Host-Eintrag bleibt. Kür, nicht
  Pflicht.

### Stufe 5 -- Lokale Wiedergabe: das Telefon als Sendspin-Player (v0.6+, optional)

Die offizielle App kann selbst Player sein (Sendspin über WebRTC/WebSocket).
Das ist die aufwendigste Stufe mit Abstand und explizit **nachgelagert** --
Stufen 1-4 sind ohne sie vollständig benutzbar.

Was die [Sendspin-Spec](https://github.com/Sendspin/spec) (Rolle `player`,
v1) vom Client verlangt:

- WebSocket zum Sendspin-Server (`ws://<host>:8927/sendspin`, lokal
  unverschlüsselt, PIN-Pairing) oder über den authentifizierten Proxy
  `/sendspin` auf 8095.
- `client/hello` mit `supported_formats` (Server **muss** `flac` und `pcm`
  können, `opus` optional) und `buffer_capacity`; laufend `client/state`
  mit `volume`, `muted`, `output_delay_ms`, `required_lead_time_ms`,
  `min_buffer_ms`.
- Binäre Audio-Chunks (Typ-Byte 4, 64-Bit-Server-Timestamp in µs,
  `send_ahead`), 15-150 ms je Chunk.
- **Der harte Teil: Synchronisation.** Time-Filter auf die Serveruhr,
  Abspiel-Fehler dauerhaft **±1 ms** (Ziel ±0,5 ms), Geschwindigkeits-
  korrektur innerhalb ±0,5 %, keine hörbaren Artefakte. Das ist über
  QtMultimedia-`MediaPlayer` nicht zu machen -- es braucht C++ mit
  direktem PulseAudio- oder GStreamer-`appsrc`-Pfad und eigener
  Resampling-/Drift-Korrektur.

Vorgehen in Unterstufen:

- **5a (Machbarkeitsprüfung, klein):** C++-Objekt, das sich als Sendspin-Player
  anmeldet, **PCM 16 bit/44,1 kHz** anfordert (kein Decoder nötig) und über
  PulseAudio ausgibt -- zunächst ohne Sync-Korrektur, nur Buffer-Timing.
  Ergebnis entscheidet, ob 5b überhaupt sinnvoll ist. Vorher zu klären:
  Welche Audio-API ist in Harbour erlaubt und was passiert bei
  Bildschirm-Aus/Anruf?
- **5b:** Time-Filter + Drift-Korrektur bis die Sync-Anforderung erfüllt ist,
  FLAC-Decoder (`libFLAC` oder GStreamer) für Bandbreite/Qualität,
  Lautstärke-/Mute-Kommandos, Persistenz von `output_delay_ms`.
- **5c:** MPRIS/Lockscreen dann "echt", Hintergrundwiedergabe, Verhalten bei
  Anruf und Kopfhörer-Wechsel.

**Alternative, falls 5a scheitert:** Das Telefon bleibt reine Fernbedienung.
Zum Mithören genügt dann ein beliebiger MA-Player im Netz -- der
Funktionsverlust ist verkraftbar, der Aufwandsunterschied riesig.

## 7. Abhängigkeiten (RPM)

Alle als QML-Plugins ohne Linken (vgl. `sailhacontrol.spec`). In v0.1 steht
nur, was Stufe 0 tatsächlich braucht:

```
Requires: sailfishsilica-qt5 >= 0.10.9
Requires: qt5-qtdeclarative-import-websockets, qt5-qtwebsockets
BuildRequires: pkgconfig(sailfishapp), pkgconfig(Qt5Core/Qt5Qml/Qt5Quick),
               pkgconfig(sailfishsecrets)
```

Ab Stufe 4 kommen dazu:

```
Requires: nemo-qml-plugin-notifications-qt5
Requires: nemo-qml-plugin-dbus-qt5
Requires: libkeepalive
```

`libsailfishsecrets` steht bewusst in keiner `Requires`-Zeile -- Harbours
Validator lehnt den Paketnamen ab, die von rpmbuild aus dem Binary abgeleitete
Soname-Abhängigkeit geht dagegen durch (in `sailhacontrol` v0.7 teuer gelernt).

Zielplattform wie bei den anderen Projekten: SailfishOS 5.1.0.11, armv7hl.
Für Stufe 5 kämen Audio-/Codec-Abhängigkeiten dazu -- **vorher** gegen die
Harbour-Whitelist prüfen, sonst wird die App nicht Store-fähig.

## 8. Reihenfolge und Abbruchpunkte

Jede Stufe ist ein veröffentlichbarer Zustand:

1. **Stufe 0+1** -- schon allein nützlich (Fernbedienung für die Anlage).
2. **+2** -- ersetzt die Web-UI für den Alltag.
3. **+3** -- Queue-Handling, Musik von Raum zu Raum mitnehmen.
4. **+4** -- fühlt sich wie eine Sailfish-App an; ab hier Store-Kandidat.
5. **+5** -- Kür, eigenes Risiko-Budget, jederzeit abbrechbar.

## 9. Offene Fragen / zu verifizieren

Erledigt seit der ersten Fassung:

- ~~Image-Proxy und Auth~~ -- geklärt, siehe Abschnitt 4 Punkt 3: Bilder über
  den unauthentifizierten Stream-Server (Port 8097) holen, dann reicht QMLs
  `Image` ohne eigenen Loader.
- ~~`partial`-Semantik~~ -- geklärt: Async-Generator-Ergebnisse gehen in
  Paketen zu 500 Einträgen mit `partial: true` raus, die Abschlussnachricht
  trägt das Flag nicht. In `MassConnection` umgesetzt.
- ~~Name/Branding~~ -- "Tonarm", siehe Abschnitt 1.

Weiterhin offen:

- **Token-Scopes:** Welche Scopes ein in der MA-UI erzeugtes Long-Lived Token
  standardmäßig bekommt. Jedes Kommando trägt serverseitig ein
  `required_scope`: `LIBRARY_READ` fürs Browsen, `QUEUES_READ`/`QUEUES_CONTROL`
  für Warteschlange und Steuerung. Der Testaufruf in Stufe 0 (`players/all`)
  zeigt als erstes, ob das Token trägt. Die einzige verbleibende Unbekannte
  der Stufe 0.
- **Server ohne angelegte Benutzer:** Ein frischer MA-Server authentifiziert
  WebSocket-Clients von sich aus (`if not self.webserver.auth.has_users`). Wie
  er dann auf ein `auth`-Kommando mit leerem Token reagiert, ist ungeprüft --
  Stufe 0 zeigt den Fehler an, statt zu raten. Für die eigene Instanz
  gegenstandslos: dort ist `onboard_done: true`, ein Token ist also nötig.
- **MPRIS ohne lokales Audio** (Stufe 4) -- siehe dort.
- **Qt-5.6-Grenzen:** keine `Qt.labs.platform`-Features, eingeschränktes
  `WebSocket`-QML-API -- bei jeder Stufe gegen die reale Toolchain prüfen,
  nicht gegen aktuelle Qt-Doku.
- **Sailjail `OrganizationName`:** auf `io.github.silly82` gesetzt (das
  SFOS-Standardtemplate lässt hier `org.example` stehen, was `sailhacontrol`
  bis heute tut). Ob Harbour darauf besteht und ob der Wechsel das
  App-Datenverzeichnis verschiebt, ist ungeprüft -- bei einem neuen Projekt
  ohne Bestandsdaten aber folgenlos.
- **Eigener MA-Server vorhanden?** Das ganze Konzept setzt eine erreichbare
  MA-Instanz im lokalen Netz voraus (ggf. als HA-Add-on). Ist keine da, ist
  Schritt eins das Aufsetzen des Servers, nicht der App.

## 10. Nächster Schritt

Stufe 0 gegen echte Hardware und einen echten Server verifizieren (Abschnitt 11
nennt die Punkte im Einzelnen). Erst danach Stufe 1.

## 11. Update 2026-09-19: Stufe 0 angelegt

Projekt unter `/home/silly/sailtonarm` erstellt, Aufbau analog zu
`sailhacontrol`. Kein Git-Repo initialisiert -- bewusst offen, bis der erste
Build auf echter Hardware läuft (gleiches Vorgehen wie dort).

**Was steht:**

- `harbour-tonarm.pro`, `.desktop` (`Permissions=Internet;Secrets;`),
  `rpm/harbour-tonarm.spec` (v0.1), Icons in allen vier Grössen
  (`icons/source/generate-icon.py`, Motiv Schallplatte + Tonarm),
  leerer Übersetzungs-Stub `translations/harbour-tonarm-en.ts`.
- `src/credentials.{h,cpp}` aus `sailhacontrol` übernommen; geändert sind die
  Secret-Namen (`harbour-tonarm-baseUrl`/`-token`) und ein neues `clear()`
  für "Zugangsdaten löschen". Die dort teuer erkauften Kommentare
  (QML-Plugin untauglich, Plugin-Namen erst beim Daemon erfragen, Delete-vor-
  Store als Upsert) sind mitgekommen.
- `qml/components/MassConnection.qml` -- die eigentliche Arbeit dieser Stufe:
  Socket, `ServerInfo`→`auth`-Handshake, Kommandoversand mit
  `message_id`-Zuordnung und Callback, `partial`-Zusammenbau,
  Ereignis-Signal, Reconnect mit Verdopplung bis 60 s, Zeitüberschreitung für
  Antworten, die nie kommen.
- `qml/lib/MassApi.js` -- zustandslos (`.pragma library`): URL-Normalisierung
  (`musicassistant.local` → `http://musicassistant.local:8095`, hinter https
  ohne Portzusatz), `wsUrl`, `streamBaseUrl`, `imageUrl`, `/info`-Probe mit
  Abbruchmöglichkeit, `classify()` für die drei Nachrichtensorten,
  Kompatibilitätsprüfung.
- `qml/pages/SettingsPage.qml` -- Adresse + Token, Vorschau der normalisierten
  Adresse, "Server erreichbar?" gegen `/info`, Löschen mit Remorse-Frist.
- `qml/pages/FirstPage.qml` -- Verbindungszustand, Servername/-version/Schema,
  angemeldeter Benutzer, und der Testaufruf `players/all`, der nach jedem
  erfolgreichen Anmelden automatisch einmal läuft.
- `qml/cover/CoverPage.qml` -- vorerst nur der Verbindungszustand.

**Noch offen / nicht verifiziert:**

- **Nichts davon wurde gebaut oder ausgeführt.** Kein `sfdk build`, kein
  Testgerät-Setup für dieses Projekt, keine echte MA-Instanz angesprochen.
  Alle API-Details stammen aus dem Serverquelltext, nicht aus einem Mitschnitt.
- Ein Item-`state` lässt sich in QML nicht überschatten -- die Property heisst
  deshalb `connectionState`. Beim ersten Start darauf achten, ob weitere
  Namenskollisionen in der Konsole auftauchen.
- `XMLHttpRequest` in `.pragma library` plus `WebSocket` aus QML sind beide in
  `sailhacontrol` auf Hardware erprobt, die Kombination in *dieser* App aber
  nicht.
- Die Quelltext-Strings sind deutsch, die `.ts`-Datei ist für Englisch
  vorgesehen und leer -- vor einer Store-Veröffentlichung umdrehen.

## 12. Update 2026-09-19: Zielserver vermessen

Der MA-Server läuft als Home-Assistant-App (`<repo>_music_assistant`,
**Version 2.10.4**) auf einem HA OS 18.2 / core-2026.9.2. Die App läuft mit
`host_network: true` -- ihre Ports liegen also direkt auf dem HA-Host, es
braucht keine Portfreigabe. Ingress (Port 8094) ist zusätzlich aktiv, für
diesen Client aber irrelevant.

**Adresse:** `http://<ha-host>:8095` -- der Server meldet sie selbst als
`internal_url` (hat der Host mehrere Netze, antwortet er auf allen).

`GET /info` liefert:

```json
{"server_id": "<server-id>", "server_version": "2.10.4", "schema_version": 65,
 "min_supported_schema_version": 28, "homeassistant_addon": true,
 "onboard_done": true, "internal_url": "http://<ha-host>:8095",
 "external_url": null, "has_remote_access": true}
```

**Handshake, mit einem echten Long-Lived Token durchgespielt:**

1. Socket offen → `ServerInfoMessage` kommt unaufgefordert, Felder exakt wie
   in Abschnitt 3 angenommen.
2. `{"message_id":"1","command":"auth","args":{"token":…,"locale":"de_CH"}}`
   → `result: {authenticated: true, user: {username, role, …}}`. Ein
   **`scopes`-Feld enthält das `user`-Objekt nicht**; das Token trägt die
   Rolle `admin`, womit die offene Scope-Frage für diese Instanz erledigt ist.
3. Kommando vor `auth` → `error_code: 20` ("Authentication is required."),
   ungültiges Token → `error_code: 23`. Beide Meldungen kommen **englisch**,
   weil der Server das mit `auth` übergebene `locale` erst nach erfolgreicher
   Anmeldung anwendet -- danach sind Fehlertexte deutsch. Genau diese zwei
   Codes übersetzt `MassApi.errorText()` deshalb selbst.

**Kommandos:** alle für Stufe 1-3 geplanten existieren auf 2.10.4
(gegen `/api-docs/commands.json` geprüft, 496 Kommandos insgesamt). Einzige
Ausnahme: **`streams/info` fehlt** (dev-only) -- die Ableitung des
Stream-Ports aus der Adresse ist also kein Rückfallweg, sondern der einzige
Weg. Erprobt wurden `players/all` (8 Player), `player_queues/all` (9),
`music/albums/count` (**2958 Alben**) und `music/albums/library_items`.

**Cover-Art: endgültig geklärt.** `/imageproxy/<id>` liefert ohne jedes Token
ein JPEG, auf Port 8095 *und* 8097. `<id>` ist das Feld **`proxy_id`** aus
`metadata.images[]`, nicht dessen `path`. Der Proxy nimmt einen
`?size=`-Parameter, aber nur aus einer festen Menge: **0, 80, 160, 256, 512,
1024** (0 = Original). Der Grössenunterschied ist erheblich -- dasselbe Cover
wog als Original 122 KB (1000×1000), mit `size=256` noch 16 KB. In Listen
also nie ohne `size` laden; `MassApi.imageUrl(base, proxyId, px)` rastet
selbst auf die nächstgrössere erlaubte Kantenlänge ein.

**Folge für Stufe 2:** bei 2958 Alben greift die 500er-Stückelung des Servers
sicher -- der `partial`-Zusammenbau in `MassConnection` ist keine Theorie.
Bibliothekslisten trotzdem mit `limit`/`offset` seitenweise holen, statt sich
3000 Objekte in einem Rutsch in den Speicher zu legen.

Nicht verifiziert bleibt damit nur noch das Verhalten der App auf dem Telefon
(zum Build siehe Abschnitt 13).

**Nebenbefund, nichts mit dieser App zu tun:** in Home Assistant existieren
*zwei* `music_assistant`-Config-Entries (beide `loaded`, beide per Zeroconf
angelegt). Vermutlich eine Dublette aus einer früheren Neuinstallation --
einen Blick wert, aber unabhängig von diesem Projekt.

## 13. Update 2026-09-19: erster Build

`sfdk build` gegen `SailfishOS-5.1.0.11-armv7hl` läuft durch:
`RPMS/harbour-tonarm-0.1-1.armv7hl.rpm` (73 KB). Keine Compiler-, qmake- oder
rpmbuild-Warnungen. Beide Prüfsuiten sind sauber:

- `sfdk check -s harbour` → **Validation succeeded** (alle Abschnitte PASSED,
  inklusive Sandboxing, Requires und Architecture)
- `sfdk check -s rpmlint` → **0 errors, 0 warnings, 0 badness**

Dass die Harbour-Prüfung schon beim ersten Anlauf durchging, liegt an den aus
`sailhacontrol` übernommenen Entscheidungen: `libsailfishsecrets` steht in
keiner `Requires:`-Zeile (die Soname-Abhängigkeit leitet rpmbuild selbst ab),
es wird keine Lizenzdatei installiert, und `%install` strippt das Binary von
Hand, weil `sfdk` qmake mit `QMAKE_STRIP=:` aufruft.

`lupdate` hat 51 übersetzbare Strings gefunden und
`translations/harbour-tonarm-en.ts` gefüllt (alle `unfinished` -- die App
läuft also auf Englisch weiterhin auf Deutsch, s. Abschnitt 11). Nebenbei legt
der Build `translations/harbour-tonarm.ts` als Basisdatei an; die ist
generiert und steht jetzt in `.gitignore`.

**Beim Bauen aufgelaufen, weil es in den SDK-Notizen steht und trotzdem
zuschlug:** `sfdk config` ist session-scoped und überlebt keinen separaten
Shell-Aufruf. Ein `sfdk config --push target …` in einem Aufruf und `sfdk
build` im nächsten benutzt still die *globale* Voreinstellung -- die zeigte
hier auf `rpm/harbour-nemoai.spec` aus einem fremden Projekt, entsprechend
lautete der Abbruch. Richtig ist, Konfiguration und Kommando zu verketten:

```sh
sfdk config target=SailfishOS-5.1.0.11-armv7hl \
  && sfdk config specfile=rpm/harbour-tonarm.spec \
  && sfdk build
```

**Weiterhin offen:** Installation und Start auf dem Telefon. Zu erwarten ist
dort beim ersten Start der Sailjail-Berechtigungsdialog, der auf dem Gerät
angetippt werden muss; die App hängt bis dahin im `sailjail`-Wrapper.

## 14. Update 2026-09-19: erster Start auf dem Telefon

Gerät: Jolla Phone (2026), aarch64, per USB-Netz erreichbar.
**Wichtig:** das Telefon ist aarch64, der erste Build war armv7hl -- vor dem
Architekturwechsel mussten erst sämtliche Objektdateien weg
(`harbour-tonarm`, `*.o`, `moc_*`, `Makefile`), sonst relinkt der In-Place-Build
stillschweigend die alten Objekte in das neue RPM.

`pkcon install-local` löste `qt5-qtdeclarative-import-websockets` von selbst
auf; das QML-Plugin liegt auf dem Gerät vollständig vor (`.so` vorhanden, nicht
der aus anderen Projekten bekannte Fall "Paket installiert, Dateien fehlen").

**Beobachtet beim ersten Start:**

- Wie erwartet blieb der Prozess zunächst im `sailjail`-Wrapper stehen
  (`/usr/bin/sailjail -p harbour-tonarm -- /usr/bin/harbour-tonarm`), bis der
  Berechtigungsdialog auf dem Gerät bestätigt wurde -- im Journal als
  Aktivierung von `com.jolla.windowprompt` sichtbar, 12 Sekunden vor dem
  eigentlichen Start. Beim zweiten Start kam der Dialog nicht wieder.
- Das Sandbox-Profil greift mit den Werten aus der `.desktop`:
  `--template=OrganizationName:io.github.silly82`,
  `--template=ApplicationName:tonarm`, und geladen werden
  `Internet.permission`, `Secrets.permission`, `Base.permission`.
- **Sailfish Secrets funktioniert.** Die Plugin-Erkennung aus
  `credentials.cpp` liefert `…plugin.storage.sqlite` +
  `…plugin.encryption.openssl`, beide Secrets melden beim Erststart korrekt
  "does not exist in collection standalone".
- **Keine einzige QML-Warnung oder -Fehlermeldung** im Journal, über zwei
  Starts hinweg. Insbesondere keine Namenskollision, kein fehlender Import,
  keine Binding-Schleife.
- Die Startseite rendert den unkonfigurierten Zustand wie entworfen
  (Statuspunkt, "Nicht konfiguriert", Hinweistext, Knopf in die
  Einstellungen); Server- und Testabschnitt bleiben korrekt ausgeblendet.
  Die Einstellungsseite rendert ebenfalls vollständig.

**Noch offen -- der letzte Schritt der Stufe 0:** Adresse und Token auf dem
Gerät eintragen und den `players/all`-Testaufruf auslösen. Der Versuch, die
Zugangsdaten zur Abkürzung ins installierte QML zu schreiben, wurde
abgebrochen (ein Token gehört nicht in eine Datei) -- die Eingabe passiert von
Hand auf dem Telefon.

**Randnotiz zum Neustarten über SSH:** `killall harbour-tonarm` beendet nur
das Binary, der `firejail`-Wrapper der alten Instanz bleibt verwaist zurück
(gezielt per PID nachräumen -- nie nach dem generischen Namen, das nähme jede
sandboxed App auf dem Gerät mit). Und der Start muss von der SSH-Sitzung
abgelöst werden (`setsid nohup invoker …`), sonst stirbt die App mit der
Sitzung.

## 15. Update 2026-09-19: Ausbaustufe 1 (v0.2 bis v0.4)

Aus der Diagnoseseite ist eine Fernbedienung geworden. Neue Dateien:
`qml/components/PlayerStore.qml` (Zustand aller Player und Queues, per Events
aktuell gehalten), `qml/lib/MassModels.js` (Rechenhilfen),
`qml/pages/PlayersPage.qml` (neue Startseite) und
`qml/pages/NowPlayingPage.qml`. `FirstPage.qml` ist entfallen; die
Serverangaben stehen jetzt in den Einstellungen.

**Vorher am laufenden Server vermessen** (dieselbe Disziplin wie Abschnitt 12
-- die Feldnamen stehen nirgends dokumentiert):

- Ein Player führt u. a. `player_id`, `display_name`, `available`, `powered`,
  `state`/`playback_state`, `volume_level` (0-100, ganzzahlig),
  `volume_muted`, `supported_features`, `power_control`, `volume_control`.
- **`current_media` am Player enthält `image_url` bereits als vollständige
  `/imageproxy`-Adresse samt `?size=512&fmt=jpg`** -- für Now Playing muss gar
  nichts zusammengebaut werden. Dazu `title`, `artist`, `album`, `media_type`
  und eine Farbpalette des Covers (für später).
- Die Queue trägt `elapsed_time` + `elapsed_time_last_updated` (Unix-Zeit),
  `current_item` mit `duration`, sowie `shuffle_enabled`, `repeat_mode`,
  `current_index`. **`items` ist eine Anzahl, keine Liste** -- die Einträge
  holt `player_queues/items` (Stufe 3).
- Ereignisnamen aus `EventType`: `player_added`, `player_updated`,
  `player_removed`, `queue_added`, `queue_updated`, `queue_time_updated`.
  Letzteres kommt im Sekundentakt, solange gespielt wird.

**Fortschrittsanzeige:** `elapsed_time` kommt nur gelegentlich, also wird
zwischen zwei Meldungen lokal weitergezählt (`MassModels.elapsedSeconds()`) --
aber nur im Zustand "playing", sonst liefe die Anzeige in der Pause weiter.

**Regler und eingehende Ereignisse entkoppeln:** weder der Lautstärke- noch
der Fortschrittsregler ist an den Serverwert gebunden. Ein Binding würde den
Griff unter dem Finger wegziehen, sobald ein `player_updated` hereinkommt.
Stattdessen wird der Wert nachgezogen, solange niemand den Griff hält.

### Am Gerät gefunden, nicht am Schreibtisch

- **Weiter/Zurück und der Fortschrittsregler waren grundlos gesperrt (v0.3).**
  Ich hatte sie an `supported_features` des Players gehängt. Falsch: diese
  Kommandos gehen an die *Warteschlange*, und die fährt der Server selbst --
  `player_queues/next` prüft im Quelltext keine einzige `PlayerFeature`,
  sondern nur, ob die Queue aktiv ist. Der benutzte Player führt weder
  `next_previous` noch `seek` oder `pause` auf und springt trotzdem
  einwandfrei. Richtig bleibt die Feature-Abfrage für alles unter
  `players/cmd/*`: Lautstärke, Stummschaltung, Netzschalter.
- **Der Fortschrittsbalken lief aus seiner Listenzeile in die nächste (v0.4).**
  Feste Zeilenhöhe, obwohl der Balken zusätzlich Platz braucht. Die Zeile
  wächst jetzt mit. Silicas `ProgressBar` ist dabei zwei Rechtecken gewichen:
  sie bringt eigene Innenabstände und eine Mindesthöhe mit und fluchtete
  nicht mit dem Text darüber.
- Das Silica-Theme hat **kein Ein/Aus-Symbol**; der Netzschalter ist deshalb
  ein Textknopf. Sichtbar ist er ohnehin nie -- alle Player der Anlage melden
  `power_control: "none"`.

### Abweichung vom ursprünglichen Plan

Abschnitt 6 versprach, die App öffne sich dort, "wo man zuletzt war". Umgesetzt
ist: der zuletzt geöffnete Player wird gemerkt, steht in der Liste oben und ist
markiert -- aber die App springt nicht von selbst auf seine Seite. Ein
automatischer Seitenwechsel beim Start würde bei jedem Öffnen eine
Rückwärtsgeste erzwingen, nur um die anderen Player zu sehen.

### Auf dem Gerät bestätigt

Cover-Art lädt, Titel/Interpret/Album stimmen, Fortschritt läuft mit, Weiter
und Zurück wechseln den Titel, Lautstärke steht auf dem Serverwert. Live-Events
kommen an: während der Prüfung wechselte der Titel von selbst, und ein neu
hinzugekommener Player (`player_added`) erschien ohne Neuladen in der Liste.
Keine QML-Warnung aus eigenem Code.

Einzige beobachtete Warnung stammt aus Silica selbst
(`Sailfish/Silica/TextField.qml:87: Binding loop detected for property
"width"`, beim Öffnen der Einstellungen) -- in Sailfish-Apps verbreitet und
ohne sichtbare Folge.

**Offen für Stufe 2:** Bibliothek und Suche.

## 16. Update 2026-09-19: Cover-Page (v0.5) und Ausbaustufe 2 (v0.6)

### Cover-Page -- vorgezogen aus Stufe 4

Das Cover zeigt jetzt laufenden Titel, Interpret und Player, mit dem Albumbild
als abgedunkeltem Hintergrund, dazu Play/Pause und Weiter als Cover-Actions.
Für eine Fernbedienung ist das die eigentliche Bedienfläche -- der teure Teil
von Stufe 4 ist MPRIS, nicht das Cover, also durfte es vor.

Gezeigt wird nicht der zuletzt geöffnete, sondern der gerade spielende Player
(`PlayerStore.activePlayer`: spielend vor pausiert vor gemerkt). Ohne diese
Reihenfolge zeigte das Cover den gemerkten Player auch dann, wenn nebenan
Musik lief.

### Stufe 2 -- Bibliothek und Suche

Neue Seiten: `LibraryPage` (Einstieg mit Anzahl je Medientyp), `MediaListPage`
(eine seitenweise geladene Liste, bedient alle fünf Typen), `AlbumPage`,
`ArtistPage`, `PlaylistPage`, `SearchPage`, `PlayerPickerPage`. Neue
Komponenten: `MediaListItem` (eine Zeile samt Kontextmenü zum Abspielen) und
`StatusToast` (kurze Rückmeldung).

**Vorher am laufenden Server geklärt:**

- `music/<typ>/library_items` nimmt `limit`, `offset`, `search`, `order_by`,
  `favorite` und mehr. Es liefert standardmässig **Summary-Objekte** --
  schlanke Einträge für Listenansichten, deren `metadata` nur `images` trägt.
  Genau das, was eine Liste braucht.
- **`get_collection` ist eine Sackgasse**: sowohl für Alben als auch für
  Interpreten antwortet der Zielserver mit `error_code 999, "list index out of
  range"` -- ein interner Fehler, kein Bedienfehler. Die brauchbaren Kommandos
  heissen `music/albums/album_tracks(item_id, provider_instance_id_or_domain)`
  und `music/artists/artist_albums(...)`; Playlists entsprechend
  `music/playlists/playlist_tracks`, das zusätzlich `limit`/`offset` kennt.
- `music/search(search_query, media_types, limit, providers)` antwortet mit
  einem Objekt, das je Medientyp eine Liste trägt. Achtung: der Schlüssel für
  Radio heisst dort **`radio`** (Einzahl), während der Bibliotheks-Präfix
  `radios` lautet.
- `QueueOption`: `play`, `replace`, `next`, `replace_next`, `add`.
- Bibliotheksbilder kommen über `metadata.images[].proxy_id` und
  `MassApi.imageUrl()`; die fertige `image_url` gibt es nur bei
  `current_media` (Now Playing).

**Gegen Grössen ausgelegt, nicht gegen Beispiele:** die Bibliothek der
Zielanlage hat 1913 Interpreten, 2960 Alben, 13847 Titel und 52 Playlists.
Listen laden deshalb in Seiten zu 60 Einträgen und ziehen nach, sobald das
Ende der geladenen Menge in Sicht kommt; Miniaturbilder werden mit `?size=`
in Zeilengrösse angefordert, nicht im Original.

**Ziel-Player:** wo etwas landet, das man in der Bibliothek antippt, ist eine
eigene Einstellung (`PlayerStore.explicitTargetPlayerId`), getrennt vom zuletzt
*angeschauten* Player. Ohne eigene Wahl gilt der gerade spielende. Jede
Bibliotheksseite zeigt das Ziel im Pulley-Menü und lässt es dort ändern.

**Auf dem Gerät bestätigt:** Bibliotheksübersicht mit allen fünf Zählungen,
Titelliste (13847) mit Suchfeld, Albumseite mit geladenem Cover, „2002 · 9
Titel" und Titelliste mit Nummer und Dauer. Keine QML-Warnung aus eigenem
Code.

Der Einreih-Pfad wurde gegen einen unbenutzten Browser-Player geprüft statt
gegen einen Lautsprecher im Wohnzimmer: `player_queues/play_media` mit
`option: "add"` brachte dessen Warteschlange von 0 auf 9 Einträge, ohne
Wiedergabe zu starten -- genau das, was die Oberfläche verspricht. Die
Testeinträge wurden danach wieder entfernt.

**Nicht durchgeklickt:** Suchseite, Kontextmenü und Player-Auswahl auf dem
Gerät selbst. Sie benutzen dieselben Code-Pfade wie das Geprüfte
(`MediaListItem`, `PlayerStore.playMedia`), sind aber nicht einzeln
verifiziert.

**Offen für Stufe 3:** die Warteschlange -- ansehen, umsortieren, an einen
anderen Player übergeben.

## 17. Update 2026-09-19: Ausbaustufe 3 (v0.7/v0.8)

Neu: `qml/pages/QueuePage.qml` und `qml/pages/SavePlaylistDialog.qml`;
`PlayerPickerPage` ist verallgemeinert (ein `pickHandler` entscheidet, was die
Auswahl bedeutet -- Ziel setzen oder Warteschlange übergeben).

Die Warteschlange zeigt, was noch kommt, markiert den laufenden Eintrag mit
einem Balken am linken Rand, springt per Tippen dorthin (`play_index`) und
lässt Einträge nach oben, nach unten, ans Ende schieben oder entfernen. Dazu
je Warteschlange: zufällige Reihenfolge, Überblenden, Wiederholen
(aus → alle → ein Titel), Übergabe an einen anderen Player, Speichern als
Playlist und Leeren mit Widerrufsfrist.

Erreichbar über das Pulley-Menü von Now Playing und über das Kontextmenü
einer Zeile in der Player-Liste.

**Zusätzlich gewünscht und umgesetzt:** die Playlist-Seite hat einen Knopf
"Zufällig", der die Playlist gleich in zufälliger Reihenfolge startet
(`play_media` mit `shuffle: true`). Das Feld wirkt serverseitig nur bei
Optionen, die sofort losspielen, und wird beim Anhängen deshalb gar nicht erst
mitgeschickt. Nicht zu verwechseln mit dem Schalter "Zufällige Reihenfolge"
auf der Warteschlangen-Seite: der ändert den Modus der Warteschlange dauerhaft,
der Knopf startet nur diesen einen Durchlauf gemischt.

**Aktualisierung:** die Seite lauscht auf `queue_items_updated` für ihre eigene
Warteschlange und lädt dann neu, statt nach einem Verschieben selbst zu raten.
Entprellt um 400 ms -- ein Umsortieren löst mehrere Ereignisse kurz
hintereinander aus, sonst lädt die Seite drei- bis viermal dasselbe.

### Am Gerät gefunden

**Die Spieldauer überdeckte das Ende langer Titel (v0.8).** Die Textspalte zog
den rechten Seitenabstand nicht ab und reichte damit unter die Dauer, statt
vorher auszublenden. Dieselbe Klasse Fehler wie der Fortschrittsbalken in
v0.4 -- bei Zeilen mit rechtsbündigem Zusatz muss dessen Breite *und* der
Seitenabstand aus der Spaltenbreite heraus.

### Gegen den echten Server geprüft

Wieder gegen einen unbenutzten Browser-Player statt gegen einen Lautsprecher:

- `move_item` mit `pos_shift: -1` rückt einen Eintrag eine Position vor, `+2`
  zwei zurück, `move_item_end` ans Ende -- alles bestätigt.
- **Ein grosser negativer `pos_shift` bewirkt nichts und meldet auch keinen
  Fehler.** Der Server lässt Einträge nicht vor den gerade laufenden rutschen.
  Für die Oberfläche folgenlos (sie benutzt nur ±1 und "ans Ende"), aber
  "Nach oben" auf dem Eintrag direkt hinter dem laufenden tut daher nichts.
- `delete_item` nimmt die `queue_item_id` und entfernt genau diesen Eintrag.
- `clear` leert zuverlässig; alle Testeinträge wurden danach entfernt.

**Nicht geprüft:** `transfer` -- dafür braucht es zwei freie Player, und zum
Zeitpunkt der Prüfung war nur noch ein Browser-Player angemeldet. Die Übergabe
an einen echten Lautsprecher wäre ein Eingriff in laufende Musik gewesen.
Ebenfalls nicht durchgeklickt: "Als Playlist speichern" (es legt einen
dauerhaften Eintrag in der Bibliothek an) und die Kontextmenü-Einträge auf dem
Gerät selbst.

**Offen:** Stufe 4 (MPRIS, Benachrichtigungen, Hintergrund) und Stufe 5
(Sendspin). Ausserdem weiterhin: Quelltext-Strings sind deutsch, die englische
Übersetzung fehlt -- vor einer Harbour-Veröffentlichung zu drehen.
