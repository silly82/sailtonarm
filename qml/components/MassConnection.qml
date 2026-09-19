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
    property string token: ""
    property bool autoConnect: true

    readonly property bool configured: MassApi.normalizeBaseUrl(baseUrl).length > 0

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

    // Ein Ereignis vom Server. eventType ist der MassEvent-Name
    // ("player_updated", "queue_updated", ...), message die ganze Nachricht
    // (event, object_id, data).
    signal serverEvent(string eventType, var message)
    signal authenticated()

    // --- Intern ----------------------------------------------------------
    property int _nextId: 1
    // message_id -> { callback: function(err, result), items: [], timeoutAt: ms }
    property var _pending: ({})
    property int _backoffMs: 2000
    // Nur wahr zwischen "Socket offen" und "auth-Antwort da" -- verhindert,
    // dass ein zweites auth rausgeht, wenn der Server ServerInfo erneut
    // schickt.
    property bool _authSent: false

    // --- API -------------------------------------------------------------

    // Schickt ein Kommando. callback(err, result): err ist null bei Erfolg,
    // sonst { hint, detail }. Kommandos vor dem Verbindungsaufbau werden
    // abgelehnt statt gepuffert -- in Ausbaustufe 0 ruft nur die UI auf, und
    // die kennt den Zustand.
    function sendCommand(command, args, callback) {
        if (connectionState !== "ready") {
            if (callback) {
                callback({ hint: "Keine Verbindung", detail: "Zustand: " + connectionState }, null)
            }
            return -1
        }
        return _send(command, args, callback)
    }

    function connectNow() {
        reconnectTimer.stop()
        _backoffMs = 2000
        lastError = ""
        socket.active = false
        socket.active = Qt.binding(function () { return conn.autoConnect && conn.configured })
    }

    function disconnect() {
        reconnectTimer.stop()
        autoConnect = false
        socket.active = false
        _failAllPending({ hint: "Verbindung getrennt", detail: "" })
        connectionState = "idle"
    }

    // --- Implementierung -------------------------------------------------

    function _send(command, args, callback) {
        var id = _nextId
        _nextId += 1
        if (callback) {
            _pending[String(id)] = {
                callback: callback,
                items: [],
                command: command,
                deadline: Date.now() + 20000
            }
            timeoutTimer.start()
        }
        socket.sendTextMessage(MassApi.commandMessage(id, command, args))
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
        _send("auth", { token: token, locale: Qt.locale().name }, function (err, result) {
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

    WebSocket {
        id: socket
        url: conn.configured ? MassApi.wsUrl(conn.baseUrl) : ""
        active: conn.autoConnect && conn.configured

        onStatusChanged: {
            if (status === WebSocket.Connecting) {
                conn.connectionState = "connecting"
            } else if (status === WebSocket.Open) {
                // Noch nicht "ready": erst kommt ServerInfo, dann auth.
                conn._authSent = false
                conn.connectionState = "connecting"
            } else if (status === WebSocket.Closed || status === WebSocket.Error) {
                var wasReady = conn.connectionState === "ready"
                conn._authSent = false
                conn.userName = ""
                if (status === WebSocket.Error && socket.errorString) {
                    conn.lastError = socket.errorString
                }
                conn.connectionState = conn.configured ? "error" : "idle"
                conn._failAllPending({ hint: "Verbindung abgebrochen", detail: conn.lastError })
                if (conn.autoConnect && conn.configured) {
                    // Nach einer stabilen Verbindung wieder kurz warten, sonst
                    // den Abstand verdoppeln -- ein dauerhaft nicht erreichbarer
                    // Server soll nicht im Sekundentakt angepingt werden.
                    if (wasReady) {
                        conn._backoffMs = 2000
                    }
                    reconnectTimer.interval = conn._backoffMs
                    reconnectTimer.restart()
                }
            }
        }

        onTextMessageReceived: {
            var msg
            try {
                msg = JSON.parse(message)
            } catch (e) {
                conn.lastError = "Unlesbare Nachricht vom Server"
                return
            }

            switch (MassApi.classify(msg)) {
            case "server_info":
                conn.serverInfo = msg
                conn._sendAuth()
                break
            case "result":
                conn._handleResult(msg)
                break
            case "error":
                conn._handleError(msg)
                break
            case "event":
                conn.serverEvent(msg.event, msg)
                break
            default:
                break
            }
        }
    }

    // QtWebSockets verbindet von sich aus nicht neu. Nach Closed/Error mit
    // wachsendem Abstand erneut versuchen, solange konfiguriert. active wird
    // per Qt.binding() wiederhergestellt, damit spätere Änderungen an
    // autoConnect/configured (z.B. Token in Settings gelöscht) den Socket
    // weiterhin reaktiv deaktivieren.
    Timer {
        id: reconnectTimer
        interval: 2000
        repeat: false
        onTriggered: {
            conn._backoffMs = Math.min(conn._backoffMs * 2, 60000)
            socket.active = false
            socket.active = Qt.binding(function () {
                return conn.autoConnect && conn.configured
            })
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
                    entry.callback({ hint: "Zeitüberschreitung",
                                     detail: entry.command }, null)
                }
            }
            if (Object.keys(conn._pending).length === 0) {
                stop()
            }
        }
    }
}
