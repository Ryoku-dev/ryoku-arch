pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons
import "Singletons"

// Labeled slider with a live readout, the house Slid vocabulary: a hairline
// track, an ink fill, a square ink handle -- no round knob, no accent gradient.
// `moved` fires continuously and drives the readout/handle (the owner holds the
// value); `released` fires once when the drag ends, so the owner commits the
// change exactly once (a file write or a compositor reload), never per-pixel.
Item {
    id: root

    property string label: ""
    property string unit: ""
    property real from: 0
    property real to: 1
    property real step: 1
    property real value: 0
    signal moved(real value)
    signal released(real value)

    implicitWidth: 320
    implicitHeight: 42

    readonly property real handleW: 6
    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    function valueAt(px) {
        var tt = Math.max(0, Math.min(1, px / Math.max(1, slot.width)));
        var v = from + tt * (to - from);
        if (step > 0)
            v = Math.round(v / step) * step;
        return Math.max(from, Math.min(to, v));
    }

    Text {
        id: lbl
        anchors.left: parent.left
        anchors.top: parent.top
        text: root.label
        color: Tokens.inkDim
        font.family: Tokens.ui
        font.pixelSize: Tokens.fSmall
        font.weight: Font.Medium
    }

    // the readout is language (a numeral a human reads), so Space Grotesk.
    Text {
        anchors.right: parent.right
        anchors.baseline: lbl.baseline
        text: Math.round(root.value) + (root.unit.length ? (" " + root.unit) : "")
        color: Tokens.ink
        font.family: Tokens.ui
        font.pixelSize: Tokens.fSmall
        font.weight: Font.DemiBold
    }

    Item {
        id: slot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 20

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            color: "transparent"
            border.width: Tokens.border
            border.color: ma.containsMouse || ma.pressed ? Tokens.lineStrong : Tokens.line
            antialiasing: false
            Behavior on border.color { ColorAnimation { duration: Motion.snap } }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.frac * parent.width
            height: 4
            color: Tokens.ink
            antialiasing: false
        }
        Rectangle {
            x: Math.min(parent.width - root.handleW, Math.max(0, root.frac * parent.width - root.handleW / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: root.handleW
            height: 17
            color: Tokens.ink
            antialiasing: false
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            onPressed: (m) => root.moved(root.valueAt(m.x))
            onPositionChanged: (m) => { if (pressed) root.moved(root.valueAt(m.x)); }
            onReleased: (m) => root.released(root.valueAt(m.x))
        }
    }
}
