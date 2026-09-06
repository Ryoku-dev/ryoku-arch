import QtQuick
import shell.services

// A segmented control: one row of options, one selected (docs/stage.md).
Rectangle {
    id: seg
    property var options: []   // [{ id, label }]
    property string current: ""
    signal chose(string id)
    implicitHeight: 38
    radius: Theme.radiusWidget
    color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06)
    border.width: 1
    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.30)
    width: parent ? parent.width : 0
    Row {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4
        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property bool active: opt.modelData.id === seg.current
                width: (parent.width - (seg.options.length - 1) * 4) / Math.max(1, seg.options.length)
                height: parent.height
                radius: Theme.radiusWidget - 4
                color: opt.active ? Theme.primary
                    : optMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                    : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.crossfade } }
                Text {
                    anchors.centerIn: parent
                    text: opt.modelData.label
                    color: opt.active ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                    font.weight: opt.active ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: optMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.chose(opt.modelData.id)
                }
            }
        }
    }
}
