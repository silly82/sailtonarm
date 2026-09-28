import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
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

    // Überall (Bibliothek und alle Anbieter) oder nur die Bibliothek. Bleibt
    // über Neustarts gemerkt -- wer nur in der eigenen Sammlung sucht, tut das
    // meistens immer.
    ConfigurationValue {
        id: libraryOnlySetting
        key: "/apps/harbour-tonarm/searchLibraryOnly"
        defaultValue: false
    }
    readonly property bool libraryOnly: libraryOnlySetting.value === true

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
        var requestedScope = libraryOnly
        var args = { search_query: query, limit: 12 }
        // `providers: ["library"]` statt des älteren `library_only`, das der
        // Server als veraltet führt.
        if (libraryOnly) {
            args.providers = ["library"]
        }
        mass.sendCommand("music/search", args, function (err, result) {
            page.loading = false
            if (requestedFor !== page.query || requestedScope !== page.libraryOnly) {
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

    function ownSubtitle(row) {
        if (row.type === "albums" || row.type === "tracks") {
            return Models.artistNames(row.item)
        }
        if (row.type === "podcasts" || row.type === "audiobooks") {
            // Nur der erste Autor, siehe Models.primaryAuthor().
            return Models.primaryAuthor(row.item) || (row.item.publisher || "")
        }
        return row.item.owner || ""
    }

    // Treffer ausserhalb der Bibliothek nennen vorn ihren Dienst ("Apple
    // Music · Interpret") -- sonst sieht ein Streaming-Treffer genauso aus
    // wie der gleichnamige in der eigenen Sammlung.
    function subtitleFor(row) {
        var own = ownSubtitle(row)
        var source = store ? store.sourceName(row.item) : ""
        if (source.length === 0) {
            return own
        }
        return own.length > 0 ? source + " · " + own : source
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

            ComboBox {
                width: parent.width
                label: qsTr("Suchen in")
                currentIndex: page.libraryOnly ? 1 : 0
                menu: ContextMenu {
                    MenuItem { text: qsTr("Überall") }
                    MenuItem { text: qsTr("Bibliothek") }
                }
                onCurrentIndexChanged: {
                    var only = currentIndex === 1
                    if (only !== page.libraryOnly) {
                        libraryOnlySetting.value = only
                        if (page.query.length > 0) {
                            debounce.stop()
                            page.search()
                        }
                    }
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
                      : (page.searched ? ""
                                       : (page.libraryOnly ? qsTr("Durchsucht die Bibliothek")
                                                           : qsTr("Durchsucht Bibliothek und Anbieter")))
        }

        delegate: Loader {
            width: listView.width
            sourceComponent: modelData.section !== undefined ? sectionHeader : mediaRow

            // In ein Item gepackt: der Loader zwingt seinem Inhalt die volle
            // Listenbreite auf, und die SectionHeader rückt sich selbst um den
            // Seitenrand ein -- zusammen ragte sie rechts hinaus und wurde
            // abgeschnitten ("Interpret" statt "Interpreten").
            Component {
                id: sectionHeader
                Item {
                    height: headerLabel.height
                    SectionHeader {
                        id: headerLabel
                        text: modelData.section
                    }
                }
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
