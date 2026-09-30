.pragma library
.import "MassApi.js" as MassApi

// Reine Rechen- und Lesehilfen auf den Server-Objekten (Player, PlayerQueue).
// Keine Anzeigetexte: alles Sichtbare wird in QML mit qsTr() gebaut, damit die
// Übersetzung einen sauberen Kontext hat. Hier stehen nur Werte.
//
// Feldnamen stammen aus einem Mitschnitt des echten Servers (MA 2.10.4), nicht
// aus der Dokumentation -- siehe KONZEPT.md Abschnitt 15.

// --- Player --------------------------------------------------------------

// PlayerFeature-Werte. Achtung, das gilt nur für Kommandos unter
// `players/cmd/*` -- also Lautstärke, Stummschaltung, Netzschalter. Alles, was
// an die Warteschlange geht (`player_queues/*`: Play/Pause, Weiter, Zurück,
// Springen), fährt der Server selbst und prüft dabei keine einzige
// PlayerFeature; solche Knöpfe danach zu sperren, sperrt sie grundlos.
// Am echten Gerät bestätigt: der benutzte Player führt weder "next_previous"
// noch "seek" oder "pause" auf und springt trotzdem einwandfrei.
var FEATURE_VOLUME_SET = "volume_set"
var FEATURE_VOLUME_MUTE = "volume_mute"
var FEATURE_POWER = "power"

function hasFeature(player, feature) {
    if (!player || !player.supported_features) {
        return false
    }
    return player.supported_features.indexOf(feature) !== -1
}

// `power_control` ist "none", wenn der Player gar keinen Ein/Aus-Begriff hat --
// dann darf auch kein Schalter erscheinen. Auf der Zielanlage trifft das auf
// alle acht Player zu, die Abfrage ist also nicht theoretisch.
function hasPower(player) {
    return hasFeature(player, FEATURE_POWER)
            && player.power_control !== undefined
            && player.power_control !== "none"
}

function playbackState(player) {
    if (!player) {
        return "unknown"
    }
    return player.playback_state || player.state || "unknown"
}

function isPlaying(player) {
    return playbackState(player) === "playing"
}

function isAvailable(player) {
    return !!player && player.available !== false
}

function playerName(player) {
    if (!player) {
        return ""
    }
    return player.display_name || player.name || player.player_id || ""
}

// Sichtbare Player: abgeschaltete (`enabled: false`) gehören gar nicht in die
// Liste, nicht verfügbare schon -- die werden nur ausgegraut, sonst
// verschwindet ein Lautsprecher scheinbar grundlos, nur weil er gerade
// schläft. Sortiert nach Namen, der zuletzt benutzte Player nach oben.
function visiblePlayers(players, preferredId) {
    var out = []
    for (var i = 0; i < players.length; i++) {
        if (players[i].enabled !== false) {
            out.push(players[i])
        }
    }
    out.sort(function (a, b) {
        if (preferredId) {
            if (a.player_id === preferredId) {
                return -1
            }
            if (b.player_id === preferredId) {
                return 1
            }
        }
        return playerName(a).localeCompare(playerName(b))
    })
    return out
}

// --- Was gerade läuft ----------------------------------------------------

// Der Server hält dieselbe Information an zwei Stellen: `player.current_media`
// (fertig aufbereitet, inklusive einer vollqualifizierten Bild-URL) und
// `queue.current_item` (mit Dauer und Queue-Position). Diese Funktion nimmt von
// beiden das Beste und liefert null, wenn nichts läuft.
//
// baseUrl ist die Adresse, über die die App verbunden ist; die Bildadresse
// wird darauf umgeschrieben (MassApi.rebaseImageUrl).
function nowPlaying(player, queue, baseUrl) {
    var media = player ? player.current_media : null
    var item = queue ? queue.current_item : null
    if (!media && !item) {
        return null
    }

    var title = ""
    var artist = ""
    var album = ""
    if (media) {
        title = media.title || ""
        artist = media.artist || ""
        album = media.album || ""
    }
    if (!title && item) {
        // Fallback: der Queue-Eintrag führt beides in einem Feld ("Interpret -
        // Titel"), das lässt sich nur grob wieder trennen.
        title = item.name || ""
        if (item.media_item && item.media_item.name) {
            title = item.media_item.name
        }
    }

    var itemMedia = (item && item.media_item) ? item.media_item : null
    var mediaType = (media && media.media_type) ? media.media_type
                                                : (itemMedia ? itemMedia.media_type || "" : "")
    var live = isLiveType(mediaType) || (itemMedia !== null && isLiveType(itemMedia.media_type))

    // Bei einem Sender schickt MA 2.10.4 den Stream-Titel (ICY, oft
    // "Interpret - Titel") als title, den Sender als artist und dessen
    // Eintrag ("Radio SRF 3 (AAC 192)") als album. Diese Albumzeile
    // wiederholt nur den Sender -- weglassen.
    if (live && artist.length > 0
            && album.toLowerCase().indexOf(artist.toLowerCase()) === 0) {
        album = ""
    }

    return {
        title: title,
        artist: artist,
        album: album,
        // image_url kommt bereits als vollständige /imageproxy-Adresse mit
        // ?size=-Parameter vom Server -- gebaut wird nichts, nur der
        // Adressteil vor /imageproxy ersetzt.
        imageUrl: (media && media.image_url)
                  ? MassApi.rebaseImageUrl(media.image_url, baseUrl) : "",
        duration: live ? 0 : durationOf(media, item),
        mediaType: mediaType,
        isLive: live,
        isSpoken: isSpokenType(mediaType)
                  || (itemMedia !== null && isSpokenType(itemMedia.media_type)),
        chapters: chaptersOf(itemMedia)
    }
}

// Radio ist ein Live-Strom: keine Länge, kein Springen, kein Zufall.
function isLiveType(mediaType) {
    return mediaType === "radio"
}

// Gesprochenes: statt Zufall/Wiederholen Sprünge um Sekunden, Kapitel und
// Tempo.
function isSpokenType(mediaType) {
    return mediaType === "audiobook" || mediaType === "podcast_episode"
}

// Kapitel eines Hörbuchs aus `metadata.chapters` (position, name, start, end;
// Sekunden ab Buchbeginn), nach Beginn sortiert. Der Queue-Eintrag trägt sie
// im vollen media_item mit.
function chaptersOf(mediaItem) {
    var raw = (mediaItem && mediaItem.metadata && mediaItem.metadata.chapters)
            ? mediaItem.metadata.chapters : []
    var out = []
    for (var i = 0; i < raw.length; i++) {
        if (raw[i] && typeof raw[i].start === "number") {
            out.push(raw[i])
        }
    }
    out.sort(function (a, b) { return a.start - b.start })
    return out
}

// Das Kapitel, in dem `elapsed` liegt, oder null.
function currentChapter(chapters, elapsed) {
    var found = null
    for (var i = 0; i < (chapters || []).length; i++) {
        if (chapters[i].start <= elapsed) {
            found = chapters[i]
        }
    }
    return found
}

// Innerhalb so vieler Sekunden nach einem Kapitelbeginn geht "Zurück" ins
// vorige Kapitel statt an den Anfang des laufenden -- wie beim CD-Spieler.
var PREVIOUS_CHAPTER_GRACE = 5

// Wohin "Weiter" (forward) bzw. "Zurück" in einem Buch mit Kapiteln springt,
// in Sekunden. -1 heisst: keine Kapitel oder keins mehr danach -- dann gilt
// das gewöhnliche next/previous der Warteschlange.
function chapterSeek(chapters, forward, elapsed) {
    if (!chapters || chapters.length === 0) {
        return -1
    }
    var i
    if (forward) {
        for (i = 0; i < chapters.length; i++) {
            if (chapters[i].start > elapsed + 0.5) {
                return Math.ceil(chapters[i].start)
            }
        }
        return -1
    }
    var currentIndex = -1
    for (i = 0; i < chapters.length; i++) {
        if (chapters[i].start <= elapsed) {
            currentIndex = i
        }
    }
    var currentStart = currentIndex >= 0 ? chapters[currentIndex].start : 0
    if (elapsed - currentStart > PREVIOUS_CHAPTER_GRACE) {
        return Math.ceil(currentStart)
    }
    return currentIndex > 0 ? Math.ceil(chapters[currentIndex - 1].start) : 0
}

function durationOf(media, item) {
    if (media && media.duration > 0) {
        return media.duration
    }
    if (item && item.duration > 0) {
        return item.duration
    }
    return 0
}

// Abgelaufene Spielzeit in Sekunden. Der Server schickt `elapsed_time` nur
// gelegentlich (plus ein queue_time_updated-Ereignis je Sekunde, das aber nicht
// garantiert durchkommt), dazu den Zeitstempel `elapsed_time_last_updated`.
// Zwischen zwei Meldungen wird deshalb lokal weitergezählt -- aber nur während
// tatsächlich gespielt wird, sonst liefe die Anzeige im Pausenzustand weiter.
function elapsedSeconds(queue, player, nowMs) {
    if (!queue) {
        return 0
    }
    var base = queue.elapsed_time || 0
    if (!isPlaying(player)) {
        return base
    }
    var stamp = queue.elapsed_time_last_updated
    if (!stamp) {
        return base
    }
    var drift = (nowMs / 1000) - stamp
    if (drift < 0) {
        // Uhren von Telefon und Server laufen auseinander; lieber den nackten
        // Serverwert zeigen als in die Vergangenheit zu rechnen.
        return base
    }
    return base + drift
}

function formatTime(seconds) {
    if (!(seconds > 0)) {
        return "0:00"
    }
    var total = Math.floor(seconds)
    var h = Math.floor(total / 3600)
    var m = Math.floor((total % 3600) / 60)
    var s = total % 60
    var mm = (h > 0 && m < 10) ? "0" + m : String(m)
    var ss = s < 10 ? "0" + s : String(s)
    return h > 0 ? (h + ":" + mm + ":" + ss) : (mm + ":" + ss)
}

// --- Medienobjekte (Bibliothek) -----------------------------------------

// Bildkennung eines Medienobjekts. In der Bibliothek liefert der Server nur
// `metadata.images[]` -- daraus zählt `proxy_id`, nicht `path` (der ist
// providerspezifisch und für den Bildproxy wertlos). Bei Now Playing ist das
// anders: dort steht in `current_media.image_url` bereits eine fertige
// Adresse, siehe nowPlaying().
function imageProxyId(item) {
    if (!item) {
        return ""
    }
    // Zwei Formen, je nachdem woher das Objekt kommt: ein volles Medienobjekt
    // aus der Bibliothek führt `metadata.images[]`, ein schlanker Verweis
    // (ItemMapping, etwa aus "zuletzt gehört" oder aus der Interpretenliste
    // eines Albums) dagegen ein einzelnes `image`. Beide tragen `proxy_id`.
    var images = (item.metadata && item.metadata.images) ? item.metadata.images : []
    for (var i = 0; i < images.length; i++) {
        if (images[i] && images[i].proxy_id) {
            return images[i].proxy_id
        }
    }
    if (item.image && item.image.proxy_id) {
        return item.image.proxy_id
    }
    return ""
}

// Die Interpreten eines Albums oder Titels als eine Zeile.
function artistNames(item) {
    if (!item || !item.artists || item.artists.length === 0) {
        return ""
    }
    var names = []
    for (var i = 0; i < item.artists.length; i++) {
        if (item.artists[i] && item.artists[i].name) {
            names.push(item.artists[i].name)
        }
    }
    return names.join(", ")
}

// Ein Medienobjekt ist spielbar, wenn der Server es so markiert. Titel aus
// einem abgemeldeten Dienst bleiben in der Bibliothek stehen, lassen sich aber
// nicht abspielen -- die gehören ausgegraut, nicht versteckt.
function isPlayable(item) {
    return !!item && item.is_playable !== false
}

// --- Gruppen -------------------------------------------------------------

// Die Player, mit denen sich dieser zusammenschalten lässt. Der Server führt
// das je Player als `can_group_with`; was dort nicht steht, kann der Anbieter
// nicht synchronisieren (AirPlay und Sonos etwa gruppieren nur jeweils unter
// ihresgleichen, plus die anbieterübergreifenden Fälle, die MA selbst kann).
function groupCandidateIds(player) {
    if (!player || !player.can_group_with) {
        return []
    }
    return player.can_group_with
}

// Gehört `other` gerade zur Gruppe von `leader`? Der Server führt das
// doppelt -- als Kindliste beim Anführer und als Rückverweis beim Mitglied --
// und je nach Anbieter ist mal das eine, mal das andere gesetzt. Deshalb
// beides prüfen.
function isGroupMember(leader, other) {
    if (!leader || !other || leader.player_id === other.player_id) {
        return false
    }
    if (other.synced_to === leader.player_id) {
        return true
    }
    if (other.active_group === leader.player_id) {
        return true
    }
    var childs = leader.group_childs || []
    if (childs.indexOf(other.player_id) !== -1) {
        return true
    }
    var members = leader.group_members || []
    return members.indexOf(other.player_id) !== -1
}

// Ist dieser Player selbst an einen anderen angeschlossen? Liefert dessen Id
// oder "".
function groupLeaderOf(player) {
    if (!player) {
        return ""
    }
    return player.synced_to || player.active_group || ""
}

// Die Lautsprecher einer Gruppe, der Anführer zuerst. Ein fester
// Gruppen-Player (`type === "group"`) spielt nicht selbst, dann nur seine
// Mitglieder -- in der Reihenfolge, in der der Server sie führt.
function groupMembers(leader, players) {
    if (!leader) {
        return []
    }
    var out = leader.type === "group" ? [] : [leader]
    for (var i = 0; i < players.length; i++) {
        if (isGroupMember(leader, players[i])) {
            out.push(players[i])
        }
    }
    return out
}

function hasGroupMembers(leader, players) {
    for (var i = 0; i < players.length; i++) {
        if (isGroupMember(leader, players[i])) {
            return true
        }
    }
    return false
}

// --- MPRIS ---------------------------------------------------------------

// `mpris:trackid` muss ein gültiger **D-Bus-Objektpfad** sein, keine blosse
// Kennung -- eine nackte queue_item_id quittiert Qt mit
// "QDBusObjectPath: invalid path" und verwirft das Feld. Erlaubt sind in
// einem Pfadelement nur A-Z, a-z, 0-9 und _; alles andere wird ersetzt.
function mprisTrackId(queueItem) {
    var raw = (queueItem && queueItem.queue_item_id) ? queueItem.queue_item_id : ""
    if (raw.length === 0) {
        return "/org/mpris/MediaPlayer2/TrackList/NoTrack"
    }
    return "/org/mpris/MediaPlayer2/Track/" + raw.replace(/[^A-Za-z0-9_]/g, "_")
}

// --- Queue ---------------------------------------------------------------

// queue_id und player_id sind auf diesem Server identisch; die Kommandos
// nehmen trotzdem ausdrücklich das eine oder das andere, deshalb wird hier
// nicht das eine für das andere eingesetzt, sondern nachgeschlagen.
function queueFor(queues, playerId) {
    if (!queues || !playerId) {
        return null
    }
    return queues[playerId] || null
}

// --- Hörbücher -----------------------------------------------------------

// Der erste Autor eines Hörbuchs, und nur der. `authors` ist eine Liste, aber
// welcher Anbieter was hineinschreibt, ist nicht einheitlich: manche liefern
// je Person einen Eintrag, andere alle Beteiligten als **einen** Eintrag mit
// Kommas darin ("Bonnie Garmus, Ulrike Wasel - Übersetzer, Klaus Berr -
// Übersetzer"). Beides endet hier beim ersten Namen -- Übersetzer und
// Bearbeiter füllen die Zeile, ohne etwas zu sagen. Dass dabei ein
// "Nachname, Vorname" auseinanderfiele, ist bei diesen Anbietern kein Fall:
// sie schreiben Namen ausgeschrieben, das Komma trennt Personen.
function primaryAuthor(item) {
    var authors = (item && item.authors) || []
    if (authors.length === 0) {
        return ""
    }
    return String(authors[0]).split(",")[0].trim()
}

// Alle Namen einer Autoren- oder Sprecherliste als eine Zeile. Die Einträge
// sind je nach Serverstand Zeichenketten oder Objekte mit `name`; beides geht.
function personNames(list) {
    var names = []
    for (var i = 0; i < (list || []).length; i++) {
        var entry = list[i]
        var name = (entry && typeof entry === "object") ? entry.name : entry
        if (name) {
            names.push(String(name))
        }
    }
    return names.join(", ")
}

// `fully_played` ist bei Hörbüchern ein Bool, bei Podcast-Folgen 0/1.
function isFullyPlayed(item) {
    return !!item && (item.fully_played === true || item.fully_played === 1)
}

// Wo das Abspielen fortsetzt, in Sekunden; 0 wenn nie begonnen.
function resumeSeconds(item) {
    return (item && item.resume_position_ms > 0) ? item.resume_position_ms / 1000 : 0
}

// Anteil schon gehört (0..1), -1 wenn nie begonnen oder bereits beendet.
function listenProgress(item) {
    if (!item || isFullyPlayed(item) || !(item.duration > 0)) {
        return -1
    }
    var resume = resumeSeconds(item)
    return resume > 0 ? Math.min(resume / item.duration, 1) : -1
}

// --- Songtexte -------------------------------------------------------------

// Zerlegt einen LRC-Text ("[01:23.45] Zeile") in [{ time, text }], nach Zeit
// sortiert. MA 2.10.4 liefert Songtexte über metadata/get_track_lyrics als
// Paar [einfach, lrc]; auf der eigenen Anlage kam nur die LRC-Fassung
// (KONZEPT.md Abschnitt 30). Eine Zeile kann mehrere Zeitmarken tragen
// (Refrain), Kopfzeilen wie [ar:...] fallen weg, [offset:+/-ms] wird
// angewandt. Leere Zeilen bleiben als Pause stehen.
function parseLrc(text) {
    var out = []
    var offset = 0
    var lines = String(text || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        var off = /^\[offset:\s*([+-]?\d+)\]/i.exec(line)
        if (off) {
            offset = parseInt(off[1], 10) / 1000
            continue
        }
        var times = []
        var m
        var rest = line
        while ((m = /^\[(\d+):(\d+(?:[.:]\d+)?)\]/.exec(rest)) !== null) {
            times.push(parseInt(m[1], 10) * 60 + parseFloat(m[2].replace(":", ".")))
            rest = rest.substring(m[0].length)
        }
        if (times.length === 0) {
            continue
        }
        for (var t = 0; t < times.length; t++) {
            out.push({ time: Math.max(0, times[t] - offset), text: rest.trim() })
        }
    }
    out.sort(function (a, b) { return a.time - b.time })
    return out
}

// Songtext ohne Zeitmarken als Zeilen mit time -1.
function plainLyricLines(text) {
    var out = []
    var lines = String(text || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
        out.push({ time: -1, text: lines[i].trim() })
    }
    return out
}

// Index der Zeile, die gerade läuft, oder -1 vor der ersten.
function currentLyricIndex(lines, elapsed) {
    var found = -1
    for (var i = 0; i < (lines || []).length; i++) {
        if (lines[i].time >= 0 && lines[i].time <= elapsed) {
            found = i
        } else if (lines[i].time > elapsed) {
            break
        }
    }
    return found
}

// --- Einschlaftimer --------------------------------------------------------

// Restzeit in Sekunden oder 0. Der Server führt das Ablaufdatum als
// Unix-Zeit am Player (`sleep_timer_expires_at`).
function sleepRemaining(player, nowMs) {
    if (!player || !(player.sleep_timer_expires_at > 0)) {
        return 0
    }
    return Math.max(0, player.sleep_timer_expires_at - nowMs / 1000)
}

// --- Podcast-Folgen --------------------------------------------------------

// Erscheinungsdatum einer Folge als Date oder null. Steht in
// `metadata.release_date` (ISO 8601); beim Overcast-Abgleich immer gesetzt.
function releaseDate(item) {
    var raw = item && item.metadata ? item.metadata.release_date : null
    if (!raw) {
        return null
    }
    var d = new Date(raw)
    return isNaN(d.getTime()) ? null : d
}

// Ganze Tage zwischen zwei Kalendertagen (lokale Zeit), >= 0 für Vergangenes.
function daysAgo(date, now) {
    var a = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    var b = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    return Math.round((b - a) / 86400000)
}

// Beschreibungen kommen aus dem Feed und enthalten oft HTML. Für ein Label
// genügt Text: Zeilenumbrüche aus <br>/<p> behalten, alle anderen Tags weg,
// die häufigen Entitäten auflösen.
function plainText(html) {
    var s = String(html || "")
    s = s.replace(/<\s*br\s*\/?>/gi, "\n").replace(/<\s*\/p\s*>/gi, "\n\n")
    s = s.replace(/<[^>]+>/g, "")
    s = s.replace(/&nbsp;/g, " ").replace(/&ndash;/g, "–").replace(/&mdash;/g, "—").replace(/&amp;/g, "&").replace(/&lt;/g, "<")
         .replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'")
         .replace(/&#(\d+);/g, function (m, n) { return String.fromCharCode(parseInt(n, 10)) })
    return s.replace(/\n{3,}/g, "\n\n").trim()
}

// --- Interpret ---------------------------------------------------------------

// `music/artists/top_tracks` mischt Bibliothek und Streamingdienst und bringt
// denselben Titel oft doppelt: einmal aus der Bibliothek, einmal vom Dienst,
// oder in zwei Fassungen vom Dienst ("Yellow" zweimal bei Coldplay). Je Name
// bleibt ein Eintrag an der Stelle seines ersten Auftretens; steht der Titel
// auch in der Bibliothek, gilt der Bibliothekseintrag.
function uniqueTracksByName(tracks) {
    var out = []
    var at = {}
    for (var i = 0; i < (tracks || []).length; i++) {
        var t = tracks[i]
        var key = String(t.name || "").toLowerCase().trim()
        if (at[key] === undefined) {
            at[key] = out.length
            out.push(t)
        } else if (t.provider === "library" && out[at[key]].provider !== "library") {
            out[at[key]] = t
        }
    }
    return out
}
