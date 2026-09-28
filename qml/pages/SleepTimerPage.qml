import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models

// Einschlaftimer für einen Player: nach der gewählten Zeit hält der Server
// die Wiedergabe an. Der Timer läuft auf dem Server, nicht in der App -- er
// greift also auch, wenn das Telefon längst schläft.
//
// Das Ablaufdatum führt der Server am Player (`sleep_timer_expires_at`), die
// Anzeige folgt dem über player_updated.
Page {
    id: page

    property var mass
    property var store
    property string playerId: ""

    readonly property var player: store ? store.playerById(playerId) : null
    readonly property var queue: store ? store.queueOf(playerId) : null
    readonly property var track: Models.nowPlaying(player, queue, "")

    allowedOrientations: defaultAllowedOrientations

    property real now: Date.now()
    readonly property real remaining: Models.sleepRemaining(player, now)

    Timer {
        interval: 1000
        repeat: true
        running: page.status === PageStatus.Active && page.remaining > 0
        onTriggered: page.now = Date.now()
    }

    // Restzeit bis zum Ende des laufenden Titels bzw. Kapitels; 0 wenn
    // unbekannt (Radio, nichts läuft).
    function untilEnd() {
        if (!track || track.isLive) {
            return 0
        }
        var elapsed = Models.elapsedSeconds(queue, player, Date.now())
        if (track.isSpoken && track.chapters.length > 0) {
            var next = Models.chapterSeek(track.chapters, true, elapsed)
            if (next > 0) {
                return next - elapsed
            }
        }
        return track.duration > 0 ? Math.max(0, track.duration - elapsed) : 0
    }

    function set(seconds) {
        store.setSleepTimer(playerId, seconds, function (err) {
            if (err) {
                pageToast.show(err.hint, true)
                return
            }
            pageStack.pop()
        })
    }

    function formatRemaining(seconds) {
        var s = Math.ceil(seconds)
        if (s >= 3600) {
            return qsTr("%1:%2 Std.").arg(Math.floor(s / 3600))
                    .arg(("0" + Math.floor((s % 3600) / 60)).slice(-2))
        }
        if (s >= 60) {
            return qsTr("%1 Min.").arg(Math.ceil(s / 60))
        }
        return qsTr("%1 s").arg(s)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width

            PageHeader {
                title: qsTr("Einschlaftimer")
                description: page.player ? Models.playerName(page.player) : ""
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                visible: page.remaining > 0
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                text: qsTr("Stoppt in %1").arg(page.formatRemaining(page.remaining))
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.remaining > 0
                text: qsTr("Timer aus")
                onClicked: store.clearSleepTimer(page.playerId, function (err) {
                    if (err) {
                        pageToast.show(err.hint, true)
                    }
                })
            }

            SectionHeader {
                text: page.remaining > 0 ? qsTr("Neu stellen") : qsTr("Stoppen nach")
            }

            Repeater {
                model: [15, 30, 45, 60, 90]
                BackgroundItem {
                    width: page.width
                    onClicked: page.set(modelData * 60)
                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("%1 Minuten").arg(modelData)
                        color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                }
            }

            BackgroundItem {
                width: page.width
                visible: page.untilEnd() > 0
                onClicked: page.set(page.untilEnd())
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    truncationMode: TruncationMode.Fade
                    text: (page.track && page.track.isSpoken && page.track.chapters.length > 0)
                          ? qsTr("Ende des Kapitels (%1)").arg(page.formatRemaining(page.untilEnd()))
                          : qsTr("Ende des Titels (%1)").arg(page.formatRemaining(page.untilEnd()))
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                topPadding: Theme.paddingLarge
                text: qsTr("Der Timer läuft auf dem Server. Er greift auch, wenn das Telefon schläft oder die App geschlossen ist.")
            }
        }

        VerticalScrollDecorator {}
    }

    StatusToast { id: pageToast }
}
