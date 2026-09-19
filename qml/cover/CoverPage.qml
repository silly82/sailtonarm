import QtQuick 2.6
import Sailfish.Silica 1.0
import "../lib/MassModels.js" as Models

// Das Cover ist für eine Fernbedienung die eigentliche Bedienfläche: laufender
// Titel und Play/Pause, ohne die App zu öffnen. Gezeigt wird der Player, der
// gerade spielt (siehe PlayerStore.activePlayer) -- nicht zwingend der zuletzt
// geöffnete.
CoverBackground {
    id: cover

    property var mass
    property var store

    readonly property var player: store ? store.activePlayer : null
    readonly property var queue: (store && player) ? store.queueOf(player.player_id) : null
    readonly property var track: Models.nowPlaying(player, queue)
    readonly property bool playing: Models.isPlaying(player)

    // Cover-Art als Hintergrund. Stark abgedunkelt, damit die Schrift darüber
    // auf jedem Bild lesbar bleibt -- ein Albumcover kann beliebig hell sein.
    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        clip: true
        source: cover.track ? cover.track.imageUrl : ""
        opacity: status === Image.Ready ? 0.35 : 0
        Behavior on opacity { FadeAnimation {} }
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.paddingMedium
        }
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: cover.player ? Models.playerName(cover.player) : qsTr("Tonarm")
        }

        Label {
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.primaryColor
            text: {
                if (cover.track && cover.track.title.length > 0) {
                    return cover.track.title
                }
                if (!mass || !mass.configured) {
                    return qsTr("nicht eingerichtet")
                }
                if (!mass.ready) {
                    return qsTr("getrennt")
                }
                return qsTr("nichts läuft")
            }
        }

        Label {
            width: parent.width
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.highlightColor
            visible: cover.track && cover.track.artist.length > 0
            text: cover.track ? cover.track.artist : ""
        }
    }

    // Ohne laufende Warteschlange gäbe es nichts zu bedienen -- dann bleiben
    // die Cover-Actions weg, statt ins Leere zu tippen.
    CoverActionList {
        enabled: cover.player !== null && cover.queue !== null
                 && cover.queue.active === true && mass && mass.ready

        CoverAction {
            iconSource: cover.playing ? "image://theme/icon-cover-pause"
                                      : "image://theme/icon-cover-play"
            onTriggered: store.playPause(cover.player.player_id)
        }

        CoverAction {
            iconSource: "image://theme/icon-cover-next-song"
            onTriggered: store.next(cover.player.player_id)
        }
    }
}
