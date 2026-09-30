import QtQuick 2.6
import Sailfish.Silica 1.0
import "../lib/MassModels.js" as Models

// Eine Playlist wählen, zu der etwas hinzugefügt werden soll. Angeboten
// werden nur bearbeitbare (`is_editable`), dazu "Neue Playlist …".
//
// Die Seite fügt nicht selbst hinzu, sondern gibt die Wahl an `pickHandler`
// weiter -- der gehört zur aufrufenden Seite, kennt deren Rückmeldung und lebt
// noch, wenn diese Seite längst geschlossen ist (die Antwort des Servers kann
// dauern).
Page {
    id: page

    property var mass
    property var store
    // Was hinzugefügt wird, nur für die Überschrift.
    property string itemName: ""
    // function(playlist) -- playlist ist ein Playlist-Objekt des Servers.
    property var pickHandler

    allowedOrientations: defaultAllowedOrientations

    property var playlists: []
    property bool loading: true
    property string errorText: ""

    function pick(playlist) {
        var handler = pickHandler
        pageStack.pop()
        if (handler) {
            handler(playlist)
        }
    }

    Component.onCompleted: {
        if (!store) {
            return
        }
        store.editablePlaylists(function (err, list) {
            page.loading = false
            if (err) {
                page.errorText = err.hint
                return
            }
            page.playlists = list
        })
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.playlists

        header: Column {
            width: listView.width

            PageHeader {
                title: qsTr("Zur Playlist hinzufügen")
                description: page.itemName
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeMedium
                enabled: mass && mass.ready
                onClicked: {
                    // Nach "Speichern" direkt zurück zur aufrufenden Seite --
                    // über acceptDestination, denn ein eigenes pop() während
                    // der Übergangsanimation des Dialogs verweigert Silica.
                    var handler = page.pickHandler
                    var playerStore = page.store
                    var dialog = pageStack.push(Qt.resolvedUrl("SavePlaylistDialog.qml"),
                                                { defaultName: "",
                                                  acceptDestination: pageStack.previousPage(page),
                                                  acceptDestinationAction: PageStackAction.Pop })
                    dialog.accepted.connect(function () {
                        var name = dialog.playlistName
                        playerStore.createPlaylist(name, function (err, created) {
                            if (handler) {
                                handler(err ? { error: err } : created)
                            }
                        })
                    })
                }

                Label {
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Neue Playlist …")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }

            SectionHeader {
                text: qsTr("Eigene Playlists")
                visible: page.playlists.length > 0
            }
        }

        ViewPlaceholder {
            enabled: page.playlists.length === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Fehler") : qsTr("Keine bearbeitbaren Playlists")
            hintText: page.errorText.length > 0
                      ? page.errorText
                      : qsTr("Mit „Neue Playlist …“ oben lässt sich eine anlegen")
        }

        delegate: BackgroundItem {
            width: listView.width
            height: Theme.itemSizeMedium
            onClicked: page.pick(modelData)

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: modelData.name
                    color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    visible: text.length > 0
                    text: store ? store.sourceName(modelData.provider_mappings && modelData.provider_mappings[0]
                                                   ? { provider: modelData.provider_mappings[0].provider_instance }
                                                   : modelData) : ""
                }
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading
        size: BusyIndicatorSize.Large
    }
}
