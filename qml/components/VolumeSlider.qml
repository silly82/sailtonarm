import QtQuick 2.6
import Sailfish.Silica 1.0

// Lautstärkeregler, der dem Finger folgt und nicht springt.
//
// - Beim Ziehen geht die Lautstärke schon raus, höchstens eine Stufe je
//   150 ms: die erste Änderung sofort, spätere als ein nachlaufender Versand
//   mit dem jeweils neuesten Wert. Beim Loslassen der Endwert, falls er noch
//   nicht draussen ist.
// - Danach zeigt der Regler seinen eigenen Wert, bis der Server den zuletzt
//   gesendeten meldet (±1, manche Player runden) oder 3 s vergangen sind.
//   Sonst spränge der Griff kurz auf den alten Stand zurück, weil das
//   player_updated mit dem neuen Wert erst nach einigen hundert Millisekunden
//   kommt.
//
// Ein Binding an den Serverwert gibt es bewusst nicht (siehe NowPlayingPage):
// `serverLevel` wird nur übernommen, solange niemand den Regler hält.
Slider {
    id: slider

    // Der Wert, den der Server meldet; negativ heisst unbekannt.
    property real serverLevel: -1

    // Bitte, diesen Pegel zu setzen. Die Seite reicht ihn an PlayerStore
    // weiter, der die Befehle je Player in Reihenfolge schickt.
    signal levelRequested(int level)

    minimumValue: 0
    maximumValue: 100
    stepSize: 1
    valueText: Math.round(value) + " %"

    // Hält der Regler gerade seinen eigenen Wert (Ziehen oder Nachlauf)?
    property bool _holding: false
    property int _lastSent: -1
    property real _lastSendTime: 0
    readonly property int _interval: 150

    function _sendCurrent() {
        var level = Math.round(value)
        if (level === _lastSent) {
            return
        }
        _lastSent = level
        _lastSendTime = Date.now()
        levelRequested(level)
    }

    function _adoptServer() {
        if (!_holding && serverLevel >= 0) {
            value = serverLevel
        }
    }

    onServerLevelChanged: {
        if (_holding && !pressed && _lastSent >= 0
                && Math.abs(serverLevel - _lastSent) <= 1) {
            settleTimer.stop()
            _holding = false
        }
        _adoptServer()
    }

    onPressedChanged: {
        if (pressed) {
            _holding = true
            settleTimer.stop()
            return
        }
        trailingTimer.stop()
        _sendCurrent()
        settleTimer.restart()
    }

    onValueChanged: {
        if (!pressed || trailingTimer.running) {
            return
        }
        var since = Date.now() - _lastSendTime
        if (since >= _interval) {
            _sendCurrent()
        } else {
            trailingTimer.interval = _interval - since
            trailingTimer.start()
        }
    }

    Component.onCompleted: _adoptServer()

    Timer {
        id: trailingTimer
        onTriggered: slider._sendCurrent()
    }

    Timer {
        id: settleTimer
        interval: 3000
        onTriggered: {
            slider._holding = false
            slider._adoptServer()
        }
    }
}
