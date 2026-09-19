import QtQuick 2.6
import Sailfish.Silica 1.0
import "../lib/MassModels.js" as Models

// Auf welchem Player soll landen, was man in der Bibliothek antippt. Ohne
// eigene Wahl entscheidet PlayerStore selbst (der gerade spielende, sonst der
// zuletzt geöffnete) -- hier wird die Wahl festgenagelt.
Page {
    id: page

    property var mass
    property var store

    allowedOrientations: Orientation.All

    SilicaListView {
        anchors.fill: parent
        model: store ? store.players : []

        header: Column {
            width: page.width

            PageHeader { title: qsTr("Ziel-Player") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                bottomPadding: Theme.paddingMedium
                text: qsTr("Hier landet, was du in der Bibliothek abspielst.")
            }
        }

        delegate: ListItem {
            id: row
            contentHeight: Theme.itemSizeMedium
            opacity: Models.isAvailable(modelData) ? 1.0 : Theme.opacityLow

            readonly property bool current:
                store && store.targetPlayerId === modelData.player_id

            onClicked: {
                store.explicitTargetPlayerId = modelData.player_id
                pageStack.pop()
            }

            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - checkMark.width - Theme.paddingMedium
                truncationMode: TruncationMode.Fade
                text: Models.playerName(modelData)
                color: row.current ? Theme.highlightColor
                                   : (row.highlighted ? Theme.highlightColor
                                                      : Theme.primaryColor)
            }

            Image {
                id: checkMark
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                source: "image://theme/icon-s-accept"
                visible: row.current
            }
        }

        VerticalScrollDecorator {}
    }
}
