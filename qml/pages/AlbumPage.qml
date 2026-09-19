import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/MassApi.js" as MassApi

// Ein Album mit seinen Titeln. Die Titel kommen über
// `music/albums/album_tracks(item_id, provider_instance_id_or_domain)` --
// nicht über `get_collection`, das auf dem Zielserver mit einem internen
// Fehler antwortet (siehe KONZEPT.md Abschnitt 16).
Page {
    id: page

    property var mass
    property var store
    property var album

    allowedOrientations: Orientation.All

    property var tracks: []
    property bool loading: false
    property string errorText: ""

    function load() {
        if (!mass || !mass.ready || !album) {
            return
        }
        loading = true
        errorText = ""
        mass.sendCommand("music/albums/album_tracks",
                         { item_id: album.item_id,
                           provider_instance_id_or_domain: album.provider },
                         function (err, result) {
            page.loading = false
            if (err) {
                page.errorText = err.hint
                return
            }
            page.tracks = result || []
        })
    }

    function playAlbum(option, label) {
        if (!store || store.targetPlayerId.length === 0) {
            pageToast.show(qsTr("Kein Player ausgewählt"), true)
            return
        }
        var target = store.playerById(store.targetPlayerId)
        var where = target ? Models.playerName(target) : ""
        store.playMedia(store.targetPlayerId, album.uri, option, function (err) {
            if (err) {
                pageToast.show(err.hint, true)
            } else {
                pageToast.show(label.arg(where))
            }
        })
    }

    Component.onCompleted: load()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.tracks

        header: Column {
            width: listView.width
            spacing: Theme.paddingMedium
            bottomPadding: Theme.paddingMedium

            PageHeader {
                title: page.album ? page.album.name : ""
                description: page.album ? Models.artistNames(page.album) : ""
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width * 0.55, Theme.itemSizeHuge * 2)
                height: width
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status === Image.Ready
                source: {
                    var id = Models.imageProxyId(page.album)
                    return id.length > 0
                            ? MassApi.imageUrl(mass ? mass.baseUrl : "", id, 512) : ""
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: {
                    if (!page.album) {
                        return ""
                    }
                    var parts = []
                    if (page.album.year > 0) {
                        parts.push(page.album.year)
                    }
                    if (page.tracks.length > 0) {
                        parts.push(qsTr("%1 Titel").arg(page.tracks.length))
                    }
                    return parts.join(" · ")
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium

                Button {
                    text: qsTr("Abspielen")
                    enabled: store && store.targetPlayerId.length > 0
                    onClicked: page.playAlbum("play", qsTr("Läuft auf %1"))
                }
                Button {
                    text: qsTr("Anhängen")
                    enabled: store && store.targetPlayerId.length > 0
                    onClicked: page.playAlbum("add", qsTr("Angehängt auf %1"))
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
            // Jede Zeile trüge dasselbe Albumcover -- stattdessen die
            // Titelnummer, die hier tatsächlich etwas unterscheidet.
            showImage: false
            subtitle: {
                var parts = []
                if (modelData.track_number > 0) {
                    parts.push(qsTr("Nr. %1").arg(modelData.track_number))
                }
                if (modelData.duration > 0) {
                    parts.push(Models.formatTime(modelData.duration))
                }
                return parts.join(" · ")
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading && page.tracks.length === 0
        size: BusyIndicatorSize.Large
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
