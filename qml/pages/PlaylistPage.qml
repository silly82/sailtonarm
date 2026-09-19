import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/MassApi.js" as MassApi

// Die Titel einer Playlist. Playlists können lang werden, deshalb seitenweise
// geladen -- `music/playlists/playlist_tracks` nimmt limit und offset.
Page {
    id: page

    property var mass
    property var store
    property var playlist

    allowedOrientations: Orientation.All

    property var tracks: []
    property bool loading: false
    property bool exhausted: false
    property string errorText: ""
    readonly property int pageSize: 60

    function loadMore() {
        if (loading || exhausted || !mass || !mass.ready || !playlist) {
            return
        }
        loading = true
        mass.sendCommand("music/playlists/playlist_tracks",
                         { item_id: playlist.item_id,
                           provider_instance_id_or_domain: playlist.provider,
                           limit: pageSize, offset: tracks.length },
                         function (err, result) {
            page.loading = false
            if (err) {
                page.errorText = err.hint
                page.exhausted = true
                return
            }
            var batch = result || []
            if (batch.length < page.pageSize) {
                page.exhausted = true
            }
            page.tracks = page.tracks.concat(batch)
        })
    }

    // shuffle wirkt serverseitig nur bei Optionen, die sofort losspielen
    // (play/replace) -- beim Anhängen wird es deshalb gar nicht erst
    // mitgeschickt.
    function playPlaylist(option, label, shuffle) {
        if (!store || store.targetPlayerId.length === 0) {
            pageToast.show(qsTr("Kein Player ausgewählt"), true)
            return
        }
        var target = store.playerById(store.targetPlayerId)
        var where = target ? Models.playerName(target) : ""
        store.playMedia(store.targetPlayerId, playlist.uri, option, function (err) {
            if (err) {
                pageToast.show(err.hint, true)
            } else {
                pageToast.show(label.arg(where))
            }
        }, shuffle)
    }

    function targetName() {
        if (!store) {
            return qsTr("keiner")
        }
        var p = store.playerById(store.targetPlayerId)
        return p ? Models.playerName(p) : qsTr("keiner")
    }

    Component.onCompleted: loadMore()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.tracks

        header: Column {
            width: listView.width
            spacing: Theme.paddingMedium
            bottomPadding: Theme.paddingMedium

            PageHeader {
                title: page.playlist ? page.playlist.name : ""
                description: page.playlist ? (page.playlist.owner || "") : ""
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width * 0.5, Theme.itemSizeHuge * 2)
                height: width
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status === Image.Ready
                source: {
                    var id = Models.imageProxyId(page.playlist)
                    return id.length > 0
                            ? MassApi.imageUrl(mass ? mass.baseUrl : "", id, 512) : ""
                }
            }

            // Flow statt Row: drei Knöpfe passen je nach Schriftgrösse und
            // Bildschirmbreite nicht zwingend nebeneinander.
            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Button {
                    text: qsTr("Abspielen")
                    enabled: store && store.targetPlayerId.length > 0
                    onClicked: page.playPlaylist("play", qsTr("Läuft auf %1"), false)
                }
                Button {
                    text: qsTr("Zufällig")
                    enabled: store && store.targetPlayerId.length > 0
                    onClicked: page.playPlaylist("play", qsTr("Zufällig auf %1"), true)
                }
                Button {
                    text: qsTr("Anhängen")
                    enabled: store && store.targetPlayerId.length > 0
                    onClicked: page.playPlaylist("add", qsTr("Angehängt auf %1"))
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
            enabled: page.tracks.length === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Fehler") : qsTr("Keine Titel")
            hintText: page.errorText
        }

        delegate: MediaListItem {
            mass: page.mass
            store: page.store
            toast: pageToast
            mediaItem: modelData
            subtitle: Models.artistNames(modelData)
            showImage: false

            Component.onCompleted: {
                if (index >= page.tracks.length - 10) {
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

    StatusToast { id: pageToast }
}
