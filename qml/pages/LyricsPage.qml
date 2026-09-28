import QtQuick 2.6
import Sailfish.Silica 1.0
import "../lib/MassModels.js" as Models

// Der Songtext zum laufenden Titel, mitlaufend: die aktuelle Zeile ist
// hervorgehoben und wandert zur Mitte, ein Tipper auf eine Zeile springt
// dorthin. Folgt dem Player -- wechselt der Titel, kommt der neue Text.
//
// Quelle ist metadata/get_track_lyrics mit dem vollen media_item des
// Queue-Eintrags; die Antwort ist ein Paar [einfach, lrc]. Die erste Abfrage
// eines Titels kann auf dem echten Server über 30 s dauern (die Anbieter
// werden erst gefragt), daher die lange Frist und die Ladeanzeige.
Page {
    id: page

    property var mass
    property var store
    property string playerId: ""

    readonly property var player: store ? store.playerById(playerId) : null
    readonly property var queue: store ? store.queueOf(playerId) : null
    readonly property var track: Models.nowPlaying(player, queue, mass ? mass.activeBaseUrl : "")
    readonly property var mediaItem: (queue && queue.current_item) ? queue.current_item.media_item : null
    readonly property string itemKey: mediaItem ? (mediaItem.uri || "") : ""
    readonly property bool isTrack: mediaItem !== null && mediaItem.media_type === "track"

    allowedOrientations: defaultAllowedOrientations

    // [{ time, text }]; time -1 bei Text ohne Zeitmarken.
    property var lines: []
    property bool synced: false
    property bool loading: false
    property string errorText: ""
    property string loadedKey: ""
    property int current: -1
    // Nach eigenem Scrollen eine Weile nicht zurückspringen.
    property real followPausedUntil: 0
    // uri -> { lines, synced }; ein Titel wird je Seitenbesuch nur einmal
    // abgefragt, auch wenn er zweimal läuft.
    property var cache: ({})

    function load() {
        if (!mass || !mass.ready || !isTrack || itemKey === loadedKey) {
            return
        }
        loadedKey = itemKey
        current = -1
        errorText = ""
        if (cache[itemKey]) {
            lines = cache[itemKey].lines
            synced = cache[itemKey].synced
            loading = false
            return
        }
        lines = []
        synced = false
        loading = true
        var key = itemKey
        mass.sendCommand("metadata/get_track_lyrics", { track: mediaItem }, function (err, result) {
            if (key !== page.itemKey) {
                return
            }
            page.loading = false
            if (err) {
                page.errorText = err.hint
                // Beim nächsten Titelwechsel oder Neuladen erneut versuchen.
                page.loadedKey = ""
                return
            }
            var plain = (result && result[0]) ? String(result[0]) : ""
            var lrc = (result && result[1]) ? String(result[1]) : ""
            var entry
            if (lrc.length > 0) {
                entry = { lines: Models.parseLrc(lrc), synced: true }
            } else if (plain.length > 0) {
                entry = { lines: Models.plainLyricLines(plain), synced: false }
            } else {
                entry = { lines: [], synced: false }
            }
            var copy = {}
            for (var k in page.cache) {
                copy[k] = page.cache[k]
            }
            copy[key] = entry
            page.cache = copy
            page.lines = entry.lines
            page.synced = entry.synced
            page.tick()
        }, 120000)
    }

    function tick() {
        if (!synced || lines.length === 0) {
            return
        }
        var index = Models.currentLyricIndex(lines, Models.elapsedSeconds(queue, player, Date.now()))
        if (index === current) {
            return
        }
        current = index
        if (index >= 0 && Date.now() >= followPausedUntil && !listView.moving) {
            listView.currentIndex = index
        }
    }

    onItemKeyChanged: load()
    onStatusChanged: if (status === PageStatus.Active) load()

    Connections {
        target: mass
        onAuthenticated: {
            page.loadedKey = ""
            page.load()
        }
    }

    Timer {
        interval: 300
        repeat: true
        running: page.status === PageStatus.Active && page.synced && Models.isPlaying(page.player)
        onTriggered: page.tick()
    }

    // Nach einem Sprung (Tippen, Seek anderswo) sofort nachziehen, nicht erst
    // beim nächsten Takt.
    onQueueChanged: tick()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.lines

        // Die laufende Zeile in der Mitte halten -- weich, über den
        // eingebauten Highlight-Bereich der ListView.
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: height / 2 - Theme.itemSizeSmall
        preferredHighlightEnd: height / 2 + Theme.itemSizeSmall
        highlightMoveDuration: 400
        currentIndex: -1

        onMovementStarted: page.followPausedUntil = Date.now() + 6000

        header: PageHeader {
            title: page.track ? page.track.title : qsTr("Songtext")
            description: page.track ? page.track.artist : ""
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Neu laden")
                enabled: mass && mass.ready && page.isTrack && !page.loading
                onClicked: {
                    var copy = {}
                    for (var k in page.cache) {
                        if (k !== page.itemKey) {
                            copy[k] = page.cache[k]
                        }
                    }
                    page.cache = copy
                    page.loadedKey = ""
                    page.load()
                }
            }
        }

        ViewPlaceholder {
            enabled: page.lines.length === 0 && !page.loading
            text: {
                if (!page.isTrack) {
                    return qsTr("Kein Titel")
                }
                return page.errorText.length > 0 ? qsTr("Fehler") : qsTr("Kein Songtext")
            }
            hintText: {
                if (!page.isTrack) {
                    return qsTr("Songtexte gibt es nur für Musiktitel, nicht für Radio, Hörbücher oder Podcasts")
                }
                return page.errorText.length > 0
                        ? page.errorText
                        : qsTr("Für diesen Titel liefert der Server keinen Text")
            }
        }

        delegate: BackgroundItem {
            id: row
            width: listView.width
            height: label.height + Theme.paddingMedium
            enabled: page.synced && modelData.time >= 0
            onClicked: store.seek(page.playerId, Math.floor(modelData.time))

            readonly property bool isCurrent: index === page.current

            Label {
                id: label
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                // Leere Zeilen sind Pausen im Lied; ein Zeichen statt einer
                // unsichtbaren Lücke.
                text: modelData.text.length > 0 ? modelData.text : "…"
                font.pixelSize: row.isCurrent ? Theme.fontSizeLarge : Theme.fontSizeMedium
                color: row.isCurrent ? Theme.highlightColor
                                     : (row.highlighted ? Theme.highlightColor : Theme.primaryColor)
                // Vergangenes gedämpft, Kommendes normal -- nur mit
                // Zeitmarken sinnvoll.
                opacity: (page.synced && page.current >= 0 && index < page.current) ? 0.45 : 1.0
                Behavior on font.pixelSize { NumberAnimation { duration: 150 } }
            }
        }

        footer: Item {
            width: listView.width
            // Luft unten, damit auch die letzte Zeile in die Mitte rücken kann.
            height: page.synced ? listView.height / 2 : Theme.paddingLarge
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading
        size: BusyIndicatorSize.Large
    }

    Label {
        anchors.top: parent.verticalCenter
        anchors.topMargin: Theme.itemSizeLarge
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: page.loading
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.secondaryHighlightColor
        text: qsTr("Der Server fragt seine Quellen — beim ersten Mal kann das eine halbe Minute dauern.")
    }
}
