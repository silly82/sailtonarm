# Material für die Jolla-Store-Einreichung

Vorbereitet für eine Harbour-Einreichung. Die Einreichung selbst läuft von Hand
über harbour.jolla.com und ist hier nicht automatisiert. Store-Metadaten
(Beschreibung, Bildschirmfotos) werden auf der "application edit page"
getrennt vom Binärpaket gepflegt und brauchen kein neues Paket und keine
erneute QA, sobald das Binärpaket einmal angenommen ist.

Feld für Feld, passend zum tatsächlichen Formular:

## Title

`Tonarm` — 6 Zeichen, weit unter der 30-Zeichen-Grenze.

Bewusst nicht "Music Assistant": Harbour verbietet fremde Marken im
Anwendungsnamen. Der Bezug steht in der Beschreibung, zusammen mit dem
Hinweis, dass die App nicht mit dem Music-Assistant-Projekt verbunden ist.

## Details → Description

`description-de.txt` / `description-en.txt` (2672 / 2471 Zeichen, unter der
4000-Zeichen-Grenze; Stand v0.30, gegliedert in Fernbedienung, Bibliothek,
Alltag). Ohne Wiederholung des App-Namens (steht schon im Feld
Title) und ohne GitHub-Link (steht schon im Feld "Open source project URL").

Beide Fassungen enthalten am Ende einen Absatz zur **Audio-Berechtigung**. Der
gehört dorthin: das Berechtigungsfenster nennt sie dem Nutzer gegenüber als
"Audio aufzeichnen und abspielen", obwohl die App weder das eine noch das
andere tut — sie ist auf SailfishOS schlicht die Berechtigung, die das
Anmelden eines MPRIS-Dienstes (Sperrbildschirm) erlaubt. Unerklärt liest sich
das wie ein Widerspruch.

Für eine zweisprachige Anzeige im Formular "+ Add a language" benutzen.

## Details → Summary

`summary-de.txt` / `summary-en.txt` (133 / 134 Zeichen, unter der
200-Zeichen-Grenze).

## Details → Recent changes

Bei der ersten Einreichung leer lassen -- das Feld ist für Aktualisierungen
gedacht. Für spätere Versionen: der Änderungsverlauf steht im `%changelog` von
`../rpm/harbour-tonarm.spec`, zweisprachige Fassungen in den Release-Notizen
auf GitHub, die ausführliche in `../KONZEPT.md`.

## Categorization → Category

Nicht vorbereitet — die Auswahlmöglichkeiten des Formulars lagen nicht vor.
Vor Ort wählen, am ehesten passt etwas in Richtung Multimedia/Audio.

## Binaries

**Alle drei Architekturen werden gebraucht.** Die Harbour-FAQ ist da
eindeutig:

> "At the moment we support armv7hl and i486 architectures." · "If your
> application contains compiled parts, it needs to be built for all the
> supported architectures." · "If you do not provide RPM for certain
> architecture, your application won't be available in store on devices with
> that architecture."

Tonarm hat mit `src/credentials.cpp` kompilierte Teile, ist also **kein
`noarch`-Paket** -- die Abkürzung "ein einziges noarch-RPM für alle Geräte"
steht hier nicht offen.

`i486` ist dabei *nicht* die Emulator-Architektur, auch wenn der SDK-Emulator
sie benutzt: es ist die Architektur des **Jolla Tablet**, und die FAQ führt sie
ausdrücklich als unterstützt. (Ältere Fassungen dieser Datei behaupteten das
Gegenteil -- das war falsch.)

| Datei | Prüfung | Gerätetest |
|---|---|---|
| `harbour-tonarm-0.33-1.aarch64.rpm` | harbour: succeeded · rpmlint: 0/0/0 | **auf echter Hardware gelaufen** (Jolla Phone 2026) |
| `harbour-tonarm-0.33-1.armv7hl.rpm` | harbour: succeeded · rpmlint: 0/0/0 | nie auf echter armv7hl-Hardware |
| `harbour-tonarm-0.33-1.i486.rpm` | harbour: succeeded · rpmlint: 0/0/0 | nie auf echter i486-Hardware |

Für die Einreichung die Pakete des neuesten Releases nehmen; jedes Release
seit v0.17 hat alle drei, gebaut aus dem getaggten Commit.

Alle drei liegen in `../RPMS/` (nicht im Repo -- `RPMS/` steht in
`.gitignore`) und hängen am GitHub-Release.

Die FAQ nennt `aarch64` übrigens gar nicht; sie stammt sichtbar aus der Zeit
vor den 64-Bit-Geräten. Hochgeladen wird es trotzdem -- ohne aarch64-Paket
sähen die aktuellen Telefone die App nicht, und genau das ist das Gerät, auf
dem sie geprüft ist.

### Bauen aller drei

**Zwischen den Architekturen zwingend aufräumen**, sonst relinkt der
In-Place-Build die Objektdateien der vorherigen Architektur still in das neue
Paket. Und `no-fix-version` setzen, sobald ein Git-Tag existiert: sfdk leitet
sonst eine Schnappschussversion aus dem Git-Zustand ab
(`0.17+master.20260921182521.2366326-1`), und die Pakete hätten
uneinheitliche Versionen.

```sh
for arch in aarch64 armv7hl i486; do
  rm -f harbour-tonarm *.o moc_*.cpp moc_*.h Makefile .qmake.stash
  sfdk config target=SailfishOS-5.1.0.11-$arch \
    && sfdk config specfile=rpm/harbour-tonarm.spec \
    && sfdk config no-fix-version \
    && sfdk build
done
```

**`sfdk build` räumt dabei ältere Pakete aus `RPMS/` weg** -- die fertigen
also nach jedem Durchgang wegkopieren und am Ende wieder zusammenlegen.

Gegenprobe, dass im Paket wirklich das richtige Binary steckt (auf dem Host
fehlt `rpm2cpio`, deshalb in der Build-Umgebung):

```sh
sfdk tools exec SailfishOS-5.1.0.11-aarch64 sh -c \
  "cd $PWD && rpm2cpio RPMS/harbour-tonarm-<v>-1.<arch>.rpm \
   | cpio -i --to-stdout ./usr/bin/harbour-tonarm > /tmp/b; file /tmp/b"
```

Erwartet: `ARM aarch64` / `ARM, EABI5` / `Intel 80386`.

## Compatibility → Device type

Phone. Auf einem Tablet-Formfaktor nie geprüft.

## Visual assets → Icon

`icon-172x172.png` — dasselbe Bild wie `../icons/172x172/harbour-tonarm.png`,
passt genau auf die vom Formular verlangten 172×172 Pixel. Seit v0.33 ein
Tropfen: drei Ecken voll gerundet, nur oben rechts eckig; die Platte liegt
konzentrisch in der Rundung, der Tonarm-Drehpunkt in der spitzen Ecke. Neu
erzeugen mit `python3 icons/source/generate-icon.py` (braucht python3-cairo);
das Skript schreibt die App-Icons und diese Datei.

## Visual assets → Cover

`cover-1080x540.png`, erzeugt von `generate-cover.py` im selben Stil wie das
App-Icon.

## Visual assets → Screenshots

In `screenshots/de/` und `screenshots/en/`, vom echten Gerät aufgenommen
(1032×2272, Jolla Phone 2026), Stand v0.32, **alle aus dem Demomodus**, je
neun Bilder in derselben Reihenfolge. Die deutschen heissen wie unten, die
englischen `01-player`, `02-now-playing`, `03-library`, `04-artist`,
`05-album`, `06-queue`, `07-audiobook`, `08-lyrics`, `09-podcast`.

Für die englischen läuft die App mit `LANG=en_GB.utf8`: Bedienoberfläche und
Raumnamen sind englisch (die Räume sind dafür in `DemoData.js` übersetzbar),
Musik, Songtext und Podcast-Folgen bleiben erfundene deutsche Inhalte. Im
Formular die englischen Bilder der englischen Sprachfassung zuordnen, sofern
es das je Sprache erlaubt; sonst die englischen nehmen.

- `01-player.png` — Player-Liste mit Gruppe und laufenden Titeln
- `02-laeuft-gerade.png` — Läuft gerade: Cover, Fortschritt, Lautstärke,
  Hintergrund in den Farben des Covers
- `03-bibliothek.png` — Bibliotheksübersicht mit Anzahl je Bereich
- `04-interpret.png` — Interpretenseite: beliebte Titel, darunter „In der
  Bibliothek"
- `05-album.png` — Albumseite mit Cover und Titelliste
- `06-warteschlange.png` — Warteschlange mit Zufall, Überblenden, Wiederholen
- `07-hoerbuch.png` — Läuft gerade bei einem Hörbuch: Kapitel, −15 s/+30 s,
  Tempo
- `08-songtext.png` — mitlaufender Songtext
- `09-podcast.png` — Podcast mit Folgen, Datum, Dauer und Hörstand

Der Demomodus (Einstellungen → Demo) zeigt fünf erfundene Räume, erfundene
Musik und abstrakte Cover ohne Schrift oder Marken (`generate-demo-art.py`).
Damit zeigen die Bilder weder die Räume einer echten Wohnung noch deren
Hörhistorie, noch fremde Albumcover. Die Player-Liste trägt oben den Hinweis
"Demomodus"; das ist ehrlich und bleibt so. Die Easter Eggs sind bewusst auf
keinem Bild.

Aufgenommen wurde mit einem vorübergehenden Einstieg in
`qml/harbour-tonarm.qml` (nicht eingecheckt), der nach dem Start je nach einem
dconf-Schlüssel direkt die gewünschte Seite öffnet -- so ist jedes Bild ein
frischer Start des Demomodus, ohne Tippen auf dem Telefon. Für Englisch
dieselbe App mit `LANG=en_GB.utf8` vor `invoker` starten.

Für Store-Bilder den Demomodus frisch einschalten (er beginnt dann immer beim
selben Ausgangszustand) und danach wieder aus.

Aufnahmerezept (Gerät im Hochformat, sonst kommt das Bild quer):

```sh
ssh defaultuser@<telefon> "devel-su sh -c 'env \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
  dbus-send --session --print-reply --dest=org.nemomobile.lipstick \
  /org/nemomobile/lipstick/screenshot \
  org.nemomobile.lipstick.saveScreenshot string:/home/defaultuser/shot.png'"
```

Der Pfad muss unterhalb des Benutzerverzeichnisses liegen, sonst lehnt
Lipstick ihn ab ("path must be under home directory").
