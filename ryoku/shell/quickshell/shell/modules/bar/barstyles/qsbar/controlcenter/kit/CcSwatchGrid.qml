import QtQuick
import "../../modules"
import Ryoku.Ui.Singletons

// The wallpaper-palette accent picker: color01..07 plus foreground. Selecting
// emits `chose(id)`; the caller writes root.barColor.
//
// This is the one control in the panel that keeps its colour, because here the
// colour IS the data: a swatch that showed its own hue as a grey plate would be
// lying about what it does. The selection ring is bone, like every other
// emphasis in the panel.
Grid {
    id: sw
    property var root
    property var tk
    property var options: root ? root.barColorOptions : []
    property string current: ""
    signal chose(string id)

    columns: 8
    columnSpacing: sw.tk ? sw.tk.gap / 2 : 6
    rowSpacing: sw.tk ? sw.tk.gap / 2 : 6

    Repeater {
        model: sw.options
        delegate: Rectangle {
            id: cell
            required property string modelData
            readonly property bool on: sw.current === modelData
            width: sw.tk ? Tokens.ctlH : 26
            height: width
            radius: sw.tk ? Tokens.radius : 6
            color: sw.root.paletteColor(modelData)
            border.width: cell.on ? 2 : 1
            border.color: cell.on ? (sw.tk ? Tokens.bone : "#cdc4ba") : (sw.tk ? Tokens.line : "#333333")
            scale: ma.pressed ? 1.0 : (ma.containsMouse ? 1.06 : 1.0)
            z: ma.containsMouse ? 1 : 0
            Behavior on scale { NumberAnimation { duration: sw.tk ? Tokens.snap : 90; easing.type: Easing.OutCubic } }

            UiText {
                anchors.centerIn: parent
                text: cell.modelData === "foreground" ? "FG" : cell.modelData.slice(-2)
                color: sw.root.paletteContrastColor(cell.modelData)
                font.family: sw.tk ? Tokens.mono : "monospace"
                font.pixelSize: sw.tk ? Tokens.fTiny : 9
                font.weight: Font.Medium
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sw.chose(cell.modelData)
            }
        }
    }
}
