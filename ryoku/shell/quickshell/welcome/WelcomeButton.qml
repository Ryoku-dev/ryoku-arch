import QtQuick
import Ryoku.Ui.Singletons
import "Singletons"

// The walkthrough's CTA, in the house Btn vocabulary. Three kinds:
//   solid   - a bone plate with black ink (inversion is the emphasis, the
//             primary act; there is no accent fill)
//   outline - a hairline that answers hover with a surface tint
//   ghost   - label only, faint->ink (Skip, tertiary)
// Space Grotesk label with the tracked-label spacing; a machine snaps, so the
// states flip on Motion.snap with no scale theatrics.
Item {
    id: btn

    property string label: ""
    property string kind: "outline"   // solid | outline | ghost
    signal clicked()

    readonly property bool solid: kind === "solid"
    readonly property bool ghost: kind === "ghost"

    implicitWidth: label_.implicitWidth + (ghost ? 20 : 32)
    implicitHeight: ghost ? 28 : 32

    opacity: enabled ? 1 : 0.3

    Rectangle {
        id: face
        anchors.fill: parent
        visible: !btn.ghost
        radius: Tokens.radius
        color: btn.solid ? Tokens.bone
             : (tap.pressed ? Tokens.tint16 : (hover.hovered ? Tokens.tint10 : "transparent"))
        border.width: Tokens.border
        border.color: btn.solid ? Tokens.bone
             : (hover.hovered ? Tokens.lineStrong : Tokens.line)
        Behavior on color { ColorAnimation { duration: Motion.snap } }
        Behavior on border.color { ColorAnimation { duration: Motion.snap } }
    }

    Text {
        id: label_
        anchors.centerIn: parent
        text: btn.label
        color: btn.solid ? Tokens.inkOnBone
             : btn.ghost ? (hover.hovered ? Tokens.ink : Tokens.inkMuted)
             : (hover.hovered ? Tokens.ink : Tokens.inkDim)
        font.family: Tokens.ui
        font.pixelSize: Tokens.fMicro
        font.weight: Font.Medium
        font.letterSpacing: Tokens.trackLabel
        Behavior on color { ColorAnimation { duration: Motion.snap } }
    }

    HoverHandler { id: hover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; enabled: btn.enabled; onTapped: btn.clicked() }
}
