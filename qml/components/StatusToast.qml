import QtQuick 2.6
import Sailfish.Silica 1.0

// Kurze Rückmeldung am unteren Rand: "Als Nächstes eingereiht" und
// Ähnliches. Nötig, weil beim Einreihen sichtbar gar nichts passiert -- ohne
// Rückmeldung weiss niemand, ob der Tipper angekommen ist.
//
// Bewusst kein System-Notification: die gehört dem Nutzer und seinem
// Sperrbildschirm, nicht einer Bestätigung innerhalb der App.
Item {
    id: toast

    anchors {
        left: parent.left
        right: parent.right
        bottom: parent.bottom
        bottomMargin: Theme.paddingLarge
    }
    height: label.height + 2 * Theme.paddingMedium
    opacity: 0
    visible: opacity > 0
    z: 100

    property bool isError: false

    function show(text, error) {
        label.text = text
        toast.isError = error === true
        toast.opacity = 1
        hideTimer.restart()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.highlightDimmerColor, 0.9)
        radius: Theme.paddingSmall
    }

    Label {
        id: label
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        color: toast.isError ? Theme.errorColor : Theme.primaryColor
    }

    Behavior on opacity { FadeAnimation { duration: 200 } }

    Timer {
        id: hideTimer
        interval: 2500
        onTriggered: toast.opacity = 0
    }
}
