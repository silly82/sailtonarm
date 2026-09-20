import QtQuick 2.6
import Amber.Mpris 1.0
import "../lib/MassModels.js" as Models

// Meldet den gerade laufenden Player als MPRIS-Dienst an. Damit steuern der
// Sperrbildschirm, die Medientasten eines Headsets und alles andere, was
// MPRIS spricht, den *entfernten* Player -- diese App gibt selbst kein Audio
// aus.
//
// Das war die offene Frage aus KONZEPT.md Abschnitt 6: ob SailfishOS einen
// MPRIS-Anbieter ohne eigene Audioausgabe akzeptiert. Amber.Mpris ist ein
// reiner D-Bus-Anbieter ohne Kopplung an eine Audio-Policy, also kein
// grundsätzliches Hindernis -- verifiziert wird es auf dem Gerät.
//
// Gespiegelt wird immer `store.activePlayer` (spielend vor pausiert vor
// gemerkt), dieselbe Wahl wie beim Cover.
Item {
    id: bridge

    property var mass
    property var store

    readonly property var player: store ? store.activePlayer : null
    readonly property var queue: (store && player) ? store.queueOf(player.player_id) : null
    readonly property var track: Models.nowPlaying(player, queue)
    readonly property bool active: player !== null && mass && mass.ready

    // Achtung, zwei Einheiten: auf dem D-Bus stehen laut MPRIS-Spezifikation
    // Mikrosekunden, aber `Amber.Mpris` nimmt und liefert **Millisekunden**
    // und rechnet selbst um -- `MprisMetaData::duration` ist laut Quelltext
    // "Length of the media in milliseconds", `position()` wird für den Bus
    // mit 1000 multipliziert, und `seekRequested`/`setPositionRequested`
    // liefern bereits durch 1000 geteilte Werte. Wer hier Mikrosekunden
    // einsetzt, meldet die tausendfache Länge (einmal passiert: 4:56 wurden
    // zu 82 Stunden).
    readonly property int millisPerSecond: 1000

    function pushPosition() {
        if (!active) {
            return
        }
        mprisPlayer.position = Math.round(
                    Models.elapsedSeconds(queue, player, Date.now()) * millisPerSecond)
    }

    onTrackChanged: pushPosition()

    // Der Sperrbildschirm fragt die Position nicht ständig ab, sondern
    // verlässt sich auf gemeldete Werte -- also im Sekundentakt nachziehen,
    // solange etwas läuft.
    Timer {
        interval: 1000
        repeat: true
        running: bridge.active && Models.isPlaying(bridge.player)
        onTriggered: bridge.pushPosition()
    }

    MprisPlayer {
        id: mprisPlayer

        // Muss zum Anwendungsnamen passen, sonst findet Lipstick das Symbol
        // nicht: der Dienst heisst org.mpris.MediaPlayer2.<serviceName>.
        serviceName: "harbour-tonarm"
        identity: "Tonarm"
        desktopEntry: "harbour-tonarm"

        canQuit: false
        canRaise: true
        canSetFullscreen: false
        hasTrackList: false

        // Fest auf true, *nicht* an den Verbindungszustand gebunden: der
        // Eigenschafts-Adaptor von Amber ruft beim ersten `GetAll` eines
        // Clients `lockProperties()` auf und entsperrt nie wieder. Genau drei
        // Properties prüfen diese Sperre -- canControl, hasShuffle,
        // hasLoopStatus. Lipstick fragt GetAll ab, sobald der Dienst am Bus
        // erscheint; zu dem Zeitpunkt steht die WebSocket-Verbindung noch
        // nicht, ein gebundenes canControl fröre also dauerhaft auf false ein
        // und riss alles andere mit (canGoNext & Co. liefern false, solange
        // canControl false ist). Genau das war in v0.11 zu sehen.
        //
        // Inhaltlich ist true auch richtig: canControl heisst in MPRIS "dieser
        // Player ist grundsätzlich steuerbar", nicht "gerade jetzt". Was im
        // Moment geht, sagen canPlay/canGoNext/canSeek -- und die unterliegen
        // der Sperre nicht.
        canControl: true
        // Transport hängt an der Warteschlange, nicht an den Fähigkeiten des
        // Players -- derselbe Grund wie auf der Now-Playing-Seite.
        canPlay: bridge.active && bridge.queue !== null && bridge.queue.active === true
        canPause: canPlay
        canGoNext: canPlay
        canGoPrevious: canPlay
        canSeek: canPlay && bridge.track !== null && bridge.track.duration > 0

        playbackStatus: {
            if (!bridge.active) {
                return Mpris.Stopped
            }
            switch (Models.playbackState(bridge.player)) {
            case "playing": return Mpris.Playing
            case "paused": return Mpris.Paused
            }
            return Mpris.Stopped
        }

        // hasShuffle und hasLoopStatus werden bewusst *nicht* gesetzt: sie
        // stehen in C++ ohnehin auf true, und da sie derselben Sperre
        // unterliegen wie canControl, würde eine Bindung sie beim ersten
        // GetAll auf false einfrieren -- die Eigenschaften Shuffle und
        // LoopStatus verschwänden dann dauerhaft vom Bus (in v0.11 genau so
        // passiert: "Property ... was not found").
        shuffle: bridge.queue ? bridge.queue.shuffle_enabled === true : false

        loopStatus: {
            if (!bridge.queue) {
                return Mpris.LoopNone
            }
            switch (bridge.queue.repeat_mode) {
            case "one": return Mpris.LoopTrack
            case "all": return Mpris.LoopPlaylist
            }
            return Mpris.LoopNone
        }

        // MPRIS führt die Lautstärke als 0..1, Music Assistant als 0..100.
        volume: (bridge.player && bridge.player.volume_level !== undefined
                 && bridge.player.volume_level !== null)
                ? bridge.player.volume_level / 100.0 : 0

        metaData.title: bridge.track ? bridge.track.title : ""
        metaData.contributingArtist: bridge.track ? bridge.track.artist : ""
        metaData.albumTitle: bridge.track ? bridge.track.album : ""
        metaData.artUrl: bridge.track ? bridge.track.imageUrl : ""
        metaData.duration: bridge.track
                           ? bridge.track.duration * bridge.millisPerSecond : 0
        // Ein stabiler Bezeichner je Stück; ohne ihn hält mancher Client zwei
        // aufeinanderfolgende Titel für denselben und aktualisiert nicht.
        // Muss ein D-Bus-Objektpfad sein, siehe MassModels.mprisTrackId().
        metaData.trackId: Models.mprisTrackId(
                              bridge.queue ? bridge.queue.current_item : null)

        onPlayPauseRequested: if (bridge.active) store.playPause(bridge.player.player_id)
        onPlayRequested: if (bridge.active && !Models.isPlaying(bridge.player))
                             store.playPause(bridge.player.player_id)
        onPauseRequested: if (bridge.active && Models.isPlaying(bridge.player))
                              store.playPause(bridge.player.player_id)
        // Kein eigenes Stop: Music Assistant kennt zwar player_queues/stop,
        // aber vom Sperrbildschirm aus ist Pause das, was gemeint ist --
        // Stop verwirft die Abspielposition.
        onStopRequested: if (bridge.active && Models.isPlaying(bridge.player))
                             store.playPause(bridge.player.player_id)
        onNextRequested: if (bridge.active) store.next(bridge.player.player_id)
        // Zurück springt in Music Assistant an den Anfang des laufenden
        // Titels, wenn dieser schon eine Weile läuft, und erst danach zum
        // vorherigen -- übliches Verhalten, kein Fehler.
        onPreviousRequested: if (bridge.active) store.previous(bridge.player.player_id)

        // offset ist relativ und in Millisekunden (Amber hat die
        // Mikrosekunden vom Bus bereits umgerechnet).
        onSeekRequested: {
            if (!bridge.active) {
                return
            }
            var current = Models.elapsedSeconds(bridge.queue, bridge.player, Date.now())
            var target = Math.max(0, current + offset / bridge.millisPerSecond)
            store.seek(bridge.player.player_id, target)
        }

        onSetPositionRequested: {
            if (bridge.active) {
                store.seek(bridge.player.player_id, position / bridge.millisPerSecond)
            }
        }

        onShuffleRequested: if (bridge.active) store.setShuffle(bridge.player.player_id, shuffle)

        onLoopStatusRequested: {
            if (!bridge.active) {
                return
            }
            var mode = "off"
            if (loopStatus === Mpris.LoopTrack) {
                mode = "one"
            } else if (loopStatus === Mpris.LoopPlaylist) {
                mode = "all"
            }
            store.setRepeat(bridge.player.player_id, mode)
        }

        onVolumeRequested: if (bridge.active)
                               store.setVolume(bridge.player.player_id, volume * 100)
    }
}
