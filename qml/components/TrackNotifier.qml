import QtQuick 2.6
import Nemo.Notifications 1.0
import "../lib/MassModels.js" as Models

// Optionale Benachrichtigung, wenn auf dem verfolgten Player ein neuer Titel
// beginnt. Standardmässig aus: bei einem Titel alle drei bis vier Minuten
// wäre das sonst eine Dauerbeschallung des Benachrichtigungsbereichs -- und
// Cover und Sperrbildschirm zeigen dasselbe ohnehin schon.
Item {
    id: notifier

    property var store
    property bool enabled: false

    readonly property var player: store ? store.activePlayer : null
    readonly property var queue: (store && player) ? store.queueOf(player.player_id) : null
    readonly property var track: Models.nowPlaying(player, queue)

    // Worauf zuletzt gemeldet wurde. Verglichen wird der Titel *zusammen mit*
    // dem Player: derselbe Titel auf einem anderen Lautsprecher ist eine neue
    // Meldung wert, ein erneutes Eintreffen derselben Angabe nicht.
    property string lastKey: ""

    onTrackChanged: {
        if (!track || track.title.length === 0 || !player) {
            return
        }
        // Trennzeichen bewusst schlicht: \u-Escapes in String-Literalen lehnt
        // der QML-Parser hier ab, und für einen Vergleichsschlüssel reicht es.
        var key = player.player_id + " // " + track.title + " // " + track.artist
        if (key === lastKey) {
            return
        }
        // Beim ersten Erkennen nach dem Start nur merken, nicht melden --
        // sonst meldet jeder App-Start den gerade laufenden Titel.
        var first = lastKey.length === 0
        lastKey = key
        if (first || !enabled || !Models.isPlaying(player)) {
            return
        }
        notification.summary = track.title
        notification.body = track.artist.length > 0
                ? qsTr("%1 · %2").arg(track.artist).arg(Models.playerName(player))
                : Models.playerName(player)
        notification.publish()
    }

    // Beim Abschalten den Merker behalten: sonst meldet das Wiedereinschalten
    // sofort den laufenden Titel.
    Notification {
        id: notification
        appName: "Tonarm"
        // x-nemo.music: ordnet die Meldung in der Ereignisansicht dort ein,
        // wo Musikmeldungen erwartet werden, und ersetzt die vorherige
        // desselben Absenders statt sie zu stapeln.
        category: "x-nemo.music"
        isTransient: false
        urgency: Notification.Low
    }
}
