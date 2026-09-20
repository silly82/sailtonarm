import QtQuick 2.6
import Sailfish.Silica 1.0
import "../lib/MassModels.js" as Models

// Einstieg in die Bibliothek: eine Handvoll Medientypen mit ihrer Anzahl.
// Die Zahlen kommen von `music/<typ>/count` und sind billig -- sie ersparen
// den Griff in eine Liste, die sich als leer herausstellt.
Page {
    id: page

    property var mass
    property var store

    allowedOrientations: defaultAllowedOrientations

    property var counts: ({})

    function loadCounts() {
        if (!mass || !mass.ready) {
            return
        }
        var types = ["artists", "albums", "tracks", "playlists", "radios"]
        for (var i = 0; i < types.length; i++) {
            loadCount(types[i])
        }
    }

    function loadCount(type) {
        mass.sendCommand("music/" + type + "/count", {}, function (err, result) {
            if (err || typeof result !== "number") {
                return
            }
            // Neu zuweisen statt den Schlüssel zu setzen: eine Änderung
            // *innerhalb* eines JS-Objekts bemerkt QML nicht.
            var next = {}
            for (var key in page.counts) {
                next[key] = page.counts[key]
            }
            next[type] = result
            page.counts = next
        })
    }

    function countText(type) {
        return (page.counts[type] !== undefined)
                ? qsTr("%1 Einträge").arg(page.counts[type]) : ""
    }

    function open(type, title) {
        pageStack.push(Qt.resolvedUrl("MediaListPage.qml"),
                       { mass: page.mass, store: page.store,
                         mediaType: type, title: title })
    }

    Component.onCompleted: loadCounts()

    Connections {
        target: mass
        onAuthenticated: page.loadCounts()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Suchen")
                enabled: mass && mass.ready
                onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"),
                                          { mass: page.mass, store: page.store })
            }
        }

        Column {
            id: column
            width: page.width

            PageHeader { title: qsTr("Bibliothek") }

            Repeater {
                model: [
                    { type: "artists", label: qsTr("Interpreten") },
                    { type: "albums", label: qsTr("Alben") },
                    { type: "tracks", label: qsTr("Titel") },
                    { type: "playlists", label: qsTr("Playlists") },
                    { type: "radios", label: qsTr("Radio") }
                ]

                ListItem {
                    width: page.width
                    contentHeight: Theme.itemSizeMedium
                    onClicked: page.open(modelData.type, modelData.label)

                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: highlighted ? Theme.highlightColor : Theme.primaryColor
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        text: page.countText(modelData.type)
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                visible: mass && !mass.ready
                text: qsTr("Keine Verbindung zum Server.")
            }
        }

        VerticalScrollDecorator {}
    }
}
