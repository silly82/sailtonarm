.pragma library

// Der Datenbestand des Demomodus: erfundene Räume, Musik, Sender, ein Hörbuch
// und ein Podcast -- in genau der Form, in der Music Assistant 2.10.4 sie
// schickt (Feldnamen wie in MassModels.js). Alles hier ist ausgedacht; die
// Cover erzeugt store/generate-demo-art.py.
//
// build() liefert jedes Mal einen frischen Bestand, damit ein erneutes
// Einschalten des Demomodus wieder beim Ausgangszustand beginnt.

var LIBRARY = "library"

// [[Sekunden, Zeile], ...] -> LRC-Text, wie der Server ihn liefert.
function lrc(rows) {
    var out = []
    for (var i = 0; i < rows.length; i++) {
        var t = rows[i][0]
        var m = Math.floor(t / 60)
        var s = t % 60
        out.push("[" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s + ".00] " + rows[i][1])
    }
    return out.join("\n")
}
var STREAM = "klangwelle--demo"

function build(artBase) {
    function art(key) {
        return artBase + key + ".jpg"
    }
    function images(key) {
        return { images: [{ type: "thumb", path: "", provider: LIBRARY, proxy_id: art(key) }] }
    }

    // --- Interpreten ------------------------------------------------------
    var artistDefs = [
        ["ar1", "Nordlicht Quartett", "nordlicht"],
        ["ar2", "Mira Solen", "mira"],
        ["ar3", "Die Kupferbahn", "kupferbahn"],
        ["ar4", "Leonie Brand", "leonie"],
        ["ar5", "Tidal Ferns", "tidal"],
        ["ar6", "Ostwind Kollektiv", "kollektiv"]
    ]
    var artists = []
    var artistById = {}
    for (var i = 0; i < artistDefs.length; i++) {
        var a = {
            item_id: artistDefs[i][0], provider: LIBRARY, media_type: "artist",
            uri: "library://artist/" + artistDefs[i][0], name: artistDefs[i][1],
            metadata: images(artistDefs[i][2]), favorite: i === 1, is_playable: true
        }
        artists.push(a)
        artistById[a.item_id] = a
    }
    function artistRef(id) {
        var a = artistById[id]
        return { item_id: a.item_id, provider: LIBRARY, media_type: "artist",
                 uri: a.uri, name: a.name }
    }

    // --- Alben und Titel --------------------------------------------------
    var albumDefs = [
        ["al1", "Weite Felder", "ar1", 2019, "weite-felder",
         ["Morgengrau", "Über die Hügel", "Weite Felder", "Heuernte", "Der lange Weg zurück", "Abendrot über dem See"]],
        ["al2", "Sommerregen", "ar2", 2021, "sommerregen",
         ["Erster Tropfen", "Sommerregen", "Unter der Markise", "Petrichor", "Wenn es aufklart"]],
        ["al3", "Kleine Stunden", "ar2", 2024, "kleine-stunden",
         ["Vier Uhr früh", "Kleine Stunden", "Laternenlicht", "Was bleibt", "Bis der Tag kommt"]],
        ["al4", "Nachtzug", "ar3", 2023, "nachtzug",
         ["Abfahrt 23:14", "Schlafwagen", "Grenzbahnhof", "Nachtzug", "Ankunft im Nebel", "Rückfahrkarte"]],
        ["al5", "Studio Sessions Vol. 2 (Live aus dem Kesselhaus, Remastered)", "ar3", 2016, "studio",
         ["Einzählen", "Kesselhaus Blues (Live)", "Dampf (Live)", "Zugabe: Nachtzug (Live, Remastered)"]],
        ["al6", "Glas und Sand", "ar4", 2020, "glas-und-sand",
         ["Glasfenster", "Sanduhr", "Zwischen den Dünen", "Scherben bringen Glück", "Ebbe"]],
        ["al7", "Low Tide Lights", "ar5", 2022, "low-tide",
         ["Harbour Lamps", "Low Tide Lights", "Salt in the Air", "Undertow", "Driftwood"]],
        ["al8", "Ostwind", "ar6", 2018, "ostwind",
         ["Auftakt", "Ostwind", "Böen", "Windstille", "Sturmwarnung", "Nachlese"]]
    ]
    var albums = []
    var albumById = {}
    var tracks = []
    var tracksByAlbum = {}
    var trackCounter = 1
    for (i = 0; i < albumDefs.length; i++) {
        var d = albumDefs[i]
        var album = {
            item_id: d[0], provider: LIBRARY, media_type: "album", uri: "library://album/" + d[0],
            name: d[1], year: d[3], artists: [artistRef(d[2])], metadata: images(d[4]),
            favorite: i === 0 || i === 5, is_playable: true
        }
        albums.push(album)
        albumById[album.item_id] = album
        var list = []
        for (var t = 0; t < d[5].length; t++) {
            var id = "t" + trackCounter
            trackCounter += 1
            var track = {
                item_id: id, provider: LIBRARY, media_type: "track", uri: "library://track/" + id,
                name: d[5][t], duration: 150 + ((trackCounter * 37) % 190), track_number: t + 1,
                disc_number: 1, artists: [artistRef(d[2])],
                album: { item_id: album.item_id, provider: LIBRARY, media_type: "album",
                         uri: album.uri, name: album.name, image: album.metadata.images[0] },
                metadata: images(d[4]), favorite: false, is_playable: true
            }
            tracks.push(track)
            list.push(track)
        }
        tracksByAlbum[album.item_id] = list
    }

    // --- Playlists --------------------------------------------------------
    function pick(ids) {
        var out = []
        for (var k = 0; k < ids.length; k++) {
            out.push(tracks[ids[k]])
        }
        return out
    }
    var playlistDefs = [
        ["pl1", "Sonntagmorgen", "sonntag", [0, 6, 11, 27, 33, 40]],
        ["pl2", "Kochen", "kochen", [7, 16, 22, 29, 35]],
        ["pl3", "Fokus", "fokus", [2, 12, 17, 31, 38, 41, 5]]
    ]
    var playlists = []
    var tracksByPlaylist = {}
    for (i = 0; i < playlistDefs.length; i++) {
        var pd = playlistDefs[i]
        playlists.push({ item_id: pd[0], provider: LIBRARY, media_type: "playlist",
                         uri: "library://playlist/" + pd[0], name: pd[1], owner: "Demo",
                         metadata: images(pd[2]), favorite: i === 0, is_playable: true })
        tracksByPlaylist[pd[0]] = pick(pd[3])
    }

    // --- Radio ------------------------------------------------------------
    var radios = [
        { item_id: "r1", provider: LIBRARY, media_type: "radio", uri: "library://radio/r1",
          name: "Radio Alpenwelle (AAC 128)", metadata: images("alpenwelle"), favorite: true, is_playable: true },
        { item_id: "r2", provider: LIBRARY, media_type: "radio", uri: "library://radio/r2",
          name: "Jazz Nachtexpress", metadata: images("jazz-express"), favorite: false, is_playable: true }
    ]

    // --- Hörbuch ----------------------------------------------------------
    var chapterNames = ["Vorspann", "1. Die Ankunft", "2. Das Fernrohr", "3. Nebel über dem See",
                        "4. Der Brief", "5. Sternkarten", "6. Die zweite Nacht", "7. Was Lotte wusste",
                        "8. Sturm", "9. Die Kuppel", "10. Heimkehr", "Nachwort"]
    var chapters = []
    var start = 0
    for (i = 0; i < chapterNames.length; i++) {
        var len = i === 0 ? 40 : (i === chapterNames.length - 1 ? 300 : 2400 + (i * 331) % 900)
        chapters.push({ position: i + 1, name: chapterNames[i], start: start, end: start + len })
        start += len
    }
    var audiobook = {
        item_id: "b1", provider: LIBRARY, media_type: "audiobook", uri: "library://audiobook/b1",
        name: "Die Sternwarte am See", authors: ["Hanna Lindqvist"], narrators: ["Paul Berger"],
        duration: start, resume_position_ms: Math.round(start * 0.23) * 1000, fully_played: false,
        metadata: { images: images("sternwarte").images, chapters: chapters },
        favorite: false, is_playable: true
    }

    // --- Podcast ----------------------------------------------------------
    var podcast = {
        item_id: "p1", provider: LIBRARY, media_type: "podcast", uri: "library://podcast/p1",
        name: "Hörsaal Klang", publisher: "Freies Klangradio", metadata: images("hoersaal"),
        favorite: false, is_playable: true
    }
    var episodeNames = ["Warum Vinyl knistert", "Die Physik der Gitarrensaite", "Hall, Echo, Raum",
                        "Kopfhörer im Test", "Wie ein Lautsprecher denkt"]
    var episodes = []
    for (i = 0; i < episodeNames.length; i++) {
        episodes.push({
            item_id: "e" + (i + 1), provider: LIBRARY, media_type: "podcast_episode",
            uri: "library://podcast_episode/e" + (i + 1), name: episodeNames[i],
            position: episodeNames.length - i, duration: 1500 + i * 311,
            resume_position_ms: i === 1 ? 600000 : 0, fully_played: i > 2 ? 1 : 0,
            metadata: {
                images: images("hoersaal").images,
                // Wöchentlich, die neueste von vorgestern -- relativ zu heute,
                // damit die Liste "vor 2 Tagen" usw. zeigt.
                release_date: new Date(Date.now() - (2 + i * 7) * 86400000).toISOString(),
                description: "<p>In dieser Folge von <b>Hörsaal Klang</b>: " + episodeNames[i]
                             + ".</p><p>Eine erfundene Folge des Demomodus &ndash; mit Studiogast, "
                             + "Hörbeispielen und einer Frage aus dem Publikum.</p>"
            },
            is_playable: true
        })
    }

    // --- Streaming-Katalog -----------------------------------------------
    // Nur für die Suche "Überall": Einträge, die nicht in der Bibliothek
    // liegen und ihren Dienst in der Unterzeile nennen.
    var streamArtist = { item_id: "s-ar1", provider: STREAM, media_type: "artist",
                         uri: "klangwelle://artist/1", name: "Mira & die Solisten",
                         metadata: images("klangwelle-1"), is_playable: true }
    var stream = {
        artists: [streamArtist],
        albums: [
            { item_id: "s-al1", provider: STREAM, media_type: "album", uri: "klangwelle://album/1",
              name: "Sommerregen (Akustik)", year: 2022, artists: [artistRef("ar2")],
              metadata: images("klangwelle-1"), is_playable: true },
            { item_id: "s-al2", provider: STREAM, media_type: "album", uri: "klangwelle://album/2",
              name: "Nordwind", year: 2025, artists: [artistRef("ar1")],
              metadata: images("klangwelle-2"), is_playable: true }
        ],
        tracks: [
            { item_id: "s-t1", provider: STREAM, media_type: "track", uri: "klangwelle://track/1",
              name: "Sommerregen (Akustik)", duration: 204, artists: [artistRef("ar2")],
              metadata: images("klangwelle-1"), is_playable: true }
        ]
    }

    // --- Räume ------------------------------------------------------------
    var roomDefs = [
        ["demo-wohnzimmer", "Wohnzimmer", 32],
        ["demo-esszimmer", "Esszimmer", 24],
        ["demo-kueche", "Küche", 40],
        ["demo-arbeitszimmer", "Arbeitszimmer", 18],
        ["demo-schlafzimmer", "Schlafzimmer", 12]
    ]
    var players = []
    var allIds = []
    for (i = 0; i < roomDefs.length; i++) {
        allIds.push(roomDefs[i][0])
    }
    for (i = 0; i < roomDefs.length; i++) {
        var others = []
        for (var j = 0; j < allIds.length; j++) {
            if (allIds[j] !== roomDefs[i][0]) {
                others.push(allIds[j])
            }
        }
        players.push({
            player_id: roomDefs[i][0], name: roomDefs[i][1], display_name: roomDefs[i][1],
            type: "player", provider: "demo", available: true, enabled: true, powered: true,
            power_control: "none", playback_state: "idle", volume_level: roomDefs[i][2],
            volume_muted: false, supported_features: ["volume_set", "volume_mute"],
            can_group_with: others, group_childs: [], group_members: [],
            synced_to: null, active_group: null, current_media: null, group_volume: roomDefs[i][2]
        })
    }

    return {
        artists: artists,
        albums: albums,
        tracks: tracks,
        playlists: playlists,
        radios: radios,
        audiobooks: [audiobook],
        podcasts: [podcast],
        tracksByAlbum: tracksByAlbum,
        tracksByPlaylist: tracksByPlaylist,
        episodes: episodes,
        stream: stream,
        players: players,
        // Was zu Beginn wo läuft: [Raum, uri, Startindex, Position in s, Zustand]
        start: [
            ["demo-wohnzimmer", "library://album/al1", 2, 71, "playing"],
            ["demo-kueche", "library://radio/r1", 0, 0, "playing"],
            ["demo-arbeitszimmer", "library://audiobook/b1", 0, Math.round(start * 0.23), "paused"],
            ["demo-schlafzimmer", "library://playlist/pl1", 0, 0, "idle"]
        ],
        // Esszimmer hängt an Wohnzimmer.
        groups: [["demo-wohnzimmer", ["demo-esszimmer"]]],
        // Songtexte (LRC, frei erfunden) für zwei Titel; alle anderen haben
        // keinen, wie Instrumentals auf dem echten Server ([null, null]).
        lyrics: {
            "Weite Felder": lrc([
                [4, "Der Wind geht durch das hohe Gras"],
                [11, "und niemand fragt, wohin"],
                [18, "Ich zähl die Wolken, eins und zwei"],
                [25, "und weiß nicht mehr, wo ich bin"],
                [33, ""],
                [38, "Weite Felder, weiter Himmel"],
                [45, "und ein Weg, der nirgends endet"],
                [52, "Weite Felder, weiter Himmel"],
                [59, "bis der Abend sich wendet"],
                [67, ""],
                [72, "Die Grillen singen ohne Takt"],
                [79, "der Staub liegt golden auf dem Land"],
                [86, "Ich hab die Karte längst verloren"],
                [93, "und halt die Zeit in meiner Hand"],
                [101, ""],
                [106, "Weite Felder, weiter Himmel"],
                [113, "und ein Weg, der nirgends endet"],
                [120, "Weite Felder, weiter Himmel"],
                [127, "bis der Abend sich wendet"],
                [140, "…bis der Abend sich wendet"]
            ]),
            "Sommerregen": lrc([
                [6, "Warme Tropfen auf dem Dach"],
                [12, "die Straße riecht nach Staub und Glück"],
                [19, "Wir bleiben unter der Markise"],
                [25, "und keiner will zurück"],
                [33, "Sommerregen, lass uns bleiben"],
                [40, "bis das Licht die Pfützen färbt"],
                [47, "Sommerregen, lass uns bleiben"],
                [54, "bis der Himmel wieder lacht"]
            ])
        },
        // Der Sender schickt den laufenden Titel als title (ICY), wie echte
        // Sender in MA 2.10.4.
        radioTitles: {
            r1: ["Leonie Brand - Glasfenster", "Tidal Ferns - Harbour Lamps", "Mira Solen - Petrichor"],
            r2: ["Nachtexpress Trio - Blue Signal", "Ella Marten - Late Platform"]
        }
    }
}
