import QtQuick 2.6
import Sailfish.Silica 1.0
import "../lib/MassModels.js" as Models

// Einstiegsseite ab Ausbaustufe 1: die Player der Anlage, jeweils mit dem was
// gerade läuft, Play/Pause direkt in der Zeile, und ein Tippen führt auf die
// Now-Playing-Seite.
Page {
    id: page

    property var mass
    property var store

    allowedOrientations: Orientation.All

    // Damit die Zeilen mitlaufen, ohne dass jede einzelne einen eigenen Timer
    // hält: ein Taktgeber für die ganze Seite, der nur läuft, wenn die Seite
    // sichtbar ist und überhaupt etwas spielt.
    property real tick: 0

    function anyPlaying() {
        if (!store) {
            return false
        }
        for (var i = 0; i < store.players.length; i++) {
            if (Models.isPlaying(store.players[i])) {
                return true
            }
        }
        return false
    }

    function stateText(player) {
        switch (Models.playbackState(player)) {
        case "playing": return qsTr("spielt")
        case "paused": return qsTr("pausiert")
        case "idle": return qsTr("bereit")
        }
        return qsTr("unbekannt")
    }

    Timer {
        interval: 1000
        repeat: true
        running: page.status === PageStatus.Active && page.anyPlaying()
        onTriggered: page.tick = Date.now()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: store ? store.players : []

        header: Column {
            width: listView.width

            PageHeader { title: qsTr("Tonarm") }

            // Verbindungszeile -- nur wenn etwas nicht stimmt. Steht alles,
            // braucht niemand eine Zeile, die "alles gut" sagt.
            Item {
                width: parent.width
                height: connectionLabel.visible ? Theme.itemSizeExtraSmall : 0

                Label {
                    id: connectionLabel
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    visible: mass && mass.connectionState !== "ready"
                    color: (mass && mass.connectionState === "error")
                           ? Theme.errorColor : Theme.secondaryHighlightColor
                    text: {
                        if (!mass) {
                            return ""
                        }
                        if (!Credentials.loaded) {
                            return qsTr("Zugangsdaten werden geladen …")
                        }
                        if (!mass.configured) {
                            return qsTr("Nicht eingerichtet — siehe Einstellungen")
                        }
                        switch (mass.connectionState) {
                        case "connecting": return qsTr("Verbinde …")
                        case "authenticating": return qsTr("Anmeldung läuft …")
                        case "error": return mass.lastError.length > 0
                                             ? mass.lastError : qsTr("Keine Verbindung")
                        }
                        return qsTr("Getrennt")
                    }
                }
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Einstellungen")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"),
                                          { mass: page.mass })
            }
            MenuItem {
                text: qsTr("Aktualisieren")
                enabled: mass && mass.ready
                onClicked: store.refresh()
            }
            MenuItem {
                text: qsTr("Suchen")
                enabled: mass && mass.ready
                onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"),
                                          { mass: page.mass, store: page.store })
            }
            MenuItem {
                text: qsTr("Bibliothek")
                enabled: mass && mass.ready
                onClicked: pageStack.push(Qt.resolvedUrl("LibraryPage.qml"),
                                          { mass: page.mass, store: page.store })
            }
        }

        ViewPlaceholder {
            enabled: store && store.players.length === 0
            text: {
                if (mass && !mass.configured) {
                    return qsTr("Noch nicht eingerichtet")
                }
                if (mass && !mass.ready) {
                    return qsTr("Keine Verbindung")
                }
                if (store && !store.loadedOnce) {
                    return qsTr("Lade …")
                }
                return qsTr("Keine Player")
            }
            hintText: {
                if (mass && !mass.configured) {
                    return qsTr("Adresse und Token im Pulley-Menü eintragen")
                }
                if (mass && !mass.ready) {
                    return qsTr("Der Server ist gerade nicht erreichbar")
                }
                return qsTr("Music Assistant meldet keine Player")
            }
        }

        delegate: ListItem {
            id: row
            // Nicht fest: die Zeile wächst um den Fortschrittsbalken, wenn
            // einer da ist. Mit fester Höhe lief er in die nächste Zeile.
            contentHeight: Math.max(Theme.itemSizeMedium,
                                    textColumn.height + 2 * Theme.paddingMedium)
            enabled: Models.isAvailable(modelData)
            opacity: enabled ? 1.0 : Theme.opacityLow

            property var queue: store ? store.queueOf(modelData.player_id) : null
            property var track: Models.nowPlaying(modelData, queue)

            onClicked: {
                store.preferredPlayerId = modelData.player_id
                pageStack.push(Qt.resolvedUrl("NowPlayingPage.qml"),
                               { mass: page.mass, store: page.store,
                                 playerId: modelData.player_id })
            }

            Column {
                id: textColumn
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - playButton.width - Theme.paddingMedium

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: Models.playerName(modelData)
                    color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: row.highlighted ? Theme.secondaryHighlightColor
                                           : Theme.secondaryColor
                    text: {
                        if (!Models.isAvailable(modelData)) {
                            return qsTr("nicht verfügbar")
                        }
                        // Angeschlossene Lautsprecher sagen, woran sie
                        // hängen -- sonst wundert man sich, warum sie das
                        // Gleiche spielen und einzeln nicht reagieren.
                        var leader = Models.groupLeaderOf(modelData)
                        if (leader.length > 0) {
                            var head = store.playerById(leader)
                            if (head) {
                                return qsTr("gruppiert mit %1").arg(Models.playerName(head))
                            }
                        }
                        if (row.track && row.track.title.length > 0) {
                            return row.track.artist.length > 0
                                    ? row.track.artist + " — " + row.track.title
                                    : row.track.title
                        }
                        return page.stateText(modelData)
                    }
                }

                // Fortschritt nur dort zeigen, wo er etwas aussagt: ohne
                // bekannte Dauer wäre der Balken eine Lüge. Bewusst zwei
                // Rechtecke statt Silicas ProgressBar -- die bringt eigene
                // Innenabstände und eine Mindesthöhe mit, die in einer
                // Listenzeile nicht mit dem Text darüber fluchten.
                Item {
                    width: parent.width
                    height: visible ? Theme.paddingSmall : 0
                    visible: row.track && row.track.duration > 0
                             && Models.playbackState(modelData) !== "idle"

                    property real fraction: {
                        if (!row.track || !(row.track.duration > 0)) {
                            return 0
                        }
                        var elapsed = Models.elapsedSeconds(
                                    row.queue, modelData,
                                    page.tick > 0 ? page.tick : Date.now())
                        return Math.max(0, Math.min(1, elapsed / row.track.duration))
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: Math.max(1, Theme.paddingSmall / 3)
                        color: Theme.rgba(Theme.secondaryColor, 0.3)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * parent.fraction
                        height: Math.max(1, Theme.paddingSmall / 3)
                        color: Theme.highlightColor
                    }
                }
            }

            IconButton {
                id: playButton
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                icon.source: Models.isPlaying(modelData)
                             ? "image://theme/icon-m-pause"
                             : "image://theme/icon-m-play"
                enabled: row.enabled && mass && mass.ready
                onClicked: store.playPause(modelData.player_id)
            }

            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Warteschlange")
                    onClicked: pageStack.push(Qt.resolvedUrl("QueuePage.qml"),
                                              { mass: page.mass, store: page.store,
                                                playerId: modelData.player_id })
                }
                MenuItem {
                    text: qsTr("Gruppieren")
                    onClicked: pageStack.push(Qt.resolvedUrl("GroupPage.qml"),
                                              { mass: page.mass, store: page.store,
                                                playerId: modelData.player_id })
                }
                MenuItem {
                    text: qsTr("Als Ziel für die Bibliothek")
                    onClicked: store.explicitTargetPlayerId = modelData.player_id
                }
            }

            // Kennzeichnet den zuletzt geöffneten Player. Er steht ohnehin
            // oben; der Punkt sagt, warum. Auf Höhe der ersten Textzeile statt
            // mittig, und weit genug vom Rand weg, um nicht angeschnitten zu
            // werden.
            Rectangle {
                y: textColumn.y + Theme.paddingSmall
                x: Theme.paddingMedium
                width: Theme.paddingSmall
                height: width
                radius: width / 2
                color: Theme.highlightColor
                visible: store && store.preferredPlayerId === modelData.player_id
            }
        }

        VerticalScrollDecorator {}
    }
}
