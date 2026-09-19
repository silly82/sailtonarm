import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/MassApi.js" as MassApi

// Die Warteschlange eines Players: was noch kommt, in welcher Reihenfolge, und
// die Möglichkeit, daran zu drehen.
//
// Das Queue-Objekt selbst trägt in `items` nur eine *Anzahl* -- die Einträge
// holt `player_queues/items`, seitenweise. Eine Warteschlange kann hunderte
// Titel lang sein.
Page {
    id: page

    property var mass
    property var store
    property string playerId: ""

    readonly property var player: store ? store.playerById(playerId) : null
    readonly property var queue: store ? store.queueOf(playerId) : null

    allowedOrientations: Orientation.All

    property var items: []
    property bool loading: false
    property bool exhausted: false
    property string errorText: ""
    readonly property int pageSize: 80

    function reload() {
        items = []
        exhausted = false
        errorText = ""
        loadMore()
    }

    function loadMore() {
        if (loading || exhausted || !mass || !mass.ready || playerId.length === 0) {
            return
        }
        loading = true
        mass.sendCommand("player_queues/items",
                         { queue_id: playerId, limit: pageSize, offset: items.length },
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
            page.items = page.items.concat(batch)
        })
    }

    function repeatLabel() {
        if (!queue) {
            return qsTr("Wiederholen: aus")
        }
        switch (queue.repeat_mode) {
        case "one": return qsTr("Wiederholen: ein Titel")
        case "all": return qsTr("Wiederholen: alle")
        }
        return qsTr("Wiederholen: aus")
    }

    // off -> all -> one -> off. Dieselbe Reihenfolge wie in der Web-UI.
    function nextRepeatMode() {
        if (!queue || queue.repeat_mode === "off" || !queue.repeat_mode) {
            return "all"
        }
        return queue.repeat_mode === "all" ? "one" : "off"
    }

    Component.onCompleted: reload()

    // Der Server meldet Änderungen an der Warteschlange -- nach einem
    // Verschieben oder Löschen also nicht selbst raten, sondern neu holen.
    Connections {
        target: mass
        onServerEvent: {
            if (message.object_id !== page.playerId) {
                return
            }
            if (eventType === "queue_items_updated") {
                reloadDebounce.restart()
            }
        }
    }

    // Ein Umsortieren löst mehrere Ereignisse kurz hintereinander aus; ohne
    // Entprellung lädt die Seite drei- bis viermal dasselbe.
    Timer {
        id: reloadDebounce
        interval: 400
        onTriggered: page.reload()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.items

        header: Column {
            width: listView.width
            bottomPadding: Theme.paddingMedium

            PageHeader {
                title: qsTr("Warteschlange")
                description: page.player ? Models.playerName(page.player) : ""
            }

            TextSwitch {
                text: qsTr("Zufällige Reihenfolge")
                checked: page.queue ? page.queue.shuffle_enabled === true : false
                enabled: page.queue !== null && mass && mass.ready
                automaticCheck: false
                onClicked: store.setShuffle(page.playerId, !checked)
            }

            TextSwitch {
                text: qsTr("Überblenden")
                description: qsTr("Titel ineinander übergehen lassen")
                checked: page.queue ? page.queue.crossfade_enabled === true : false
                enabled: page.queue !== null && mass && mass.ready
                automaticCheck: false
                onClicked: store.setCrossfade(page.playerId, !checked)
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.repeatLabel()
                enabled: page.queue !== null && mass && mass.ready
                onClicked: store.setRepeat(page.playerId, page.nextRepeatMode())
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("An anderen Player übergeben")
                enabled: page.queue !== null && mass && mass.ready
                onClicked: pageStack.push(Qt.resolvedUrl("PlayerPickerPage.qml"), {
                    mass: page.mass,
                    store: page.store,
                    title: qsTr("Übergeben an"),
                    hint: qsTr("Die Warteschlange wandert mitsamt Abspielposition dorthin."),
                    excludePlayerId: page.playerId,
                    pickHandler: function (targetId) {
                        var target = store.playerById(targetId)
                        var where = target ? Models.playerName(target) : ""
                        store.transferQueue(page.playerId, targetId, true, function (err) {
                            if (err) {
                                pageToast.show(err.hint, true)
                            } else {
                                pageToast.show(qsTr("Übergeben an %1").arg(where))
                            }
                        })
                    }
                })
            }
            MenuItem {
                text: qsTr("Als Playlist speichern")
                enabled: page.items.length > 0 && mass && mass.ready
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("SavePlaylistDialog.qml"), {
                        defaultName: page.player ? Models.playerName(page.player) : ""
                    })
                    dialog.accepted.connect(function () {
                        store.saveAsPlaylist(page.playerId, dialog.playlistName,
                                             function (err) {
                            if (err) {
                                pageToast.show(err.hint, true)
                            } else {
                                pageToast.show(qsTr("Als Playlist gespeichert"))
                            }
                        })
                    })
                }
            }
            MenuItem {
                text: qsTr("Warteschlange leeren")
                enabled: page.items.length > 0 && mass && mass.ready
                onClicked: remorse.execute(qsTr("Warteschlange wird geleert"),
                                           function () { store.clearQueue(page.playerId) })
            }
            MenuItem {
                text: qsTr("Neu laden")
                enabled: mass && mass.ready
                onClicked: page.reload()
            }
        }

        ViewPlaceholder {
            enabled: page.items.length === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Fehler") : qsTr("Warteschlange leer")
            hintText: page.errorText.length > 0
                      ? page.errorText
                      : qsTr("Aus der Bibliothek etwas hinzufügen")
        }

        delegate: ListItem {
            id: row
            contentHeight: Theme.itemSizeMedium

            readonly property bool current:
                page.queue && page.queue.current_index === index
            readonly property var media: modelData.media_item

            onClicked: store.playIndex(page.playerId, index)

            Component.onCompleted: {
                if (index >= page.items.length - 15) {
                    page.loadMore()
                }
            }

            // Marke für den gerade laufenden Eintrag -- ohne sie ist in einer
            // langen Warteschlange nicht erkennbar, wo man sich befindet.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.paddingSmall
                width: Theme.paddingSmall / 2
                height: parent.height - Theme.paddingMedium
                color: Theme.highlightColor
                visible: row.current
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                // Die Dauer hängt am rechten Rand *mit* Seitenabstand -- der
                // muss hier ebenfalls abgezogen werden, sonst reicht die
                // Spalte unter die Dauer und der Titel wird davon überdeckt
                // statt vorher auszublenden.
                width: parent.width - x - Theme.horizontalPageMargin
                       - durationLabel.width - Theme.paddingMedium

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: modelData.name || ""
                    color: row.current ? Theme.highlightColor
                                       : (row.highlighted ? Theme.highlightColor
                                                          : Theme.primaryColor)
                }

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    visible: text.length > 0
                    text: row.media ? Models.artistNames(row.media) : ""
                }
            }

            Label {
                id: durationLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: modelData.duration > 0 ? Models.formatTime(modelData.duration) : ""
            }

            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Nach oben")
                    onClicked: store.moveItem(page.playerId, modelData.queue_item_id, -1)
                }
                MenuItem {
                    text: qsTr("Nach unten")
                    onClicked: store.moveItem(page.playerId, modelData.queue_item_id, 1)
                }
                MenuItem {
                    text: qsTr("Ans Ende")
                    onClicked: store.moveItemEnd(page.playerId, modelData.queue_item_id)
                }
                MenuItem {
                    text: qsTr("Entfernen")
                    onClicked: store.deleteItem(page.playerId, modelData.queue_item_id)
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

    RemorsePopup { id: remorse }
    StatusToast { id: pageToast }
}
