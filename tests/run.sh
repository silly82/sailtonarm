#!/bin/sh
# Führt die QML-Tests (tests/tst_*.qml) im i486-Bauziel des Sailfish SDK aus:
# i486 läuft im Build-Engine direkt, ohne Telefon oder Emulator.
#
# Einmalig nötig: qmltestrunner im Bauziel installieren
#   sfdk engine exec sb2 -t <ziel> -m sdk-install -R \
#       zypper -n in qt5-qtdeclarative-devel-tools
#
# Aufruf aus dem Projektverzeichnis:  sh tests/run.sh [ziel]
# Endet mit Status 0 nur, wenn alle Tests bestehen.
TARGET=${1:-SailfishOS-5.1.0.11-i486}
SFDK=${SFDK:-$HOME/SailfishOS/bin/sfdk}
cd "$(dirname "$0")" || exit 1
OUT=$("$SFDK" engine exec sb2 -t "$TARGET" sh -c \
    "cd '$PWD' && QT_QPA_PLATFORM=minimal /usr/lib/qt5/bin/qmltestrunner -input . ; echo \"exit=\$?\"" 2>&1)
printf '%s\n' "$OUT" | grep -v 'SOFT ASSERT' | grep -v '^exit='
printf '%s\n' "$OUT" | grep -q '^exit=0$'
