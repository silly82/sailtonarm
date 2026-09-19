import QtQuick 2.6
import "../lib/MassModels.js" as Models

// Hält den Zustand aller Player und Warteschlangen und hält ihn per
// Server-Events aktuell. Die UI liest nur von hier und pollt nie -- der Server
// schickt zu jeder Änderung ein Ereignis, das ist die einzige Wahrheitsquelle.
//
// Einmal geladen wird nur beim Anmelden (und nach einem Reconnect); danach
// tragen ausschliesslich Ereignisse Änderungen ein.
Item {
    id: store

    property var mass

    // Array<Player>, bereits gefiltert und sortiert. Wird bei jeder Änderung
    // *neu zugewiesen* statt an Ort und Stelle geändert -- QML bemerkt eine
    // Mutation innerhalb eines JS-Arrays nicht, Bindings würden nicht neu
    // auswerten.
    property var players: []
    // queue_id -> PlayerQueue, ebenfalls immer neu zugewiesen.
    property var queues: ({})

    // Der zuletzt geöffnete Player. Wird in der Liste nach oben sortiert und
    // markiert; die App springt aber nicht von selbst auf seine Seite -- das
    // würde bei jedem Start eine Rückwärtsgeste erzwingen.
    property string preferredPlayerId: ""

    property bool loading: false
    property string lastError: ""
    // Zeitstempel des letzten erfolgreichen Ladens, damit die UI "noch nie
    // geladen" von "gerade leer" unterscheiden kann.
    property bool loadedOnce: false

    function refresh() {
        if (!mass || !mass.ready) {
            return
        }
        loading = true
        lastError = ""

        mass.sendCommand("players/all", {}, function (err, result) {
            store.loading = false
            if (err) {
                store.lastError = err.hint
                return
            }
            store.loadedOnce = true
            store._setPlayers(result || [])
        })

        mass.sendCommand("player_queues/all", {}, function (err, result) {
            if (err) {
                // Kein lastError: ohne Queues bleibt die Player-Liste nutzbar,
                // nur die Titelzeile fehlt. Ein roter Fehler wäre übertrieben.
                return
            }
            var map = {}
            var list = result || []
            for (var i = 0; i < list.length; i++) {
                map[list[i].queue_id] = list[i]
            }
            store.queues = map
        })
    }

    function playerById(playerId) {
        for (var i = 0; i < players.length; i++) {
            if (players[i].player_id === playerId) {
                return players[i]
            }
        }
        return null
    }

    function queueOf(playerId) {
        return Models.queueFor(queues, playerId)
    }

    // --- Kommandos -------------------------------------------------------
    // Absichtlich hier gebündelt statt in den Seiten verstreut: so gibt es
    // genau eine Stelle, an der Kommandonamen und Argumentnamen stehen.

    function playPause(playerId) {
        _send("player_queues/play_pause", { queue_id: playerId })
    }

    function next(playerId) {
        _send("player_queues/next", { queue_id: playerId })
    }

    function previous(playerId) {
        _send("player_queues/previous", { queue_id: playerId })
    }

    function seek(playerId, positionSeconds) {
        _send("player_queues/seek", { queue_id: playerId,
                                      position: Math.round(positionSeconds) })
    }

    function setVolume(playerId, level) {
        _send("players/cmd/volume_set", { player_id: playerId,
                                          volume_level: Math.round(level) })
    }

    function setMuted(playerId, muted) {
        _send("players/cmd/volume_mute", { player_id: playerId, muted: muted })
    }

    function setPower(playerId, powered) {
        _send("players/cmd/power", { player_id: playerId, powered: powered })
    }

    function _send(command, args) {
        if (!mass) {
            return
        }
        mass.sendCommand(command, args, function (err) {
            if (err) {
                store.lastError = err.hint
            }
        })
    }

    // --- Intern ----------------------------------------------------------

    function _setPlayers(list) {
        players = Models.visiblePlayers(list, preferredPlayerId)
    }

    function _upsertPlayer(player) {
        if (!player || !player.player_id) {
            return
        }
        var copy = players.slice()
        var found = false
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].player_id === player.player_id) {
                copy[i] = player
                found = true
                break
            }
        }
        if (!found) {
            copy.push(player)
        }
        _setPlayers(copy)
    }

    function _removePlayer(playerId) {
        var copy = []
        for (var i = 0; i < players.length; i++) {
            if (players[i].player_id !== playerId) {
                copy.push(players[i])
            }
        }
        players = copy
    }

    function _upsertQueue(queue) {
        if (!queue || !queue.queue_id) {
            return
        }
        var map = {}
        for (var key in queues) {
            map[key] = queues[key]
        }
        map[queue.queue_id] = queue
        queues = map
    }

    // queue_time_updated kommt im Sekundentakt, solange etwas läuft. Es trägt
    // nur die abgelaufene Zeit, nicht die ganze Queue -- also gezielt dieses
    // eine Feld nachziehen und den Zeitstempel auf jetzt setzen, damit die
    // lokale Weiterzählung in MassModels.elapsedSeconds() daran andockt.
    function _updateQueueTime(queueId, data) {
        var queue = queues[queueId]
        if (!queue) {
            return
        }
        var seconds = (typeof data === "number")
                ? data
                : (data && data.elapsed_time !== undefined ? data.elapsed_time : null)
        if (seconds === null) {
            return
        }
        var updated = {}
        for (var field in queue) {
            updated[field] = queue[field]
        }
        updated.elapsed_time = seconds
        updated.elapsed_time_last_updated = Date.now() / 1000
        _upsertQueue(updated)
    }

    Connections {
        target: mass
        onAuthenticated: store.refresh()
        onServerEvent: {
            switch (eventType) {
            case "player_added":
            case "player_updated":
                store._upsertPlayer(message.data)
                break
            case "player_removed":
                store._removePlayer(message.object_id)
                break
            case "queue_added":
            case "queue_updated":
                store._upsertQueue(message.data)
                break
            case "queue_time_updated":
                store._updateQueueTime(message.object_id, message.data)
                break
            default:
                break
            }
        }
    }
}
