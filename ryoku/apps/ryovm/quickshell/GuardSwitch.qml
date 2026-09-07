import QtQuick
import Ryoku.Ui.Singletons

// A guarded destructive switch: the verb lives under a flip-up cover plate, like
// a missile switch. First click lifts the cover and arms the bed; clicking the
// armed bed fires; the cover slams shut by itself after 3s of hesitation. Two
// distinct, deliberate motions for destruction: interaction design, not decor.
//
// Monochrome grammar (DESIGN 3.4): the cover is a flat paperLift plate with
// 45-degree ink hazard hatching (pattern replaces colour); the armed bed is the
// contract's destructive plate: bone fill, black verb, 2px border. No red.
Item {
    id: gs

    property string label: I18n.tr("DELETE")
    property string armedLabel: I18n.tr("CONFIRM")
    property bool enabled: true
    signal fired()

    property bool armed: false

    implicitWidth: 128
    implicitHeight: 34
    opacity: gs.enabled ? 1 : 0.3

    onArmedChanged: if (armed) slam.restart(); else slam.stop()
    Timer { id: slam; interval: 3000; onTriggered: gs.armed = false }

    // the armed bed: bone plate, 2px border, black verb, waiting.
    Rectangle {
        id: bed
        anchors.fill: parent
        radius: Tokens.radius
        color: gs.armed ? Tokens.bone : "transparent"
        border.width: gs.armed ? 2 : Tokens.border
        border.color: gs.armed ? Tokens.bone : Tokens.line
        antialiasing: false

        Text {
            anchors.centerIn: parent
            text: gs.armed ? gs.armedLabel : ""
            color: Tokens.inkOnBone
            font.family: Tokens.ui
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: Tokens.trackLabel
        }

        TapHandler {
            enabled: gs.enabled && gs.armed
            onTapped: { gs.armed = false; gs.fired(); }
        }
        HoverHandler { enabled: gs.enabled && gs.armed; cursorShape: Qt.PointingHandCursor }
    }

    // the cover plate: hinged on its top edge, hazard-hatched.
    Item {
        id: coverPivot
        anchors.fill: parent
        transform: Rotation {
            id: hinge
            origin.x: 0
            origin.y: 0
            axis { x: 1; y: 0; z: 0 }
            angle: gs.armed ? 78 : 0
            Behavior on angle { NumberAnimation { duration: Tokens.move; easing.type: Tokens.easeSnap } }
        }
        visible: hinge.angle < 89

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radius
            color: Tokens.paperLift
            border.width: Tokens.border
            border.color: Tokens.lineStrong
            antialiasing: false
            clip: true

            // 45-degree ink hazard hatching across the whole cover.
            Repeater {
                model: Math.ceil((gs.width + gs.height) / 12)
                delegate: Rectangle {
                    required property int index
                    width: 3
                    height: gs.height * 3
                    rotation: 45
                    antialiasing: false
                    color: Tokens.line
                    x: index * 12 - gs.height
                    y: -gs.height
                }
            }

            Text {
                anchors.centerIn: parent
                text: I18n.tr(gs.label)
                color: gh.hovered && gs.enabled ? Tokens.ink : Tokens.inkDim
                font.family: Tokens.ui
                font.pixelSize: 11
                font.weight: Font.Medium
                font.letterSpacing: Tokens.trackLabel
                Behavior on color { ColorAnimation { duration: Tokens.snap } }
            }
        }

        TapHandler {
            enabled: gs.enabled && !gs.armed
            onTapped: gs.armed = true
        }
        HoverHandler { id: gh; enabled: gs.enabled && !gs.armed; cursorShape: Qt.PointingHandCursor }
    }
}
