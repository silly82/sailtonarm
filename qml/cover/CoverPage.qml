import QtQuick 2.6
import Sailfish.Silica 1.0

// Ausbaustufe 0: nur der Verbindungszustand. Ab Stufe 4 steht hier das
// laufende Stück mit Cover-Art und zwei Cover-Actions (Play/Pause, Weiter).
CoverBackground {
    id: cover

    property var mass

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingMedium
        spacing: Theme.paddingMedium

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Tonarm")
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.primaryColor
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: (mass && mass.ready) ? Theme.highlightColor : Theme.secondaryColor
            text: {
                if (!mass || !mass.configured) {
                    return qsTr("nicht eingerichtet")
                }
                if (mass.ready) {
                    return (mass.serverInfo && mass.serverInfo.name)
                            ? mass.serverInfo.name : qsTr("verbunden")
                }
                return qsTr("getrennt")
            }
        }
    }
}
