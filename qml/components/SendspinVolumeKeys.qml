import QtQuick 2.6
import Nemo.Policy 1.0
import Sailfish.Media 1.0

// Nur in der OpenRepos-Variante (KONZEPT.md Abschnitt 38): Solange das Telefon
// selbst spielt und Tonarm im Vordergrund ist, stellen die Lautstärketasten
// die Sendspin-Lautstärke statt der Systemlautstärke. Die Tasten holt die
// Ressource ScaleButton, wie in der Kamera-App; Music Assistant erfährt die
// neue Lautstärke über client/state.
Item {
    id: keys

    property bool active: false
    readonly property int step: 5

    function change(delta) {
        Sendspin.volume = Math.max(0, Math.min(100, Sendspin.volume + delta))
    }

    Permissions {
        enabled: keys.active && Qt.application.state === Qt.ApplicationActive
        autoRelease: true
        applicationClass: "player"

        Resource {
            id: scaleButton
            type: Resource.ScaleButton
            optional: true
        }
    }

    MediaKey {
        enabled: scaleButton.acquired
        key: Qt.Key_VolumeUp
        onPressed: keys.change(keys.step)
        onRepeat: keys.change(keys.step)
    }

    MediaKey {
        enabled: scaleButton.acquired
        key: Qt.Key_VolumeDown
        onPressed: keys.change(-keys.step)
        onRepeat: keys.change(-keys.step)
    }
}
