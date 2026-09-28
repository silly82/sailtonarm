import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models
import "../lib/MassApi.js" as MassApi

// Ein Hörbuch: Cover, Autoren und Sprecher, Fortschritt, Weiterhören oder von
// vorn, und die Kapitel. Läuft das Buch gerade auf dem Ziel-Player, ist das
// aktuelle Kapitel markiert und ein Tippen auf ein Kapitel springt dorthin.
//
// Die Liste liefert das Buch schon mit, aber ohne Gewähr für Kapitel und
// frischen Fortschritt -- `music/audiobooks/get` holt beides nach. Bis dahin
// zeigt die Seite, was sie hat.
Page {
    id: page

    property var mass
    property var store
    property var audiobook

    allowedOrientations: defaultAllowedOrientations

    property var loaded: null
    property bool loading: false
    property string errorText: ""
    // Nach "beendet markieren" oder "von vorn": der Stand, den der Server
    // gerade bekommen hat. Er schickt dafür kein Ereignis, also lokal merken.
    property var localState: null

    readonly property var book: {
        var base = loaded || audiobook
        if (!base || !localState) {
            return base
        }
        var copy = {}
        for (var key in base) {
            copy[key] = base[key]
        }
        for (key in localState) {
            copy[key] = localState[key]
        }
        return copy
    }
    readonly property var chapters: Models.chaptersOf(book)
    readonly property real progress: Models.listenProgress(book)
    readonly property bool started: progress >= 0
    readonly property bool finished: Models.isFullyPlayed(book)

    // Spielt der Ziel-Player gerade dieses Buch?
    readonly property var targetQueue: store ? store.queueOf(store.targetPlayerId) : null
    readonly property var targetPlayer: store ? store.playerById(store.targetPlayerId) : null
    readonly property bool playingHere: {
        var item = targetQueue ? targetQueue.current_item : null
        return !!(item && item.media_item && book && item.media_item.uri === book.uri)
    }
    property real elapsed: 0
    readonly property var currentChapter: playingHere
                                          ? Models.currentChapter(chapters, elapsed) : null

    function refreshElapsed() {
        elapsed = playingHere ? Models.elapsedSeconds(targetQueue, targetPlayer, Date.now()) : 0
    }

    function load() {
        if (!mass || !mass.ready || !audiobook) {
            return
        }
        loading = true
        errorText = ""
        mass.sendCommand("music/audiobooks/get",
                         { item_id: audiobook.item_id,
                           provider_instance_id_or_domain: audiobook.provider },
                         function (err, result) {
            page.loading = false
            if (err) {
                page.errorText = err.hint
                return
            }
            var first = page.loaded === null
            page.loaded = result
            page.localState = null
            if (!first) {
                return
            }
            // Mit dem geladenen Buch wächst der Kopf (Kapitelzahl, Status);
            // oben bleiben, statt in die Kapitel zu rutschen. Erst nach dem
            // nächsten Layout-Durchgang, vorher hat der Kopf die neue Höhe
            // noch nicht.
            toTopTimer.restart()
        })
    }

    function targetName() {
        if (!store) {
            return qsTr("keiner")
        }
        var p = store.playerById(store.targetPlayerId)
        return p ? Models.playerName(p) : qsTr("keiner")
    }

    function requireTarget() {
        if (!store || store.targetPlayerId.length === 0) {
            pageToast.show(qsTr("Kein Player ausgewählt"), true)
            return false
        }
        return true
    }

    function play(option, label) {
        if (!requireTarget()) {
            return
        }
        var where = targetName()
        store.playMedia(store.targetPlayerId, book.uri, option, function (err) {
            if (err) {
                pageToast.show(err.hint, true)
            } else {
                pageToast.show(label.arg(where))
            }
        })
    }

    function playFromStart() {
        if (!requireTarget()) {
            return
        }
        var where = targetName()
        store.playFromStart(store.targetPlayerId, book, function (err) {
            if (err) {
                pageToast.show(err.hint, true)
            } else {
                page.localState = { fully_played: false, resume_position_ms: 0 }
                pageToast.show(qsTr("Läuft von vorn auf %1").arg(where))
            }
        })
    }

    function setPlayed(played) {
        store.setPlayed(book, played, function (err) {
            if (err) {
                pageToast.show(err.hint, true)
                return
            }
            page.localState = { fully_played: played, resume_position_ms: 0 }
            pageToast.show(played ? qsTr("Als beendet markiert")
                                  : qsTr("Als nicht begonnen markiert"))
        })
    }

    function durationText(seconds) {
        if (!(seconds > 0)) {
            return ""
        }
        var hours = Math.floor(seconds / 3600)
        var minutes = Math.round((seconds % 3600) / 60)
        return hours > 0 ? qsTr("%1 Std. %2 Min.").arg(hours).arg(minutes)
                         : qsTr("%1 Min.").arg(minutes)
    }

    function statusText() {
        if (finished) {
            return qsTr("Beendet")
        }
        if (started) {
            return qsTr("%1 % gehört, noch %2")
                    .arg(Math.round(progress * 100))
                    .arg(durationText(book.duration - Models.resumeSeconds(book)))
        }
        return qsTr("Nicht begonnen")
    }

    // Ende eines Kapitels: eigenes `end`, sonst der Beginn des nächsten, sonst
    // das Buchende.
    function chapterEnd(index) {
        var c = chapters[index]
        if (c.end > c.start) {
            return c.end
        }
        if (index + 1 < chapters.length) {
            return chapters[index + 1].start
        }
        return book && book.duration > 0 ? book.duration : 0
    }

    // Zurück auf der Seite (etwa aus "Läuft gerade"): der Fortschritt kann
    // sich inzwischen geändert haben, und dafür gibt es kein Ereignis.
    property bool wasShown: false
    onStatusChanged: {
        if (status !== PageStatus.Active) {
            return
        }
        if (wasShown) {
            load()
        }
        wasShown = true
    }

    onPlayingHereChanged: refreshElapsed()
    onTargetQueueChanged: refreshElapsed()
    Component.onCompleted: load()

    Connections {
        target: mass
        onAuthenticated: page.load()
    }

    Timer {
        id: toTopTimer
        interval: 50
        onTriggered: listView.positionViewAtBeginning()
    }

    // Die Markierung folgt der Position; alle paar Sekunden genügt.
    Timer {
        interval: 3000
        repeat: true
        running: page.status === PageStatus.Active && page.playingHere
        onTriggered: page.refreshElapsed()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.chapters

        header: Column {
            width: listView.width
            spacing: Theme.paddingMedium
            bottomPadding: Theme.paddingMedium

            PageHeader {
                title: page.book ? page.book.name : ""
            }

            // Der Platz fürs Cover steht von Anfang an fest. Wüchse der Kopf
            // erst, wenn das Bild geladen ist, schöbe die Liste ihn dabei aus
            // dem Bild -- die Seite öffnete dann mitten in den Kapiteln.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width * 0.5, Theme.itemSizeHuge * 2)
                height: width
                visible: Models.imageProxyId(page.book).length > 0

                Rectangle {
                    anchors.fill: parent
                    visible: coverImage.status !== Image.Ready
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.15)
                }

                Image {
                    id: coverImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: {
                        var id = Models.imageProxyId(page.book)
                        return id.length > 0
                                ? MassApi.imageUrl(mass ? mass.activeBaseUrl : "", id, 512) : ""
                    }
                }
            }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    visible: text.length > 0
                    text: page.book ? Models.personNames(page.book.authors) : ""
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                    property string names: page.book ? Models.personNames(page.book.narrators) : ""
                    visible: names.length > 0
                    text: qsTr("Gelesen von %1").arg(names)
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    visible: text.length > 0
                    text: page.book ? page.durationText(page.book.duration) : ""
                }
            }

            ProgressBar {
                width: parent.width
                visible: page.started
                minimumValue: 0
                maximumValue: 1
                value: Math.max(0, page.progress)
                label: page.statusText()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                visible: !page.started
                text: page.statusText()
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium

                Button {
                    text: page.started ? qsTr("Weiterhören") : qsTr("Abspielen")
                    enabled: store && store.targetPlayerId.length > 0 && page.book
                    onClicked: page.play("replace", qsTr("Läuft auf %1"))
                }
                Button {
                    text: qsTr("Von vorn")
                    visible: page.started || page.finished
                    enabled: store && store.targetPlayerId.length > 0 && page.book
                    onClicked: page.playFromStart()
                }
            }

            SectionHeader {
                visible: page.chapters.length > 0
                text: qsTr("%n Kapitel", "", page.chapters.length)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                visible: page.chapters.length > 0 && page.playingHere
                text: qsTr("Tippen springt zum Kapitel")
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Ziel-Player: %1").arg(page.targetName())
                onClicked: pageStack.push(Qt.resolvedUrl("PlayerPickerPage.qml"),
                                          { mass: page.mass, store: page.store })
            }
            // Zurücksetzen gilt auch für ein angefangenes Buch, nicht nur für
            // ein beendetes -- etwa nach versehentlichem Anspielen.
            MenuItem {
                text: qsTr("Als nicht begonnen markieren")
                visible: page.started || page.finished
                enabled: mass && mass.ready && page.book
                onClicked: page.setPlayed(false)
            }
            MenuItem {
                text: qsTr("Als beendet markieren")
                visible: !page.finished
                enabled: mass && mass.ready && page.book
                onClicked: page.setPlayed(true)
            }
            MenuItem {
                text: qsTr("Anhängen")
                enabled: store && store.targetPlayerId.length > 0 && page.book
                onClicked: page.play("add", qsTr("Angehängt auf %1"))
            }
        }

        ViewPlaceholder {
            enabled: page.chapters.length === 0 && !page.loading
                     && page.errorText.length > 0
            text: qsTr("Fehler")
            hintText: page.errorText
        }

        delegate: ListItem {
            id: chapterRow
            readonly property bool isCurrent: page.currentChapter !== null
                                              && page.currentChapter.start === modelData.start
            contentHeight: Math.max(Theme.itemSizeSmall,
                                    chapterColumn.height + 2 * Theme.paddingSmall)
            // Springen geht nur, während das Buch hier läuft; sonst ist die
            // Liste eine Übersicht.
            enabled: page.playingHere
            onClicked: store.seek(store.targetPlayerId, Math.ceil(modelData.start))

            Column {
                id: chapterColumn
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                // Die Kapitellänge rechts mitsamt Abstand heraus, sonst
                // überdeckt sie den Namen statt ihn ausblenden zu lassen.
                width: parent.width - x - Theme.horizontalPageMargin
                       - lengthLabel.width - Theme.paddingMedium

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.bold: chapterRow.isCurrent
                    color: (chapterRow.isCurrent || chapterRow.highlighted)
                           ? Theme.highlightColor : Theme.primaryColor
                    text: modelData.name || qsTr("Kapitel %1").arg(index + 1)
                }

                Label {
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: Models.formatTime(modelData.start)
                }
            }

            Label {
                id: lengthLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: {
                    // Manche Anbieter setzen Zwischentitel ("Erstes Buch") als
                    // Kapitel von Sekundenbruchteilen -- "0:00" sagte dort nichts.
                    var end = page.chapterEnd(index)
                    return end - modelData.start >= 1 ? Models.formatTime(end - modelData.start) : ""
                }
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading && page.chapters.length === 0
        size: BusyIndicatorSize.Large
    }

    StatusToast { id: pageToast }
}
