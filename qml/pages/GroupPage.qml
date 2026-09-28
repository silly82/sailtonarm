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

    // Die Lautsprecher der Gruppe, der Anführer zuerst -- für die
    // Einzellautstärken. Ein fester Gruppen-Player (MA-Typ "group") ist selbst
    // kein Lautsprecher, dann nur seine Mitglieder.
    readonly property var members: store && player
                                   ? Models.groupMembers(player, store.players) : []

    // Die Regler hängen an einem ListModel mit den Ids, nicht direkt an
    // `members`: das ist bei jedem player_updated ein neues Array, und ein
    // Repeater baut dann alle Delegates neu -- auch den Regler, den man gerade
    // zieht, und das Ziehen selbst löst solche Ereignisse aus. Neu aufgebaut
    // wird nur, wenn sich die Zusammensetzung ändert.
    readonly property string memberKey: {
        var ids = []
        for (var i = 0; i < members.length; i++) {
            ids.push(members[i].player_id)
        }
        return ids.join("|")
    }
    function rebuildMembers() {
        memberModel.clear()
        for (var i = 0; i < members.length; i++) {
            memberModel.append({ memberId: members[i].player_id })
        }
    }
    onMemberKeyChanged: rebuildMembers()
    Component.onCompleted: rebuildMembers()

    ListModel { id: memberModel }

    allowedOrientations: defaultAllowedOrientations

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

            // Die Gruppenlautstärke zieht die Einzelwerte im Verhältnis mit
            // (PlayerStore.setGroupVolume); die Regler darunter folgen dem
            // über die Ereignisse vom Server.
            VolumeSlider {
                id: groupVolume
                width: parent.width
                visible: page.hasMembers
                enabled: mass && mass.ready
                label: qsTr("Lautstärke der Gruppe")
                serverLevel: (page.player && typeof page.player.group_volume === "number")
                             ? page.player.group_volume : -1
                onLevelRequested: store.setGroupVolume(page.playerId, level)
            }

            SectionHeader {
                visible: page.hasMembers && page.members.length > 0
                text: qsTr("Einzeln")
            }

            Repeater {
                model: memberModel

                VolumeSlider {
                    readonly property var member: store ? store.playerById(memberId) : null
                    width: parent.width
                    visible: page.hasMembers
                             && Models.hasFeature(member, Models.FEATURE_VOLUME_SET)
                    enabled: mass && mass.ready && Models.isAvailable(member)
                    label: Models.playerName(member)
                    serverLevel: (member && typeof member.volume_level === "number")
                                 ? member.volume_level : -1
                    onLevelRequested: store.setVolume(memberId, level)
                }
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
