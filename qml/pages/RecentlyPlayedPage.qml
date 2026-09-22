import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/Navigate.js" as Nav

// Was zuletzt lief -- über alle Medientypen hinweg, neueste zuerst.
//
// Anders als die Bibliothekslisten liefert `music/recently_played_items` keine
// vollen Medienobjekte, sondern schlanke Verweise (ItemMapping): kein
// `metadata`, dafür ein einzelnes `image`, und `media_type` wechselt von Zeile
// zu Zeile. Beides ist berücksichtigt -- `Models.imageProxyId()` kennt jetzt
// beide Formen, und wohin ein Tipper führt, entscheidet `Navigate.js` je
// Zeile statt einmal für die ganze Seite.
Page {
    id: page

    property var mass
    property var store

    allowedOrientations: defaultAllowedOrientations

    property var items: []
    property bool loading: false
    property string errorText: ""

    function load() {
        if (!mass || !mass.ready) {
            return
        }
        loading = true
        errorText = ""
        mass.sendCommand("music/recently_played_items", { limit: 50 },
                         function (err, result) {
            page.loading = false
            if (err) {
                page.errorText = err.hint
                return
            }
            page.items = result || []
        })
    }

    // Statt Interpret oder Jahr -- die gibt es in einem ItemMapping nicht --
    // sagt die Unterzeile, um was für ein Ding es sich handelt. In einer
    // gemischten Liste ist genau das die nützliche Information.
    function typeLabel(mediaType) {
        switch (mediaType) {
        case "artist": return qsTr("Interpret")
        case "album": return qsTr("Album")
        case "track": return qsTr("Titel")
        case "playlist": return qsTr("Playlist")
        case "radio": return qsTr("Radio")
        case "podcast": return qsTr("Podcast")
        case "podcast_episode": return qsTr("Podcast-Folge")
        case "audiobook": return qsTr("Hörbuch")
        }
        return ""
    }

    function open(item) {
        var file = Nav.pageFor(item.media_type)
        if (file.length > 0) {
            pageStack.push(Qt.resolvedUrl(file),
                           Nav.propsFor(item.media_type, item, page.mass, page.store))
        }
    }

    function targetName() {
        if (!store) {
            return qsTr("keiner")
        }
        var p = store.playerById(store.targetPlayerId)
        return p ? Models.playerName(p) : qsTr("keiner")
    }

    Component.onCompleted: load()

    Connections {
        target: mass
        onAuthenticated: page.load()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.items

        header: PageHeader { title: qsTr("Zuletzt gehört") }

        PullDownMenu {
            MenuItem {
                text: qsTr("Ziel-Player: %1").arg(page.targetName())
                onClicked: pageStack.push(Qt.resolvedUrl("PlayerPickerPage.qml"),
                                          { mass: page.mass, store: page.store })
            }
            MenuItem {
                text: qsTr("Neu laden")
                enabled: mass && mass.ready
                onClicked: page.load()
            }
        }

        ViewPlaceholder {
            enabled: page.items.length === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Fehler") : qsTr("Noch nichts gehört")
            hintText: page.errorText.length > 0
                      ? page.errorText
                      : qsTr("Hier steht, was zuletzt gelaufen ist")
        }

        delegate: MediaListItem {
            mass: page.mass
            store: page.store
            toast: pageToast
            mediaItem: modelData
            subtitle: page.typeLabel(modelData.media_type)
            onActivated: page.open(modelData)
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading && page.items.length === 0
        size: BusyIndicatorSize.Large
    }

    StatusToast { id: pageToast }
}
