import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../lib/MassModels.js" as Models

// Lautsprecher zusammenschalten: ein Player ist der Anführer, die übrigen
// werden an ihn angeschlossen und spielen synchron dasselbe.
//
// Angeboten werden nur die Player aus `can_group_with` des Anführers -- was
// dort nicht steht, kann der Anbieter nicht synchronisieren, und ein Schalter
// dafür wäre ein Versprechen, das der Server nicht hält.
Page {
    id: page

    property var mass
    property var store
    property string playerId: ""

    readonly property var player: store ? store.playerById(playerId) : null
    readonly property var candidates: {
        if (!store || !player) {
            return []
        }
        var ids = Models.groupCandidateIds(player)
        var out = []
        for (var i = 0; i < store.players.length; i++) {
            var p = store.players[i]
            if (p.player_id !== page.playerId && ids.indexOf(p.player_id) !== -1) {
                out.push(p)
            }
        }
        return out
    }
    readonly property bool hasMembers:
        store && player ? Models.hasGroupMembers(player, store.players) : false

    allowedOrientations: Orientation.All

    // Gruppenlautstärke wie jeder andere Regler: nicht an den Serverwert
    // gebunden, sondern nachgezogen, solange niemand den Griff hält.
    function syncGroupVolume() {
        if (!groupVolume.pressed && player && player.group_volume !== undefined
                && player.group_volume !== null) {
            groupVolume.value = player.group_volume
        }
    }

    onPlayerChanged: syncGroupVolume()
    Component.onCompleted: syncGroupVolume()

    function toggleMember(other, shouldBeMember) {
        if (shouldBeMember) {
            store.setGroupMembers(page.playerId, [other.player_id], [], function (err) {
                if (err) {
                    pageToast.show(err.hint, true)
                } else {
                    pageToast.show(qsTr("%1 dazugeschaltet").arg(Models.playerName(other)))
                }
            })
        } else {
            store.setGroupMembers(page.playerId, [], [other.player_id], function (err) {
                if (err) {
                    pageToast.show(err.hint, true)
                } else {
                    pageToast.show(qsTr("%1 abgetrennt").arg(Models.playerName(other)))
                }
            })
        }
    }

    function disbandGroup() {
        var ids = []
        for (var i = 0; i < page.candidates.length; i++) {
            if (Models.isGroupMember(page.player, page.candidates[i])) {
                ids.push(page.candidates[i].player_id)
            }
        }
        if (ids.length === 0) {
            return
        }
        store.setGroupMembers(page.playerId, [], ids, function (err) {
            if (err) {
                pageToast.show(err.hint, true)
            } else {
                pageToast.show(qsTr("Gruppe aufgelöst"))
            }
        })
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.candidates

        header: Column {
            width: listView.width
            bottomPadding: Theme.paddingMedium

            PageHeader {
                title: qsTr("Gruppe")
                description: page.player ? Models.playerName(page.player) : ""
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Zugeschaltete Lautsprecher spielen synchron dasselbe wie %1.")
                      .arg(page.player ? Models.playerName(page.player) : "")
            }

            Slider {
                id: groupVolume
                width: parent.width
                visible: page.hasMembers
                label: qsTr("Lautstärke der Gruppe")
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                valueText: Math.round(value) + " %"
                onReleased: store.setGroupVolume(page.playerId, value)
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.hasMembers
                text: qsTr("Gruppe auflösen")
                onClicked: page.disbandGroup()
            }

            SectionHeader { text: qsTr("Lautsprecher") }
        }

        ViewPlaceholder {
            enabled: page.candidates.length === 0
            text: qsTr("Keine passenden Lautsprecher")
            hintText: qsTr("Dieser Player lässt sich mit keinem anderen zusammenschalten")
        }

        delegate: TextSwitch {
            width: listView.width
            text: Models.playerName(modelData)
            description: {
                if (!Models.isAvailable(modelData)) {
                    return qsTr("nicht verfügbar")
                }
                // Hängt der Lautsprecher an einer *anderen* Gruppe, sagt das
                // die Zeile -- sonst wundert man sich, warum das Zuschalten
                // ihn woanders wegnimmt.
                var leader = Models.groupLeaderOf(modelData)
                if (leader.length > 0 && leader !== page.playerId) {
                    var other = store.playerById(leader)
                    return other ? qsTr("gehört zu %1").arg(Models.playerName(other))
                                 : qsTr("gehört zu einer anderen Gruppe")
                }
                return ""
            }
            checked: Models.isGroupMember(page.player, modelData)
            enabled: Models.isAvailable(modelData) && mass && mass.ready
            // Nicht selbst umschalten: der Zustand kommt vom Server, und erst
            // dessen Ereignis darf den Schalter bewegen.
            automaticCheck: false
            onClicked: page.toggleMember(modelData, !checked)
        }

        VerticalScrollDecorator {}
    }

    StatusToast { id: pageToast }
}
