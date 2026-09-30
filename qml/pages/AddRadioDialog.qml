import QtQuick 2.6
import Sailfish.Silica 1.0

// Ein Sender über seine Stream-Adresse -- für Sender, die in keinem
// Verzeichnis stehen (Lokalradio, eigener Icecast-Server).
Dialog {
    id: dialog

    readonly property string stationName: nameField.text.trim()
    readonly property string streamUrl: urlField.text.trim()

    canAccept: stationName.length > 0 && /^https?:\/\/\S+$/i.test(streamUrl)

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Aufnehmen")
        }

        TextField {
            id: nameField
            width: parent.width
            label: qsTr("Name des Senders")
            placeholderText: label
            focus: true
            EnterKey.iconSource: "image://theme/icon-m-enter-next"
            EnterKey.onClicked: urlField.focus = true
        }

        TextField {
            id: urlField
            width: parent.width
            label: qsTr("Stream-Adresse (http:// oder https://)")
            placeholderText: "https://…"
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: if (dialog.canAccept) dialog.accept()
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("Die Adresse des Audiostroms selbst, nicht die Webseite des Senders. Sie steht meist in einer .m3u- oder .pls-Datei auf der Seite des Senders.")
        }
    }
}
