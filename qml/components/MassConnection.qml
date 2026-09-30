import QtQuick 2.6
import QtWebSockets 1.0
import "../lib/MassApi.js" as MassApi

// Die eine WebSocket-Verbindung zum Music-Assistant-Server: Handshake,
// Kommandoversand mit Antwortzuordnung, Ereignisverteilung, Reconnect.
//
// Bewusst *ein* Objekt, im Wurzelfenster angelegt und den Seiten per Property
// mitgegeben (siehe harbour-tonarm.qml) -- kein QML-Singleton: die brauchten
// eine qmldir-Datei und haben sich anderswo in diesem Setup als unzuverlässig
// erwiesen. Explizite Weitergabe ist langweilig und funktioniert.
//
// Ablauf laut Server (music_assistant/controllers/webserver/websocket_client.py):
//   1. Socket offen -> der Server schickt unaufgefordert ServerInfoMessage
//   2. Client schickt {command: "auth", args: {token, locale}}
//   3. Server antwortet mit {message_id, result: {authenticated: true, user: ...}}
//      und abonniert den Client ab da automatisch auf alle Events
// Ein Server ganz ohne angelegte Benutzer authentifiziert von sich aus -- dann
// bleibt Schritt 2 ohne Token trotzdem erfolgreich, siehe onTextMessageReceived.
Item {
    id: conn

    // --- Konfiguration ---------------------------------------------------
    property string baseUrl: ""
    // Optionale zweite Adresse desselben Servers für unterwegs (VPN,
    // Tailscale, Reverse-Proxy), siehe _startAttempt().
    property string awayUrl: ""
    property string token: ""
    property bool autoConnect: true
    // Gegenstück zu DemoConnection.isDemo.
    readonly property bool isDemo: false
    // Erst verbinden, wenn die Zugangsdaten vollständig geladen sind -- sonst
    // ginge das erste auth mit leerem Token raus, weil Credentials Adresse,
    // Token und Unterwegs-Adresse nacheinander liefert.
    property bool startAllowed: true

    readonly property bool configured: MassApi.normalizeBaseUrl(baseUrl).length > 0
    readonly property bool hasAway: {
        var away = MassApi.normalizeBaseUrl(awayUrl)
        return away.length > 0 && away !== MassApi.normalizeBaseUrl(baseUrl)
    }

    // --- Zustand nach aussen ---------------------------------------------
    // "idle" | "connecting" | "authenticating" | "ready" | "error"
    // Heisst nicht "state": Item bringt bereits eine Property dieses Namens mit
    // (Zustandsgruppen), und die zu überschatten geht schief.
    property string connectionState: "idle"
    property string lastError: ""
    property var serverInfo: null
    property string userName: ""
    readonly property bool ready: connectionState === "ready"
    readonly property string compatibilityWarning:
        serverInfo ? MassApi.compatibilityWarning(serverInfo) : ""
    // Aus baseUrl abgeleitet, damit Cover-Art ab Ausbaustufe 2 ohne
    // Authorization-Header geladen werden kann (siehe MassApi.streamBaseUrl).
    readonly property string streamBaseUrl: MassApi.streamBaseUrl(baseUrl)

    // Die Adresse, über die die Verbindung gerade tatsächlich läuft -- für
    // alle Bildadressen. Ohne Verbindung die Heimadresse.
    readonly property string activeBaseUrl: _winnerUrl.length > 0
                                            ? _winnerUrl : MassApi.normalizeBaseUrl(baseUrl)
    // "home" | "away" | "" -- für die Anzeige in den Einstellungen.
    property string connectedVia: ""

    // Ein Ereignis vom Server. eventType ist der MassEvent-Name
    // ("player_updated", "queue_updated", ...), message die ganze Nachricht
    // (event, object_id, data).
    signal serverEvent(string eventType, var message)
    signal authenticated()
    // Die App war im Hintergrund oder das Telefon hat geschlafen, und die
    // Verbindung hat die Rückkehr überlebt. Ereignisse aus der Zwischenzeit
    // können aber verloren sein -- wer Zustand hält, lädt ihn neu.
    signal resynced()

    // Erst nach etwa 1,5 s ohne Verbindung wahr. Ein kurzes Neuverbinden
    // (Rückkehr aus dem Hintergrund, Netzwechsel) soll nicht als Fehlerzeile
    // aufblitzen; hält der Zustand an, steht er da.
    property bool problemVisible: false

    // --- Intern ----------------------------------------------------------
    property int _nextId: 1
    // message_id -> { callback: function(err, result), items: [], timeoutAt: ms }
    property var _pending: ({})
    property int _backoffMs: 2000
    // Nur wahr zwischen "Socket offen" und "auth-Antwort da" -- verhindert,
    // dass ein zweites auth rausgeht, wenn der Server ServerInfo erneut
    // schickt.
    property bool _authSent: false
    // Der Socket, der das Rennen gewonnen hat (siehe _startAttempt), und
    // dessen Stammadresse. null, solange keiner gewonnen hat.
    property var _winner: null
    property string _winnerUrl: ""
    property bool _racing: false

    // --- API -------------------------------------------------------------

    // Schickt ein Kommando. callback(err, result): err ist null bei Erfolg,
    // sonst { hint, detail }. Kommandos vor dem Verbindungsaufbau werden
    // abgelehnt statt gepuffert -- in Ausbaustufe 0 ruft nur die UI auf, und
    // die kennt den Zustand.
    //
    // Fehler, die nur sagen "gerade keine Verbindung", tragen `offline: true`:
    // die Statuszeile erklärt das bereits, Aufrufer zeigen sie nicht noch
    // einmal an.
    //
    // timeoutMs ist optional (Standard 20 s).
    function sendCommand(command, args, callback, timeoutMs) {
        if (connectionState !== "ready") {
            if (callback) {
                callback({ hint: qsTr("Keine Verbindung"), detail: connectionState,
                           offline: true }, null)
            }
            return -1
        }
        return _send(command, args, callback, timeoutMs)
    }

    // Sofort (neu) verbinden, ohne Backoff -- aus den Einstellungen, per
    // Tippen auf die Statuszeile und nach einer toten Verbindung.
    function connectNow() {
        reconnectTimer.stop()
        _backoffMs = 2000
        lastError = ""
        _failAllPending({ hint: qsTr("Verbindung wird neu aufgebaut"), detail: "", offline: true })
        _startAttempt()
    }

    function disconnect() {
        reconnectTimer.stop()
        autoConnect = false
        _stopSockets()
        _failAllPending({ hint: qsTr("Verbindung getrennt"), detail: "" })
        connectionState = "idle"
    }

    // --- Implementierung -------------------------------------------------

    // Beim Zurückkommen in den Vordergrund: steht die Verbindung noch? Ein
    // Socket kann nach dem Schlafen tot sein, während der Zustand weiterhin
    // "ready" sagt -- dann liefe jeder Tipper 20 s in die Zeitüberschreitung.
    // Also ein billiges `info` mit kurzer Frist: keine Antwort heisst sofort
    // neu verbinden, eine Antwort heisst neu laden, was verpasst sein kann.
    // Wartet gerade ein Reconnect mit langem Backoff, wird er vorgezogen.
    function checkAfterResume() {
        if (!configured || !autoConnect) {
            return
        }
        if (connectionState === "ready") {
            sendCommand("info", {}, function (err) {
                if (err) {
                    console.log("MassConnection: keine Antwort nach Rückkehr, verbinde neu")
                    conn.connectNow()
                } else {
                    conn.resynced()
                }
            }, 3000)
        } else if (connectionState === "error" || connectionState === "idle") {
            connectNow()
        }
    }

    function _send(command, args, callback, timeoutMs) {
        var id = _nextId
        _nextId += 1
        if (callback) {
            _pending[String(id)] = {
                callback: callback,
                items: [],
                command: command,
                deadline: Date.now() + (timeoutMs > 0 ? timeoutMs : 20000)
            }
            timeoutTimer.start()
        }
        _winner.sendTextMessage(MassApi.commandMessage(id, command, args))
        return id
    }

    function _failAllPending(err) {
        var keys = Object.keys(_pending)
        for (var i = 0; i < keys.length; i++) {
            var entry = _pending[keys[i]]
            delete _pending[keys[i]]
            if (entry && entry.callback) {
                entry.callback(err, null)
            }
        }
        timeoutTimer.stop()
    }

    function _handleResult(msg) {
        var key = String(msg.message_id)
        var entry = _pending[key]
        if (!entry) {
            // Antwort auf ein Kommando ohne Callback (oder auf eines, das schon
            // in die Zeitüberschreitung gelaufen ist) -- nichts zu tun.
            return
        }

        // Grosse Listen kommen in Stücken zu je 500 Einträgen: jede Teilantwort
        // trägt partial: true, die letzte partial: false (bzw. gar kein Feld).
        // Erst dann ist das Ergebnis vollständig.
        if (msg.partial === true) {
            if (msg.result && msg.result.length !== undefined) {
                entry.items = entry.items.concat(msg.result)
            }
            return
        }

        delete _pending[key]
        var result = msg.result
        if (entry.items.length > 0) {
            result = entry.items.concat(
                (result && result.length !== undefined) ? result : [])
        }
        if (Object.keys(_pending).length === 0) {
            timeoutTimer.stop()
        }
        entry.callback(null, result)
    }

    function _handleError(msg) {
        var key = String(msg.message_id)
        var entry = _pending[key]
        var err = { hint: MassApi.errorText(msg), detail: "Code " + msg.error_code }
        if (!entry) {
            lastError = err.hint
            return
        }
        delete _pending[key]
        if (Object.keys(_pending).length === 0) {
            timeoutTimer.stop()
        }
        entry.callback(err, null)
    }

    function _sendAuth() {
        if (_authSent) {
            return
        }
        _authSent = true
        connectionState = "authenticating"
        // device_name: damit der Server den Client beim Namen führt statt als
        // namenlose Sitzung.
        _send("auth", { token: token, locale: Qt.locale().name,
                        device_name: "Tonarm (Sailfish)" }, function (err, result) {
            if (err) {
                // Ein Server ohne angelegte Benutzer braucht kein Token und
                // lehnt den leeren auth-Aufruf trotzdem ab -- die Verbindung
                // ist in dem Fall aber bereits nutzbar. Statt hier zu raten,
                // wird der Fehler gezeigt und ein Testkommando entscheidet.
                conn.lastError = err.hint
                conn.connectionState = "error"
                return
            }
            conn.userName = (result && result.user && result.user.username)
                    ? result.user.username : ""
            conn.lastError = ""
            conn.connectionState = "ready"
            conn._backoffMs = 2000
            conn.authenticated()
        })
    }

    // --- Zwei Adressen ----------------------------------------------------
    //
    // Ein Verbindungsversuch ist ein Rennen: die Heimadresse startet sofort,
    // die Adresse für unterwegs 0,5 s später (oder sofort, wenn die
    // Heimadresse vorher scheitert). Der erste Socket, von dem ServerInfo
    // kommt, gewinnt; der andere wird geschlossen. Zu Hause antwortet das LAN
    // in Millisekunden, die Unterwegs-Adresse wird also nie angefasst.
    //
    // Jeder Versuch beginnt wieder mit der Heimadresse -- nach einem
    // Netzwechsel (erkannt über die Rückkehr aus dem Hintergrund, siehe
    // checkAfterResume) ist das die richtige Reihenfolge.
    //
    // Statusmeldungen eines Sockets, den die App selbst geschlossen hat
    // (`active` false), werden ignoriert: das ist der Verlierer eines Rennens
    // oder ein Versuch, der gerade durch einen neuen ersetzt wird.

    function _startAttempt() {
        _stopSockets()
        if (!autoConnect || !configured || !startAllowed) {
            connectionState = "idle"
            return
        }
        connectionState = "connecting"
        _racing = true
        homeSocket.url = MassApi.wsUrl(baseUrl)
        homeSocket.active = true
        if (hasAway) {
            awayTimer.restart()
        }
        attemptTimer.restart()
    }

    function _startAway() {
        if (!_racing || _winner !== null || !hasAway || awaySocket.active) {
            return
        }
        awayTimer.stop()
        awaySocket.url = MassApi.wsUrl(awayUrl)
        awaySocket.active = true
    }

    function _stopSockets() {
        awayTimer.stop()
        attemptTimer.stop()
        _racing = false
        _winner = null
        _winnerUrl = ""
        connectedVia = ""
        _authSent = false
        userName = ""
        homeSocket.active = false
        awaySocket.active = false
    }

    function _scheduleReconnect(wasReady) {
        if (!autoConnect || !configured) {
            return
        }
        // Nach einer stabilen Verbindung wieder kurz warten, sonst den
        // Abstand verdoppeln -- ein dauerhaft nicht erreichbarer Server soll
        // nicht im Sekundentakt angepingt werden.
        if (wasReady) {
            _backoffMs = 2000
        }
        reconnectTimer.interval = _backoffMs
        reconnectTimer.restart()
    }

    function _attemptFailed(reason) {
        _stopSockets()
        if (reason) {
            lastError = reason
        }
        connectionState = configured ? "error" : "idle"
        _failAllPending({ hint: qsTr("Verbindung abgebrochen"), detail: lastError, offline: true })
        _scheduleReconnect(false)
    }

    function _onSocketStatus(sock) {
        if (!sock.active) {
            return
        }
        if (sock.status !== WebSocket.Closed && sock.status !== WebSocket.Error) {
            return
        }
        var reason = (sock.status === WebSocket.Error && sock.errorString)
                ? sock.errorString : ""
        if (sock === _winner) {
            // Eine stehende Verbindung ist abgerissen.
            var wasReady = connectionState === "ready"
            _stopSockets()
            if (reason) {
                lastError = reason
            }
            connectionState = configured ? "error" : "idle"
            _failAllPending({ hint: qsTr("Verbindung abgebrochen"), detail: lastError, offline: true })
            _scheduleReconnect(wasReady)
            return
        }
        sock.active = false
        if (_winner !== null || !_racing) {
            return
        }
        // Im Rennen gescheitert. Die Heimadresse als erste: dann nicht die
        // halbe Sekunde abwarten, sondern die andere sofort starten.
        if (sock === homeSocket && hasAway && !awaySocket.active) {
            lastError = reason
            _startAway()
            return
        }
        if (homeSocket.active || awaySocket.active) {
            lastError = reason
            return
        }
        _attemptFailed(reason)
    }

    function _onSocketMessage(sock, message) {
        var msg
        try {
            msg = JSON.parse(message)
        } catch (e) {
            lastError = qsTr("Unlesbare Nachricht vom Server")
            return
        }

        var kind = MassApi.classify(msg)
        if (kind === "server_info" && _winner === null && _racing) {
            _winner = sock
            _racing = false
            awayTimer.stop()
            attemptTimer.stop()
            var viaHome = sock === homeSocket
            _winnerUrl = MassApi.normalizeBaseUrl(viaHome ? baseUrl : awayUrl)
            connectedVia = viaHome ? "home" : "away"
            // Den Verlierer schliessen; seine Statusmeldung wird ignoriert.
            if (viaHome) {
                awaySocket.active = false
            } else {
                homeSocket.active = false
            }
            console.log("MassConnection: verbunden über", viaHome ? "Heimadresse" : "Unterwegs-Adresse")
        }
        if (sock !== _winner) {
            return
        }

        switch (kind) {
        case "server_info":
            serverInfo = msg
            _sendAuth()
            break
        case "result":
            _handleResult(msg)
            break
        case "error":
            _handleError(msg)
            break
        case "event":
            serverEvent(msg.event, msg)
            break
        default:
            break
        }
    }

    WebSocket {
        id: homeSocket
        active: false
        onStatusChanged: conn._onSocketStatus(homeSocket)
        onTextMessageReceived: conn._onSocketMessage(homeSocket, message)
    }

    WebSocket {
        id: awaySocket
        active: false
        onStatusChanged: conn._onSocketStatus(awaySocket)
        onTextMessageReceived: conn._onSocketMessage(awaySocket, message)
    }

    Timer {
        id: awayTimer
        interval: 500
        onTriggered: conn._startAway()
    }

    // Eine Adresse, die nicht antwortet, hängt sonst bis zum TCP-Timeout des
    // Systems (Minuten) auf "Verbinde …".
    Timer {
        id: attemptTimer
        interval: 10000
        onTriggered: {
            if (conn._winner === null) {
                conn._attemptFailed(qsTr("Zeitüberschreitung beim Verbinden"))
            }
        }
    }

    // Geänderte Zugangsdaten verbinden neu. Kurz gesammelt, weil Credentials
    // mehrere Werte nacheinander setzt.
    Timer {
        id: restartTimer
        interval: 50
        onTriggered: conn.connectNow()
    }
    onBaseUrlChanged: restartTimer.restart()
    onAwayUrlChanged: restartTimer.restart()
    onAutoConnectChanged: if (autoConnect) restartTimer.restart()
    onStartAllowedChanged: restartTimer.restart()

    onConnectionStateChanged: {
        if (connectionState === "ready") {
            problemTimer.stop()
            problemVisible = false
        } else if (!problemVisible && !problemTimer.running) {
            problemTimer.start()
        }
    }

    Timer {
        id: problemTimer
        interval: 1500
        onTriggered: conn.problemVisible = conn.connectionState !== "ready"
    }

    Component.onCompleted: {
        if (connectionState !== "ready") {
            problemTimer.start()
        }
        restartTimer.restart()
    }

    // Qt.application.state wird Active, wenn die App aus dem Hintergrund
    // (oder das Telefon aus dem Schlaf) zurückkommt.
    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive) {
                conn.checkAfterResume()
            }
        }
    }

    // QtWebSockets verbindet von sich aus nicht neu. Nach Closed/Error mit
    // wachsendem Abstand erneut versuchen, solange konfiguriert -- jedes Mal
    // ein neues Rennen, wieder mit der Heimadresse vorn.
    Timer {
        id: reconnectTimer
        interval: 2000
        repeat: false
        onTriggered: {
            conn._backoffMs = Math.min(conn._backoffMs * 2, 60000)
            conn._startAttempt()
        }
    }

    // Antworten, die nie kommen, dürfen die UI nicht ewig warten lassen --
    // derselbe Grund wie beim XMLHttpRequest-Timeout in MassApi.js. Läuft nur,
    // solange überhaupt etwas offen ist.
    Timer {
        id: timeoutTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            var now = Date.now()
            var keys = Object.keys(conn._pending)
            for (var i = 0; i < keys.length; i++) {
                var entry = conn._pending[keys[i]]
                if (entry && entry.deadline <= now) {
                    delete conn._pending[keys[i]]
                    entry.callback({ hint: qsTr("Zeitüberschreitung"),
                                     detail: entry.command }, null)
                }
            }
            if (Object.keys(conn._pending).length === 0) {
                stop()
            }
        }
    }
}
