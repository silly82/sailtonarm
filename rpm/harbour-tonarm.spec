Name:       harbour-tonarm

Summary:    Fernbedienung für einen Music-Assistant-Server
Version:    0.15
Release:    1
License:    MIT
URL:        https://github.com/silly82/sailtonarm
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   qt5-qtdeclarative-import-websockets
Requires:   qt5-qtwebsockets
# Amber.Mpris meldet die App als MPRIS-Dienst an (Sperrbildschirm,
# Medientasten); Nemo.Notifications nur für die abschaltbare Meldung bei
# Titelwechsel. Beides reine QML-Plugins -- nichts wird dagegen gelinkt.
Requires:   amber-qml-plugin-mpris
Requires:   nemo-qml-plugin-notifications-qt5
# libsailfishsecrets (die C++-API hinter src/credentials.{h,cpp}) steht hier
# absichtlich *nicht*: Harbours Validator lehnt den reinen Paketnamen ab
# ("Dependency not allowed"), während die automatische Soname-Abhängigkeit, die
# rpmbuild aus dem gelinkten Binary ableitet (libsailfishsecrets.so.0, auf
# Harbours Allowed-APIs-Liste), durchgeht. Die Soname von Hand einzutragen war
# in harbour-hacontrol v0.7 genau das, was die pkcon-Installation zerlegt hat.
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(sailfishsecrets)
BuildRequires:  desktop-file-utils

%description
Inoffizieller SailfishOS-Client für Music-Assistant-Server. Fernbedienung
für die Player der Anlage: Liste aller Player mit dem, was gerade läuft,
Play/Pause direkt in der Zeile, und je Player eine Seite mit Cover,
Titelangaben, Fortschritt zum Springen, Weiter/Zurück und Lautstärke.
Alle Bedienelemente richten sich nach den Fähigkeiten des jeweiligen
Players. Aktualisierung per Server-Events, nicht durch Nachfragen.
Serveradresse und Zugriffstoken liegen verschlüsselt in Sailfish Secrets.
Bibliothek, Suche und Warteschlange folgen in den nächsten Ausbaustufen
(siehe KONZEPT.md).

%prep
%autosetup -n %{name}-%{version}

%build

%qmake5

%make_build


%install
%qmake5_install

# sfdk ruft qmake entwicklungsfreundlich mit QMAKE_STRIP=: auf (ein No-Op), das
# automatische Strippen läuft also nie -- explizit strippen, sonst meckert
# Harbours rpmlint über ein ungestripptes Binary.
%{__strip} %{buildroot}%{_bindir}/%{name}

desktop-file-install --delete-original       \
  --dir %{buildroot}%{_datadir}/applications             \
   %{buildroot}%{_datadir}/applications/*.desktop

%files
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Sun Sep 20 2026 silly82 <siliwalker@gmail.com> - 0.15-1
- Lautsprecher lassen sich zusammenschalten: im Kontextmenü einer Zeile
  der Player-Liste öffnet "Gruppieren" eine Seite, auf der die passenden
  Lautsprecher per Schalter dazu- oder abgeschaltet werden. Dazu eine
  Lautstärke für die ganze Gruppe und "Gruppe auflösen". Angeboten werden
  nur Lautsprecher, die der Server auch tatsächlich synchronisieren kann.
  Angeschlossene Lautsprecher zeigen in der Player-Liste, woran sie hängen.
- Favoriten: im Kontextmenü jeder Bibliothekszeile hinzufügen oder
  entfernen, als Stern in der Liste sichtbar, und im Pulley-Menü lässt sich
  eine Liste auf "Nur Favoriten" umstellen.

* Sun Sep 20 2026 silly82 <siliwalker@gmail.com> - 0.14-1
- Fehlgeschlagene Steuerbefehle landen jetzt im Systemprotokoll. Bisher
  verschwanden sie lautlos, wenn sie nicht von einer offenen Seite kamen --
  etwa vom Sperrbildschirm oder vom Cover.

* Sun Sep 20 2026 silly82 <siliwalker@gmail.com> - 0.12-1
- Die Knöpfe auf dem Sperrbildschirm blieben wirkungslos und Zufalls- wie
  Wiederholmodus fehlten dort ganz: drei MPRIS-Eigenschaften frieren beim
  ersten Abruf durch den Sperrbildschirm dauerhaft ein, und zu dem
  Zeitpunkt stand die Verbindung zum Server noch nicht.

* Sun Sep 20 2026 silly82 <siliwalker@gmail.com> - 0.11-1
- Der Sperrbildschirm zeigte die tausendfache Spiellänge (aus 4:56 wurden
  82 Stunden): Amber.Mpris rechnet in Millisekunden und wandelt selbst in
  die Mikrosekunden des D-Bus um. Betraf auch Spielzeit und Springen.

* Sun Sep 20 2026 silly82 <siliwalker@gmail.com> - 0.10-1
- Der MPRIS-Dienst meldete sich gar nicht am Bus an: Sailjail erlaubt einer
  App nur den aus OrganizationName/ApplicationName abgeleiteten Busnamen.
  "org.mpris.MediaPlayer2.*" gewährt die Audio-Berechtigung, die deshalb
  jetzt in der .desktop steht -- trotz ihres Namens nicht fürs Abspielen,
  die App gibt weiterhin kein Audio aus.
- Die Titelkennung für den Sperrbildschirm muss ein D-Bus-Objektpfad sein;
  die nackte Queue-Kennung verwarf Qt mit "invalid path".

* Sat Sep 19 2026 silly82 <siliwalker@gmail.com> - 0.9-1
- Ausbaustufe 4: Sperrbildschirm und Medientasten steuern jetzt den
  entfernten Player. Die App meldet sich als MPRIS-Dienst an und spiegelt
  Titel, Interpret, Album, Cover, Spielzeit, Lautstärke sowie Zufalls- und
  Wiederholmodus dorthin -- und nimmt von dort Play/Pause, Weiter, Zurück,
  Springen und Lautstärke entgegen.
- Optionale Benachrichtigung bei Titelwechsel, in den Einstellungen
  einzuschalten und bewusst standardmässig aus.

* Sat Sep 19 2026 silly82 <siliwalker@gmail.com> - 0.8-1
- In der Warteschlange überdeckte die Spieldauer das Ende langer Titel: die
  Textspalte reichte unter die Dauer, statt vorher auszublenden.

* Sat Sep 19 2026 silly82 <siliwalker@gmail.com> - 0.7-1
- Ausbaustufe 3: die Warteschlange. Zu sehen, was noch kommt, der laufende
  Eintrag markiert, ein Tippen springt dorthin. Einträge lassen sich nach
  oben, nach unten, ans Ende schieben oder entfernen.
- Zufällige Reihenfolge, Überblenden und Wiederholen (aus / alle / ein
  Titel) je Warteschlange.
- Die Warteschlange an einen anderen Player übergeben -- sie wandert
  mitsamt Abspielposition mit.
- Die Warteschlange als Playlist in der Bibliothek speichern, und sie
  leeren (mit Widerrufsfrist).
- Playlists haben jetzt einen Knopf "Zufällig", der die Playlist gleich in
  zufälliger Reihenfolge startet.
- Erreichbar über das Pulley-Menü von Now Playing und über das
  Kontextmenü einer Zeile in der Player-Liste.

* Sat Sep 19 2026 silly82 <siliwalker@gmail.com> - 0.6-1
- Ausbaustufe 2: Bibliothek und Suche. Interpreten, Alben, Titel, Playlists
  und Radio mit Anzahl, seitenweise nachgeladen und je Liste durchsuchbar.
  Album- und Interpretenseiten mit Cover und Titel- bzw. Albumliste,
  Playlists mit ihren Titeln.
- Suche über alle Medientypen auf einer Seite, nach Typ gruppiert.
- Abspielen aus jeder Liste per Kontextmenü: jetzt spielen, als Nächstes,
  anhängen. Auf welchem Player das landet, wählt man einmal aus; ohne
  eigene Wahl gilt der Player, der gerade spielt.

* Sat Sep 19 2026 silly82 <siliwalker@gmail.com> - 0.5-1
- Das Cover zeigt jetzt, was läuft: Albumbild als Hintergrund, Titel,
  Interpret und den Namen des Players, dazu Play/Pause und Weiter als
  Cover-Actions. Gezeigt wird der Player, der gerade spielt -- nicht
  zwingend der zuletzt geöffnete. Damit lässt sich die Anlage bedienen,
  ohne die App zu öffnen.

* Sat Sep 19 2026 silly82 <siliwalker@gmail.com> - 0.4-1
- Der Fortschrittsbalken in der Player-Liste lief aus seiner Zeile heraus in
  die darunter: die Zeilenhöhe war fest, obwohl der Balken zusätzlich Platz
  braucht. Die Zeile wächst jetzt mit, und der Balken fluchtet mit dem Text
  darüber.
- Die Markierung des zuletzt benutzten Players wurde am Bildschirmrand
  angeschnitten.

* Sat Sep 19 2026 silly82 <siliwalker@gmail.com> - 0.3-1
- Weiter, Zurück und der Fortschrittsregler waren gesperrt, obwohl sie
  funktionieren: sie hingen an den Fähigkeiten des Players, diese Kommandos
  gehen aber an die Warteschlange, und die fährt der Server selbst. Jetzt
  entscheidet allein, ob eine Warteschlange aktiv ist.

* Sat Sep 19 2026 silly82 <siliwalker@gmail.com> - 0.2-1
- Ausbaustufe 1: aus der Diagnoseseite wird eine Fernbedienung. Die
  Startseite listet die Player der Anlage mit laufendem Titel,
  Fortschrittsbalken und Play/Pause in der Zeile; ein Tippen öffnet eine
  Seite mit Cover, Titel/Interpret/Album, Fortschrittsregler zum Springen,
  Weiter/Zurück, Lautstärke und Stummschaltung.
- Der Zustand kommt jetzt per Server-Events (player_updated, queue_updated,
  queue_time_updated) statt durch Nachfragen; zwischen zwei Meldungen zählt
  die Spielzeit lokal weiter.
- Bedienelemente richten sich nach supported_features des Players: was ein
  Player nicht kann, erscheint gar nicht erst.
- Die Serverangaben (Name, Version, API-Schema, angemeldeter Benutzer) sind
  von der Startseite in die Einstellungen gewandert.
- Der zuletzt geöffnete Player wird gemerkt, steht in der Liste oben und ist
  markiert.

* Sat Sep 19 2026 silly82 <siliwalker@gmail.com> - 0.1-1
- Ausbaustufe 0: Projektgerüst, Einstellungen (Serveradresse + Token,
  verschlüsselt über Sailfish Secrets), WebSocket-Verbindung zum
  Music-Assistant-Server inklusive ServerInfo/auth-Handshake und
  automatischem Reconnect, Verbindungsstatus und Servermeldungen in der UI,
  Testaufruf players/all zur Überprüfung von Token und Scopes.
