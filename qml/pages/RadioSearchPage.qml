import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models

// Sender suchen und in die Bibliothek aufnehmen. Gesucht wird über alle
// Anbieter mit Radio -- auf der eigenen Anlage RadioBrowser, das weltweite
// Senderverzeichnis. Ein Tipper nimmt den Sender auf; spielen geht wie überall
// über das Kontextmenü. Für Sender, die in keinem Verzeichnis stehen: eigene
// Stream-Adresse im Pulley-Menü.
Page {
    id: page

    property var mass
    property var store

    allowedOrientations: defaultAllowedOrientations

    property var results: []
    property bool loading: false
    property bool searched: false
    property string query: ""
    property string errorText: ""

    function search() {
        if (!mass || !mass.ready || query.length === 0) {
            return
        }
        loading = true
        errorText = ""
        var asked = query
        mass.sendCommand("music/search", { search_query: asked, media_types: ["radio"], limit: 40 },
                         function (err, result) {
            if (asked !== page.query) {
                return
            }
            page.loading = false
            page.searched = true
            if (err) {
                page.errorText = err.hint
                page.results = []
                return
            }
            page.results = (result && result.radio) || []
        }, 60000)
    }

    function addStation(item, row) {
        if (item.provider === "library" || row.inLibrary) {
            pageToast.show(qsTr("Schon in der Bibliothek"))
            return
        }
        var t = pageToast
        store.addToLibrary(item.uri, function (err) {
            if (err) {
                t.show(err.hint, true)
                return
            }
            row.libraryOverride = true
            t.show(qsTr("„%1“ aufgenommen").arg(item.name))
        })
    }

    Timer {
        id: debounce
        interval: 500
        onTriggered: page.search()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.results

        header: Column {
            width: listView.width

            PageHeader { title: qsTr("Sender hinzufügen") }

            SearchField {
                width: parent.width
                placeholderText: qsTr("Sendername, z. B. SRF 1")
                inputMethodHints: Qt.ImhNoAutoUppercase
                focus: true
                onTextChanged: {
                    page.query = text.trim()
                    if (page.query.length === 0) {
                        page.results = []
                        page.searched = false
                        debounce.stop()
                    } else {
                        debounce.restart()
                    }
                }
                EnterKey.iconSource: "image://theme/icon-m-search"
                EnterKey.onClicked: {
                    debounce.stop()
                    page.search()
                }
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Eigene Stream-Adresse …")
                enabled: mass && mass.ready
                onClicked: {
                    var t = pageToast
                    var playerStore = page.store
                    var dialog = pageStack.push(Qt.resolvedUrl("AddRadioDialog.qml"))
                    dialog.accepted.connect(function () {
                        var name = dialog.stationName
                        playerStore.addRadioByUrl(name, dialog.streamUrl, function (err) {
                            t.show(err ? err.hint : qsTr("„%1“ aufgenommen").arg(name), !!err)
                        })
                    })
                }
            }
        }

        ViewPlaceholder {
            enabled: page.results.length === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Fehler")
                  : (page.searched ? qsTr("Nichts gefunden") : qsTr("Sender suchen"))
            hintText: page.errorText.length > 0 ? page.errorText
                      : (page.searched ? "" : qsTr("Ein Tippen nimmt den Sender in die Bibliothek auf"))
        }

        delegate: MediaListItem {
            id: stationRow
            mass: page.mass
            store: page.store
            toast: pageToast
            mediaItem: modelData
            subtitle: inLibrary ? qsTr("in der Bibliothek") : (store ? store.sourceName(modelData) : "")
            onActivated: page.addStation(modelData, stationRow)
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading
        size: BusyIndicatorSize.Large
    }

    StatusToast { id: pageToast }
}
