import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../components"
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
    readonly property var track: Models.nowPlaying(player, queue, mass ? mass.activeBaseUrl : "")
    readonly property bool playing: Models.isPlaying(player)

    allowedOrientations: defaultAllowedOrientations

    // Lokal weitergezählte Spielzeit. Der Server meldet sie nur gelegentlich;
    // dazwischen rechnet MassModels.elapsedSeconds() hoch.
    property real elapsed: 0

    // Adresse des laufenden Musiktitels, für "Ähnliches abspielen"; leer bei
    // Radio, Hörbüchern und Podcasts.
    readonly property string currentUri: {
        var item = queue ? queue.current_item : null
        var media = item ? item.media_item : null
        return (media && media.media_type === "track" && media.uri) ? media.uri : ""
    }

    // Einschlaftimer: Restzeit, sekündlich nachgezogen solange einer läuft.
    property real sleepNow: Date.now()
    readonly property real sleepRemaining: Models.sleepRemaining(player, sleepNow)

    Timer {
        interval: 1000
        repeat: true
        running: page.status === PageStatus.Active && page.sleepRemaining > 0
        onTriggered: page.sleepNow = Date.now()
    }

    // Hörbuch mit Kapiteln: das Kapitel, in dem die Position liegt.
    readonly property var chapter: (track && track.isSpoken)
                                   ? Models.currentChapter(track.chapters, elapsed) : null

    // Tempo gibt es nur, wo die Queue `playback_speed` meldet.
    readonly property bool hasSpeed: track !== null && track.isSpoken
                                     && queue !== null && typeof queue.playback_speed === "number"
    readonly property var speeds: [0.75, 1, 1.25, 1.5, 1.75, 2]

    function speedLabel(speed) {
        return String(speed).replace(".", Qt.locale().decimalPoint) + "×"
    }

    // Wie beim Lautstärkeregler kein Binding: die Auswahl nachziehen, wenn
    // der Server ein neues Tempo meldet.
    function syncSpeed() {
        if (!hasSpeed) {
            return
        }
        var best = 0
        for (var i = 1; i < speeds.length; i++) {
            if (Math.abs(speeds[i] - queue.playback_speed)
                    < Math.abs(speeds[best] - queue.playback_speed)) {
                best = i
            }
        }
        speedBox.currentIndex = best
    }

    function refreshElapsed() {
        elapsed = Models.elapsedSeconds(queue, player, Date.now())
        // Denselben Grund wie beim Lautstärkeregler: kein Binding, sondern
        // nachziehen, solange der Griff frei ist.
        if (!progressSlider.pressed) {
            progressSlider.value = Math.min(elapsed, progressSlider.maximumValue)
        }
    }

    onQueueChanged: {
        refreshElapsed()
        syncSpeed()
    }
    onHasSpeedChanged: syncSpeed()
    // Zurück von einer Unterseite (Songtext, Warteschlange): der Takt lief
    // dort nicht, also sofort nachziehen statt eine Sekunde lang die alte
    // Position zu zeigen.
    onStatusChanged: if (status === PageStatus.Activating) refreshElapsed()

    Component.onCompleted: {
        refreshPalette()
        refreshElapsed()
        syncSpeed()
    }

    Timer {
        interval: 1000
        repeat: true
        running: page.status === PageStatus.Active && page.playing
        onTriggered: page.refreshElapsed()
    }

    // --- Farben aus dem Cover ---------------------------------------------
    // Der Server rechnet aus dem Cover eine Palette aus
    // (metadata/get_image_palette, KONZEPT.md Abschnitt 34). Hinter dem Cover
    // läuft ein Verlauf in dessen Hintergrundfarbe aus -- zurückhaltend, damit
    // Silica-Schrift und -Bedienelemente überall lesbar bleiben. Abschaltbar
    // in den Einstellungen.
    ConfigurationValue {
        id: coverColorsSetting
        key: "/apps/harbour-tonarm/coverColors"
        defaultValue: true
    }

    // Easter Egg (KONZEPT.md Abschnitt 35): siebenmal aufs Cover tippen, und
    // es wird zur Schallplatte mit Tonarm. Siebenmal mehr, und es ist wieder
    // das Cover. Die Wahl bleibt gespeichert.
    ConfigurationValue {
        id: vinylSetting
        key: "/apps/harbour-tonarm/vinylMode"
        defaultValue: false
    }

    property int coverTaps: 0

    function coverTapped() {
        coverTaps++
        tapReset.restart()
        if (coverTaps < 7) {
            return
        }
        coverTaps = 0
        vinylSetting.value = !vinylSetting.value
        pageToast.show(vinylSetting.value ? qsTr("Aufgelegt. 33⅓ Umdrehungen pro Minute.")
                                          : qsTr("Zurück in die Hülle."), false)
    }

    Timer {
        id: tapReset
        interval: 1500
        onTriggered: page.coverTaps = 0
    }

    // Die Kennung steckt in der Bildadresse: .../imageproxy/<proxy_id>?size=...
    readonly property string imageProxyId: {
        var url = track ? String(track.imageUrl) : ""
        var m = /\/imageproxy\/([^?\/]+)/.exec(url)
        if (m) {
            return decodeURIComponent(m[1])
        }
        // Demomodus: die Cover sind Dateien, die Kennung ist die Adresse.
        return /^file:/.test(url) ? url : ""
    }
    property color tint: "transparent"

    function applyPalette(pal) {
        var rgb = null
        if (pal) {
            // Auf dunklem Silica-Thema die dunkle Hintergrundfarbe, auf hellem
            // die helle -- sonst sähe der Verlauf wie ein Fleck aus.
            rgb = Theme.colorScheme === Theme.LightOnDark ? pal.background_dark : pal.background_light
            if (!rgb) {
                rgb = pal.primary
            }
        }
        tint = rgb ? Qt.rgba(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 0.85) : "transparent"
    }

    onImageProxyIdChanged: refreshPalette()

    function refreshPalette() {
        if (coverColorsSetting.value !== true || imageProxyId.length === 0 || !store) {
            tint = "transparent"
            return
        }
        var id = imageProxyId
        store.palette(id, function (pal) {
            if (id === page.imageProxyId) {
                page.applyPalette(pal)
            }
        })
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: parent.height * 0.75
        visible: page.tint.a > 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: page.tint }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    Behavior on tint { ColorAnimation { duration: 400 } }

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
                text: page.sleepRemaining > 0
                      ? qsTr("Einschlaftimer: noch %1 Min.").arg(Math.ceil(page.sleepRemaining / 60))
                      : qsTr("Einschlaftimer")
                enabled: mass && mass.ready && page.player !== null
                onClicked: pageStack.push(Qt.resolvedUrl("SleepTimerPage.qml"),
                                          { mass: page.mass, store: page.store,
                                            playerId: page.playerId })
            }
            // Aus dem, was gerade läuft, eine endlose Folge Ähnlicher machen --
            // auf diesem Player, die Warteschlange wird ersetzt.
            MenuItem {
                text: qsTr("Ähnliches abspielen")
                visible: page.currentUri.length > 0
                enabled: mass && mass.ready
                onClicked: store.playSimilar(page.playerId, page.currentUri, function (err) {
                    if (err) {
                        pageToast.show(err.hint, true)
                    } else {
                        pageToast.show(qsTr("Ähnliches läuft"))
                    }
                })
            }
            MenuItem {
                text: qsTr("Zur Playlist hinzufügen …")
                visible: page.currentUri.length > 0
                enabled: mass && mass.ready
                onClicked: {
                    var uri = page.currentUri
                    var name = page.track ? page.track.title : ""
                    var t = pageToast
                    var playerStore = page.store
                    pageStack.push(Qt.resolvedUrl("PlaylistPickerPage.qml"), {
                        mass: page.mass, store: page.store, itemName: name,
                        pickHandler: function (playlist) {
                            if (playlist.error) {
                                t.show(playlist.error.hint, true)
                                return
                            }
                            playerStore.addToPlaylist(playlist, [uri], function (err) {
                                t.show(err ? err.hint : qsTr("Zu „%1“ hinzugefügt").arg(playlist.name), !!err)
                            })
                        }
                    })
                }
            }
            MenuItem {
                text: qsTr("Songtext")
                // Nur Musiktitel haben Songtexte; Radio, Hörbücher und
                // Podcasts nicht.
                visible: page.track !== null && page.track.mediaType === "track"
                enabled: mass && mass.ready
                onClicked: pageStack.push(Qt.resolvedUrl("LyricsPage.qml"),
                                          { mass: page.mass, store: page.store,
                                            playerId: page.playerId })
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
                    visible: status === Image.Ready && !vinylSetting.value
                }

                Loader {
                    anchors.fill: parent
                    active: vinylSetting.value
                    sourceComponent: VinylRecord {
                        source: page.track ? page.track.imageUrl : ""
                        // Nicht im Hintergrund weiterdrehen.
                        spinning: page.playing && Qt.application.active
                    }
                }

                // Platzhalter, solange (oder falls) kein Bild da ist -- ein
                // leeres Loch wäre schlechter als ein Notenzeichen.
                Rectangle {
                    anchors.centerIn: parent
                    height: parent.height
                    width: height
                    visible: !cover.visible && !vinylSetting.value
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.15)
                    radius: Theme.paddingSmall

                    Image {
                        anchors.centerIn: parent
                        source: "image://theme/icon-l-music"
                        opacity: 0.4
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.coverTapped()
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

            // Ein Sender hat keine Länge und keinen Regler -- statt einer
            // Lücke sagen, dass es live ist.
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.track !== null && page.track.isLive
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: Theme.highlightColor
                text: qsTr("Live")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                truncationMode: TruncationMode.Fade
                visible: page.chapter !== null
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.chapter ? page.chapter.name : ""
            }

            // --- Transport -----------------------------------------------
            // Bei Gesprochenem zusätzlich -15 s / +30 s. Weiter und Zurück
            // springen dort zwischen Kapiteln (PlayerStore.nextOrChapter).
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: page.track && page.track.isSpoken ? Theme.paddingMedium
                                                           : Theme.paddingLarge

                Column {
                    visible: page.track !== null && page.track.isSpoken
                    anchors.verticalCenter: parent.verticalCenter
                    IconButton {
                        id: backButton
                        icon.source: "image://theme/icon-m-media-rewind"
                        enabled: page.transportEnabled
                        onClicked: store.skip(page.playerId, -15)
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.secondaryColor
                        opacity: backButton.enabled ? 1.0 : Theme.opacityLow
                        text: qsTr("%1 s").arg(15)
                    }
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-previous"
                    enabled: page.transportEnabled
                    onClicked: store.previousOrChapter(page.playerId)
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: page.playing ? "image://theme/icon-l-pause"
                                              : "image://theme/icon-l-play"
                    enabled: page.transportEnabled
                    onClicked: store.playPause(page.playerId)
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-next"
                    enabled: page.transportEnabled
                    onClicked: store.nextOrChapter(page.playerId)
                }

                Column {
                    visible: page.track !== null && page.track.isSpoken
                    anchors.verticalCenter: parent.verticalCenter
                    IconButton {
                        id: forwardButton
                        icon.source: "image://theme/icon-m-media-forward"
                        enabled: page.transportEnabled
                        onClicked: store.skip(page.playerId, 30)
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.secondaryColor
                        opacity: forwardButton.enabled ? 1.0 : Theme.opacityLow
                        text: qsTr("%1 s").arg(30)
                    }
                }
            }

            ComboBox {
                id: speedBox
                width: parent.width
                visible: page.hasSpeed
                enabled: page.controlsEnabled
                label: qsTr("Tempo")
                menu: ContextMenu {
                    Repeater {
                        model: page.speeds
                        MenuItem {
                            text: page.speedLabel(modelData)
                            onClicked: store.setPlaybackSpeed(page.playerId, modelData)
                        }
                    }
                }
            }

            // --- Lautstärke ----------------------------------------------
            // Geht schon beim Ziehen raus und springt danach nicht zurück,
            // siehe VolumeSlider.
            VolumeSlider {
                id: volumeSlider
                width: parent.width
                visible: Models.hasFeature(page.player, Models.FEATURE_VOLUME_SET)
                enabled: page.controlsEnabled
                label: qsTr("Lautstärke")
                serverLevel: (page.player && typeof page.player.volume_level === "number")
                             ? page.player.volume_level : -1
                onLevelRequested: store.setVolume(page.playerId, level)
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

            // Ein laufender Timer soll sichtbar sein, ohne das Pulley-Menü
            // aufzuziehen -- sonst wundert man sich, warum die Musik stoppt.
            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeExtraSmall
                visible: page.sleepRemaining > 0
                onClicked: pageStack.push(Qt.resolvedUrl("SleepTimerPage.qml"),
                                          { mass: page.mass, store: page.store,
                                            playerId: page.playerId })
                Label {
                    anchors.centerIn: parent
                    font.pixelSize: Theme.fontSizeSmall
                    color: parent.highlighted ? Theme.highlightColor : Theme.secondaryHighlightColor
                    text: page.sleepRemaining >= 60
                          ? qsTr("Einschlaftimer: stoppt in %1 Min.").arg(Math.ceil(page.sleepRemaining / 60))
                          : qsTr("Einschlaftimer: stoppt in %1 s").arg(Math.ceil(page.sleepRemaining))
                }
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

    StatusToast { id: pageToast }
}
