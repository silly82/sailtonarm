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

    // Beim Wechsel zwischen echtem Server und Demo nichts vom anderen
    // behalten.
    onMassChanged: {
        players = []
        queues = {}
        providerNames = {}
        loadedOnce = false
        lastError = ""
        explicitTargetPlayerId = ""
        if (mass && mass.ready) {
            refresh()
            loadProviders()
        }
    }

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

    // --- Anbieter ---------------------------------------------------------

    // Instanz-Id bzw. Domain -> Anzeigename ("Apple Music"), einmal je
    // Verbindung geladen. Damit sagt ein Suchtreffer ausserhalb der
    // Bibliothek, woher er kommt.
    property var providerNames: ({})

    function loadProviders() {
        if (!mass || !mass.ready) {
            return
        }
        mass.sendCommand("providers", {}, function (err, result) {
            if (err) {
                return
            }
            var names = {}
            var list = result || []
            for (var i = 0; i < list.length; i++) {
                var p = list[i]
                if (!p || !p.name) {
                    continue
                }
                if (p.instance_id) {
                    names[p.instance_id] = p.name
                }
                if (p.domain && names[p.domain] === undefined) {
                    names[p.domain] = p.name
                }
            }
            store.providerNames = names
        })
    }

    // Name des Dienstes, aus dem ein Eintrag stammt; "" für
    // Bibliothekseinträge. Instanz-Ids sehen aus wie "spotify--a1b2c3" --
    // fehlt die Instanz in der Liste, hilft die Domain davor, und zur Not
    // wird die Domain selbst lesbar gemacht.
    function sourceName(item) {
        var provider = (item && item.provider) ? String(item.provider) : ""
        if (provider.length === 0 || provider === "library") {
            return ""
        }
        if (providerNames[provider]) {
            return providerNames[provider]
        }
        var domain = provider.split("--")[0]
        if (providerNames[domain]) {
            return providerNames[domain]
        }
        return domain.replace(/_/g, " ").replace(/\b[a-z]/g, function (c) {
            return c.toUpperCase()
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
                store._noteError(err)
            }
            if (callback) {
                callback(err)
            }
        })
    }

    // Ähnliches abspielen: der Server baut aus dem Objekt eine endlose
    // Warteschlange passender Titel ("Endless Mix", Plugin radio_playlist,
    // gespeist aus Last.fm bzw. dem Streamingdienst). `radio_mode` führt MA
    // 2.10.4 als veraltet und übersetzt es selbst in eine
    // radio_playlist://-Adresse; deren Form ist nicht dokumentiert, daher
    // bleibt es beim Schalter. Auf dem Gerät geprüft (KONZEPT.md Abschnitt 31).
    //
    // music/tracks/similar_tracks wäre der direkte Weg, liefert auf diesem
    // Server aber nur zwei Titel: den Ausgangstitel und einen einzigen
    // ähnlichen.
    function playSimilar(playerId, uri, callback) {
        if (!mass) {
            return
        }
        mass.sendCommand("player_queues/play_media",
                         { queue_id: playerId, media: uri, option: "replace", radio_mode: true },
                         function (err) {
                             store._noteError(err)
                             if (callback) {
                                 callback(err)
                             }
                         })
    }

    // --- Playlists und Bibliothek ------------------------------------------
    // Gegen den echten Server geprüft (KONZEPT.md Abschnitt 34). Hinzufügen
    // und Entfernen in Playlists laufen als Hintergrundaufgabe des Servers:
    // die Antwort kommt sofort, der neue Stand ein paar Sekunden später.

    // Bearbeitbar sind Playlists mit `is_editable`; auf dieser Anlage die
    // eigenen bei Apple Music und die des Music-Assistant-Anbieters.
    function editablePlaylists(callback) {
        if (!mass) {
            return
        }
        mass.sendCommand("music/playlists/library_items", { limit: 500 }, function (err, result) {
            var list = (result || []).filter(function (p) { return p.is_editable === true })
            list.sort(function (a, b) { return String(a.name).localeCompare(String(b.name)) })
            callback(err, list)
        }, 60000)
    }

    function addToPlaylist(playlist, uris, callback) {
        _sendWithResult("music/playlists/add_playlist_tracks",
                        { db_playlist_id: playlist.item_id, uris: uris }, callback)
    }

    // positions sind die `position`-Werte der Titel in der Playlist (ab 1).
    function removeFromPlaylist(playlist, positions, callback) {
        _sendWithResult("music/playlists/remove_playlist_tracks",
                        { db_playlist_id: playlist.item_id, positions_to_remove: positions }, callback)
    }

    // Neue Playlists legt der Music-Assistant-eigene Anbieter an: Apple Music
    // kann bestehende bearbeiten, aber keine neuen anlegen (Fehler 3,
    // "Daten ungültig"). Liefert die neue Playlist.
    function createPlaylist(name, callback) {
        if (!mass) {
            return
        }
        mass.sendCommand("music/playlists/create_playlist",
                         { name: name, provider_instance_or_domain: "builtin" },
                         function (err, result) {
                             store._noteError(err)
                             callback(err, result)
                         }, 60000)
    }

    // Ein Objekt eines Anbieters (Streamingdienst, RadioBrowser) in die
    // eigene Bibliothek aufnehmen. Liefert den neuen Bibliothekseintrag.
    function addToLibrary(uri, callback) {
        if (!mass) {
            return
        }
        mass.sendCommand("music/library/add_item", { item: uri }, function (err, result) {
            store._noteError(err)
            callback(err, result)
        }, 60000)
    }

    // Aus der Bibliothek entfernen. Der Server nennt das selbst "destruktiv":
    // bei einem Album gehen dessen Titel mit. Die Oberfläche fragt deshalb
    // mit Rückgängig-Frist, bevor sie das schickt.
    function removeFromLibrary(mediaType, libraryItemId, callback) {
        _sendWithResult("music/library/remove_item",
                        { media_type: mediaType, library_item_id: libraryItemId }, callback)
    }

    // Einen Sender über seine Stream-Adresse anlegen (eigener Sender, der in
    // keinem Verzeichnis steht).
    function addRadioByUrl(name, url, callback) {
        if (!mass) {
            return
        }
        mass.sendCommand("builtin/add_radio", { name: name, url: url }, function (err, result) {
            store._noteError(err)
            callback(err, result)
        }, 60000)
    }

    // --- Farben aus dem Cover ----------------------------------------------

    // proxy_id -> Palette (primary, accent, on_dark, on_light,
    // background_dark, background_light; je [r, g, b] oder null). Der Server
    // rechnet sie einmal aus und hält sie selbst im Cache; hier nur, damit ein
    // Titelwechsel hin und zurück keine neue Anfrage braucht.
    property var _palettes: ({})

    function palette(proxyId, callback) {
        if (!proxyId) {
            callback(null)
            return
        }
        if (_palettes[proxyId] !== undefined) {
            callback(_palettes[proxyId])
            return
        }
        if (!mass || !mass.ready) {
            callback(null)
            return
        }
        mass.sendCommand("metadata/get_image_palette", { image_id: proxyId }, function (err, result) {
            var value = err ? null : result
            store._palettes[proxyId] = value
            callback(value)
        }, 30000)
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
    // mit, ausgehend von einer Momentaufnahme ihrer Werte (MA 2.10.4,
    // `set_group_volume`): nach unten im Verhältnis, nach oben jede um
    // denselben Anteil Richtung 100 -- 30/10 bei Gruppe 15 ergibt 15/5.
    function setGroupVolume(playerId, level) {
        _sendVolume("group:" + playerId, "players/cmd/group_volume",
                    { player_id: playerId, volume_level: Math.round(level) })
    }

    function _sendWithResult(command, args, callback) {
        if (!mass) {
            return
        }
        mass.sendCommand(command, args, function (err) {
            if (err) {
                store._noteError(err)
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
                                 store._noteError(err)
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
                                 store._noteError(err)
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

    // Weiter/Zurück, wie sie Knöpfe, Cover und Sperrbildschirm meinen: in
    // einem Hörbuch mit Kapiteln springen sie zwischen den Kapiteln (per
    // Seek), sonst zum nächsten/vorigen Eintrag der Warteschlange.
    function nextOrChapter(playerId) {
        var target = _chapterTarget(playerId, true)
        if (target >= 0) {
            seek(playerId, target)
        } else {
            next(playerId)
        }
    }

    function previousOrChapter(playerId) {
        var target = _chapterTarget(playerId, false)
        if (target >= 0) {
            seek(playerId, target)
        } else {
            previous(playerId)
        }
    }

    function _chapterTarget(playerId, forward) {
        var player = playerById(playerId)
        var queue = queueOf(playerId)
        var track = Models.nowPlaying(player, queue)
        if (!track || !track.isSpoken) {
            return -1
        }
        return Models.chapterSeek(track.chapters, forward,
                                  Models.elapsedSeconds(queue, player, Date.now()))
    }

    // Relativer Sprung (Hörbuch: -15 s / +30 s), innerhalb des Eintrags
    // gehalten.
    function skip(playerId, seconds) {
        var player = playerById(playerId)
        var queue = queueOf(playerId)
        var track = Models.nowPlaying(player, queue)
        var target = Math.max(0, Models.elapsedSeconds(queue, player, Date.now()) + seconds)
        if (track && track.duration > 0) {
            target = Math.min(target, track.duration - 1)
        }
        seek(playerId, target)
    }

    // Tempo 0.5..3.0; der Server bietet es nur an, wo die Queue
    // `playback_speed` meldet.
    function setPlaybackSpeed(playerId, speed) {
        _send("player_queues/set_playback_speed", { queue_id: playerId, speed: speed })
    }

    // --- Hörbücher -------------------------------------------------------

    // Beendet bzw. nicht begonnen markieren. `media_item` will das Objekt
    // genau so zurück, wie der Server es geschickt hat.
    function setPlayed(mediaItem, played, callback) {
        _sendWithResult(played ? "music/mark_played" : "music/mark_unplayed",
                        { media_item: mediaItem }, callback)
    }

    // Von vorn: der Server setzt ein begonnenes Buch beim Abspielen fort,
    // also erst den Fortschritt verwerfen, dann spielen -- in Reihenfolge,
    // das Abspielen wartet auf die Bestätigung.
    function playFromStart(playerId, mediaItem, callback) {
        setPlayed(mediaItem, false, function (err) {
            if (err) {
                if (callback) {
                    callback(err)
                }
                return
            }
            store.playMedia(playerId, mediaItem.uri, "replace", callback)
        })
    }

    function seek(playerId, positionSeconds) {
        _send("player_queues/seek", { queue_id: playerId,
                                      position: Math.round(positionSeconds) })
    }

    // Durchsage: der Server spricht `message` per TTS auf dem Player (über
    // die Sprachausgabe, die in Music Assistant eingerichtet ist -- hier die
    // von Home Assistant) und setzt danach fort, was lief. volumeLevel < 0
    // heisst: Lautstärke nicht ändern.
    function announce(playerId, message, volumeLevel, preAnnounce, callback) {
        var args = { player_id: playerId, message: message, pre_announce: preAnnounce === true }
        if (volumeLevel >= 0) {
            args.volume_level = Math.round(volumeLevel)
        }
        if (!mass) {
            return
        }
        // Die Antwort kommt erst, wenn die Durchsage gesprochen ist -- das
        // kann mit Gong und TTS-Erzeugung gut 20 s dauern.
        mass.sendCommand("players/cmd/play_announcement", args, function (err) {
            store._noteError(err)
            if (callback) {
                callback(err)
            }
        }, 90000)
    }

    // Einschlaftimer: nach `seconds` hält der Server die Wiedergabe an.
    function setSleepTimer(playerId, seconds, callback) {
        _sendWithResult("players/sleep_timer/set",
                        { player_id: playerId, seconds: Math.max(1, Math.round(seconds)) }, callback)
    }

    function clearSleepTimer(playerId, callback) {
        _sendWithResult("players/sleep_timer/clear", { player_id: playerId }, callback)
    }

    function setVolume(playerId, level) {
        _sendVolume("player:" + playerId, "players/cmd/volume_set",
                    { player_id: playerId, volume_level: Math.round(level) })
    }

    // Lautstärkebefehle je Player in Reihenfolge, nie parallel: parallel
    // abgeschickt kann ein älterer Wert nach einem neueren ankommen, und der
    // Lautsprecher bliebe auf dem falschen stehen. Läuft schon einer, wird
    // nur der neueste Wert gemerkt und nach dessen Antwort geschickt --
    // Zwischenstufen eines Ziehens braucht niemand.
    property var _volumeBusy: ({})
    property var _volumeNext: ({})

    function _sendVolume(key, command, args) {
        if (_volumeBusy[key]) {
            _volumeNext[key] = { command: command, args: args }
            return
        }
        _volumeBusy[key] = true
        if (!mass) {
            _volumeBusy[key] = false
            return
        }
        mass.sendCommand(command, args, function (err) {
            if (err) {
                store._noteError(err)
                console.warn("PlayerStore:", command, "fehlgeschlagen:", err.hint)
            }
            store._volumeBusy[key] = false
            var next = store._volumeNext[key]
            if (next) {
                delete store._volumeNext[key]
                store._sendVolume(key, next.command, next.args)
            }
        })
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
                store._noteError(err)
                // Auch ins Journal: `lastError` zeigt nur die Seite an, die
                // gerade offen ist -- ein Kommando vom Sperrbildschirm oder
                // vom Cover scheiterte sonst vollkommen lautlos.
                console.warn("PlayerStore:", command, "fehlgeschlagen:",
                             err.hint, err.detail ? "(" + err.detail + ")" : "")
            }
        })
    }

    // --- Intern ----------------------------------------------------------

    // "Keine Verbindung" nicht als Fehler unter die Bedienelemente schreiben:
    // die Statuszeile sagt das schon, und nach dem Neuverbinden stünde die
    // Meldung sonst veraltet da.
    function _noteError(err) {
        if (err && !err.offline) {
            store.lastError = err.hint
        }
    }

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
        onAuthenticated: {
            store.refresh()
            store.loadProviders()
        }
        onResynced: store.refresh()
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
