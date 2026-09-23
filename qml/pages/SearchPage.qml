import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/Navigate.js" as Nav

// Suche über alle Medientypen. `music/search` antwortet mit einem Objekt, das
// je Typ eine Liste trägt (artists, albums, tracks, playlists, radio, ...) --
// hier flach hintereinander mit Zwischenüberschriften gezeigt, damit man nicht
// erst einen Typ wählen muss, bevor man etwas sieht.
Page {
    id: page

    property var mass
    property var store

    allowedOrientations: defaultAllowedOrientations

    // Flache Liste aus { section: "..." } und { item: ..., type: "..." }
    property var rows: []
    property bool loading: false
    property bool searched: false
    property string errorText: ""
    property string query: ""

    // Reihenfolge und Beschriftung der Abschnitte. `radio` heisst im Ergebnis
    // wirklich so (Einzahl), anders als der Bibliotheks-Präfix `radios`.
    readonly property var sections: [
        { key: "artists", label: qsTr("Interpreten") },
        { key: "albums", label: qsTr("Alben") },
        { key: "tracks", label: qsTr("Titel") },
        { key: "playlists", label: qsTr("Playlists") },
        { key: "radio", label: qsTr("Radio") },
        { key: "podcasts", label: qsTr("Podcasts") },
        { key: "audiobooks", label: qsTr("Hörbücher") }
    ]

    function search() {
        if (!mass || !mass.ready || query.length === 0) {
            return
        }
        loading = true
        errorText = ""
        var requestedFor = query
        mass.sendCommand("music/search",
                         { search_query: query, limit: 12 },
                         function (err, result) {
            page.loading = false
            if (requestedFor !== page.query) {
                return
            }
            page.searched = true
            if (err) {
                page.errorText = err.hint
                page.rows = []
                return
            }
            page.rows = page.flatten(result || {})
        })
    }

    function flatten(result) {
        var out = []
        for (var i = 0; i < sections.length; i++) {
            var key = sections[i].key
            var list = result[key]
            if (!list || list.length === 0) {
                continue
            }
            out.push({ section: sections[i].label })
            for (var j = 0; j < list.length; j++) {
                out.push({ item: list[j], type: key })
            }
        }
        return out
    }

    function subtitleFor(row) {
        if (row.type === "albums" || row.type === "tracks") {
            return Models.artistNames(row.item)
        }
        if (row.type === "podcasts" || row.type === "audiobooks") {
            // Nur der erste Autor, siehe Models.primaryAuthor().
            return Models.primaryAuthor(row.item) || (row.item.publisher || "")
        }
        return row.item.owner || ""
    }

    function openRow(row) {
        var single = Nav.singular(row.type)
        var file = Nav.pageFor(single)
        if (file.length > 0) {
            pageStack.push(Qt.resolvedUrl(file),
                           Nav.propsFor(single, row.item, page.mass, page.store))
        }
    }

    function targetName() {
        if (!store) {
            return qsTr("keiner")
        }
        var p = store.playerById(store.targetPlayerId)
        return p ? Models.playerName(p) : qsTr("keiner")
    }

    Timer {
        id: debounce
        interval: 500
        onTriggered: page.search()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.rows

        header: Column {
            width: listView.width

            PageHeader { title: qsTr("Suche") }

            SearchField {
                width: parent.width
                placeholderText: qsTr("Interpret, Album, Titel …")
                inputMethodHints: Qt.ImhNoAutoUppercase
                focus: true
                onTextChanged: {
                    page.query = text.trim()
                    if (page.query.length === 0) {
                        page.rows = []
                        page.searched = false
                        debounce.stop()
                    } else {
                        debounce.restart()
                    }
                }
                EnterKey.iconSource: "image://theme/icon-m-search"
                EnterKey.onClicked: {
                    debounce.stop()
                    page.search()
                }
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Ziel-Player: %1").arg(page.targetName())
                onClicked: pageStack.push(Qt.resolvedUrl("PlayerPickerPage.qml"),
                                          { mass: page.mass, store: page.store })
            }
        }

        ViewPlaceholder {
            enabled: page.rows.length === 0 && !page.loading
            text: {
                if (page.errorText.length > 0) {
                    return qsTr("Fehler")
                }
                return page.searched ? qsTr("Nichts gefunden") : qsTr("Suche")
            }
            hintText: page.errorText.length > 0
                      ? page.errorText
                      : (page.searched ? "" : qsTr("Durchsucht Bibliothek und Anbieter"))
        }

        delegate: Loader {
            width: listView.width
            sourceComponent: modelData.section !== undefined ? sectionHeader : mediaRow

            Component {
                id: sectionHeader
                SectionHeader { text: modelData.section }
            }

            Component {
                id: mediaRow
                MediaListItem {
                    mass: page.mass
                    store: page.store
                    toast: pageToast
                    mediaItem: modelData.item
                    subtitle: page.subtitleFor(modelData)
                    showImage: modelData.type !== "tracks"
                    onActivated: page.openRow(modelData)
                }
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading
        size: BusyIndicatorSize.Large
    }

    StatusToast { id: pageToast }
}
