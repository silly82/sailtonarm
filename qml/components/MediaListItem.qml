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
    // "Beschreibung" im Kontextmenü; nur wenn die Seite darauf reagiert.
    signal infoRequested()
    property bool hasInfo: false

    readonly property bool inListView: !!row.ListView.view
                                       || (!!row.parent && !!row.parent.ListView.view)

    // Mit zweizeiligem Titel wächst die Zeile über die Normalhöhe hinaus.
    // Entfernte Zeilen fallen auf Höhe 0 (ListItem rechnet die Höhe selbst
    // aus contentHeight und einem offenen Menü).
    contentHeight: removed ? 0 : Math.max(showImage ? Theme.itemSizeLarge : Theme.itemSizeMedium,
                            textColumn.height + 2 * Theme.paddingMedium)
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
        // je vorbeikam. Auf der Suchseite steckt die Zeile in einem Loader,
        // dann trägt dieser das ListView-Attached -- ohne diesen zweiten
        // Blick blieben dort alle Bilder leer.
        source: (row.showImage && row.inListView && proxyId.length > 0)
                ? MassApi.imageUrl(mass ? mass.activeBaseUrl : "", proxyId, Theme.itemSizeMedium)
                : ""
        property string proxyId: Models.imageProxyId(row.mediaItem)

        Rectangle {
            anchors.fill: parent
            visible: parent.status !== Image.Ready
            color: Theme.rgba(Theme.highlightBackgroundColor, 0.15)
        }
    }

    Column {
        id: textColumn
        anchors.verticalCenter: parent.verticalCenter
        x: row.showImage ? (thumb.x + thumb.width + Theme.paddingMedium)
                         : Theme.horizontalPageMargin
        // Der Favoritenstern hängt rechts *mit* Seitenabstand -- beides muss
        // heraus, sonst überdeckt er das Textende, statt es ausblenden zu
        // lassen. Dritter Anlauf dieser Sorte Fehler in diesem Projekt.
        width: parent.width - x - Theme.horizontalPageMargin
               - (favoriteMark.visible ? favoriteMark.width + Theme.paddingMedium : 0)

        // Zwei Zeilen statt Ausblenden: lange Titel unterscheiden sich oft
        // erst am Ende ("... (Live)", "... Remastered 2011", "Buch 3").
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
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

    // Favoritenstand: erst der Wert vom Server, nach eigenem Umschalten der
    // lokale Merker. Der Server schickt für Favoriten kein Ereignis, das die
    // Liste aktualisieren würde -- ohne den Merker spränge die Zeile beim
    // nächsten Blick zurück.
    property var favoriteOverride: null
    readonly property bool isFavorite: favoriteOverride !== null
                                       ? favoriteOverride
                                       : (mediaItem && mediaItem.favorite === true)
    // Aus den Favoriten nehmen verlangt Medientyp und Bibliothekskennung --
    // das geht nur bei Einträgen, die tatsächlich in der Bibliothek liegen.
    readonly property bool canUnfavorite: mediaItem && mediaItem.provider === "library"

    function toggleFavorite() {
        if (!store || !mediaItem) {
            return
        }
        if (isFavorite) {
            store.removeFavorite(mediaItem.media_type, mediaItem.item_id, function (err) {
                if (err) {
                    if (toast) toast.show(err.hint, true)
                } else {
                    row.favoriteOverride = false
                    if (toast) toast.show(qsTr("Aus Favoriten entfernt"))
                }
            })
        } else {
            store.addFavorite(mediaItem.uri, function (err) {
                if (err) {
                    if (toast) toast.show(err.hint, true)
                } else {
                    row.favoriteOverride = true
                    if (toast) toast.show(qsTr("Zu Favoriten hinzugefügt"))
                }
            })
        }
    }

    // Gehört/nicht gehört für Folgen und Hörbücher. Der Server schickt dafür
    // kein Ereignis, also merkt sich die Zeile ihren Stand selbst, wie beim
    // Favoriten.
    readonly property bool canMarkPlayed: mediaItem
                                          && (mediaItem.media_type === "podcast_episode"
                                              || mediaItem.media_type === "audiobook")
    property var playedOverride: null
    readonly property bool isPlayed: playedOverride !== null
                                     ? playedOverride : Models.isFullyPlayed(mediaItem)
    // Nach einer Markierung gilt der Fortschritt nicht mehr (der Server setzt
    // ihn zurück).
    readonly property real progress: playedOverride !== null ? -1 : Models.listenProgress(mediaItem)

    function setPlayed(played) {
        if (!store || !mediaItem) {
            return
        }
        var item = mediaItem
        store.setPlayed(item, played, function (err) {
            if (err) {
                if (toast) toast.show(err.hint, true)
                return
            }
            // Bei Podcast-Folgen nachlesen, ob der Server den Stand
            // übernommen hat. Stammt die Folge von einem Anbieter, der den
            // Hörstand selbst führt (Overcast), nimmt der Server die
            // Markierung an und meldet danach trotzdem den Stand des
            // Anbieters -- auf dem Gerät geprüft (KONZEPT.md Abschnitt 33).
            // Dann nicht so tun, als hätte es geklappt.
            if (item.media_type !== "podcast_episode" || !mass) {
                row.playedOverride = played
                if (toast) toast.show(played ? qsTr("Als gehört markiert")
                                             : qsTr("Als nicht gehört markiert"))
                return
            }
            mass.sendCommand("music/podcasts/podcast_episode",
                             { item_id: item.item_id, provider_instance_id_or_domain: item.provider },
                             function (err2, fresh) {
                var took = !err2 && fresh && Models.isFullyPlayed(fresh) === played
                if (took) {
                    row.playedOverride = played
                    if (toast) toast.show(played ? qsTr("Als gehört markiert")
                                                 : qsTr("Als nicht gehört markiert"))
                } else if (toast) {
                    toast.show(qsTr("Der Podcast-Anbieter führt den Hörstand selbst – bitte dort ändern"), true)
                }
            }, 30000)
        })
    }

    // Ähnliches gibt es für Titel und Interpreten -- dafür hat der Server
    // Daten (Last.fm, Streamingdienst). Ersetzt die Warteschlange.
    readonly property bool canPlaySimilar: mediaItem
                                           && (mediaItem.media_type === "track"
                                               || mediaItem.media_type === "artist")

    function playSimilar() {
        if (!store || store.targetPlayerId.length === 0) {
            if (toast) {
                toast.show(qsTr("Kein Player ausgewählt"), true)
            }
            return
        }
        var target = store.playerById(store.targetPlayerId)
        var where = target ? Models.playerName(target) : ""
        store.playSimilar(store.targetPlayerId, mediaItem.uri, function (err) {
            if (!toast) {
                return
            }
            if (err) {
                toast.show(err.hint, true)
            } else {
                toast.show(qsTr("Ähnliches läuft auf %1").arg(where))
            }
        })
    }

    // --- Playlists und Bibliothek ----------------------------------------

    // Nur Titel gehen in Playlists (der Server nimmt Titel-URIs).
    readonly property bool canAddToPlaylist: mediaItem && mediaItem.media_type === "track"

    // Auf einer bearbeitbaren Playlist-Seite: die Position des Titels (ab 1),
    // sonst -1. Die Seite reagiert auf removeFromPlaylistRequested.
    property int playlistPosition: -1
    signal removeFromPlaylistRequested()

    // In die Bibliothek aufnehmen, was von einem Anbieter kommt; entfernen,
    // was drinliegt. Entfernen nur bei Titeln, Alben und Sendern -- bei einem
    // Interpreten nähme der Server alle Alben mit, bei einer Playlist eines
    // Dienstes ist unklar, was mit dem Original geschieht.
    property bool libraryOverride: false
    readonly property bool inLibrary: libraryOverride
                                      || (!!mediaItem && mediaItem.provider === "library")
    readonly property bool canAddToLibrary: !!mediaItem && !inLibrary
            && ["track", "album", "artist", "playlist", "radio", "podcast", "audiobook"]
               .indexOf(mediaItem.media_type) !== -1
    readonly property bool canRemoveFromLibrary: !!mediaItem && mediaItem.provider === "library"
            && ["track", "album", "radio"].indexOf(mediaItem.media_type) !== -1
    // Nach dem Entfernen verschwindet die Zeile, ohne dass die Liste neu
    // geladen werden muss.
    property bool removed: false
    visible: !removed

    function pickPlaylist() {
        if (!store) {
            return
        }
        // Alles festhalten, was die späte Antwort braucht (siehe
        // PlayersPage, Durchsage).
        var item = mediaItem
        var t = toast
        var playerStore = store
        pageStack.push(Qt.resolvedUrl("../pages/PlaylistPickerPage.qml"), {
            mass: mass, store: store, itemName: item.name,
            pickHandler: function (playlist) {
                if (playlist.error) {
                    if (t) t.show(playlist.error.hint, true)
                    return
                }
                playerStore.addToPlaylist(playlist, [item.uri], function (err) {
                    if (t) t.show(err ? err.hint : qsTr("Zu „%1“ hinzugefügt").arg(playlist.name), !!err)
                })
            }
        })
    }

    function addToLibrary() {
        var t = toast
        store.addToLibrary(mediaItem.uri, function (err) {
            if (err) {
                if (t) t.show(err.hint, true)
                return
            }
            row.libraryOverride = true
            if (t) t.show(qsTr("In die Bibliothek aufgenommen"))
        })
    }

    function removeFromLibrary() {
        var item = mediaItem
        var t = toast
        var playerStore = store
        remorseAction(qsTr("Wird aus der Bibliothek entfernt"), function () {
            playerStore.removeFromLibrary(item.media_type, item.item_id, function (err) {
                if (err) {
                    if (t) t.show(err.hint, true)
                    return
                }
                row.removed = true
                if (t) t.show(qsTr("Aus der Bibliothek entfernt"))
            })
        })
    }

    menu: ContextMenu {
        MenuItem {
            text: qsTr("Jetzt spielen")
            onClicked: row.enqueue("play", qsTr("Läuft auf %1"))
        }
        MenuItem {
            text: qsTr("Ähnliches abspielen")
            visible: row.canPlaySimilar
            onClicked: row.playSimilar()
        }
        MenuItem {
            text: qsTr("Als Nächstes")
            onClicked: row.enqueue("next", qsTr("Als Nächstes auf %1"))
        }
        MenuItem {
            text: qsTr("Anhängen")
            onClicked: row.enqueue("add", qsTr("Angehängt auf %1"))
        }
        MenuItem {
            text: qsTr("Zur Playlist hinzufügen …")
            visible: row.canAddToPlaylist
            onClicked: row.pickPlaylist()
        }
        MenuItem {
            text: qsTr("Aus dieser Playlist entfernen")
            visible: row.playlistPosition > 0
            onClicked: row.removeFromPlaylistRequested()
        }
        MenuItem {
            text: row.isPlayed ? qsTr("Als nicht gehört markieren") : qsTr("Als gehört markieren")
            visible: row.canMarkPlayed
            onClicked: row.setPlayed(!row.isPlayed)
        }
        MenuItem {
            text: qsTr("Beschreibung")
            visible: row.hasInfo
            onClicked: row.infoRequested()
        }
        MenuItem {
            text: row.isFavorite ? qsTr("Aus Favoriten") : qsTr("Zu Favoriten")
            // Ein bereits markierter Eintrag, der nicht in der Bibliothek
            // liegt, lässt sich nicht wieder abwählen -- dann lieber keinen
            // Eintrag zeigen als einen, der scheitert.
            visible: !row.isFavorite || row.canUnfavorite
            onClicked: row.toggleFavorite()
        }
        MenuItem {
            text: qsTr("In die Bibliothek aufnehmen")
            visible: row.canAddToLibrary
            onClicked: row.addToLibrary()
        }
        MenuItem {
            text: qsTr("Aus der Bibliothek entfernen")
            visible: row.canRemoveFromLibrary && !row.removed
            onClicked: row.removeFromLibrary()
        }
    }

    // Kleiner Stern am rechten Rand, damit man Favoriten in der Liste sieht,
    // ohne jede Zeile aufzuklappen.
    Image {
        id: favoriteMark
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        source: "image://theme/icon-s-favorite"
        visible: row.isFavorite
        opacity: 0.8
    }
}
