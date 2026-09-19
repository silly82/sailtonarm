Name:       harbour-tonarm

Summary:    Fernbedienung für einen Music-Assistant-Server
Version:    0.6
Release:    1
License:    MIT
URL:        https://github.com/silly82/sailtonarm
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   qt5-qtdeclarative-import-websockets
Requires:   qt5-qtwebsockets
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
