import QtQuick 2.6
import "../lib/DemoData.js" as DemoData
import "../lib/MassModels.js" as Models

// Ein Music-Assistant-Server im Speicher, für den Demomodus: erfundene Räume
// und Musik, ohne Netz. Gleiche Schnittstelle wie MassConnection
// (sendCommand, serverEvent, authenticated, ready, ...), die Seiten merken
// also keinen Unterschied und müssen nichts davon wissen.
//
// Wozu: Bildschirmfotos für den Store, ohne die Räume und die Hörhistorie
// einer echten Wohnung zu zeigen, und ein erster Blick für Leute ohne
// Server. Deshalb gibt es auch Fortschritt, Titelwechsel, Gruppen und
// Lautstärke -- ein Stillleben sähe auf den Fotos falsch aus.
//
// Nachgebildet ist, was die App tatsächlich aufruft, mit dem Verhalten von
// MA 2.10.4 soweit in KONZEPT.md vermessen (Zurück startet nach ein paar
// Sekunden den Titel neu, Radio schickt den ICY-Titel als title, die
// Gruppenlautstärke skaliert die Mitglieder, ...). Unbekannte Kommandos
// antworten mit einem Fehler, wie der echte Server auch.
Item {
    id: demo

    // --- Wie MassConnection --------------------------------------------
    property bool active: false
    property bool autoConnect: true
    readonly property bool isDemo: true
    readonly property string baseUrl: ""
    readonly property string awayUrl: ""
    readonly property string token: ""
    // Nicht leer, weil MassApi.imageUrl() ohne Stammadresse nichts baut. Die
    // Demo-Cover sind aber Dateiadressen und werden durchgereicht, siehe dort.
    readonly property string activeBaseUrl: "http://demo.invalid"
    readonly property string streamBaseUrl: ""
    readonly property bool configured: active
    readonly property bool hasAway: false
    readonly property string connectedVia: ""
    readonly property string compatibilityWarning: ""
    property string connectionState: "idle"
    property string lastError: ""
    property var serverInfo: null
    property string userName: ""
    readonly property bool ready: connectionState === "ready"
    readonly property bool problemVisible: false

    signal serverEvent(string eventType, var message)
    signal authenticated()
    signal resynced()

    function sendCommand(command, args, callback, timeoutMs) {
        if (connectionState !== "ready") {
            if (callback) {
                callback({ hint: "Keine Verbindung", detail: "Demo", offline: true }, null)
            }
            return -1
        }
        var result
        var err = null
        try {
            result = _handle(command, args || {})
        } catch (e) {
            err = { hint: String(e), detail: command }
            console.warn("DemoConnection:", command, "->", e)
        }
        // Wie übers Netz: Antworten kommen nie synchron. Einige Seiten
        // verlassen sich darauf, dass ihr Zustand vor dem Callback steht.
        _later(function () {
            if (callback) {
                callback(err, err ? null : _clone(result))
            }
        })
        return 1
    }

    function connectNow() {
        if (active) {
            _connect()
        }
    }

    function disconnect() {
        connectionState = "idle"
    }

    function checkAfterResume() {
        if (ready) {
            resynced()
        }
    }

    // --- Zustand ---------------------------------------------------------
    property var _data: null
    property var _queues: ({})
    property var _items: ({})
    property var _recent: []
    property int _nextItem: 1
    property var _tasks: []

    readonly property string _artBase: Qt.resolvedUrl("../demo/art/")

    onActiveChanged: {
        if (active) {
            _reset()
            _connect()
        } else {
            clock.stop()
            connectionState = "idle"
            serverInfo = null
            userName = ""
        }
    }

    function _connect() {
        connectionState = "connecting"
        connectTimer.restart()
    }

    Timer {
        id: connectTimer
        interval: 350
        onTriggered: {
            demo.serverInfo = { server_id: "demo", server_version: "2.10.4",
                                schema_version: 65, min_supported_schema_version: 28,
                                name: qsTr("Demo-Server"), base_url: demo.activeBaseUrl }
            demo.userName = "demo"
            demo.connectionState = "ready"
            clock.start()
            demo.authenticated()
        }
    }

    function _clone(value) {
        return value === undefined ? null : JSON.parse(JSON.stringify(value))
    }

    function _now() {
        return Date.now() / 1000
    }

    function _later(fn) {
        _tasks.push(fn)
        if (!taskTimer.running) {
            taskTimer.start()
        }
    }

    Timer {
        id: taskTimer
        interval: 30
        onTriggered: {
            var tasks = demo._tasks
            demo._tasks = []
            for (var i = 0; i < tasks.length; i++) {
                tasks[i]()
            }
        }
    }

    function _reset() {
        _data = DemoData.build(_artBase)
        _queues = {}
        _items = {}
        _nextItem = 1
        var players = _data.players
        for (var i = 0; i < players.length; i++) {
            var id = players[i].player_id
            _queues[id] = {
                queue_id: id, display_name: players[i].name, active: false, available: true,
                items: 0, shuffle_enabled: false, repeat_mode: "off", crossfade_enabled: false,
                current_index: null, current_item: null, elapsed_time: 0,
                elapsed_time_last_updated: _now(), state: "idle"
            }
            _items[id] = []
        }
        for (i = 0; i < _data.start.length; i++) {
            var s = _data.start[i]
            _replaceQueue(s[0], _resolve(s[1]), s[2])
            var q = _queues[s[0]]
            q.elapsed_time = s[3]
            q.elapsed_time_last_updated = _now()
            _setState(s[0], s[4])
        }
        _queues["demo-wohnzimmer"].repeat_mode = "all"
        for (i = 0; i < _data.groups.length; i++) {
            var g = _data.groups[i]
            for (var m = 0; m < g[1].length; m++) {
                _join(g[0], g[1][m])
            }
        }
        _recent = [_findByUri("library://album/al1"), _findByUri("library://radio/r1"),
                   _findByUri("library://audiobook/b1"), _findByUri("library://playlist/pl1"),
                   _findByUri("library://podcast_episode/e2"), _findByUri("library://album/al7"),
                   _findByUri("library://artist/ar3")]
        _syncAllMedia()
    }

    // --- Nachschlagen ----------------------------------------------------

    function _allItems() {
        var d = _data
        return [].concat(d.artists, d.albums, d.tracks, d.playlists, d.radios,
                         d.audiobooks, d.podcasts, d.episodes,
                         d.stream.artists, d.stream.albums, d.stream.tracks)
    }

    function _findByUri(uri) {
        var all = _allItems()
        for (var i = 0; i < all.length; i++) {
            if (all[i].uri === uri) {
                return all[i]
            }
        }
        return null
    }

    function _collection(type) {
        switch (type) {
        case "artists": case "artist": return _data.artists
        case "albums": case "album": return _data.albums
        case "tracks": case "track": return _data.tracks
        case "playlists": case "playlist": return _data.playlists
        case "radios": case "radio": return _data.radios
        case "podcasts": case "podcast": return _data.podcasts
        case "audiobooks": case "audiobook": return _data.audiobooks
        case "podcast_episode": return _data.episodes
        }
        throw "Unbekannter Medientyp: " + type
    }

    // Was ein Abspielauftrag tatsächlich in die Warteschlange legt.
    function _resolve(uri) {
        var item = _findByUri(uri)
        if (!item) {
            throw "Nicht gefunden: " + uri
        }
        switch (item.media_type) {
        case "album":
            if (item.provider !== DemoData.LIBRARY) {
                return item.item_id === "s-al1" ? _data.stream.tracks.slice() : []
            }
            return _data.tracksByAlbum[item.item_id].slice()
        case "playlist":
            return _data.tracksByPlaylist[item.item_id].slice()
        case "artist":
            var out = []
            for (var i = 0; i < _data.albums.length; i++) {
                if (_data.albums[i].artists[0].item_id === item.item_id) {
                    out = out.concat(_data.tracksByAlbum[_data.albums[i].item_id])
                }
            }
            return out
        case "podcast":
            return _data.episodes.slice()
        }
        return [item]
    }

    function _player(id) {
        for (var i = 0; i < _data.players.length; i++) {
            if (_data.players[i].player_id === id) {
                return _data.players[i]
            }
        }
        throw "Unbekannter Player: " + id
    }

    // Kommandos an ein angeschlossenes Mitglied gehen an den Anführer --
    // dessen Warteschlange spielt, wie beim echten Server.
    function _queueId(id) {
        var p = _player(id)
        return p.synced_to ? p.synced_to : id
    }

    // --- Warteschlange ---------------------------------------------------

    function _makeItem(media) {
        var id = "demo-qi-" + _nextItem
        _nextItem += 1
        return { queue_item_id: id, name: media.name,
                 duration: media.media_type === "radio" ? null : (media.duration || 0),
                 media_item: media }
    }

    function _elapsed(q) {
        var base = q.elapsed_time || 0
        if (q.state !== "playing") {
            return base
        }
        var speed = typeof q.playback_speed === "number" ? q.playback_speed : 1
        return base + Math.max(0, _now() - q.elapsed_time_last_updated) * speed
    }

    function _freeze(q) {
        q.elapsed_time = _elapsed(q)
        q.elapsed_time_last_updated = _now()
    }

    function _currentMedia(q) {
        var item = q.current_item
        if (!item) {
            return null
        }
        var m = item.media_item
        var image = (m.metadata && m.metadata.images && m.metadata.images.length > 0)
                ? m.metadata.images[0].proxy_id : ""
        switch (m.media_type) {
        case "radio":
            var station = m.name.replace(/\s*\(.*\)\s*$/, "")
            var titles = _data.radioTitles[m.item_id] || [station]
            var slot = Math.floor(_now() / 45) % titles.length
            return { title: titles[slot], artist: station, album: m.name, image_url: image,
                     duration: null, media_type: "radio", uri: m.uri }
        case "audiobook":
            return { title: m.name, artist: Models.primaryAuthor(m), album: "", image_url: image,
                     duration: m.duration, media_type: "audiobook", uri: m.uri }
        case "podcast_episode":
            return { title: m.name, artist: _data.podcasts[0].name, album: "", image_url: image,
                     duration: m.duration, media_type: "podcast_episode", uri: m.uri }
        }
        return { title: m.name, artist: Models.artistNames(m),
                 album: m.album ? m.album.name : "", image_url: image,
                 duration: m.duration, media_type: m.media_type, uri: m.uri }
    }

    function _setIndex(qid, index) {
        var q = _queues[qid]
        var list = _items[qid]
        if (index === null || index < 0 || index >= list.length) {
            q.current_index = null
            q.current_item = null
        } else {
            q.current_index = index
            q.current_item = list[index]
        }
        q.elapsed_time = 0
        q.elapsed_time_last_updated = _now()
        var spoken = q.current_item && Models.isSpokenType(q.current_item.media_item.media_type)
        if (spoken) {
            if (typeof q.playback_speed !== "number") {
                q.playback_speed = 1
            }
            var m = q.current_item.media_item
            if (m.resume_position_ms > 0 && !Models.isFullyPlayed(m)) {
                q.elapsed_time = m.resume_position_ms / 1000
            }
        } else {
            delete q.playback_speed
        }
    }

    function _replaceQueue(qid, medias, startIndex) {
        var list = []
        for (var i = 0; i < medias.length; i++) {
            list.push(_makeItem(medias[i]))
        }
        _items[qid] = list
        _queues[qid].items = list.length
        _queues[qid].active = list.length > 0
        _setIndex(qid, list.length > 0 ? (startIndex || 0) : null)
    }

    function _setState(qid, state) {
        var q = _queues[qid]
        _freeze(q)
        q.state = state
        _player(qid).playback_state = state
    }

    // Spielstand eines Hörbuchs/einer Folge mitschreiben, damit "Weiterhören"
    // und die Hörbuchseite stimmen.
    function _recordProgress(q) {
        if (!q.current_item) {
            return
        }
        var m = q.current_item.media_item
        if (!Models.isSpokenType(m.media_type)) {
            return
        }
        var original = _findByUri(m.uri)
        if (original) {
            original.resume_position_ms = Math.round(_elapsed(q) * 1000)
        }
    }

    function _advance(qid, forward) {
        var q = _queues[qid]
        var list = _items[qid]
        if (list.length === 0) {
            return
        }
        var index = q.current_index === null ? 0 : q.current_index + (forward ? 1 : -1)
        if (index >= list.length) {
            if (q.repeat_mode === "all") {
                index = 0
            } else {
                _setState(qid, "idle")
                _setIndex(qid, list.length - 1)
                return
            }
        }
        if (index < 0) {
            index = 0
        }
        var state = q.state
        _setIndex(qid, index)
        q.state = state === "idle" ? "playing" : state
        _player(qid).playback_state = q.state
    }

    // --- Gruppen ---------------------------------------------------------

    function _join(leaderId, memberId) {
        var leader = _player(leaderId)
        var member = _player(memberId)
        if (member.synced_to === leaderId) {
            return
        }
        if (member.synced_to) {
            _leave(memberId)
        }
        member.synced_to = leaderId
        member.active_group = null
        leader.group_childs = leader.group_childs.concat([memberId])
        leader.group_members = [leaderId].concat(leader.group_childs)
        _updateGroupVolume(leaderId)
    }

    function _leave(memberId) {
        var member = _player(memberId)
        var leaderId = member.synced_to
        if (!leaderId) {
            return
        }
        var leader = _player(leaderId)
        leader.group_childs = leader.group_childs.filter(function (id) { return id !== memberId })
        leader.group_members = leader.group_childs.length > 0
                ? [leaderId].concat(leader.group_childs) : []
        member.synced_to = null
        member.playback_state = _queues[memberId].state
        _updateGroupVolume(leaderId)
    }

    // Die gemeldete Gruppenlautstärke folgt dem lautesten Mitglied, wie auf
    // der eigenen Anlage beobachtet (KONZEPT.md Abschnitt 25).
    function _updateGroupVolume(leaderId) {
        var leader = _player(leaderId)
        var max = leader.volume_level
        for (var i = 0; i < leader.group_childs.length; i++) {
            max = Math.max(max, _player(leader.group_childs[i]).volume_level)
        }
        leader.group_volume = max
    }

    // Anzeige der Player aus ihrer Warteschlange nachziehen; Mitglieder
    // zeigen, was ihr Anführer spielt.
    function _syncAllMedia() {
        var players = _data.players
        for (var i = 0; i < players.length; i++) {
            var p = players[i]
            var qid = p.synced_to ? p.synced_to : p.player_id
            var q = _queues[qid]
            p.current_media = _currentMedia(q)
            p.playback_state = q.state
        }
    }

    // --- Ereignisse ------------------------------------------------------

    function _emitAll(itemsChangedFor) {
        _syncAllMedia()
        var players = _data.players
        for (var i = 0; i < players.length; i++) {
            serverEvent("player_updated", { event: "player_updated",
                                            object_id: players[i].player_id,
                                            data: _clone(players[i]) })
            var q = _queues[players[i].player_id]
            serverEvent("queue_updated", { event: "queue_updated", object_id: q.queue_id,
                                           data: _clone(q) })
        }
        if (itemsChangedFor) {
            serverEvent("queue_items_updated", { event: "queue_items_updated",
                                                 object_id: itemsChangedFor, data: null })
        }
    }

    function _changed(itemsChangedFor) {
        _later(function () { demo._emitAll(itemsChangedFor) })
    }

    // Der Lauf der Zeit: Titelende, Wechsel des Radiotitels.
    Timer {
        id: clock
        interval: 1000
        repeat: true
        property int ticks: 0
        onTriggered: {
            ticks += 1
            var changed = false
            // Einschlaftimer: abgelaufen -> anhalten, wie der Server.
            var ps = demo._data.players
            for (var pi = 0; pi < ps.length; pi++) {
                var sp = ps[pi]
                if (sp.sleep_timer_expires_at > 0 && sp.sleep_timer_expires_at <= demo._now()) {
                    sp.sleep_timer_expires_at = null
                    var sq = demo._queueId(sp.player_id)
                    if (demo._queues[sq].state === "playing") {
                        demo._setState(sq, "paused")
                    }
                    changed = true
                }
            }
            for (var qid in demo._queues) {
                var q = demo._queues[qid]
                if (q.state !== "playing" || !q.current_item) {
                    continue
                }
                demo._recordProgress(q)
                var duration = q.current_item.duration
                if (duration > 0 && demo._elapsed(q) >= duration) {
                    var m = q.current_item.media_item
                    if (Models.isSpokenType(m.media_type)) {
                        var original = demo._findByUri(m.uri)
                        if (original) {
                            original.fully_played = m.media_type === "audiobook" ? true : 1
                            original.resume_position_ms = 0
                        }
                    }
                    if (q.repeat_mode === "one") {
                        q.elapsed_time = 0
                        q.elapsed_time_last_updated = demo._now()
                    } else {
                        demo._advance(qid, true)
                    }
                    changed = true
                }
            }
            // Radiotitel wechseln alle 45 s (siehe _currentMedia).
            if (changed || ticks % 15 === 0) {
                demo._emitAll(null)
            }
        }
    }

    // --- Kommandos -------------------------------------------------------

    function _sorted(list) {
        return list.slice().sort(function (a, b) { return a.name.localeCompare(b.name) })
    }

    function _matches(item, query) {
        if (item.name.toLowerCase().indexOf(query) !== -1) {
            return true
        }
        return Models.artistNames(item).toLowerCase().indexOf(query) !== -1
    }

    function _handle(command, args) {
        var qid, q, p, list, i, item

        var library = /^music\/(artists|albums|tracks|playlists|radios|podcasts|audiobooks)\/(count|library_items)$/
                .exec(command)
        if (library) {
            list = _sorted(_collection(library[1]))
            if (args.favorite) {
                list = list.filter(function (x) { return x.favorite === true })
            }
            if (args.search) {
                var s = String(args.search).toLowerCase()
                list = list.filter(function (x) { return demo._matches(x, s) })
            }
            if (library[2] === "count") {
                return list.length
            }
            var offset = args.offset || 0
            return list.slice(offset, offset + (args.limit || 500))
        }

        switch (command) {
        case "info":
            return serverInfo
        case "providers":
            return [{ instance_id: "library", domain: "library", name: qsTr("Bibliothek") },
                    { instance_id: DemoData.STREAM, domain: "klangwelle", name: "Klangwelle" }]
        case "players/all":
            _syncAllMedia()
            return _data.players
        case "player_queues/all":
            var queues = []
            for (qid in _queues) {
                queues.push(_queues[qid])
            }
            return queues
        case "player_queues/items":
            list = _items[args.queue_id] || []
            var off = args.offset || 0
            return list.slice(off, off + (args.limit || 500)).map(function (x, n) {
                var copy = demo._clone(x)
                copy.index = off + n
                return copy
            })

        // --- Transport
        case "player_queues/play_pause":
            qid = _queueId(args.queue_id)
            q = _queues[qid]
            if (!q.current_item) {
                throw "Warteschlange leer"
            }
            _setState(qid, q.state === "playing" ? "paused" : "playing")
            _changed()
            return null
        case "player_queues/next":
            _advance(_queueId(args.queue_id), true)
            _changed()
            return null
        case "player_queues/previous":
            qid = _queueId(args.queue_id)
            q = _queues[qid]
            // Wie MA: nach ein paar Sekunden erst an den Anfang des Titels.
            if (_elapsed(q) > 5) {
                q.elapsed_time = 0
                q.elapsed_time_last_updated = _now()
            } else {
                _advance(qid, false)
            }
            _changed()
            return null
        case "player_queues/seek":
            qid = _queueId(args.queue_id)
            q = _queues[qid]
            q.elapsed_time = Math.max(0, args.position)
            q.elapsed_time_last_updated = _now()
            _recordProgress(q)
            _changed()
            return null
        case "player_queues/play_index":
            qid = _queueId(args.queue_id)
            _setIndex(qid, args.index)
            _setState(qid, "playing")
            _changed()
            return null
        case "player_queues/set_playback_speed":
            q = _queues[_queueId(args.queue_id)]
            _freeze(q)
            q.playback_speed = args.speed
            _changed()
            return null
        case "player_queues/shuffle":
            _queues[_queueId(args.queue_id)].shuffle_enabled = args.shuffle_enabled === true
            _changed()
            return null
        case "player_queues/repeat":
            _queues[_queueId(args.queue_id)].repeat_mode = args.repeat_mode
            _changed()
            return null
        case "player_queues/crossfade":
            _queues[_queueId(args.queue_id)].crossfade_enabled = args.crossfade_enabled === true
            _changed()
            return null

        // --- Warteschlange bearbeiten
        case "player_queues/play_media":
            qid = _queueId(args.queue_id)
            q = _queues[qid]
            var medias = _resolve(args.media)
            if (args.shuffle === true) {
                medias.sort(function () { return Math.random() - 0.5 })
            }
            var target = _findByUri(args.media)
            if (target) {
                _recent = [target].concat(_recent.filter(function (x) { return x.uri !== target.uri }))
                        .slice(0, 20)
            }
            var fresh = medias.map(function (m) { return demo._makeItem(m) })
            list = _items[qid]
            var at = q.current_index === null ? list.length : q.current_index + 1
            if (args.option === "replace" || list.length === 0) {
                _items[qid] = fresh
                _setIndex(qid, 0)
                _setState(qid, "playing")
            } else if (args.option === "play") {
                _items[qid] = list.slice(0, at).concat(fresh, list.slice(at))
                _setIndex(qid, at)
                _setState(qid, "playing")
            } else if (args.option === "next") {
                _items[qid] = list.slice(0, at).concat(fresh, list.slice(at))
            } else {
                _items[qid] = list.concat(fresh)
            }
            q.items = _items[qid].length
            q.active = true
            _changed(qid)
            return null
        case "player_queues/move_item":
            qid = args.queue_id
            list = _items[qid]
            for (i = 0; i < list.length; i++) {
                if (list[i].queue_item_id === args.queue_item_id) {
                    break
                }
            }
            var to = i + args.pos_shift
            q = _queues[qid]
            // Wie MA: nichts vor den laufenden Eintrag schieben.
            if (i < list.length && to >= 0 && to < list.length
                    && (q.current_index === null || to > q.current_index)) {
                item = list.splice(i, 1)[0]
                list.splice(to, 0, item)
            }
            _changed(qid)
            return null
        case "player_queues/move_item_end":
            qid = args.queue_id
            list = _items[qid]
            for (i = 0; i < list.length; i++) {
                if (list[i].queue_item_id === args.queue_item_id && i !== _queues[qid].current_index) {
                    list.push(list.splice(i, 1)[0])
                    break
                }
            }
            _changed(qid)
            return null
        case "player_queues/delete_item":
            qid = args.queue_id
            q = _queues[qid]
            list = _items[qid]
            for (i = 0; i < list.length; i++) {
                if (list[i].queue_item_id === args.item_id_or_index && i !== q.current_index) {
                    list.splice(i, 1)
                    if (q.current_index !== null && i < q.current_index) {
                        q.current_index -= 1
                    }
                    break
                }
            }
            q.items = list.length
            _changed(qid)
            return null
        case "player_queues/clear":
            qid = args.queue_id
            _items[qid] = []
            _setState(qid, "idle")
            _setIndex(qid, null)
            _queues[qid].items = 0
            _queues[qid].active = false
            _changed(qid)
            return null
        case "player_queues/transfer":
            var from = _queueId(args.source_queue_id)
            var to2 = args.target_queue_id
            _freeze(_queues[from])
            var elapsed = _queues[from].elapsed_time
            _items[to2] = _items[from]
            _queues[to2].items = _items[to2].length
            _queues[to2].active = true
            _setIndex(to2, _queues[from].current_index)
            _queues[to2].elapsed_time = elapsed
            _setState(to2, args.auto_play ? "playing" : "paused")
            _items[from] = []
            _setState(from, "idle")
            _setIndex(from, null)
            _queues[from].items = 0
            _queues[from].active = false
            _changed(to2)
            return null
        case "player_queues/save_as_playlist":
            var tracks = _items[args.queue_id].map(function (x) { return x.media_item })
                    .filter(function (m) { return m.media_type === "track" })
            var pid = "pl" + (_data.playlists.length + 1)
            _data.playlists.push({ item_id: pid, provider: DemoData.LIBRARY, media_type: "playlist",
                                   uri: "library://playlist/" + pid, name: args.name, owner: "Demo",
                                   metadata: tracks.length > 0 ? tracks[0].metadata : {},
                                   favorite: false, is_playable: true })
            _data.tracksByPlaylist[pid] = tracks
            return null

        // --- Player
        case "players/cmd/volume_set":
            p = _player(args.player_id)
            p.volume_level = Math.max(0, Math.min(100, args.volume_level))
            if (p.synced_to) {
                _updateGroupVolume(p.synced_to)
            } else if (p.group_childs.length > 0) {
                _updateGroupVolume(p.player_id)
            } else {
                p.group_volume = p.volume_level
            }
            _changed()
            return null
        case "players/cmd/group_volume":
            p = _player(args.player_id)
            var ids = [p.player_id].concat(p.group_childs)
            var current = p.group_volume > 0 ? p.group_volume : 1
            var level = Math.max(0, Math.min(100, args.volume_level))
            // Wie MA 2.10.4: nach unten im Verhältnis, nach oben jedes um
            // denselben Anteil Richtung 100.
            for (i = 0; i < ids.length; i++) {
                var member = _player(ids[i])
                var v = member.volume_level
                member.volume_level = Math.round(level <= current
                        ? v * level / current
                        : v + (100 - v) * (level - current) / Math.max(1, 100 - current))
            }
            p.group_volume = level
            _changed()
            return null
        case "players/cmd/volume_mute":
            _player(args.player_id).volume_muted = args.muted === true
            _changed()
            return null
        case "players/cmd/set_members":
            var add = args.player_ids_to_add || []
            var remove = args.player_ids_to_remove || []
            for (i = 0; i < remove.length; i++) {
                _leave(remove[i])
            }
            for (i = 0; i < add.length; i++) {
                _join(args.target_player, add[i])
            }
            _changed()
            return null
        case "players/cmd/ungroup":
            p = _player(args.player_id)
            if (p.synced_to) {
                _leave(p.player_id)
            } else {
                var childs = p.group_childs.slice()
                for (i = 0; i < childs.length; i++) {
                    _leave(childs[i])
                }
            }
            _changed()
            return null
        case "players/sleep_timer/set":
            p = _player(args.player_id)
            p.sleep_timer_expires_at = _now() + args.seconds
            _changed()
            return p.sleep_timer_expires_at
        case "players/sleep_timer/clear":
            _player(args.player_id).sleep_timer_expires_at = null
            _changed()
            return null
        case "players/sleep_timer/get":
            return _player(args.player_id).sleep_timer_expires_at || null
        case "metadata/get_track_lyrics":
            var text = args.track ? _data.lyrics[args.track.name] : null
            return [null, text || null]
        case "players/cmd/power":
            _player(args.player_id).powered = args.powered === true
            _changed()
            return null

        // --- Bibliothek
        case "music/albums/album_tracks":
            if (args.item_id === "s-al1") {
                return _data.stream.tracks
            }
            return _data.tracksByAlbum[args.item_id] || []
        case "music/artists/artist_albums":
            return _data.albums.filter(function (a) { return a.artists[0].item_id === args.item_id })
        case "music/playlists/playlist_tracks":
            return _data.tracksByPlaylist[args.item_id] || []
        case "music/podcasts/podcast_episodes":
            return _data.episodes
        case "music/audiobooks/get":
            return _data.audiobooks[0]
        case "music/recently_played_items":
            return _recent.slice(0, args.limit || 50)
        case "music/in_progress_items":
            return [].concat(_data.audiobooks, _data.episodes).filter(function (x) {
                return x.resume_position_ms > 0 && !Models.isFullyPlayed(x)
            })
        case "music/search":
            var query = String(args.search_query || "").toLowerCase()
            var libraryOnly = args.providers && args.providers.length === 1
                    && args.providers[0] === "library"
            var limit = args.limit || 25
            var find = function (listIn) {
                return listIn.filter(function (x) { return demo._matches(x, query) }).slice(0, limit)
            }
            var stream = _data.stream
            return {
                artists: find(_data.artists.concat(libraryOnly ? [] : stream.artists)),
                albums: find(_data.albums.concat(libraryOnly ? [] : stream.albums)),
                tracks: find(_data.tracks.concat(libraryOnly ? [] : stream.tracks)),
                playlists: find(_data.playlists),
                radio: find(_data.radios),
                podcasts: find(_data.podcasts),
                audiobooks: find(_data.audiobooks)
            }
        case "music/favorites/add_item":
            item = _findByUri(args.item)
            if (item) {
                item.favorite = true
            }
            return null
        case "music/favorites/remove_item":
            list = _collection(args.media_type)
            for (i = 0; i < list.length; i++) {
                if (list[i].item_id === String(args.library_item_id)) {
                    list[i].favorite = false
                }
            }
            return null
        case "music/mark_played":
        case "music/mark_unplayed":
            item = _findByUri(args.media_item ? args.media_item.uri : "")
            if (!item) {
                throw "Nicht gefunden"
            }
            var played = command === "music/mark_played"
            item.fully_played = item.media_type === "podcast_episode" ? (played ? 1 : 0) : played
            item.resume_position_ms = 0
            return null
        }
        throw "Im Demomodus nicht verfügbar: " + command
    }
}
