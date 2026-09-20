import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "pages"
import "cover"
import "components"

ApplicationWindow {
    id: appWindow

    // Die eine Verbindung für die ganze App. Sie lebt hier, weil sie einen
    // Seitenwechsel überdauern muss -- läge sie in einer Seite, risse jedes
    // Aufziehen der Einstellungen den Socket mit ab.
    //
    // Weitergabe an Seiten und Cover ausdrücklich per Property (mass: ...)
    // statt über ein QML-Singleton: siehe Kommentar in MassConnection.qml.
    MassConnection {
        id: massConnection
        // Credentials ist die C++-Kontext-Property aus main() und liefert die
        // Werte erst, wenn der Secrets-Daemon geantwortet hat -- die Bindings
        // ziehen dann von selbst nach und der Socket geht auf.
        baseUrl: Credentials.baseUrl
        token: Credentials.token
    }

    // Zustand aller Player und Warteschlangen, per Server-Events aktuell
    // gehalten. Ebenfalls hier, damit er Seitenwechsel überdauert: sonst
    // müsste jede Rückkehr zur Liste alles neu laden.
    PlayerStore {
        id: playerStore
        mass: massConnection
        preferredPlayerId: preferredPlayerSetting.value
        onPreferredPlayerIdChanged: preferredPlayerSetting.value = preferredPlayerId
    }

    // Meldet den laufenden Player als MPRIS-Dienst an: damit steuern
    // Sperrbildschirm und Medientasten den entfernten Player. Gehört ins
    // Wurzelfenster, weil der Dienst unabhängig von der gerade sichtbaren
    // Seite bestehen muss.
    MprisBridge {
        mass: massConnection
        store: playerStore
    }

    TrackNotifier {
        store: playerStore
        enabled: notifySetting.value === true
    }

    // Hochkant festhalten. Die Seiten sind für Hochformat entworfen; quer
    // funktionieren sie, sehen aber gestreckt aus. Wer das Telefon beim
    // Hören ohnehin hinlegt, will nicht, dass die Liste dabei kippt.
    // Wirkt über das Wurzelfenster: alle Seiten übernehmen es, weil sie
    // `defaultAllowedOrientations` benutzen statt eigener Werte.
    ConfigurationValue {
        id: portraitLockSetting
        key: "/apps/harbour-tonarm/lockPortrait"
        defaultValue: false
    }

    ConfigurationValue {
        id: notifySetting
        key: "/apps/harbour-tonarm/notifyOnTrackChange"
        defaultValue: false
    }

    // Der zuletzt geöffnete Player überlebt den App-Neustart. Nur eine
    // Bequemlichkeit (Sortierung und Markierung in der Liste), deshalb reicht
    // dconf -- hier liegt nichts Schützenswertes, anders als bei Adresse und
    // Token.
    ConfigurationValue {
        id: preferredPlayerSetting
        key: "/apps/harbour-tonarm/preferredPlayerId"
        defaultValue: ""
    }

    initialPage: Component {
        PlayersPage { mass: massConnection; store: playerStore }
    }
    cover: Component {
        CoverPage { mass: massConnection; store: playerStore }
    }
    allowedOrientations: portraitLockSetting.value === true
                         ? Orientation.Portrait : Orientation.All
}
