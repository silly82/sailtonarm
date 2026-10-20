import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// Nur in der OpenRepos-Variante (KONZEPT.md Abschnitt 38): verschlüsselter
// Sendspin-Handshake und Anmeldung als Player unter dem eingestellten Namen.
// Mit dem Schalter meldet sich der Player verfügbar, sobald die Uhr
// abgeglichen ist, und spielt, was Music Assistant schickt (Stufe 5c).
// Die Verbindung bleibt, solange die Seite offen ist.
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
        Sendspin.playbackEnabled = false
        Sendspin.playerName = nameSetting.value
        Sendspin.openForServer(Credentials.baseUrl)
    }

    // Per URL geladen, damit die Seite selbst nichts aus Nemo.Policy importiert.
    Loader {
        active: Sendspin.streaming
        source: "../components/SendspinVolumeKeys.qml"
        onLoaded: item.active = true
    }

    Component.onCompleted: connect()
    Component.onDestruction: {
        Sendspin.playbackEnabled = false
        Sendspin.close()
    }

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
                      ? qsTr("Als Player „%1“ bei „%2“ angemeldet.")
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

            TextSwitch {
                visible: page.registered
                text: qsTr("Als Lautsprecher verfügbar")
                description: Sendspin.available
                             ? (Sendspin.streaming ? qsTr("Spielt, Lautstärke %1 %%2. Die Lautstärketasten stellen sie.").arg(Sendspin.volume)
                                                     .arg(Sendspin.muted ? qsTr(", stumm") : "")
                                                   : qsTr("Verfügbar. In Music Assistant auswählen, dann spielt das Telefon."))
                             : Sendspin.playbackEnabled ? qsTr("Uhr wird abgeglichen …")
                                                        : qsTr("Aus: Music Assistant schickt keinen Ton.")
                checked: Sendspin.playbackEnabled
                automaticCheck: false
                onClicked: Sendspin.playbackEnabled = !checked
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WrapAnywhere
                font.pixelSize: Theme.fontSizeExtraSmall
                font.family: "Monospace"
                color: Theme.highlightColor
                visible: text.length > 0
                text: Sendspin.syncText
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
