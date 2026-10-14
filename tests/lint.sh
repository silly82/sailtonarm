#!/bin/sh
# Prüft alle QML- und JS-Dateien mit dem qmllint aus dem i486-Bauziel -- das
# ist Qt 5.6 wie auf dem Telefon, und anders als der qmllint des PCs endet er
# bei einem Fehler auch mit einem Fehlerstatus.
#
# Einmalig nötig: wie tests/run.sh (qt5-qtdeclarative-devel-tools im Bauziel).
# Aufruf aus dem Projektverzeichnis:  sh tests/lint.sh [ziel]
TARGET=${1:-SailfishOS-5.1.0.11-i486}
SFDK=${SFDK:-$HOME/SailfishOS/bin/sfdk}
cd "$(dirname "$0")/.." || exit 1
OUT=$("$SFDK" engine exec sb2 -t "$TARGET" sh -c "cd '$PWD' && bad=0; \
    for f in \$(find qml tests -name '*.qml' -o -name '*.js'); do \
        /usr/lib/qt5/bin/qmllint \"\$f\" 2>&1 || { echo \"FEHLER: \$f\"; bad=1; }; \
    done; echo \"exit=\$bad\"" 2>&1)
printf '%s\n' "$OUT" | grep -v 'SOFT ASSERT' | grep -v '^exit='
printf '%s\n' "$OUT" | grep -q '^exit=0$' && echo "qmllint: alles in Ordnung"
