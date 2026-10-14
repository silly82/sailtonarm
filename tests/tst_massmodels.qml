import QtQuick 2.6
import QtTest 1.0
import "../qml/lib/MassModels.js" as Models

// Tests für die reinen Hilfsfunktionen in MassModels.js. Laufen mit
// qmltestrunner im i486-Bauziel, siehe tests/run.sh.
TestCase {
    name: "MassModels"

    // --- Interpret ----------------------------------------------------------

    function test_uniqueTracksByName_keepsFirstPosition() {
        var r = Models.uniqueTracksByName([
            { name: "Yellow", provider: "apple_music", id: 1 },
            { name: "Yellow", provider: "apple_music", id: 2 },
            { name: "Viva la Vida", provider: "library", id: 3 }
        ])
        compare(r.length, 2)
        compare(r[0].id, 1)
        compare(r[1].id, 3)
    }

    function test_uniqueTracksByName_prefersLibrary() {
        var r = Models.uniqueTracksByName([
            { name: "The Scientist", provider: "apple_music", id: 1 },
            { name: "Fix You", provider: "apple_music", id: 2 },
            { name: "the scientist ", provider: "library", id: 3 }
        ])
        compare(r.length, 2)
        compare(r[0].id, 3, "Bibliothekseintrag ersetzt den des Dienstes an derselben Stelle")
        compare(r[1].id, 2)
    }

    function test_uniqueTracksByName_empty() {
        compare(Models.uniqueTracksByName([]).length, 0)
        compare(Models.uniqueTracksByName(null).length, 0)
    }

    // --- Zeit -------------------------------------------------------------------

    function test_formatTime_data() {
        return [
            { tag: "null", s: 0, out: "0:00" },
            { tag: "negativ", s: -5, out: "0:00" },
            { tag: "undefined", s: undefined, out: "0:00" },
            { tag: "Sekunden", s: 9, out: "0:09" },
            { tag: "Minuten", s: 298.7, out: "4:58" },
            { tag: "Stunden", s: 3600 + 5 * 60 + 7, out: "1:05:07" },
            { tag: "Hörbuch", s: 8 * 3600 + 4 * 60 + 5, out: "8:04:05" }
        ]
    }
    function test_formatTime(d) {
        compare(Models.formatTime(d.s), d.out)
    }

    function test_elapsedSeconds_pausedDoesNotDrift() {
        var queue = { elapsed_time: 80, elapsed_time_last_updated: 1000 }
        var paused = { playback_state: "paused" }
        compare(Models.elapsedSeconds(queue, paused, 1010 * 1000), 80)
    }

    function test_elapsedSeconds_playingDrifts() {
        var queue = { elapsed_time: 80, elapsed_time_last_updated: 1000 }
        var playing = { playback_state: "playing" }
        compare(Models.elapsedSeconds(queue, playing, 1010 * 1000), 90)
    }

    function test_elapsedSeconds_clockSkew() {
        var queue = { elapsed_time: 80, elapsed_time_last_updated: 2000 }
        var playing = { playback_state: "playing" }
        compare(Models.elapsedSeconds(queue, playing, 1000 * 1000), 80,
                "Telefonuhr hinter der Serveruhr: nicht zurückrechnen")
    }

    // --- Kapitel -----------------------------------------------------------------

    readonly property var chapters: [
        { position: 2, name: "Zwei", start: 600 },
        { position: 1, name: "Eins", start: 0 },
        { position: 3, name: "Drei", start: 1200 }
    ]

    function test_chaptersOf_sortsAndFilters() {
        var c = Models.chaptersOf({ metadata: { chapters: chapters.concat([{ name: "kaputt" }]) } })
        compare(c.length, 3)
        compare(c[0].name, "Eins")
        compare(c[2].name, "Drei")
        compare(Models.chaptersOf(null).length, 0)
    }

    function test_currentChapter() {
        var c = Models.chaptersOf({ metadata: { chapters: chapters } })
        compare(Models.currentChapter(c, 0).name, "Eins")
        compare(Models.currentChapter(c, 650).name, "Zwei")
        compare(Models.currentChapter(c, 5000).name, "Drei")
        compare(Models.currentChapter([], 10), null)
    }

    function test_chapterSeek_data() {
        return [
            { tag: "weiter aus Kapitel 1", forward: true, at: 100, out: 600 },
            { tag: "weiter knapp vor Kapitelbeginn", forward: true, at: 599.8, out: 1200 },
            { tag: "weiter im letzten Kapitel", forward: true, at: 1300, out: -1 },
            { tag: "zurück mitten im Kapitel: an dessen Anfang", forward: false, at: 700, out: 600 },
            { tag: "zurück kurz nach Kapitelbeginn: ins vorige", forward: false, at: 603, out: 0 },
            { tag: "zurück im ersten Kapitel kurz nach Beginn", forward: false, at: 2, out: 0 }
        ]
    }
    function test_chapterSeek(d) {
        var c = Models.chaptersOf({ metadata: { chapters: chapters } })
        compare(Models.chapterSeek(c, d.forward, d.at), d.out)
    }

    function test_chapterSeek_noChapters() {
        compare(Models.chapterSeek([], true, 10), -1)
        compare(Models.chapterSeek(null, false, 10), -1)
    }

    // --- Medientypen und Hörstand -------------------------------------------------

    function test_mediaTypes() {
        verify(Models.isLiveType("radio"))
        verify(!Models.isLiveType("track"))
        verify(Models.isSpokenType("audiobook"))
        verify(Models.isSpokenType("podcast_episode"))
        verify(!Models.isSpokenType("podcast"))
    }

    function test_listenProgress() {
        compare(Models.listenProgress({ duration: 100, resume_position_ms: 25000 }), 0.25)
        compare(Models.listenProgress({ duration: 100, resume_position_ms: 0 }), -1, "nie begonnen")
        compare(Models.listenProgress({ duration: 100, resume_position_ms: 50000, fully_played: true }), -1, "beendet (Hörbuch: Bool)")
        compare(Models.listenProgress({ duration: 100, resume_position_ms: 50000, fully_played: 1 }), -1, "beendet (Folge: 0/1)")
        compare(Models.listenProgress({ duration: 0, resume_position_ms: 5000 }), -1, "ohne Länge")
    }

    // --- Bilder ---------------------------------------------------------------------

    function test_imageProxyId() {
        compare(Models.imageProxyId({ metadata: { images: [{ path: "x" }, { proxy_id: "abc" }] } }), "abc")
        compare(Models.imageProxyId({ image: { proxy_id: "def" } }), "def", "schlanker Verweis (ItemMapping)")
        compare(Models.imageProxyId({ metadata: { images: [{ path: "nur-pfad" }] } }), "")
        compare(Models.imageProxyId(null), "")
    }

    // --- Songtexte ----------------------------------------------------------------------

    function test_parseLrc() {
        var lines = Models.parseLrc("[ar:Jemand]\n[00:10.50] Zwei\n[00:01.00][00:20.00] Refrain\n[00:15.00]\n")
        compare(lines.length, 4)
        compare(lines[0].time, 1)
        compare(lines[0].text, "Refrain")
        compare(lines[1].text, "Zwei")
        compare(lines[2].text, "", "leere Zeile bleibt als Pause")
        compare(lines[3].time, 20)
    }

    function test_parseLrc_offset() {
        var lines = Models.parseLrc("[offset:+500]\n[00:10.00] Zeile")
        compare(lines[0].time, 9.5)
    }

    function test_currentLyricIndex() {
        var lines = Models.parseLrc("[00:05.00] a\n[00:10.00] b\n[00:20.00] c")
        compare(Models.currentLyricIndex(lines, 2), -1, "vor der ersten Zeile")
        compare(Models.currentLyricIndex(lines, 10), 1)
        compare(Models.currentLyricIndex(lines, 99), 2)
    }

    // --- Einschlaftimer und Podcasts ---------------------------------------------------

    function test_sleepRemaining() {
        compare(Models.sleepRemaining({ sleep_timer_expires_at: 1100 }, 1000 * 1000), 100)
        compare(Models.sleepRemaining({ sleep_timer_expires_at: 900 }, 1000 * 1000), 0, "abgelaufen")
        compare(Models.sleepRemaining({}, 1000 * 1000), 0)
    }

    function test_releaseDateAndDaysAgo() {
        var d = Models.releaseDate({ metadata: { release_date: "2026-09-28T06:00:00+00:00" } })
        verify(d !== null)
        compare(Models.daysAgo(new Date(2026, 8, 28, 23, 0), new Date(2026, 8, 30, 1, 0)), 2)
        compare(Models.releaseDate({ metadata: { release_date: "kein Datum" } }), null)
        compare(Models.releaseDate({}), null)
    }

    function test_plainText() {
        compare(Models.plainText("<p>Erste&nbsp;Zeile</p><p>Zweite <b>fett</b> &amp; mehr</p>"),
                "Erste Zeile\n\nZweite fett & mehr")
        compare(Models.plainText("a<br/>b&#39;c"), "a\nb'c")
        compare(Models.plainText(null), "")
    }
}
