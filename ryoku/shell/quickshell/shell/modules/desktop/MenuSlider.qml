pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"
import Ryoku.Ui.Singletons

// A slider row for the desktop context menu, in the quiet-tile idiom of
// MenuRow: a label on the left, a live value on the right, a hairline track
// with an ink fill and a bone-edged handle between them. Drag scrubs live
// (moved) so a value bound through Config re-renders the widget in place;
// release commits once (released) -- the same setLive-then-set split the
// corner resize handle uses, so a drag never thrashes the config file.
Item {
    id: sld

    property string label: ""       // pre-translated by the caller
    property real from: 0
    property real to: 1
    property real value: 0
    property real step: 0.01
    property int decimals: 2
    property string valueText: sld.value.toFixed(sld.decimals)

    signal moved(real v)            // live, on every drag step
    signal released(real v)         // once, to persist

    width: parent ? parent.width : 0
    implicitHeight: Theme.s6

    readonly property real frac: sld.to > sld.from
        ? Math.max(0, Math.min(1, (sld.value - sld.from) / (sld.to - sld.from))) : 0

    Text {
        id: lbl
        anchors { left: parent.left; leftMargin: Theme.s3; verticalCenter: parent.verticalCenter }
        width: Theme.s5 * 2
        elide: Text.ElideRight
        text: I18n.tr(sld.label)
        color: Theme.inkSoft
        font.family: Theme.font
        font.pixelSize: Theme.fBody
        font.weight: Font.Medium
    }
    Text {
        id: val
        anchors { right: parent.right; rightMargin: Theme.s3; verticalCenter: parent.verticalCenter }
        width: Theme.s6
        horizontalAlignment: Text.AlignRight
        text: sld.valueText
        color: Theme.inkDim
        font.family: Theme.mono
        font.pixelSize: Theme.fMicro
        font.weight: Font.Medium
    }
    Item {
        id: track
        anchors { left: lbl.right; leftMargin: Theme.s3; right: val.left; rightMargin: Theme.s3; verticalCenter: parent.verticalCenter }
        height: Theme.s5

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Theme.s1
            radius: Theme.menuTileRadius
            color: Theme.tile
            Rectangle {
                width: Math.round(parent.width * sld.frac)
                height: parent.height
                radius: Theme.menuTileRadius
                color: Theme.ink
            }
        }
        Rectangle {
            width: Theme.s4
            height: Theme.s4
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: Math.round((track.width - width) * sld.frac)
            color: Theme.surface
            border.width: 1
            border.color: Theme.ink
            scale: drag.pressed ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -Theme.s2
            preventStealing: true
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function at(mx) {
                const fr = Math.max(0, Math.min(1, mx / track.width));
                const v = sld.from + fr * (sld.to - sld.from);
                return Math.max(sld.from, Math.min(sld.to, Math.round(v / sld.step) * sld.step));
            }
            onPressed: (m) => sld.moved(at(m.x))
            onPositionChanged: (m) => { if (pressed) sld.moved(at(m.x)); }
            onReleased: (m) => sld.released(at(m.x))
        }
    }
}
