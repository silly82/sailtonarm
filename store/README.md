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

`description-de.txt` / `description-en.txt` (2766 / 2436 Zeichen, unter der
4000-Zeichen-Grenze). Ohne Wiederholung des App-Namens (steht schon im Feld
Title) und ohne GitHub-Link (steht schon im Feld "Open source project URL").

Beide Fassungen enthalten am Ende einen Absatz zur **Audio-Berechtigung**. Der
gehört dorthin: das Berechtigungsfenster nennt sie dem Nutzer gegenüber als
"Audio aufzeichnen und abspielen", obwohl die App weder das eine noch das
andere tut — sie ist auf SailfishOS schlicht die Berechtigung, die das
Anmelden eines MPRIS-Dienstes (Sperrbildschirm) erlaubt. Unerklärt liest sich
das wie ein Widerspruch.

Für eine zweisprachige Anzeige im Formular "+ Add a language" benutzen.

## Details → Summary

`summary-de.txt` / `summary-en.txt` (137 / 127 Zeichen, unter der
200-Zeichen-Grenze).

## Details → Recent changes

Nicht vorbereitet — das Feld ist für Aktualisierungsmeldungen gedacht, und dies
wäre die erste Einreichung. Der Änderungsverlauf steht im `%changelog` von
`../rpm/harbour-tonarm.spec`, die ausführliche Fassung in `../KONZEPT.md`.

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
| `harbour-tonarm-0.17-1.aarch64.rpm` | harbour: succeeded · rpmlint: 0/0/0 | **auf echter Hardware gelaufen** (Jolla Phone 2026) |
| `harbour-tonarm-0.17-1.armv7hl.rpm` | harbour: succeeded · rpmlint: 0/0/0 | nie auf echter armv7hl-Hardware |
| `harbour-tonarm-0.17-1.i486.rpm` | harbour: succeeded · rpmlint: 0/0/0 | nie auf echter i486-Hardware |

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

`icon-172x172.png` — Kopie von `../icons/172x172/harbour-tonarm.png`, passt
genau auf die vom Formular verlangten 172×172 Pixel. Neu erzeugen mit
`python3 icons/source/generate-icon.py` (braucht python3-cairo).

## Visual assets → Cover

`cover-1080x540.png`, erzeugt von `generate-cover.py` im selben Stil wie das
App-Icon.

## Visual assets → Screenshots

In `screenshots/`, vom echten Gerät aufgenommen (1032×2272, Jolla Phone 2026):

- `01-bibliothek.png` — Bibliotheksübersicht mit Anzahl je Bereich
- `02-album.png` — Albumseite mit Cover und Titelliste
- `03-titelliste.png` — Titelliste mit Suchfeld

**Bewusst nicht dabei:** Bildschirmfotos der Player-Liste, der
Now-Playing-Seite und der Warteschlange. Die sehen zwar besser aus, zeigen
aber zwangsläufig die eigenen Lautsprechernamen (also die Räume der Wohnung)
und die zuletzt gehörte Musik. Für eine öffentliche Store-Anzeige ist das eine
Entscheidung, die der Einreichende selbst treffen sollte — entweder mit
umbenannten Testplayern neu aufnehmen oder die vorhandenen bewusst
dazunehmen.

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
