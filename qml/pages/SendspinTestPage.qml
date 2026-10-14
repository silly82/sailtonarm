import QtQuick 2.6
import Sailfish.Silica 1.0

// Stufe 5a, nur in der OpenRepos-Variante (KONZEPT.md Abschnitt 38): der
// verschlüsselte Sendspin-Handshake mit dem Server, ohne Ton. Zeigt das
// Protokoll der Verbindung; am Ende verabschiedet sich die App wieder.
Page {
    id: page

    property bool done: false

    Connections {
        target: Sendspin
        onServerHelloReceived: closeTimer.start()
    }

    // Kurz verbunden bleiben, falls der Server noch etwas schickt, dann gehen.
    Timer {
        id: closeTimer
        interval: 1500
        onTriggered: {
            Sendspin.close()
            page.done = true
        }
    }

    Component.onCompleted: Sendspin.openForServer(Credentials.baseUrl)
    Component.onDestruction: Sendspin.close()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Erneut versuchen")
                onClicked: {
                    page.done = false
                    Sendspin.close()
                    Sendspin.openForServer(Credentials.baseUrl)
                }
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("Sendspin-Test") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: Sendspin.serverName.length > 0
                      ? qsTr("Verschlüsselt verbunden mit „%1“.").arg(Sendspin.serverName)
                      : Sendspin.state === 4 /* Failed */
                        ? qsTr("Fehlgeschlagen: %1").arg(Sendspin.lastError)
                        : qsTr("Verbinde …")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WrapAnywhere
                font.pixelSize: Theme.fontSizeExtraSmall
                font.family: "Monospace"
                color: Theme.secondaryColor
                text: Sendspin.logText
            }
        }

        VerticalScrollDecorator {}
    }
}
