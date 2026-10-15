import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// Nur in der OpenRepos-Variante (KONZEPT.md Abschnitt 38): verschlüsselter
// Sendspin-Handshake und Anmeldung als Player unter dem eingestellten Namen.
// Noch ohne Ton (Stufe 5c), deshalb meldet sich der Player als nicht
// verfügbar. Die Verbindung bleibt, solange die Seite offen ist.
Page {
    id: page

    readonly property bool registered: Sendspin.activeRoles.indexOf("player@v1") >= 0

    ConfigurationValue {
        id: nameSetting
        key: "/apps/harbour-tonarm/sendspinName"
        defaultValue: ""
    }

    function connect() {
        Sendspin.close()
        Sendspin.playerName = nameSetting.value
        Sendspin.openForServer(Credentials.baseUrl)
    }

    Component.onCompleted: connect()
    Component.onDestruction: Sendspin.close()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Erneut versuchen")
                onClicked: page.connect()
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
                text: page.registered
                      ? qsTr("Als Player „%1“ bei „%2“ angemeldet. Noch ohne Ton; der Player bleibt nicht verfügbar.")
                        .arg(Sendspin.playerName.length > 0 ? Sendspin.playerName : Sendspin.defaultPlayerName)
                        .arg(Sendspin.serverName)
                      : Sendspin.serverName.length > 0
                        ? qsTr("Verschlüsselt verbunden mit „%1“.").arg(Sendspin.serverName)
                        : Sendspin.state === 4 /* Failed */
                          ? qsTr("Fehlgeschlagen: %1").arg(Sendspin.lastError)
                          : qsTr("Verbinde …")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                visible: page.registered
                text: qsTr("Beim Verlassen der Seite meldet sich das Telefon wieder ab.")
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
