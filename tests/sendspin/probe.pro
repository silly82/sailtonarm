# Stufe-5a-Probe, nur für den Rechner (i486-Bauziel), nicht Teil der App.
# Bauen: siehe Kopf von probe.cpp und docs/DEVELOPMENT.md.
TEMPLATE = app
TARGET = probe
QT = core network websockets
CONFIG += console c++11 link_pkgconfig
PKGCONFIG += libcrypto
SOURCES += probe.cpp ../../src/sendspin/noisesession.cpp ../../src/sendspin/sendspinclient.cpp
HEADERS += ../../src/sendspin/noisesession.h ../../src/sendspin/sendspinclient.h
