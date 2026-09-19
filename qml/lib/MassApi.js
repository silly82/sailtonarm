.pragma library

// Reine Hilfsfunktionen rund um die Music-Assistant-API: URL-Ableitung,
// Nachrichtenbau, ein HTTP-Probe auf /info. Alles Zustandsbehaftete (offener
// Socket, Handshake, offene Anfragen) liegt in components/MassConnection.qml --
// `.pragma library` teilt diese Datei über alle Importe hinweg, hier darf also
// nichts Verbindungsspezifisches stehen.
//
// Callback-Stil statt Promises: hält es einheitlich mit dem Rest der
// SailfishOS-QML-Umgebung, in der Promise-Unterstützung nicht vorausgesetzt
// werden kann.

// Standardports des MA-Servers.
var DEFAULT_PORT = 8095
var DEFAULT_STREAM_PORT = 8097

// Schema-Version, gegen die dieser Client entwickelt wurde (music_assistant/
// constants.py, Branch dev, 2026-09-19: API_SCHEMA_VERSION = 77,
// MIN_SCHEMA_VERSION = 28). Der Zielserver (MA 2.10.4 als HA-App) meldet
// schema_version 65 / min_supported 28 -- beides innerhalb dieser Grenzen,
// es wird also nicht gewarnt. MIN_SERVER_SCHEMA ist bewusst niedrig: die in
// Ausbaustufe 0-3 benutzten Kommandos gibt es seit langem, gegen den echten
// Server geprüft (nur streams/info fehlt dort, s. streamBaseUrl).
var CLIENT_SCHEMA_VERSION = 77
var MIN_SERVER_SCHEMA = 28

// Macht aus der Nutzereingabe eine brauchbare Stammadresse:
//   "musicassistant.local"            -> "http://musicassistant.local:8095"
//   "192.168.1.5:8095/"               -> "http://192.168.1.5:8095"
//   "https://mass.example.com"        -> "https://mass.example.com"  (kein Port ergänzt)
// Der Port wird nur bei http:// ergänzt -- hinter einem TLS-Reverse-Proxy ist
// 443 richtig, und ein angehängtes :8095 wäre dort schlicht falsch.
function normalizeBaseUrl(input) {
    var url = String(input || "").trim()
    if (url.length === 0) {
        return ""
    }
    if (!/^[a-z]+:\/\//i.test(url)) {
        url = "http://" + url
    }
    url = url.replace(/\/+$/, "")

    var isHttps = /^https:\/\//i.test(url)
    // Port vorhanden? Nur im Autoritätsteil suchen, nicht im Pfad.
    var authority = url.replace(/^[a-z]+:\/\//i, "").split("/")[0]
    var hasPort = /:\d+$/.test(authority)
    if (!hasPort && !isHttps) {
        url += ":" + DEFAULT_PORT
    }
    return url
}

// WebSocket-Adresse der API: http -> ws, https -> wss, Pfad /ws.
function wsUrl(baseUrl) {
    var url = normalizeBaseUrl(baseUrl)
    if (url.length === 0) {
        return ""
    }
    return url.replace(/^http/i, "ws") + "/ws"
}

// Stammadresse des Stream-Servers (Standardport 8097). Der Stream-Server ist
// bewusst unauthentifiziert -- dort holen sich auch Chromecast & Co. ihre
// Daten --, und er bedient dieselbe /imageproxy/*-Route wie die API. Damit
// kommt QMLs Image-Element ohne Authorization-Header an Cover-Art heran, was
// aus QML sonst nicht ginge.
//
// Diese Ableitung ist kein Zwischenschritt, sondern der einzige Weg: das
// Kommando "streams/info", das die tatsächlich veröffentlichte Adresse meldet,
// gibt es erst im dev-Zweig -- auf dem Zielserver (2.10.4, Schema 65) ist es
// nicht vorhanden (gegen /api-docs/commands.json geprüft). Sollte es später
// auftauchen, ist es die bessere Quelle: der Server kann auf einer anderen
// IP/Port veröffentlichen, etwa in Docker ohne Host-Netz.
//
// Gegen den Zielserver geprüft: /imageproxy/<proxy_id> liefert ohne jedes
// Token ein JPEG, auf Port 8095 *und* 8097. `imageUrl()` nimmt darum einfach
// die konfigurierte Adresse; diese Funktion bleibt für den Fall, dass ein
// künftiger Server die API-Route doch absichert.
function streamBaseUrl(baseUrl) {
    var url = normalizeBaseUrl(baseUrl)
    if (url.length === 0) {
        return ""
    }
    return url.replace(/:\d+$/, ":" + DEFAULT_STREAM_PORT)
}

// Die einzigen Kantenlängen, die der Server annimmt -- alles andere quittiert
// er mit HTTP 400 ("Unsupported size 200: must be one of 0, 80, 160, 256, 512,
// 1024"). 0 bedeutet Originalgrösse; die ist teuer (ein Cover kam mit
// 1000x1000 und 122 KB zurück, dasselbe in 256 wog 16 KB), also in Listen
// niemals ungefragt.
var IMAGE_SIZES = [80, 160, 256, 512, 1024]

// Rastet auf die nächstgrössere erlaubte Kantenlänge ein, damit Aufrufer
// einfach die gewünschte Pixelzahl übergeben können.
function snapImageSize(px) {
    for (var i = 0; i < IMAGE_SIZES.length; i++) {
        if (px <= IMAGE_SIZES[i]) {
            return IMAGE_SIZES[i]
        }
    }
    return 0  // grösser als 1024 -> Original
}

// imageId ist das Feld `proxy_id` aus `metadata.images[]` eines Medienobjekts,
// nicht dessen `path` (der ist providerspezifisch und für den Proxy wertlos).
function imageUrl(base, imageId, sizePx) {
    if (!base || !imageId) {
        return ""
    }
    var url = normalizeBaseUrl(base) + "/imageproxy/" + encodeURIComponent(imageId)
    if (sizePx !== undefined && sizePx !== null) {
        url += "?size=" + snapImageSize(sizePx)
    }
    return url
}

// GET /info -- die einzige Route, die ohne Token antwortet. Damit lässt sich in
// den Einstellungen "erreichbar?" von "Token falsch?" trennen, bevor überhaupt
// ein Socket aufgemacht wird.
function fetchServerInfo(baseUrl, timeoutMs, onSuccess, onError) {
    var url = normalizeBaseUrl(baseUrl)
    if (url.length === 0) {
        onError({ hint: "Keine Serveradresse angegeben", detail: "" })
        return
    }

    var xhr = new XMLHttpRequest()
    var finished = false

    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || finished) {
            return
        }
        finished = true
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                onSuccess(JSON.parse(xhr.responseText))
            } catch (e) {
                onError({ hint: "Antwort war kein gültiges JSON", detail: String(e) })
            }
        } else if (xhr.status === 0) {
            onError({ hint: "Server nicht erreichbar", detail: url })
        } else {
            onError({ hint: "HTTP " + xhr.status, detail: xhr.responseText })
        }
    }

    // QMLs XMLHttpRequest feuert bei einem nicht erreichbaren Host weder
    // Erfolgs- noch Fehler-Callback, bis das TCP-Timeout des Systems nach
    // Minuten aufgibt -- der Aufrufer wartete sonst ewig. Deshalb der eigene
    // Wecker; er wird vom Aufrufer gestellt (QML-Timer), hier nur ausgewertet.
    xhr.open("GET", url + "/info")
    xhr.send()

    return {
        abort: function () {
            if (finished) {
                return
            }
            finished = true
            xhr.abort()
            onError({ hint: "Zeitüberschreitung", detail: url + " nach " + timeoutMs + " ms" })
        }
    }
}

// --- Nachrichten ---------------------------------------------------------

function commandMessage(messageId, command, args) {
    return JSON.stringify({
        message_id: String(messageId),
        command: command,
        args: args || {}
    })
}

// Klassifiziert eine eingehende Nachricht. Der Server schickt drei Sorten über
// denselben Socket, unterscheidbar nur an den vorhandenen Feldern:
//   ResultMessage  -> hat message_id (error_code zusätzlich, wenn Fehler)
//   EventMessage   -> hat event (MassEvent: event, object_id, data)
//   ServerInfo     -> hat server_id, kommt unaufgefordert direkt nach connect
function classify(msg) {
    if (msg === null || typeof msg !== "object") {
        return "unknown"
    }
    if (msg.message_id !== undefined) {
        return msg.error_code !== undefined ? "error" : "result"
    }
    if (msg.event !== undefined) {
        return "event"
    }
    if (msg.server_id !== undefined) {
        return "server_info"
    }
    return "unknown"
}

// Die zwei Codes, die in Stufe 0 tatsächlich auftreten, gegen den echten
// Server abgeklopft (MA 2.10.4): 20 "Authentication is required.", 23 "The
// access token is invalid or has expired." Der Server liefert `details` erst
// nach erfolgreicher Anmeldung in der Sprache des Clients -- genau diese
// beiden Meldungen kommen also immer englisch an. Deshalb hier übersetzt;
// alles andere wird durchgereicht.
var ERROR_AUTH_REQUIRED = 20
var ERROR_INVALID_TOKEN = 23

function errorText(msg) {
    if (msg.error_code === ERROR_INVALID_TOKEN) {
        return "Token ungültig oder abgelaufen"
    }
    if (msg.error_code === ERROR_AUTH_REQUIRED) {
        return "Anmeldung erforderlich"
    }
    var detail = msg.details || ""
    if (detail.length > 0) {
        return detail
    }
    return "Fehlercode " + msg.error_code
}

// Server zu alt/zu neu? Gibt "" zurück, wenn alles passt, sonst einen Text für
// die UI. Beide Richtungen sind möglich: unser Client ist gegen Schema 77
// gebaut, ein noch neuerer Server kann Schema-Mindestanforderungen stellen,
// die wir nicht erfüllen.
function compatibilityWarning(serverInfo) {
    if (!serverInfo) {
        return ""
    }
    if (serverInfo.schema_version !== undefined
            && serverInfo.schema_version < MIN_SERVER_SCHEMA) {
        return "Server spricht API-Schema " + serverInfo.schema_version
                + ", dieser Client erwartet mindestens " + MIN_SERVER_SCHEMA + "."
    }
    if (serverInfo.min_supported_schema_version !== undefined
            && serverInfo.min_supported_schema_version > CLIENT_SCHEMA_VERSION) {
        return "Der Server verlangt mindestens API-Schema "
                + serverInfo.min_supported_schema_version
                + ", dieser Client ist gegen " + CLIENT_SCHEMA_VERSION + " gebaut."
    }
    return ""
}
