# Tonarm – Benutzerhandbuch

Tonarm ist eine Fernbedienung für deinen eigenen
[Music-Assistant](https://www.music-assistant.io/)-Server, für SailfishOS. Die
App spielt selbst keine Musik ab: sie steuert die Lautsprecher, die an deinem
Server hängen (Sonos, AirPlay, Chromecast, DLNA und was Music Assistant sonst
kennt), und zeigt, was dort läuft.

Stand: Version 0.31. *English version: [USER_GUIDE.md](USER_GUIDE.md).*

---

## Inhalt

1. [Einrichten](#1-einrichten)
2. [Die Startseite: deine Player](#2-die-startseite-deine-player)
3. [Läuft gerade](#3-läuft-gerade)
4. [Musik auswählen: die Bibliothek](#4-musik-auswählen-die-bibliothek)
5. [Das Kontextmenü](#5-das-kontextmenü)
6. [Hörbücher und Podcasts](#6-hörbücher-und-podcasts)
7. [Warteschlange, Gruppen, Durchsagen](#7-warteschlange-gruppen-durchsagen)
8. [Playlists, Bibliothek, Radiosender pflegen](#8-playlists-bibliothek-radiosender-pflegen)
9. [Ohne die App zu öffnen](#9-ohne-die-app-zu-öffnen)
10. [Unterwegs](#10-unterwegs)
11. [Einstellungen im Überblick](#11-einstellungen-im-überblick)
12. [Gut zu wissen](#12-gut-zu-wissen)
13. [Wenn etwas nicht geht](#13-wenn-etwas-nicht-geht)

---

## 1. Einrichten

Du brauchst zwei Dinge aus deinem Music-Assistant-Server:

- **Die Adresse**, zum Beispiel `192.168.1.20` oder `musicassistant.local`.
  Ohne Angabe ergänzt die App `http://` und den Standardport `8095`.
  Läuft Music Assistant als **App in Home Assistant**, ist das die Adresse
  deines Home-Assistant-Rechners -- nicht die Adresse, unter der du Music
  Assistant in der Home-Assistant-Oberfläche siehst.
- **Ein Zugriffstoken**: in der Music-Assistant-Oberfläche unter
  *Einstellungen → Profil* ein langlebiges Token erzeugen und kopieren.

So geht's:

1. Tonarm öffnen, das Pulley-Menü herunterziehen, **Einstellungen**.
2. **Serveradresse** und **Zugriffstoken** eintragen. Gespeichert wird beim
   Verlassen des Feldes, verschlüsselt und an die Gerätesperre gebunden.
3. Mit **Server erreichbar?** prüfen, ob die Adresse stimmt.
4. Zurück zur Startseite -- nach ein, zwei Sekunden erscheinen deine Player.

Beim ersten Start fragt SailfishOS nach Berechtigungen. Die
**Audio**-Berechtigung wird als "Audio aufzeichnen und abspielen" angezeigt,
obwohl Tonarm weder das eine noch das andere tut: auf SailfishOS ist es die
Berechtigung, mit der eine App die Bedienelemente auf dem Sperrbildschirm
anbieten darf. Nach einem Update fragt SailfishOS unter Umständen noch einmal,
ob Tonarm seine gespeicherten Zugangsdaten lesen darf -- bestätigen.

**Ohne eigenen Server ausprobieren:** in den Einstellungen den **Demomodus**
einschalten. Dann zeigt die App einen erfundenen Server mit fünf Räumen,
Musik, Radio, einem Hörbuch und einem Podcast. Deine Zugangsdaten bleiben
dabei erhalten; ausgeschaltet ist die App wieder an deinem Server.

---

## 2. Die Startseite: deine Player

Jede Zeile ist ein Player (Lautsprecher, Raum, Gruppe) mit dem, was gerade
läuft, einem Fortschrittsbalken und einem Play/Pause-Knopf rechts.

- **Tippen** öffnet "Läuft gerade" für diesen Player.
- **Lange drücken** öffnet das Menü des Players: *Warteschlange*,
  *Gruppieren*, *Durchsage …* und *Als Ziel für die Bibliothek*.
- Nicht verfügbare Player (ausgeschaltet, offline) bleiben gedämpft sichtbar.
- Ein Punkt links markiert den zuletzt geöffneten Player; er steht oben.
- Das **Pulley-Menü** führt zu *Einstellungen*, *Suchen* und *Bibliothek*.

**Der Ziel-Player.** Wenn du in der Bibliothek etwas abspielst, landet es auf
dem *Ziel-Player*: dem, der gerade spielt, sonst dem zuletzt geöffneten. Mit
*Als Ziel für die Bibliothek* oder im Pulley-Menü jeder Bibliotheksseite
(*Ziel-Player: …*) legst du ihn fest.

Stimmt die Verbindung nicht, steht oben eine Zeile mit dem Grund. Ein Tippen
darauf verbindet sofort neu.

---

## 3. Läuft gerade

Cover, Titel, Interpret, Album, Fortschritt (zum Springen ziehen),
Zurück / Play-Pause / Weiter und die Lautstärke. Die Lautstärke ändert sich
schon beim Ziehen.

- **Radio**: statt eines Fortschrittsbalkens steht *Live*.
- **Hörbuch oder Podcast-Folge**: zusätzlich −15 s / +30 s, das aktuelle
  Kapitel und das *Tempo* (0,75× bis 2×). Weiter und Zurück springen zwischen
  Kapiteln; Zurück innerhalb der ersten fünf Sekunden eines Kapitels geht ins
  vorige.
- Der Hintergrund nimmt die **Farben des Covers** auf (abschaltbar).

Im **Pulley-Menü**:

| Eintrag | Was er tut |
|---|---|
| Einschlaftimer | 15–90 Minuten oder bis zum Ende des Titels/Kapitels. Läuft auf dem Server, greift also auch, wenn das Telefon schläft. Solange er läuft, steht die Restzeit unter den Knöpfen. |
| Ähnliches abspielen | Der Server baut aus dem laufenden Titel eine endlose Folge passender Musik und ersetzt damit die Warteschlange. |
| Zur Playlist hinzufügen … | Den laufenden Titel zu einer eigenen Playlist hinzufügen (siehe [Abschnitt 8](#8-playlists-bibliothek-radiosender-pflegen)). |
| Songtext | Der Text läuft mit dem Lied mit; die aktuelle Zeile ist hervorgehoben. Ein Tippen auf eine Zeile springt dorthin. Die erste Abfrage kann eine halbe Minute dauern. |
| Warteschlange | Siehe [Abschnitt 7](#7-warteschlange-gruppen-durchsagen). |

Ob es einen Songtext gibt, hängt von den Quellen deines Servers ab
(Streamingdienst, Tags der Dateien, ein Songtext-Anbieter in Music Assistant).

---

## 4. Musik auswählen: die Bibliothek

Pulley-Menü → **Bibliothek**. Oben *Zuletzt gehört* und *Weiterhören*
(angefangene Hörbücher und Podcast-Folgen), darunter die Bereiche mit ihrer
Anzahl: Interpreten, Alben, Titel, Playlists, Radio, Podcasts, Hörbücher.

- Jede Liste lädt beim Scrollen nach und hat oben ein Suchfeld.
- Im Pulley-Menü einer Liste: *Nur Favoriten*, *Ziel-Player*, *Neu laden*.
- **Interpreten** zeigen ihre **beliebten Titel** (auch bei Interpreten aus
  der eigenen Bibliothek, gemischt mit dem Streamingdienst), darunter *In der
  Bibliothek* die eigenen Titel, dann Alben und **ähnliche Interpreten**;
  oben *Abspielen* und *Ähnliches*. Die beliebten Titel brauchen beim ersten
  Mal bis zu zehn Sekunden.
- Alben zeigen ihre Titel mit *Abspielen* und *Anhängen*, Playlists
  zusätzlich *Zufällig*.

**Suche** (Pulley-Menü der Startseite oder der Bibliothek): durchsucht alle
Medientypen auf einmal, nach Typ gruppiert. Mit *Suchen in* wählst du
*Überall* (Bibliothek und Streamingdienste) oder nur *Bibliothek*. Treffer
eines Dienstes nennen ihn in der zweiten Zeile, zum Beispiel
"Apple Music · Adele".

---

## 5. Das Kontextmenü

**Lange drücken** auf einen Eintrag in einer Liste. Welche Punkte erscheinen,
hängt vom Eintrag ab:

| Eintrag | Wofür |
|---|---|
| Jetzt spielen | Spielt sofort auf dem Ziel-Player. |
| Ähnliches abspielen | Endlose Folge passender Titel (bei Titeln und Interpreten). |
| Als Nächstes / Anhängen | Einreihen nach dem laufenden Titel bzw. ans Ende. |
| Zur Playlist hinzufügen … | Bei Titeln. |
| Aus dieser Playlist entfernen | Nur auf einer eigenen Playlist. |
| Als gehört / nicht gehört markieren | Bei Podcast-Folgen und Hörbüchern. |
| Beschreibung | Bei Podcast-Folgen. |
| Zu Favoriten / Aus Favoriten | Favoriten sind als Stern in der Liste markiert. |
| In die Bibliothek aufnehmen | Bei Treffern eines Dienstes oder des Senderverzeichnisses. |
| Aus der Bibliothek entfernen | Bei Titeln, Alben und Sendern. |

Einträge, die etwas löschen, zeigen kurz *Tippe zum Abbrechen* -- in diesen
Sekunden lässt sich der Vorgang zurücknehmen.

---

## 6. Hörbücher und Podcasts

**Hörbücher** (Bibliothek → Hörbücher, ein Buch antippen): Autor, Sprecher,
Fortschritt ("43 % gehört, noch 5 Std."), *Weiterhören* bzw. *Abspielen*,
*Von vorn* und die Kapitelliste. Läuft das Buch, ist das aktuelle Kapitel
markiert, und ein Tippen auf ein Kapitel springt dorthin. Im Pulley-Menü:
*Als beendet markieren* / *Als nicht begonnen markieren*.

**Podcasts** (Bibliothek → Podcasts, einen Podcast antippen): die Folgen mit
Erscheinungsdatum ("gestern", "vor 3 Tagen"), Dauer und Stand -- *neu*,
*43 % gehört* oder *gehört* (gedämpft). **Ein Tippen spielt die Folge ab**,
dort weiter, wo du aufgehört hast. Die Beschreibung einer Folge steht im
Kontextmenü.

**Weiterhören** in der Bibliothek listet angefangene Hörbücher und Folgen.

> Kommen deine Podcasts über einen Podcatcher-Abgleich in Music Assistant (zum
> Beispiel Overcast), führt der **Podcatcher den Hörstand**. "Als gehört
> markieren" in Tonarm wirkt dann nicht; die App sagt das. Ändere den Stand im
> Podcatcher. Solche Abgleiche geben oft nur die letzten zehn Folgen weiter.

---

## 7. Warteschlange, Gruppen, Durchsagen

**Warteschlange** (lange auf einen Player drücken, oder Pulley-Menü von
"Läuft gerade"): was noch kommt, der laufende Titel markiert.

- Tippen springt zu einem Eintrag; im Kontextmenü *Nach oben*, *Nach unten*,
  *Ans Ende*, *Entfernen*.
- Oben *Zufällige Reihenfolge*, *Überblenden* und *Wiederholen*.
- Im Pulley-Menü: *An anderen Player übergeben* (die Musik zieht mitsamt
  Position um), *Als Playlist speichern*, *Warteschlange leeren*.

**Gruppen** (lange drücken → *Gruppieren*): weitere Lautsprecher per Schalter
dazunehmen; sie spielen synchron dasselbe. Angeboten werden nur Lautsprecher,
die der Server mit diesem synchronisieren kann. Darüber die *Lautstärke der
Gruppe* und unter *Einzeln* ein Regler je Lautsprecher. *Gruppe auflösen*
trennt alle.

**Durchsage** (lange drücken → *Durchsage …*): Text eingeben, wahlweise *Gong
vorab* und eine *Eigene Lautstärke*, dann *Durchsagen*. Der Server spricht
den Text mit der Sprachausgabe, die in Music Assistant eingerichtet ist, und
stellt danach die vorige Lautstärke wieder her. Die Bestätigung kommt, wenn
die Durchsage gesprochen ist -- das kann 20 Sekunden dauern.

---

## 8. Playlists, Bibliothek, Radiosender pflegen

**Zur Playlist hinzufügen:** Kontextmenü eines Titels oder Pulley-Menü von
"Läuft gerade" → *Zur Playlist hinzufügen …* → eine Playlist wählen. Angeboten
werden nur Playlists, die sich bearbeiten lassen. Mit *Neue Playlist …* legst
du eine neue an.

> Bei Apple Music lassen sich deine eigenen Playlists bearbeiten, aber keine
> neuen anlegen. Neue Playlists legt Tonarm deshalb in Music Assistant selbst
> an; sie erscheinen in der Bibliothek, nicht bei Apple Music.

**Aus einer Playlist entfernen:** eigene Playlist öffnen, Titel lange drücken,
*Aus dieser Playlist entfernen*. Nach ein paar Sekunden lädt die Liste neu.

**Bibliothek:** Treffer eines Streamingdienstes (etwa aus der Suche mit
*Überall*) lassen sich mit *In die Bibliothek aufnehmen* dauerhaft ablegen.
*Aus der Bibliothek entfernen* gibt es für Titel, Alben und Sender -- bei
einem Album gehen seine Titel mit.

**Radiosender:** Bibliothek → Radio → Pulley-Menü → *Sender hinzufügen …*.
Namen suchen (etwa "SRF 1") -- durchsucht wird das weltweite Verzeichnis
RadioBrowser. Ein Tippen nimmt den Sender auf. Steht ein Sender dort nicht,
im Pulley-Menü *Eigene Stream-Adresse …*: Name und die Adresse des
Audiostroms (nicht der Webseite; sie steht meist in einer .m3u- oder
.pls-Datei auf der Seite des Senders).

---

## 9. Ohne die App zu öffnen

- **Cover** (in der Übersicht der laufenden Apps): Raum, Titel, Interpret,
  Play/Pause und Weiter. Bei Hörbüchern und Podcasts springt der zweite Knopf
  +30 s, und das Kapitel steht mit auf dem Cover. Das Cover zeigt den Player,
  der gerade spielt.
- **Sperrbildschirm und Medientasten** (Kopfhörer, Bluetooth): Play/Pause,
  Weiter, Zurück, Springen -- sie steuern den Lautsprecher, nicht das Telefon.
  Bei Hörbüchern springen Weiter und Zurück zwischen Kapiteln.
- **Benachrichtigung bei Titelwechsel**: in den Einstellungen einschaltbar,
  standardmässig aus.

---

## 10. Unterwegs

Von unterwegs erreicht das Telefon deinen Server nur über einen Tunnel ins
Heimnetz: ein VPN, [Tailscale](https://tailscale.com/) oder einen
Reverse-Proxy. Trage dessen Adresse in den Einstellungen unter **Adresse
unterwegs** ein -- bei Tailscale etwa `server.dein-tailnet.ts.net`.

Die App versucht immer zuerst die Heimadresse und eine halbe Sekunde später
die andere; es gilt, was zuerst antwortet. Zu Hause wird die zweite Adresse
also nie benutzt. Unter *Verbindung* zeigen die Einstellungen, worüber die App
gerade verbunden ist. Das Telefon selbst muss dafür im VPN bzw. Tailnet sein.

Cover bleiben auf dem Gerät gespeichert (bis 100 MB) und kommen nicht jedes
Mal neu über das Netz -- das spart unterwegs Daten.

---

## 11. Einstellungen im Überblick

| Abschnitt | Einstellung |
|---|---|
| (oben) | Serveradresse, Adresse unterwegs, Zugriffstoken |
| Prüfen | *Server erreichbar?* -- prüft beide Adressen; sagt nichts über das Token |
| Demo | *Demomodus* |
| Anzeige | *Hochkant festhalten*, *Farben aus dem Cover*, Cover-Zwischenspeicher mit Grösse und *leeren* |
| Benachrichtigungen | *Bei jedem Titelwechsel melden* |
| Verbindung | Servername, Version, *Verbunden über*, *Angemeldet als* |
| Zugangsdaten | *Zugangsdaten löschen*, *Jetzt neu verbinden* |
| (unten) | die Version der App -- und für Neugierige vielleicht mehr |

Ein leeres Tokenfeld lässt das gespeicherte Token unverändert; zum Entfernen
*Zugangsdaten löschen* benutzen.

---

## 12. Gut zu wissen

- **Zurück** startet einen Titel neu, wenn er schon ein paar Sekunden läuft;
  erst ein zweites Zurück geht zum vorigen. Das macht der Server so.
- **Ähnliches abspielen** schaltet beim Server die Zufallswiedergabe ein.
- Nach einer Durchsage zeigen manche Sonos-Lautsprecher in Home Assistant noch
  eine Weile "spielt", obwohl nichts zu hören ist. Tonarm betrifft das nicht.
- Kommt die App aus dem Hintergrund zurück, prüft sie kurz die Verbindung und
  lädt nach, was sie verpasst haben könnte.

---

## 13. Wenn etwas nicht geht

| Problem | Was helfen kann |
|---|---|
| "Server nicht erreichbar" | Adresse prüfen (bei Home Assistant: Adresse des HA-Rechners, Port 8095). Ist das Telefon im selben WLAN bzw. im VPN? |
| "Token ungültig oder abgelaufen" | In Music Assistant ein neues Token erzeugen und eintragen. |
| Keine Player zu sehen | *Aktualisieren* im Pulley-Menü; in Music Assistant prüfen, ob Player eingerichtet und aktiviert sind. |
| Tippen bewirkt scheinbar nichts | Die App wartet auf den Server; bei langsamen Anbietern (Songtext, Titel eines Streaming-Interpreten) kann das dauern. Nicht mehrfach tippen. |
| Cover fehlen unterwegs | *Adresse unterwegs* eintragen; Cover laden über die gerade verbundene Adresse. |
| "Der Podcast-Anbieter führt den Hörstand selbst" | Den Stand im Podcatcher ändern (siehe [Abschnitt 6](#6-hörbücher-und-podcasts)). |
| App hängt nach einem Update beim Start | SailfishOS wartet vermutlich auf eine Bestätigung (Berechtigungen oder Zugangsdaten) -- auf dem Bildschirm bestätigen. |

Fehler und Wünsche: [github.com/silly82/sailtonarm/issues](https://github.com/silly82/sailtonarm/issues).
