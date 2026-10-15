# Sendspin-Probe für Rechner (i486) oder Telefon (aarch64), nicht Teil der App.
# Bauen: siehe Kopf von probe.cpp und docs/DEVELOPMENT.md.
TEMPLATE = app
TARGET = probe
QT = core network websockets
CONFIG += console c++11 link_pkgconfig
CONFIG += thread
PKGCONFIG += libcrypto libpulse-simple
SOURCES += probe.cpp ../../src/sendspin/noisesession.cpp ../../src/sendspin/sendspinclient.cpp \
    ../../src/sendspin/timefilter.cpp ../../src/sendspin/audiooutput.cpp
HEADERS += ../../src/sendspin/noisesession.h ../../src/sendspin/sendspinclient.h \
    ../../src/sendspin/timefilter.h ../../src/sendspin/audiooutput.h
