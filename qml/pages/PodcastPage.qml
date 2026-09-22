import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/MassApi.js" as MassApi

// Die Folgen eines Podcasts.
//
// `music/podcasts/podcast_episodes` kennt **kein** limit/offset -- der Server
// liefert einen Async-Generator und schickt das Ergebnis in Paketen zu 500
// Einträgen mit `partial: true`. Das ist der erste Ort in dieser App, an dem
// die Stückelung aus `MassConnection` wirklich gebraucht wird statt nur
// vorsorglich da zu sein; seitenweises Laden gibt es hier nicht.
Page {
    id: page

    property var mass
    property var store
    property var podcast

    allowedOrientations: defaultAllowedOrientations

    property var episodes: []
    property bool loading: false
    property string errorText: ""

    function load() {
        if (!mass || !mass.ready || !podcast) {
            return
        }
        loading = true
        errorText = ""
        mass.sendCommand("music/podcasts/podcast_episodes",
                         { item_id: podcast.item_id,
                           provider_instance_id_or_domain: podcast.provider },
                         function (err, result) {
            page.loading = false
            if (err) {
                page.errorText = err.hint
                return
            }
            page.episodes = result || []
        })
    }

    function playPodcast(option, label) {
        if (!store || store.targetPlayerId.length === 0) {
            pageToast.show(qsTr("Kein Player ausgewählt"), true)
            return
        }
        var target = store.playerById(store.targetPlayerId)
        var where = target ? Models.playerName(target) : ""
        store.playMedia(store.targetPlayerId, podcast.uri, option, function (err) {
            if (err) {
                pageToast.show(err.hint, true)
            } else {
                pageToast.show(label.arg(where))
            }
        })
    }

    function targetName() {
        if (!store) {
            return qsTr("keiner")
        }
        var p = store.playerById(store.targetPlayerId)
        return p ? Models.playerName(p) : qsTr("keiner")
    }

    // Eine Folge trägt oft ein Erscheinungsdatum; ohne das bleibt die Dauer.
    function episodeSubtitle(ep) {
        var parts = []
        if (ep.position > 0) {
            parts.push(qsTr("Folge %1").arg(ep.position))
        }
        if (ep.duration > 0) {
            parts.push(Models.formatTime(ep.duration))
        }
        return parts.join(" · ")
    }

    Component.onCompleted: load()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.episodes

        header: Column {
            width: listView.width
            spacing: Theme.paddingMedium
            bottomPadding: Theme.paddingMedium

            PageHeader {
                title: page.podcast ? page.podcast.name : ""
                description: page.podcast ? (page.podcast.publisher || "") : ""
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width * 0.5, Theme.itemSizeHuge * 2)
                height: width
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status === Image.Ready
                source: {
                    var id = Models.imageProxyId(page.podcast)
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
                visible: page.episodes.length > 0
                text: qsTr("%1 Folgen").arg(page.episodes.length)
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium

                Button {
                    text: qsTr("Abspielen")
                    enabled: store && store.targetPlayerId.length > 0
                    onClicked: page.playPodcast("play", qsTr("Läuft auf %1"))
                }
                Button {
                    text: qsTr("Anhängen")
                    enabled: store && store.targetPlayerId.length > 0
                    onClicked: page.playPodcast("add", qsTr("Angehängt auf %1"))
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
            enabled: page.episodes.length === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Fehler") : qsTr("Keine Folgen")
            hintText: page.errorText
        }

        delegate: MediaListItem {
            mass: page.mass
            store: page.store
            toast: pageToast
            mediaItem: modelData
            // Jede Folge trüge dasselbe Podcast-Bild.
            showImage: false
            subtitle: page.episodeSubtitle(modelData)
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading && page.episodes.length === 0
        size: BusyIndicatorSize.Large
    }

    StatusToast { id: pageToast }
}
