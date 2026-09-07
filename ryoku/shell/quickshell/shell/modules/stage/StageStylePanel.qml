pragma ComponentBehavior: Bound
import QtQuick
import shell.services

// Visualizer Style panel (docs/stage.md): the looks the spectrum knows, the
// current one lit. Picking one retunes the running visualizer; the panel stays
// open so looks can be compared. The name is the control -- no gallery chrome.
StagePanel {
    id: sp
    title: "Style"
    kind: "style"
    bodyWidth: 260

    property var styles: []
    property string current: ""
    signal chose(string key)

    function cap(s) { return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

    Grid {
        width: parent.width
        columns: 2
        rowSpacing: 6
        columnSpacing: 6
        Repeater {
            model: sp.styles
            delegate: Rectangle {
                id: cell
                required property string modelData
                readonly property bool active: sp.current === cell.modelData
                width: (sp.width - 24 - 6) / 2
                height: 34
                radius: Theme.radiusWidget
                color: cell.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                    : cellMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
                border.width: cell.active ? 0 : 1
                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Text {
                    anchors.centerIn: parent
                    text: sp.cap(cell.modelData)
                    color: cell.active ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                    font.weight: cell.active ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: cellMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sp.chose(cell.modelData)
                }
            }
        }
    }
}
