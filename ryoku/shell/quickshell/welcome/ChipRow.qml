pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons
import "Singletons"

// A wrapping row of single-select chips, the house Chips vocabulary: the
// selected chip inverts to a bone plate (emphasis is inversion, never an accent
// fill). Unlike the fixed segmented control it holds two choices or seven
// without crowding, and wraps on a narrow column. `model` is a list of
// { key, label }, kept over Ryoku.Ui's Chips because a key may differ from its
// displayed label.
Flow {
    id: chips

    property var model: []
    property string current: ""
    signal selected(string key)

    spacing: 5

    Repeater {
        model: chips.model

        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool on: chips.current === chip.modelData.key

            implicitWidth: t.implicitWidth + 18
            height: 24
            radius: Tokens.radius
            color: chip.on ? Tokens.bone : (h.hovered ? Tokens.tint10 : "transparent")
            border.width: Tokens.border
            border.color: h.hovered && !chip.on ? Tokens.lineStrong : Tokens.line
            Behavior on color { ColorAnimation { duration: Motion.snap } }
            Behavior on border.color { ColorAnimation { duration: Motion.snap } }

            Text {
                id: t
                anchors.centerIn: parent
                text: chip.modelData.label
                color: chip.on ? Tokens.inkOnBone : Tokens.inkDim
                font.family: Tokens.ui
                font.pixelSize: 10
                font.weight: Font.Medium
                Behavior on color { ColorAnimation { duration: Motion.snap } }
            }

            HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: chips.selected(chip.modelData.key) }
        }
    }
}
