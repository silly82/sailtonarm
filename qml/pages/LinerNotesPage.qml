import QtQuick 2.6
import Sailfish.Silica 1.0

// Easter Egg (KONZEPT.md Abschnitt 35): siebenmal auf die Versionsnummer in
// den Einstellungen tippen. Die Rückseite einer Doppel-LP -- jede Version ist
// ein Stück, die Titel spielen auf den Changelog in rpm/harbour-tonarm.spec
// an. Neue Versionen kommen hinten auf Seite D dazu.
Page {
    id: page

    allowedOrientations: defaultAllowedOrientations

    // Die Spieldauern sind erfunden, aber fest: aus der Versionsnummer
    // abgeleitet, damit sie bei jedem Öffnen gleich sind.
    function runningTime(n) {
        var seconds = 150 + (n * 97) % 150
        var s = seconds % 60
        return Math.floor(seconds / 60) + ":" + (s < 10 ? "0" : "") + s
    }

    function sideTime(tracks) {
        var total = 0
        for (var i = 0; i < tracks.length; i++) {
            total += 150 + (tracks[i].n * 97) % 150
        }
        var s = total % 60
        return Math.floor(total / 60) + ":" + (s < 10 ? "0" : "") + s
    }

    readonly property var sides: [
        { name: "A", tracks: [
            { n: 1, v: "0.1", title: QT_TR_NOOP("Erster Kontakt") },
            { n: 2, v: "0.2", title: QT_TR_NOOP("Fernbedienung") },
            { n: 3, v: "0.3", title: QT_TR_NOOP("Die Warteschlange fährt selbst") },
            { n: 4, v: "0.4", title: QT_TR_NOOP("Aus der Zeile gefallen") },
            { n: 5, v: "0.5", title: QT_TR_NOOP("Cover-Version") },
            { n: 6, v: "0.6", title: QT_TR_NOOP("Bibliothek bei Nacht") },
            { n: 7, v: "0.7", title: QT_TR_NOOP("Was noch kommt") },
            { n: 8, v: "0.8", title: QT_TR_NOOP("Überlänge") }
        ] },
        { name: "B", tracks: [
            { n: 9, v: "0.9", title: QT_TR_NOOP("Sperrbildschirm-Blues") },
            { n: 10, v: "0.10", title: QT_TR_NOOP("Sailjail Rock") },
            { n: 11, v: "0.11", title: QT_TR_NOOP("Tausendmal zu lang") },
            { n: 12, v: "0.12", title: QT_TR_NOOP("Knöpfe ohne Wirkung") },
            { n: 14, v: "0.14", title: QT_TR_NOOP("Fürs Protokoll") },
            { n: 15, v: "0.15", title: QT_TR_NOOP("Alle zusammen") },
            { n: 16, v: "0.16", title: QT_TR_NOOP("Auch auf Englisch") }
        ] },
        { name: "C", tracks: [
            { n: 17, v: "0.17", title: QT_TR_NOOP("Das Token bleibt geheim") },
            { n: 18, v: "0.18", title: QT_TR_NOOP("Zuletzt gehört") },
            { n: 19, v: "0.19", title: QT_TR_NOOP("Spieldauer eines Hörbuchs") },
            { n: 20, v: "0.20", title: QT_TR_NOOP("Live") },
            { n: 21, v: "0.21", title: QT_TR_NOOP("Leiser, schon beim Ziehen") },
            { n: 22, v: "0.22", title: QT_TR_NOOP("Nur was mir gehört") },
            { n: 23, v: "0.23", title: QT_TR_NOOP("Unterwegs") },
            { n: 24, v: "0.24", title: QT_TR_NOOP("Fünf erfundene Räume") }
        ] },
        { name: "D", tracks: [
            { n: 25, v: "0.25", title: QT_TR_NOOP("Im Zwischenspeicher") },
            { n: 26, v: "0.26", title: QT_TR_NOOP("Zeile für Zeile") },
            { n: 27, v: "0.27", title: QT_TR_NOOP("Mehr davon") },
            { n: 28, v: "0.28", title: QT_TR_NOOP("Achtung, eine Durchsage") },
            { n: 29, v: "0.29", title: QT_TR_NOOP("Neue Folge") },
            { n: 30, v: "0.30", title: QT_TR_NOOP("Farben aus dem Cover") },
            { n: 31, v: "0.31", title: QT_TR_NOOP("Ein Tonarm für Tonarm (Hidden Track)") },
            { n: 32, v: "0.32", title: QT_TR_NOOP("Ein Album, nicht Alben") },
            { n: 33, v: "0.33", title: QT_TR_NOOP("Tropfenform") }
        ] }
    ]

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge * 2

        Column {
            id: column
            width: page.width

            PageHeader {
                title: qsTr("Liner Notes")
                description: "Tonarm " + Qt.application.version
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeExtraSmall
                font.letterSpacing: 2
                color: Theme.secondaryHighlightColor
                text: qsTr("DOPPELALBUM · STEREO · 33⅓ U/MIN")
            }

            Repeater {
                model: page.sides

                Column {
                    width: column.width

                    SectionHeader {
                        text: qsTr("Seite %1 · %2").arg(modelData.name).arg(page.sideTime(modelData.tracks))
                    }

                    Repeater {
                        model: modelData.tracks

                        Item {
                            width: column.width
                            height: trackTitle.height + Theme.paddingSmall

                            Label {
                                id: trackNo
                                x: Theme.horizontalPageMargin
                                width: Theme.itemSizeExtraSmall
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.secondaryHighlightColor
                                text: modelData.v
                            }
                            Label {
                                id: trackTitle
                                anchors {
                                    left: trackNo.right
                                    right: trackTime.left
                                    rightMargin: Theme.paddingMedium
                                }
                                wrapMode: Text.Wrap
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.highlightColor
                                text: qsTr(modelData.title)
                            }
                            Label {
                                id: trackTime
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.horizontalPageMargin
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.secondaryColor
                                text: page.runningTime(modelData.n)
                            }
                        }
                    }
                }
            }

            SectionHeader { text: qsTr("Mitwirkende") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
                lineHeight: 1.2
                text: qsTr("Produziert von silly82\n"
                           + "Die Musik kommt von Music Assistant\n"
                           + "Aufgenommen mit Sailfish Silica auf einem Jolla Phone")
            }

            Item { width: 1; height: Theme.paddingLarge }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                font.italic: true
                color: Theme.secondaryColor
                text: qsTr("Diese Aufnahme spielt keinen einzigen Ton selbst. "
                           + "Für beste Ergebnisse Lautsprecher anschliessen.")
            }

            Item { width: 1; height: Theme.paddingLarge }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeTiny
                color: Theme.secondaryColor
                text: "HARBOUR-TONARM " + Qt.application.version + " · ℗ © 2026 silly82 · MIT"
            }
        }

        VerticalScrollDecorator {}
    }
}
