#!/bin/sh
# Baut und startet die C++-Tests für Sendspin (tests/sendspin/tst_*.cpp) im
# i486-Bauziel des Sailfish SDK, ohne Telefon.
#
# Einmalig nötig: Header im Bauziel installieren
#   sfdk engine exec sb2 -t <ziel> -m sdk-install -R \
#       zypper -n in openssl-devel qt5-qtwebsockets-devel pulseaudio-devel
#
# Aufruf aus dem Projektverzeichnis:  sh tests/sendspin/run.sh [ziel]
# Endet mit Status 0 nur, wenn alle Tests bestehen.
TARGET=${1:-SailfishOS-5.1.0.11-i486}
SFDK=${SFDK:-$HOME/SailfishOS/bin/sfdk}
cd "$(dirname "$0")" || exit 1
OUT=$("$SFDK" engine exec sb2 -t "$TARGET" sh -c "
    cd '$PWD' && mkdir -p .build &&
    g++ -std=c++11 -fPIC -Wall -o .build/tst_noise tst_noise.cpp ../../src/sendspin/noisesession.cpp \
        \$(pkg-config --cflags --libs Qt5Core libcrypto) &&
    .build/tst_noise vectors-chachapoly.json vectors-aesgcm.json; echo \"exit=\$?\"" 2>&1)
printf '%s\n' "$OUT" | grep -v '^exit=' | grep -v 'SOFT ASSERT'
printf '%s\n' "$OUT" | grep -q '^exit=0$'
