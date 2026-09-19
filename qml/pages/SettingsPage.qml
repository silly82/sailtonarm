import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../lib/MassApi.js" as MassApi

Page {
    id: page

    property var mass

    allowedOrientations: Orientation.All

    // Ergebnis des /info-Tests -- die einzige Route des Servers, die ohne Token
    // antwortet. Damit lässt sich "Adresse falsch" von "Token falsch" trennen,
    // bevor überhaupt ein Socket aufgemacht wird.
    property string probeState: ""      // "" | "running" | "ok" | "failed"
    property string probeText: ""
    property var _probeHandle: null

    // Geschrieben wird erst, wenn beide Felder ausgefüllt sind und sich
    // gegenüber dem gespeicherten Stand geändert haben -- dem Secrets-Daemon
    // zuliebe (jeder Tastendruck wäre sonst ein Request) und damit ein halb
    // ausgefülltes Feld den gültigen Satz nicht überschreibt. Ausgelöst beim
    // Fokusverlust und beim Verlassen der Seite.
    function saveIfComplete() {
        var url = MassApi.normalizeBaseUrl(baseUrlField.text)
        if (url.length === 0 || tokenField.text.length === 0) {
            return
        }
        if (url === Credentials.baseUrl && tokenField.text === Credentials.token) {
            return
        }
        Credentials.save(url, tokenField.text)
    }

    function testConnection() {
        var url = MassApi.normalizeBaseUrl(baseUrlField.text)
        if (url.length === 0) {
            probeState = "failed"
            probeText = qsTr("Bitte zuerst eine Adresse eintragen.")
            return
        }
        probeState = "running"
        probeText = qsTr("Frage %1 ab …").arg(url + "/info")
        _probeHandle = MassApi.fetchServerInfo(url, 8000, function (info) {
            probeTimeout.stop()
            page.probeState = "ok"
            page.probeText = qsTr("Erreichbar: %1 (Version %2, API-Schema %3)")
                .arg(info.name || qsTr("Music Assistant"))
                .arg(info.server_version)
                .arg(info.schema_version)
        }, function (err) {
            probeTimeout.stop()
            page.probeState = "failed"
            page.probeText = err.hint + (err.detail ? " — " + err.detail : "")
        })
        probeTimeout.restart()
    }

    onStatusChanged: if (status === PageStatus.Deactivating) saveIfComplete()

    // QMLs XMLHttpRequest ruft bei einem nicht erreichbaren Host keinen der
    // beiden Callbacks auf, bis das TCP-Timeout des Systems nach Minuten
    // aufgibt. Ohne diesen Wecker bliebe "Frage ab …" ewig stehen.
    Timer {
        id: probeTimeout
        interval: 8000
        repeat: false
        onTriggered: if (page._probeHandle) page._probeHandle.abort()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("Einstellungen") }

            TextField {
                id: baseUrlField
                width: parent.width
                label: qsTr("Serveradresse")
                placeholderText: qsTr("musicassistant.local")
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                text: Credentials.baseUrl
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: tokenField.focus = true
                onActiveFocusChanged: if (!activeFocus) page.saveIfComplete()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Ohne Angabe wird http:// und Port 8095 ergänzt. Ergibt: %1")
                      .arg(MassApi.normalizeBaseUrl(baseUrlField.text) || "—")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Läuft Music Assistant als Home-Assistant-App, ist das die Adresse des HA-Rechners: die App benutzt das Host-Netz, Port 8095 liegt also direkt dort. Nicht die Ingress-Adresse aus der HA-Oberfläche.")
            }

            TextField {
                id: tokenField
                width: parent.width
                label: qsTr("Zugriffstoken")
                placeholderText: qsTr("in MA: Einstellungen → Profil")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                text: Credentials.token
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
                onActiveFocusChanged: if (!activeFocus) page.saveIfComplete()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.errorColor
                visible: Credentials.lastError.length > 0
                text: qsTr("Speichern fehlgeschlagen: %1").arg(Credentials.lastError)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Adresse und Token werden über Sailfish Secrets verschlüsselt gespeichert und sind an die Gerätesperre gebunden. Gespeichert wird, sobald beide Felder ausgefüllt sind und den Fokus verlassen.")
            }

            SectionHeader { text: qsTr("Prüfen") }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: probeState === "running" ? qsTr("prüfe …") : qsTr("Server erreichbar?")
                enabled: probeState !== "running"
                onClicked: page.testConnection()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                visible: probeText.length > 0
                text: probeText
                color: probeState === "failed" ? Theme.errorColor
                                               : Theme.secondaryHighlightColor
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Der Test spricht nur /info an — die einzige Route ohne Anmeldung. Er sagt also, ob der Server erreichbar ist, nicht ob das Token gültig ist. Das zeigt die Startseite.")
            }

            SectionHeader { text: qsTr("Benachrichtigungen") }

            TextSwitch {
                width: parent.width
                text: qsTr("Bei jedem Titelwechsel melden")
                description: qsTr("Standardmässig aus: bei einem Titel alle paar Minuten füllt das schnell den Benachrichtigungsbereich. Cover und Sperrbildschirm zeigen den laufenden Titel ohnehin.")
                checked: notifySetting.value === true
                automaticCheck: false
                onClicked: notifySetting.value = !checked
            }

            ConfigurationValue {
                id: notifySetting
                key: "/apps/harbour-tonarm/notifyOnTrackChange"
                defaultValue: false
            }

            // Was der Server über sich meldet -- stand bis Ausbaustufe 0 auf
            // der Startseite, die jetzt die Player zeigt. Als Diagnose bleibt
            // es nützlich, gehört aber nicht mehr in den täglichen Weg.
            SectionHeader {
                text: qsTr("Verbindung")
                visible: mass && mass.serverInfo !== null
            }

            DetailItem {
                label: qsTr("Server")
                value: (mass && mass.serverInfo && mass.serverInfo.name)
                       ? mass.serverInfo.name : qsTr("unbenannt")
                visible: mass && mass.serverInfo !== null
            }
            DetailItem {
                label: qsTr("Version")
                value: (mass && mass.serverInfo) ? mass.serverInfo.server_version : ""
                visible: mass && mass.serverInfo !== null
            }
            DetailItem {
                label: qsTr("API-Schema")
                value: (mass && mass.serverInfo)
                       ? qsTr("%1 (unterstützt ab %2)")
                         .arg(mass.serverInfo.schema_version)
                         .arg(mass.serverInfo.min_supported_schema_version)
                       : ""
                visible: mass && mass.serverInfo !== null
            }
            DetailItem {
                label: qsTr("Angemeldet als")
                value: (mass && mass.userName.length > 0) ? mass.userName : qsTr("—")
                visible: mass && mass.connectionState === "ready"
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.errorColor
                visible: mass && mass.compatibilityWarning.length > 0
                text: mass ? mass.compatibilityWarning : ""
            }

            SectionHeader { text: qsTr("Zugangsdaten") }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Zugangsdaten löschen")
                enabled: !Credentials.saveBusy
                         && (Credentials.baseUrl.length > 0 || Credentials.token.length > 0)
                onClicked: remorse.execute(qsTr("Zugangsdaten werden gelöscht"), function () {
                    Credentials.clear()
                    baseUrlField.text = ""
                    tokenField.text = ""
                })
            }

            // Die Verbindung zieht bei geänderten Zugangsdaten von selbst nach
            // (MassConnection bindet an Credentials). Der Knopf ist für den
            // Fall, dass der Server zwischendurch neu gestartet wurde und man
            // nicht auf den nächsten Reconnect-Versuch warten will.
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Jetzt neu verbinden")
                enabled: mass && mass.configured
                onClicked: {
                    page.saveIfComplete()
                    mass.autoConnect = true
                    mass.connectNow()
                }
            }
        }

        VerticalScrollDecorator {}
    }

    // Ausserhalb der Column: ein RemorsePopup ist ein Item und würde dort
    // Platz in der Anordnung beanspruchen.
    RemorsePopup { id: remorse }
}
