import QtQuick 2.6
import Sailfish.Silica 1.0

// Easter Egg (KONZEPT.md Abschnitt 35): das Cover als Schallplatte. Das
// Albumbild ist das runde Etikett in der Mitte, die Platte dreht sich mit
// 33⅓ U/min, solange `spinning` gilt, läuft beim Anhalten aus, und ein
// Tonarm schwenkt auf die Platte und wieder zurück.
//
// Das Element ist so hoch wie die Platte und so breit wie der Platz daneben
// es erlaubt: Der Tonarm steht rechts neben der Platte.
Item {
    id: root

    property url source
    property bool spinning: false

    readonly property real radius: height / 2
    // Eine Umdrehung bei 33⅓ U/min dauert 1,8 s.
    readonly property int revolution: 1800
    // Anlauf und Auslauf. Bei gleichmässiger Beschleunigung legt die Platte
    // dabei den halben Weg der vollen Geschwindigkeit zurück -- so gibt es
    // beim Übergang keinen Ruck.
    readonly property int rampTime: 1200
    readonly property real rampAngle: 360 * rampTime / revolution / 2

    function startSpinning() {
        coast.stop()
        disc.rotation = disc.rotation % 360
        rampUp.from = disc.rotation
        rampUp.to = disc.rotation + rampAngle
        spinUp.start()
    }

    function stopSpinning() {
        spinUp.stop()
        loop.stop()
        coast.from = disc.rotation
        coast.to = disc.rotation + rampAngle
        coast.start()
    }

    onSpinningChanged: spinning ? startSpinning() : stopSpinning()
    Component.onCompleted: if (spinning) startSpinning()

    SequentialAnimation {
        id: spinUp
        NumberAnimation {
            id: rampUp
            target: disc
            property: "rotation"
            duration: root.rampTime
            easing.type: Easing.InQuad
        }
        ScriptAction {
            script: {
                loop.from = disc.rotation
                loop.to = disc.rotation + 360
                loop.start()
            }
        }
    }

    NumberAnimation {
        id: loop
        target: disc
        property: "rotation"
        duration: root.revolution
        loops: Animation.Infinite
    }

    NumberAnimation {
        id: coast
        target: disc
        property: "rotation"
        duration: root.rampTime
        easing.type: Easing.OutQuad
    }

    // --- Platte ------------------------------------------------------------
    Item {
        id: disc
        width: root.height
        height: root.height
        anchors.centerIn: parent

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#141414"
        }

        // Rillen: ein paar feine Ringe, nach innen dichter.
        Repeater {
            model: 9
            Rectangle {
                anchors.centerIn: parent
                width: disc.width * (0.94 - index * 0.055)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, index % 3 === 0 ? 0.10 : 0.05)
            }
        }

        // Etikett: das Albumbild, rund ausgeschnitten.
        Rectangle {
            id: labelBackground
            anchors.centerIn: parent
            width: disc.width * 0.4
            height: width
            radius: width / 2
            color: Theme.highlightDimmerColor
            visible: labelImage.status !== Image.Ready
        }
        Image {
            id: labelImage
            anchors.centerIn: parent
            width: disc.width * 0.4
            height: width
            sourceSize.width: width
            sourceSize.height: height
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.source
            layer.enabled: true
            layer.effect: ShaderEffect {
                fragmentShader: "
                    varying highp vec2 qt_TexCoord0;
                    uniform sampler2D source;
                    uniform lowp float qt_Opacity;
                    void main() {
                        highp vec2 d = qt_TexCoord0 - vec2(0.5);
                        lowp float inside = 1.0 - smoothstep(0.245, 0.25, dot(d, d));
                        gl_FragColor = texture2D(source, qt_TexCoord0) * inside * qt_Opacity;
                    }"
            }
        }

        // Mittelloch
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(4, disc.width * 0.03)
            height: width
            radius: width / 2
            color: "#141414"
        }
    }

    // Glanz: dreht sich nicht mit, so sieht man die Drehung am Etikett und
    // nicht an einem wandernden Lichtfleck.
    Rectangle {
        anchors.fill: disc
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
            GradientStop { position: 0.45; color: "transparent" }
            GradientStop { position: 0.55; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.04) }
        }
    }

    // --- Tonarm ------------------------------------------------------------
    // Drehpunkt rechts oben neben der Platte. In Ruhe hängt der Arm senkrecht
    // neben ihr; beim Abspielen schwenkt er um 19°, dann liegt die Nadel etwa
    // auf 0,8 des Plattenradius -- mitten in den Rillen.
    Item {
        id: arm
        readonly property real length: root.radius * 1.5
        x: disc.x + root.radius * 2.05 - width / 2
        y: disc.y + root.radius * 0.2
        width: Math.max(3, root.radius * 0.05)
        height: length
        transformOrigin: Item.Top
        rotation: root.spinning ? 19 : 0

        Behavior on rotation {
            NumberAnimation { duration: 900; easing.type: Easing.InOutQuad }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: parent.height - head.height / 2
            radius: width / 2
            color: "#b8b8b8"
        }

        // Tonkopf
        Rectangle {
            id: head
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: parent.width * 3
            height: width * 1.6
            radius: width * 0.2
            color: "#d0d0d0"
        }
    }

    // Lagerbock, über dem Arm
    Rectangle {
        x: arm.x + arm.width / 2 - width / 2
        y: arm.y - height / 2
        width: root.radius * 0.24
        height: width
        radius: width / 2
        color: "#909090"
        border.width: Math.max(1, width * 0.12)
        border.color: "#c8c8c8"
    }
}
