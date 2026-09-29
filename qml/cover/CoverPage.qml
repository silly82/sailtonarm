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
    readonly property var track: Models.nowPlaying(player, queue, mass ? mass.activeBaseUrl : "")
    readonly property bool playing: Models.isPlaying(player)
    // Hörbücher und Podcast-Folgen: statt "nächster Titel" +30 s, und das
    // Kapitel steht mit auf dem Cover.
    readonly property bool spoken: track !== null && track.isSpoken

    property real elapsed: 0
    readonly property var chapter: spoken ? Models.currentChapter(track.chapters, elapsed) : null

    // Nur solange das Cover sichtbar ist, und selten -- das Kapitel wechselt
    // alle paar Minuten.
    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: cover.spoken && cover.status === Cover.Active
        onTriggered: cover.elapsed = Models.elapsedSeconds(cover.queue, cover.player, Date.now())
    }

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

        Label {
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            visible: cover.chapter !== null
            text: cover.chapter ? cover.chapter.name : ""
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

        // Bei Gesprochenem +30 s statt "nächster Titel": ein Hörbuch hat
        // keinen nächsten Titel, und ein Kapitelsprung ist vom Cover aus zu
        // grob.
        CoverAction {
            iconSource: cover.spoken ? "image://theme/icon-cover-next"
                                     : "image://theme/icon-cover-next-song"
            onTriggered: {
                if (cover.spoken) {
                    store.skip(cover.player.player_id, 30)
                } else {
                    store.nextOrChapter(cover.player.player_id)
                }
            }
        }
    }
}
