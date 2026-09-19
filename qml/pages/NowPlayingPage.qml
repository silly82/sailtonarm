import QtQuick 2.6
import Sailfish.Silica 1.0
import "../lib/MassModels.js" as Models

// Was auf einem Player gerade läuft, mit den Bedienelementen dazu. Alle
// Elemente hängen an den Fähigkeiten des Players (`supported_features`): auf
// der Zielanlage hat kein einziger Player eine Ein/Aus-Steuerung, ein
// Netzschalter wäre dort also totes Bedienelement.
Page {
    id: page

    property var mass
    property var store
    property string playerId: ""

    readonly property var player: store ? store.playerById(playerId) : null
    readonly property var queue: store ? store.queueOf(playerId) : null
    readonly property var track: Models.nowPlaying(player, queue)
    readonly property bool playing: Models.isPlaying(player)

    allowedOrientations: Orientation.All

    // Lokal weitergezählte Spielzeit. Der Server meldet sie nur gelegentlich;
    // dazwischen rechnet MassModels.elapsedSeconds() hoch.
    property real elapsed: 0

    function refreshElapsed() {
        elapsed = Models.elapsedSeconds(queue, player, Date.now())
        // Denselben Grund wie beim Lautstärkeregler: kein Binding, sondern
        // nachziehen, solange der Griff frei ist.
        if (!progressSlider.pressed) {
            progressSlider.value = Math.min(elapsed, progressSlider.maximumValue)
        }
    }

    // Lautstärke wird bewusst *nicht* an den Serverwert gebunden: käme während
    // des Ziehens ein player_updated herein, spränge der Griff unter dem Finger
    // weg. Stattdessen wird nachgezogen, solange niemand ihn hält.
    function syncVolume() {
        if (!volumeSlider.pressed && player && player.volume_level !== undefined
                && player.volume_level !== null) {
            volumeSlider.value = player.volume_level
        }
    }

    onPlayerChanged: syncVolume()
    onQueueChanged: refreshElapsed()
    Component.onCompleted: {
        syncVolume()
        refreshElapsed()
    }

    Timer {
        interval: 1000
        repeat: true
        running: page.status === PageStatus.Active && page.playing
        onTriggered: page.refreshElapsed()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Aktualisieren")
                enabled: mass && mass.ready
                onClicked: store.refresh()
            }
            MenuItem {
                text: qsTr("Warteschlange")
                enabled: mass && mass.ready && page.queue !== null
                onClicked: pageStack.push(Qt.resolvedUrl("QueuePage.qml"),
                                          { mass: page.mass, store: page.store,
                                            playerId: page.playerId })
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: Models.playerName(page.player)
                description: page.player && !Models.isAvailable(page.player)
                             ? qsTr("nicht verfügbar") : ""
            }

            // --- Cover ---------------------------------------------------
            Item {
                width: parent.width
                height: width * 0.62
                visible: page.track !== null

                Image {
                    id: cover
                    anchors.centerIn: parent
                    height: parent.height
                    width: height
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    // Der Server liefert in current_media.image_url bereits
                    // eine vollständige /imageproxy-Adresse samt Grössenangabe
                    // -- die wird unverändert übernommen, nichts gebaut.
                    source: page.track ? page.track.imageUrl : ""
                    visible: status === Image.Ready
                }

                // Platzhalter, solange (oder falls) kein Bild da ist -- ein
                // leeres Loch wäre schlechter als ein Notenzeichen.
                Rectangle {
                    anchors.centerIn: parent
                    height: parent.height
                    width: height
                    visible: !cover.visible
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.15)
                    radius: Theme.paddingSmall

                    Image {
                        anchors.centerIn: parent
                        source: "image://theme/icon-l-music"
                        opacity: 0.4
                    }
                }
            }

            // --- Titel ---------------------------------------------------
            Column {
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingSmall
                visible: page.track !== null

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.primaryColor
                    text: page.track ? page.track.title : ""
                }

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    color: Theme.highlightColor
                    visible: page.track && page.track.artist.length > 0
                    text: page.track ? page.track.artist : ""
                }

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    visible: page.track && page.track.album.length > 0
                    text: page.track ? page.track.album : ""
                }
            }

            // Nichts geladen: sagen statt eine leere Seite zeigen.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.secondaryHighlightColor
                visible: page.track === null
                text: qsTr("Auf diesem Player läuft gerade nichts.")
            }

            // --- Fortschritt ---------------------------------------------
            Slider {
                id: progressSlider
                width: parent.width
                visible: page.track !== null && page.track.duration > 0
                enabled: page.transportEnabled
                minimumValue: 0
                maximumValue: page.track && page.track.duration > 0
                              ? page.track.duration : 1
                valueText: Models.formatTime(value) + " / "
                           + Models.formatTime(page.track ? page.track.duration : 0)
                onReleased: store.seek(page.playerId, value)
            }

            // --- Transport -----------------------------------------------
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge

                IconButton {
                    icon.source: "image://theme/icon-m-previous"
                    enabled: page.transportEnabled
                    onClicked: store.previous(page.playerId)
                }

                IconButton {
                    icon.source: page.playing ? "image://theme/icon-l-pause"
                                              : "image://theme/icon-l-play"
                    enabled: page.transportEnabled
                    onClicked: store.playPause(page.playerId)
                }

                IconButton {
                    icon.source: "image://theme/icon-m-next"
                    enabled: page.transportEnabled
                    onClicked: store.next(page.playerId)
                }
            }

            // --- Lautstärke ----------------------------------------------
            Slider {
                id: volumeSlider
                width: parent.width
                visible: Models.hasFeature(page.player, Models.FEATURE_VOLUME_SET)
                enabled: page.controlsEnabled
                label: qsTr("Lautstärke")
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                valueText: Math.round(value) + " %"
                onReleased: store.setVolume(page.playerId, value)
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge

                IconButton {
                    visible: Models.hasFeature(page.player, Models.FEATURE_VOLUME_MUTE)
                    enabled: page.controlsEnabled
                    icon.source: (page.player && page.player.volume_muted)
                                 ? "image://theme/icon-m-speaker-mute"
                                 : "image://theme/icon-m-speaker"
                    onClicked: store.setMuted(page.playerId,
                                              !(page.player && page.player.volume_muted))
                }

            }

            // Auf der Zielanlage nie sichtbar (power_control ist bei allen acht
            // Playern "none"), andere Aufbauten haben aber echte Netzschalter.
            // Bewusst als Textknopf: das Silica-Theme hat gar kein
            // Ein/Aus-Symbol, und ein falsches Icon wäre schlechter als Worte.
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Models.hasPower(page.player)
                enabled: page.controlsEnabled
                text: (page.player && page.player.powered) ? qsTr("Ausschalten")
                                                           : qsTr("Einschalten")
                onClicked: store.setPower(page.playerId,
                                          !(page.player && page.player.powered))
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.errorColor
                visible: store && store.lastError.length > 0
                text: store ? store.lastError : ""
            }
        }

        VerticalScrollDecorator {}
    }

    readonly property bool controlsEnabled:
        mass && mass.ready && player !== null && Models.isAvailable(player)

    // Transport (Play/Pause, Weiter, Zurück, Springen) hängt *nicht* an den
    // Fähigkeiten des Players: diese Kommandos gehen an die Warteschlange, und
    // die fährt der Server selbst -- `player_queues/next` prüft im Quelltext
    // keine einzige PlayerFeature, sondern nur, ob die Queue aktiv ist.
    // (Auf der Zielanlage hat der benutzte Player weder "next_previous" noch
    // "seek" oder "pause" in supported_features, springt aber einwandfrei --
    // die ursprüngliche Verknüpfung hatte die Knöpfe grundlos gesperrt.)
    // PlayerFeature bleibt richtig für alles unter players/cmd/*: Lautstärke,
    // Stummschaltung, Netzschalter.
    readonly property bool transportEnabled:
        controlsEnabled && queue !== null && queue.active === true
}
