import QtQuick 2.6
import Sailfish.Silica 1.0
import "../lib/MassModels.js" as Models
import "../lib/MassApi.js" as MassApi

// Eine Zeile in einer Bibliotheksliste: Miniaturbild, Name, Unterzeile, und
// im Kontextmenü die drei Arten, das Ding abzuspielen. Von allen
// Bibliotheksseiten benutzt, damit "jetzt spielen" überall dasselbe bedeutet.
ListItem {
    id: row

    property var mass
    property var store
    property var mediaItem
    property string subtitle: ""
    // Titel innerhalb eines Albums brauchen kein eigenes Cover -- es wäre für
    // jede Zeile dasselbe Bild.
    property bool showImage: true
    // Ziel der Rückmeldung; von der Seite gesetzt.
    property var toast

    signal activated()

    contentHeight: showImage ? Theme.itemSizeLarge : Theme.itemSizeMedium
    // Nicht spielbares bleibt sichtbar, aber gedämpft: ein Titel aus einem
    // abgemeldeten Dienst verschwindet sonst scheinbar grundlos.
    opacity: Models.isPlayable(mediaItem) ? 1.0 : Theme.opacityLow

    onClicked: row.activated()

    function enqueue(option, label) {
        if (!store || store.targetPlayerId.length === 0) {
            if (toast) {
                toast.show(qsTr("Kein Player ausgewählt"), true)
            }
            return
        }
        var target = store.playerById(store.targetPlayerId)
        var where = target ? Models.playerName(target) : ""
        store.playMedia(store.targetPlayerId, mediaItem.uri, option, function (err) {
            if (!toast) {
                return
            }
            if (err) {
                toast.show(err.hint, true)
            } else {
                toast.show(label.arg(where))
            }
        })
    }

    Image {
        id: thumb
        visible: row.showImage
        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? Theme.itemSizeMedium : 0
        height: width
        fillMode: Image.PreserveAspectCrop
        clip: true
        asynchronous: true
        // Erst laden, wenn die Zeile wirklich zu sehen ist. Bei ein paar
        // tausend Alben lädt eine Liste sonst beim Durchwischen alles, was
        // je vorbeikam.
        source: (row.showImage && row.ListView.view && proxyId.length > 0)
                ? MassApi.imageUrl(mass ? mass.baseUrl : "", proxyId, Theme.itemSizeMedium)
                : ""
        property string proxyId: Models.imageProxyId(row.mediaItem)

        Rectangle {
            anchors.fill: parent
            visible: parent.status !== Image.Ready
            color: Theme.rgba(Theme.highlightBackgroundColor, 0.15)
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        x: row.showImage ? (thumb.x + thumb.width + Theme.paddingMedium)
                         : Theme.horizontalPageMargin
        width: parent.width - x - Theme.horizontalPageMargin

        Label {
            width: parent.width
            truncationMode: TruncationMode.Fade
            text: row.mediaItem ? row.mediaItem.name : ""
            color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
        }

        Label {
            width: parent.width
            truncationMode: TruncationMode.Fade
            visible: row.subtitle.length > 0
            font.pixelSize: Theme.fontSizeExtraSmall
            color: row.highlighted ? Theme.secondaryHighlightColor
                                   : Theme.secondaryColor
            text: row.subtitle
        }
    }

    menu: ContextMenu {
        MenuItem {
            text: qsTr("Jetzt spielen")
            onClicked: row.enqueue("play", qsTr("Läuft auf %1"))
        }
        MenuItem {
            text: qsTr("Als Nächstes")
            onClicked: row.enqueue("next", qsTr("Als Nächstes auf %1"))
        }
        MenuItem {
            text: qsTr("Anhängen")
            onClicked: row.enqueue("add", qsTr("Angehängt auf %1"))
        }
    }
}
