import QtQuick 2.6
import Sailfish.Silica 1.0

// Name für die aus der Warteschlange erzeugte Playlist. Eigener Dialog statt
// Direktspeichern: der Name landet in der Bibliothek und bleibt dort stehen.
Dialog {
    id: dialog

    property string defaultName: ""
    readonly property string playlistName: nameField.text.trim()

    canAccept: playlistName.length > 0

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Speichern")
            cancelText: qsTr("Abbrechen")
        }

        TextField {
            id: nameField
            width: parent.width
            label: qsTr("Name der Playlist")
            placeholderText: qsTr("Name der Playlist")
            text: dialog.defaultName.length > 0
                  ? qsTr("Warteschlange %1").arg(dialog.defaultName) : ""
            focus: true
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: if (dialog.canAccept) dialog.accept()
        }
    }
}
