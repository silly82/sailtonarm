import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models

// Eine Bibliotheksliste für genau einen Medientyp. Dieselbe Seite bedient
// Interpreten, Alben, Titel, Playlists und Radio -- der Unterschied sind der
// Kommandopräfix, die Unterzeile und wohin ein Tipper führt.
//
// Seitenweise geladen. Bei knapp 3000 Alben ist das keine Vorsorge: alles auf
// einmal zu holen hiesse, dreitausend Objekte zu parsen und dreitausend
// Delegates vorzuhalten, bevor die erste Zeile steht.
Page {
    id: page

    property var mass
    property var store
    // "artists" | "albums" | "tracks" | "playlists" | "radios"
    property string mediaType: "albums"
    property string title: ""

    allowedOrientations: defaultAllowedOrientations

    property var items: []
    property int totalCount: -1
    property bool loading: false
    property bool exhausted: false
    property string errorText: ""
    property string searchText: ""
    // Nur Favoriten zeigen. Läuft serverseitig über den `favorite`-Filter von
    // library_items, nicht über Nachfiltern -- bei 13847 Titeln wäre das
    // sonst sinnlos, weil immer nur die geladene Seite gefiltert würde.
    property bool favoritesOnly: false

    readonly property int pageSize: 60

    function reload() {
        items = []
        exhausted = false
        errorText = ""
        totalCount = -1
        loadCount()
        loadMore()
    }

    function loadCount() {
        if (!mass || !mass.ready) {
            return
        }
        // Bei aktiver Suche sagt die Gesamtzahl der Bibliothek nichts über das
        // Ergebnis aus -- dann gar keine Zahl zeigen statt einer falschen.
        if (searchText.length > 0 || favoritesOnly) {
            totalCount = -1
            return
        }
        mass.sendCommand("music/" + mediaType + "/count", {}, function (err, result) {
            if (!err && typeof result === "number") {
                page.totalCount = result
            }
        })
    }

    function loadMore() {
        if (loading || exhausted || !mass || !mass.ready) {
            return
        }
        loading = true
        var args = { limit: pageSize, offset: items.length }
        if (searchText.length > 0) {
            args.search = searchText
        }
        if (favoritesOnly) {
            args.favorite = true
        }
        var requestedFor = searchText
        mass.sendCommand("music/" + mediaType + "/library_items", args,
                         function (err, result) {
            page.loading = false
            // Während die Antwort unterwegs war, kann der Suchbegriff sich
            // geändert haben -- dann gehört dieses Ergebnis nicht mehr hierher.
            if (requestedFor !== page.searchText) {
                return
            }
            if (err) {
                page.errorText = err.hint
                return
            }
            var batch = result || []
            if (batch.length < page.pageSize) {
                page.exhausted = true
            }
            page.items = page.items.concat(batch)
        })
    }

    function subtitleFor(item) {
        if (mediaType === "albums") {
            var artists = Models.artistNames(item)
            if (item.year > 0) {
                return artists.length > 0 ? (artists + " · " + item.year)
                                          : String(item.year)
            }
            return artists
        }
        if (mediaType === "tracks") {
            return Models.artistNames(item)
        }
        if (mediaType === "playlists" || mediaType === "radios") {
            return item.owner || ""
        }
        return ""
    }

    function openItem(item) {
        if (mediaType === "albums") {
            pageStack.push(Qt.resolvedUrl("AlbumPage.qml"),
                           { mass: page.mass, store: page.store, album: item })
        } else if (mediaType === "artists") {
            pageStack.push(Qt.resolvedUrl("ArtistPage.qml"),
                           { mass: page.mass, store: page.store, artist: item })
        } else if (mediaType === "playlists") {
            pageStack.push(Qt.resolvedUrl("PlaylistPage.qml"),
                           { mass: page.mass, store: page.store, playlist: item })
        }
        // Titel und Radio haben keine Unterseite -- die spielt man über das
        // Kontextmenü, ein Tipper tut hier nichts.
    }

    Component.onCompleted: reload()

    Connections {
        target: mass
        onAuthenticated: page.reload()
    }

    // Nicht bei jedem Tastendruck eine Abfrage losschicken.
    Timer {
        id: searchDebounce
        interval: 450
        onTriggered: page.reload()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.items

        header: Column {
            width: listView.width

            PageHeader {
                title: page.title
                description: {
                    if (page.favoritesOnly) {
                        return qsTr("nur Favoriten")
                    }
                    return page.totalCount >= 0
                            ? qsTr("%1 Einträge").arg(page.totalCount) : ""
                }
            }

            SearchField {
                width: parent.width
                placeholderText: qsTr("In der Bibliothek suchen")
                inputMethodHints: Qt.ImhNoAutoUppercase
                onTextChanged: {
                    page.searchText = text.trim()
                    searchDebounce.restart()
                }
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Ziel-Player: %1").arg(targetName())
                onClicked: pageStack.push(Qt.resolvedUrl("PlayerPickerPage.qml"),
                                          { mass: page.mass, store: page.store })
            }
            MenuItem {
                text: page.favoritesOnly ? qsTr("Alle zeigen") : qsTr("Nur Favoriten")
                onClicked: {
                    page.favoritesOnly = !page.favoritesOnly
                    page.reload()
                }
            }
            MenuItem {
                text: qsTr("Neu laden")
                enabled: mass && mass.ready
                onClicked: page.reload()
            }
        }

        ViewPlaceholder {
            enabled: page.items.length === 0 && !page.loading
            text: {
                if (page.errorText.length > 0) {
                    return qsTr("Fehler")
                }
                if (page.searchText.length > 0) {
                    return qsTr("Nichts gefunden")
                }
                return page.favoritesOnly ? qsTr("Keine Favoriten")
                                          : qsTr("Nichts in der Bibliothek")
            }
            hintText: page.errorText.length > 0 ? page.errorText : ""
        }

        delegate: MediaListItem {
            mass: page.mass
            store: page.store
            toast: pageToast
            mediaItem: modelData
            subtitle: page.subtitleFor(modelData)
            showImage: page.mediaType !== "tracks"
            onActivated: page.openItem(modelData)

            // Nachladen, sobald das Ende der geladenen Menge in Sicht kommt.
            Component.onCompleted: {
                if (index >= page.items.length - 10) {
                    page.loadMore()
                }
            }
        }

        footer: Item {
            width: listView.width
            height: page.loading ? Theme.itemSizeMedium : 0

            BusyIndicator {
                anchors.centerIn: parent
                running: page.loading
                size: BusyIndicatorSize.Medium
            }
        }

        VerticalScrollDecorator {}
    }

    function targetName() {
        if (!store) {
            return qsTr("keiner")
        }
        var p = store.playerById(store.targetPlayerId)
        return p ? Models.playerName(p) : qsTr("keiner")
    }

    StatusToast { id: pageToast }
}
