import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/MassApi.js" as MassApi

// Ein Interpret: seine Titel, seine Alben und ähnliche Interpreten.
//
// Drei Abfragen, unabhängig voneinander -- was zuerst da ist, steht zuerst
// da. Gegen den echten Server vermessen (KONZEPT.md Abschnitt 31):
//
// - `music/artists/artist_tracks` liefert bei einem Streamingdienst dessen
//   Reihenfolge, also die bekanntesten Titel zuerst; bei einem
//   Bibliothekseintrag dagegen alle eigenen Titel alphabetisch. Deshalb
//   heisst der Abschnitt nur beim Dienst "Beliebte Titel", und es werden erst
//   zehn gezeigt.
// - `music/artists/similar_artists` kommt aus Last.fm bzw. dem Dienst,
//   gemischt aus Bibliothek und Dienst, mit Bild.
// - Die Alben wie bisher über `artist_albums`.
Page {
    id: page

    property var mass
    property var store
    property var artist

    allowedOrientations: defaultAllowedOrientations

    property var tracks: []
    property var albums: []
    property var similar: []
    property bool showAllTracks: false
    property int pendingLoads: 0
    property string errorText: ""

    readonly property bool fromLibrary: artist && artist.provider === "library"
    readonly property int trackPreview: 10

    // Flache Liste aus { section }, { more }, { item, kind } -- wie auf der
    // Suchseite, damit alles in einer einzigen ListView scrollt.
    readonly property var rows: {
        var out = []
        if (tracks.length > 0) {
            out.push({ section: fromLibrary ? qsTr("Titel") : qsTr("Beliebte Titel") })
            var shown = showAllTracks ? tracks : tracks.slice(0, trackPreview)
            for (var i = 0; i < shown.length; i++) {
                out.push({ item: shown[i], kind: "track" })
            }
            if (!showAllTracks && tracks.length > trackPreview) {
                out.push({ more: qsTr("Alle %1 Titel zeigen").arg(tracks.length) })
            }
        }
        if (albums.length > 0) {
            out.push({ section: qsTr("Alben") })
            for (i = 0; i < albums.length; i++) {
                out.push({ item: albums[i], kind: "album" })
            }
        }
        if (similar.length > 0) {
            out.push({ section: qsTr("Ähnliche Interpreten") })
            for (i = 0; i < similar.length; i++) {
                out.push({ item: similar[i], kind: "artist" })
            }
        }
        return out
    }

    function query(command, args, assign) {
        pendingLoads += 1
        mass.sendCommand(command, args, function (err, result) {
            page.pendingLoads -= 1
            if (err) {
                // Ein fehlender Abschnitt ist kein Grund, die Seite leer zu
                // lassen; gezeigt wird der Fehler nur, wenn gar nichts kam.
                page.errorText = err.hint
                return
            }
            assign(result || [])
        }, 60000)
    }

    function load() {
        if (!mass || !mass.ready || !artist) {
            return
        }
        errorText = ""
        var ref = { item_id: artist.item_id, provider_instance_id_or_domain: artist.provider }
        query("music/artists/artist_albums", ref, function (r) { page.albums = r })
        query("music/artists/artist_tracks", ref, function (r) { page.tracks = r })
        query("music/artists/similar_artists",
              { item_id: artist.item_id, provider_instance_id_or_domain: artist.provider, limit: 20 },
              function (r) { page.similar = r })
    }

    function targetName() {
        if (!store) {
            return qsTr("keiner")
        }
        var p = store.playerById(store.targetPlayerId)
        return p ? Models.playerName(p) : qsTr("keiner")
    }

    function subtitleFor(row) {
        if (row.kind === "album") {
            return row.item.year > 0 ? String(row.item.year) : ""
        }
        if (row.kind === "track") {
            var album = row.item.album ? row.item.album.name : ""
            var dur = row.item.duration > 0 ? Models.formatTime(row.item.duration) : ""
            return album.length > 0 && dur.length > 0 ? album + " · " + dur : (album || dur)
        }
        // Ähnliche Interpreten: sagen, ob er in der eigenen Sammlung steht.
        return store ? store.sourceName(row.item) : ""
    }

    function openRow(row) {
        if (row.kind === "album") {
            pageStack.push(Qt.resolvedUrl("AlbumPage.qml"),
                           { mass: page.mass, store: page.store, album: row.item })
        } else if (row.kind === "artist") {
            pageStack.push(Qt.resolvedUrl("ArtistPage.qml"),
                           { mass: page.mass, store: page.store, artist: row.item })
        }
    }

    function play(option, label) {
        if (!store || store.targetPlayerId.length === 0) {
            pageToast.show(qsTr("Kein Player ausgewählt"), true)
            return
        }
        var where = targetName()
        if (option === "similar") {
            store.playSimilar(store.targetPlayerId, artist.uri, function (err) {
                pageToast.show(err ? err.hint : qsTr("Ähnliches läuft auf %1").arg(where), !!err)
            })
            return
        }
        store.playMedia(store.targetPlayerId, artist.uri, option, function (err) {
            pageToast.show(err ? err.hint : label.arg(where), !!err)
        })
    }

    Component.onCompleted: load()

    Connections {
        target: mass
        onAuthenticated: page.load()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.rows

        header: Column {
            width: listView.width
            spacing: Theme.paddingMedium
            bottomPadding: Theme.paddingMedium

            PageHeader {
                title: page.artist ? page.artist.name : ""
                description: page.albums.length > 0
                             ? qsTr("%1 Alben").arg(page.albums.length) : ""
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width * 0.45, Theme.itemSizeHuge * 1.5)
                height: width
                fillMode: Image.PreserveAspectCrop
                clip: true
                asynchronous: true
                visible: status === Image.Ready
                source: {
                    var id = Models.imageProxyId(page.artist)
                    return id.length > 0
                            ? MassApi.imageUrl(mass ? mass.activeBaseUrl : "", id, 512) : ""
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium

                Button {
                    text: qsTr("Abspielen")
                    enabled: store && store.targetPlayerId.length > 0
                    onClicked: page.play("replace", qsTr("Läuft auf %1"))
                }
                Button {
                    text: qsTr("Ähnliches")
                    enabled: store && store.targetPlayerId.length > 0
                    onClicked: page.play("similar")
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
            enabled: page.rows.length === 0 && page.pendingLoads === 0
            text: page.errorText.length > 0 ? qsTr("Fehler") : qsTr("Nichts gefunden")
            hintText: page.errorText.length > 0
                      ? page.errorText
                      : qsTr("Dieser Anbieter listet für den Interpreten weder Titel noch Alben")
        }

        delegate: Loader {
            width: listView.width
            sourceComponent: modelData.section !== undefined ? sectionHeader
                           : (modelData.more !== undefined ? moreRow : mediaRow)

            // In ein Item gepackt, sonst ragt die SectionHeader rechts hinaus
            // (siehe SearchPage).
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
                id: moreRow
                BackgroundItem {
                    height: Theme.itemSizeSmall
                    onClicked: page.showAllTracks = true
                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.more
                        color: parent.highlighted ? Theme.highlightColor : Theme.secondaryHighlightColor
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
                    // Titel tragen das Cover ihres Albums, und bei zehn
                    // verschiedenen Alben ist das hier sogar hilfreich.
                    showImage: true
                    onActivated: page.openRow(modelData)
                }
            }
        }

        // Die Abfragen brauchen unterschiedlich lang (die Titel eines
        // Streaming-Interpreten auf dem echten Server über 10 s). Steht schon
        // etwas da, sagt ein kleiner Hinweis unten, dass noch mehr kommt.
        footer: Item {
            width: listView.width
            height: page.pendingLoads > 0 && page.rows.length > 0 ? Theme.itemSizeMedium : 0
            visible: height > 0

            Row {
                anchors.centerIn: parent
                spacing: Theme.paddingMedium
                BusyIndicator {
                    size: BusyIndicatorSize.ExtraSmall
                    running: parent.parent.visible
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                    text: qsTr("Lade weitere …")
                }
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.pendingLoads > 0 && page.rows.length === 0
        size: BusyIndicatorSize.Large
    }

    StatusToast { id: pageToast }
}
