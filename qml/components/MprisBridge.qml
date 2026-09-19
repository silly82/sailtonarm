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

    // MPRIS rechnet in Mikrosekunden, Music Assistant in Sekunden.
    readonly property int microsPerSecond: 1000000

    function pushPosition() {
        if (!active) {
            return
        }
        mprisPlayer.position = Math.round(
                    Models.elapsedSeconds(queue, player, Date.now()) * microsPerSecond)
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

        canControl: bridge.active
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

        hasShuffle: bridge.queue !== null
        shuffle: bridge.queue ? bridge.queue.shuffle_enabled === true : false

        hasLoopStatus: bridge.queue !== null
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
                           ? bridge.track.duration * bridge.microsPerSecond : 0
        // Ein stabiler Bezeichner je Stück; ohne ihn hält mancher Client zwei
        // aufeinanderfolgende Titel für denselben und aktualisiert nicht.
        metaData.trackId: (bridge.queue && bridge.queue.current_item)
                          ? bridge.queue.current_item.queue_item_id : ""

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
        onPreviousRequested: if (bridge.active) store.previous(bridge.player.player_id)

        // offset ist relativ und in Mikrosekunden.
        onSeekRequested: {
            if (!bridge.active) {
                return
            }
            var current = Models.elapsedSeconds(bridge.queue, bridge.player, Date.now())
            var target = Math.max(0, current + offset / bridge.microsPerSecond)
            store.seek(bridge.player.player_id, target)
        }

        onSetPositionRequested: {
            if (bridge.active) {
                store.seek(bridge.player.player_id, position / bridge.microsPerSecond)
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
