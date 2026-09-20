import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/MassApi.js" as MassApi

// Die Alben eines Interpreten. Für Bibliothekseinträge liefert der Server die
// Alben aus der Bibliothek; für Einträge eines Anbieters dessen Auflistung,
// die auch leer sein kann.
Page {
    id: page

    property var mass
    property var store
    property var artist

    allowedOrientations: defaultAllowedOrientations

    property var albums: []
    property bool loading: false
    property string errorText: ""

    function load() {
        if (!mass || !mass.ready || !artist) {
            return
        }
        loading = true
        errorText = ""
        mass.sendCommand("music/artists/artist_albums",
                         { item_id: artist.item_id,
                           provider_instance_id_or_domain: artist.provider },
                         function (err, result) {
            page.loading = false
            if (err) {
                page.errorText = err.hint
                return
            }
            page.albums = result || []
        })
    }

    function targetName() {
        if (!store) {
            return qsTr("keiner")
        }
        var p = store.playerById(store.targetPlayerId)
        return p ? Models.playerName(p) : qsTr("keiner")
    }

    Component.onCompleted: load()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.albums

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
                            ? MassApi.imageUrl(mass ? mass.baseUrl : "", id, 512) : ""
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
            enabled: page.albums.length === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Fehler") : qsTr("Keine Alben")
            hintText: page.errorText.length > 0
                      ? page.errorText
                      : qsTr("Dieser Anbieter listet für den Interpreten keine Alben")
        }

        delegate: MediaListItem {
            mass: page.mass
            store: page.store
            toast: pageToast
            mediaItem: modelData
            subtitle: modelData.year > 0 ? String(modelData.year) : ""
            onActivated: pageStack.push(Qt.resolvedUrl("AlbumPage.qml"),
                                        { mass: page.mass, store: page.store,
                                          album: modelData })
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading && page.albums.length === 0
        size: BusyIndicatorSize.Large
    }

    StatusToast { id: pageToast }
}
