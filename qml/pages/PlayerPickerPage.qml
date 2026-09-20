import QtQuick 2.6
import Sailfish.Silica 1.0
import "../lib/MassModels.js" as Models

// Einen Player auswählen. Zwei Verwendungen: Ziel für alles, was man in der
// Bibliothek abspielt (Voreinstellung), und Ziel einer Warteschlangen-
// Übergabe -- dann setzt `pickHandler` die Bedeutung, und die Seite ändert
// selbst nichts.
Page {
    id: page

    property var mass
    property var store

    property string title: qsTr("Ziel-Player")
    property string hint: qsTr("Hier landet, was du in der Bibliothek abspielst.")
    // Nicht anbieten: beim Übergeben die Quelle selbst.
    property string excludePlayerId: ""
    // function(playerId). Ohne Angabe wird der Ziel-Player gesetzt.
    property var pickHandler: null

    allowedOrientations: defaultAllowedOrientations

    readonly property var choices: {
        if (!store) {
            return []
        }
        if (excludePlayerId.length === 0) {
            return store.players
        }
        var out = []
        for (var i = 0; i < store.players.length; i++) {
            if (store.players[i].player_id !== excludePlayerId) {
                out.push(store.players[i])
            }
        }
        return out
    }

    SilicaListView {
        anchors.fill: parent
        model: page.choices

        header: Column {
            width: page.width

            PageHeader { title: page.title }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                bottomPadding: Theme.paddingMedium
                text: page.hint
            }
        }

        ViewPlaceholder {
            enabled: page.choices.length === 0
            text: qsTr("Kein anderer Player")
        }

        delegate: ListItem {
            id: row
            contentHeight: Theme.itemSizeMedium
            opacity: Models.isAvailable(modelData) ? 1.0 : Theme.opacityLow

            // Das Häkchen ergibt nur beim Einstellen eines Ziels Sinn; beim
            // Übergeben gibt es kein "aktuelles" Ziel.
            readonly property bool current:
                page.pickHandler === null && store
                && store.targetPlayerId === modelData.player_id

            onClicked: {
                if (page.pickHandler) {
                    page.pickHandler(modelData.player_id)
                } else {
                    store.explicitTargetPlayerId = modelData.player_id
                }
                pageStack.pop()
            }

            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - checkMark.width - Theme.paddingMedium
                truncationMode: TruncationMode.Fade
                text: Models.playerName(modelData)
                color: (row.current || row.highlighted) ? Theme.highlightColor
                                                        : Theme.primaryColor
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
