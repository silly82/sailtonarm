# NOTICE:
#
# Application name defined in TARGET has a corresponding QML filename.
# If name defined in TARGET is changed, the following needs to be done
# to match new name:
#   - corresponding QML filename must be changed
#   - desktop icon filename must be changed
#   - desktop filename must be changed
#   - icon definition filename in desktop file must be changed
#   - translation filenames have to be changed

TARGET = harbour-tonarm

CONFIG += sailfishapp

# Sailfish.Secrets is driven from C++ (src/credentials.{h,cpp}), not from QML --
# the QML plugin cannot express the two requests we need, see src/credentials.h.
CONFIG += link_pkgconfig c++11
# sailfishapp is listed in PKGCONFIG on purpose even though "CONFIG +=
# sailfishapp" already pulls it in: sailfishapp's own .prf appends itself to
# PKGCONFIG, and the list must be complete whenever qmake evaluates it. With
# only "PKGCONFIG += sailfishsecrets" the sailfishapp libs silently drop out of
# the link line ("undefined reference to SailfishApp::createView()") -- learned
# the hard way in harbour-hacontrol.
PKGCONFIG += sailfishsecrets sailfishapp

SOURCES += src/harbour-tonarm.cpp \
    src/credentials.cpp

HEADERS += \
    src/credentials.h

DISTFILES += qml/harbour-tonarm.qml \
    qml/cover/CoverPage.qml \
    qml/components/MassConnection.qml \
    qml/components/PlayerStore.qml \
    qml/lib/MassApi.js \
    qml/lib/MassModels.js \
    qml/pages/PlayersPage.qml \
    qml/pages/NowPlayingPage.qml \
    qml/pages/SettingsPage.qml \
    rpm/harbour-tonarm.spec \
    harbour-tonarm.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

CONFIG += sailfishapp_i18n

# Quelltext-Strings sind deutsch (siehe README, Abschnitt "Sprache"); die
# englische Fassung ist die Übersetzung.
TRANSLATIONS += translations/harbour-tonarm-en.ts
