import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/MassApi.js" as MassApi

// Eine Podcast-Folge im Einzelnen: Titel, Datum, Dauer, Fortschritt und die
// Beschreibung aus dem Feed. Die Folgenliste zeigt davon nur eine Zeile.
Page {
    id: page

    property var mass
    property var store
    property var episode
    property var podcast

    allowedOrientations: defaultAllowedOrientations

    readonly property real progress: Models.listenProgress(episode)
    readonly property bool played: Models.isFullyPlayed(episode)
    readonly property var released: Models.releaseDate(episode)
    readonly property string description: {
        var md = episode && episode.metadata ? episode.metadata : {}
        return Models.plainText(md.description || "")
    }

    function targetName() {
        var p = store ? store.playerById(store.targetPlayerId) : null
        return p ? Models.playerName(p) : qsTr("keiner")
    }

    function play() {
        if (!store || store.targetPlayerId.length === 0) {
            pageToast.show(qsTr("Kein Player ausgewählt"), true)
            return
        }
        var where = targetName()
        store.playMedia(store.targetPlayerId, episode.uri, "play", function (err) {
            pageToast.show(err ? err.hint : qsTr("Läuft auf %1").arg(where), !!err)
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Ziel-Player: %1").arg(page.targetName())
                onClicked: pageStack.push(Qt.resolvedUrl("PlayerPickerPage.qml"),
                                          { mass: page.mass, store: page.store })
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: page.podcast ? page.podcast.name : ""
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width * 0.4, Theme.itemSizeHuge * 1.3)
                height: width
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status === Image.Ready
                source: {
                    var id = Models.imageProxyId(page.episode) || Models.imageProxyId(page.podcast)
                    return id.length > 0
                            ? MassApi.imageUrl(mass ? mass.activeBaseUrl : "", id, 512) : ""
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                text: page.episode ? page.episode.name : ""
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: {
                    var parts = []
                    if (page.released) {
                        parts.push(Qt.formatDate(page.released, Qt.DefaultLocaleLongDate))
                    }
                    if (page.episode && page.episode.duration > 0) {
                        parts.push(Models.formatTime(page.episode.duration))
                    }
                    if (page.played) {
                        parts.push(qsTr("gehört"))
                    } else if (page.progress >= 0) {
                        parts.push(qsTr("%1 % gehört").arg(Math.round(page.progress * 100)))
                    }
                    return parts.join(" · ")
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.progress >= 0 ? qsTr("Weiterhören") : qsTr("Abspielen")
                enabled: store && store.targetPlayerId.length > 0
                onClicked: page.play()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primaryColor
                visible: text.length > 0
                text: page.description
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                visible: page.description.length === 0
                text: qsTr("Der Feed enthält keine Beschreibung für diese Folge.")
            }
        }

        VerticalScrollDecorator {}
    }

    StatusToast { id: pageToast }
}
