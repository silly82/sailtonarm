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

    // Der Player, den das Cover zeigt und den eine Bedienung ohne weitere
    // Angabe meint: zuerst einer, der gerade spielt, sonst ein pausierter,
    // sonst der zuletzt geöffnete. Ohne diese Reihenfolge zeigte das Cover
    // den gemerkten Player auch dann, wenn nebenan tatsächlich Musik läuft.
    readonly property var activePlayer: {
        var paused = null
        var preferred = null
        for (var i = 0; i < players.length; i++) {
            var p = players[i]
            if (!Models.isAvailable(p)) {
                continue
            }
            if (Models.isPlaying(p)) {
                return p
            }
            if (Models.playbackState(p) === "paused" && paused === null) {
                paused = p
            }
            if (p.player_id === preferredPlayerId) {
                preferred = p
            }
        }
        return paused !== null ? paused : preferred
    }

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

    // Ziel für "abspielen" aus der Bibliothek. Getrennt von
    // preferredPlayerId gehalten, weil beides Verschiedenes meint: welchen
    // Player man zuletzt *angeschaut* hat, und auf welchem etwas *landen*
    // soll. Ohne eigene Wahl gilt der Player, der gerade spielt, sonst der
    // zuletzt geöffnete.
    property string explicitTargetPlayerId: ""
    readonly property string targetPlayerId: {
        if (explicitTargetPlayerId.length > 0 && playerById(explicitTargetPlayerId)) {
            return explicitTargetPlayerId
        }
        if (activePlayer) {
            return activePlayer.player_id
        }
        return preferredPlayerId
    }

    // option ist eine QueueOption: "play" (jetzt), "next" (als Nächstes),
    // "add" (anhängen), "replace" (Warteschlange ersetzen). `shuffle` wirkt
    // laut Server nur bei den Optionen, die sofort losspielen (play/replace).
    function playMedia(playerId, uri, option, callback, shuffle) {
        if (!mass) {
            return
        }
        var args = { queue_id: playerId, media: uri, option: option }
        if (shuffle !== undefined) {
            args.shuffle = shuffle
        }
        mass.sendCommand("player_queues/play_media", args, function (err) {
            if (err) {
                store.lastError = err.hint
            }
            if (callback) {
                callback(err)
            }
        })
    }

    // --- Favoriten -------------------------------------------------------

    // Hinzufügen nimmt die URI und geht für jedes Objekt, auch für eines, das
    // nur bei einem Anbieter liegt.
    function addFavorite(uri, callback) {
        _sendWithResult("music/favorites/add_item", { item: uri }, callback)
    }

    // Entfernen braucht dagegen Medientyp *und* Bibliothekskennung -- es wirkt
    // nur auf Bibliothekseinträge. Aufrufer prüfen daher vorher
    // `provider === "library"`.
    function removeFavorite(mediaType, libraryItemId, callback) {
        _sendWithResult("music/favorites/remove_item",
                        { media_type: mediaType, library_item_id: libraryItemId },
                        callback)
    }

    // --- Gruppen ---------------------------------------------------------

    // Schliesst Player an einen Zielplayer an oder löst sie von ihm. Beide
    // Listen sind optional, eine davon genügt.
    function setGroupMembers(targetPlayerId, idsToAdd, idsToRemove, callback) {
        var args = { target_player: targetPlayerId }
        if (idsToAdd && idsToAdd.length > 0) {
            args.player_ids_to_add = idsToAdd
        }
        if (idsToRemove && idsToRemove.length > 0) {
            args.player_ids_to_remove = idsToRemove
        }
        _sendWithResult("players/cmd/set_members", args, callback)
    }

    // Löst diesen einen Player aus seiner Gruppe.
    function ungroup(playerId) {
        _send("players/cmd/ungroup", { player_id: playerId })
    }

    // Lautstärke der ganzen Gruppe; die Einzellautstärken zieht der Server
    // im Verhältnis mit.
    function setGroupVolume(playerId, level) {
        _send("players/cmd/group_volume", { player_id: playerId,
                                            volume_level: Math.round(level) })
    }

    function _sendWithResult(command, args, callback) {
        if (!mass) {
            return
        }
        mass.sendCommand(command, args, function (err) {
            if (err) {
                store.lastError = err.hint
                console.warn("PlayerStore:", command, "fehlgeschlagen:", err.hint)
            }
            if (callback) {
                callback(err)
            }
        })
    }

    // --- Warteschlange ---------------------------------------------------

    function playIndex(playerId, index) {
        _send("player_queues/play_index", { queue_id: playerId, index: index })
    }

    // pos_shift: negativ nach vorn, positiv nach hinten.
    function moveItem(playerId, queueItemId, posShift) {
        _send("player_queues/move_item", { queue_id: playerId,
                                           queue_item_id: queueItemId,
                                           pos_shift: posShift })
    }

    function moveItemEnd(playerId, queueItemId) {
        _send("player_queues/move_item_end", { queue_id: playerId,
                                               queue_item_id: queueItemId })
    }

    function deleteItem(playerId, queueItemId) {
        _send("player_queues/delete_item", { queue_id: playerId,
                                             item_id_or_index: queueItemId })
    }

    function clearQueue(playerId) {
        _send("player_queues/clear", { queue_id: playerId })
    }

    function saveAsPlaylist(playerId, name, callback) {
        if (!mass) {
            return
        }
        mass.sendCommand("player_queues/save_as_playlist",
                         { queue_id: playerId, name: name },
                         function (err) {
                             if (err) {
                                 store.lastError = err.hint
                             }
                             if (callback) {
                                 callback(err)
                             }
                         })
    }

    // Übergibt die laufende Warteschlange an einen anderen Player --
    // "die Musik folgt mir".
    function transferQueue(sourcePlayerId, targetPlayerId, autoPlay, callback) {
        if (!mass) {
            return
        }
        mass.sendCommand("player_queues/transfer",
                         { source_queue_id: sourcePlayerId,
                           target_queue_id: targetPlayerId,
                           auto_play: autoPlay === true },
                         function (err) {
                             if (err) {
                                 store.lastError = err.hint
                             }
                             if (callback) {
                                 callback(err)
                             }
                         })
    }

    function setShuffle(playerId, enabled) {
        _send("player_queues/shuffle", { queue_id: playerId,
                                         shuffle_enabled: enabled })
    }

    // RepeatMode: "off", "one", "all".
    function setRepeat(playerId, mode) {
        _send("player_queues/repeat", { queue_id: playerId, repeat_mode: mode })
    }

    function setCrossfade(playerId, enabled) {
        _send("player_queues/crossfade", { queue_id: playerId,
                                           crossfade_enabled: enabled })
    }

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
            console.warn("PlayerStore: kein Verbindungsobjekt für", command)
            return
        }
        mass.sendCommand(command, args, function (err) {
            if (err) {
                store.lastError = err.hint
                // Auch ins Journal: `lastError` zeigt nur die Seite an, die
                // gerade offen ist -- ein Kommando vom Sperrbildschirm oder
                // vom Cover scheiterte sonst vollkommen lautlos.
                console.warn("PlayerStore:", command, "fehlgeschlagen:",
                             err.hint, err.detail ? "(" + err.detail + ")" : "")
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
