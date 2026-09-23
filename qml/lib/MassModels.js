.pragma library

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
function nowPlaying(player, queue) {
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

    return {
        title: title,
        artist: artist,
        album: album,
        // image_url kommt bereits als vollständige /imageproxy-Adresse mit
        // ?size=-Parameter vom Server -- nichts selbst zusammenbauen.
        imageUrl: (media && media.image_url) ? media.image_url : "",
        duration: durationOf(media, item),
        mediaType: media ? media.media_type : (item && item.media_item
                                               ? item.media_item.media_type : "")
    }
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
