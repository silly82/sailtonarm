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

`../RPMS/harbour-tonarm-<version>-1.aarch64.rpm` — deckt aktuelle 64-Bit-Geräte
ab und ist auf echter Hardware geprüft (Jolla Phone 2026).

`armv7hl` baut ebenfalls und besteht die Harbour-Prüfung, wurde aber nie auf
echter armv7hl-Hardware ausgeführt. Nur mit hochladen, wenn Mehrarchitektur
trotzdem gewünscht ist. `i486` ist reine Emulator-Architektur und gehört nicht
in eine Einreichung.

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
