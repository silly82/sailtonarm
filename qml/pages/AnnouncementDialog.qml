import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../lib/MassModels.js" as Models

// Eine Durchsage auf einem Lautsprecher: Text eingeben, der Server spricht
// ihn per TTS und setzt danach fort, was lief ("Essen ist fertig").
//
// Lautstärke und Gong merkt sich die App, damit die nächste Durchsage nicht
// wieder eingestellt werden muss.
Dialog {
    id: dialog

    property var player
    readonly property string message: textArea.text.trim()
    readonly property int volumeLevel: ownVolume.checked ? Math.round(volumeSlider.value) : -1
    readonly property bool preAnnounce: gongSwitch.checked

    canAccept: message.length > 0

    ConfigurationValue {
        id: volumeSetting
        key: "/apps/harbour-tonarm/announceVolume"
        defaultValue: 40
    }
    ConfigurationValue {
        id: ownVolumeSetting
        key: "/apps/harbour-tonarm/announceOwnVolume"
        defaultValue: true
    }
    ConfigurationValue {
        id: gongSetting
        key: "/apps/harbour-tonarm/announceGong"
        defaultValue: true
    }

    onAccepted: {
        volumeSetting.value = Math.round(volumeSlider.value)
        ownVolumeSetting.value = ownVolume.checked
        gongSetting.value = gongSwitch.checked
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Durchsagen")
                title: dialog.player ? Models.playerName(dialog.player) : ""
            }

            TextArea {
                id: textArea
                width: parent.width
                label: qsTr("Text der Durchsage")
                placeholderText: qsTr("z. B. Essen ist fertig!")
                focus: true
            }

            TextSwitch {
                id: gongSwitch
                text: qsTr("Gong vorab")
                description: qsTr("Ein kurzer Ton vor dem Text, damit man hinhört")
                checked: gongSetting.value === true
            }

            TextSwitch {
                id: ownVolume
                text: qsTr("Eigene Lautstärke")
                description: qsTr("Sonst spricht der Lautsprecher in seiner aktuellen Lautstärke")
                checked: ownVolumeSetting.value === true
            }

            Slider {
                id: volumeSlider
                width: parent.width
                visible: ownVolume.checked
                label: qsTr("Lautstärke der Durchsage")
                minimumValue: 5
                maximumValue: 100
                stepSize: 1
                value: volumeSetting.value
                valueText: Math.round(value) + " %"
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Gesprochen wird mit der Sprachausgabe, die in Music Assistant eingerichtet ist. Was gerade läuft, wird danach fortgesetzt.")
            }
        }
    }
}
