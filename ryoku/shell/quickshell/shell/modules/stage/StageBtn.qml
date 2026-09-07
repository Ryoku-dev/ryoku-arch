import QtQuick
import shell.services
import "../../components"
import Ryoku.Ui.Singletons

// An action button: filled / outlined / ghost (docs/stage.md).
Rectangle {
    id: btn
    property string icon: ""
    property string label: ""
    property string kind: "outlined"   // filled | outlined | ghost
    property bool enabledAct: true
    signal act()
    width: parent ? parent.width : 0
    height: 44
    radius: Theme.radiusWidget
    opacity: btn.enabledAct ? 1 : 0.4
    color: btn.kind === "filled"
        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, ma.containsMouse && btn.enabledAct ? 0.30 : 0.22)
        : (ma.containsMouse && btn.enabledAct) ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
    border.width: btn.kind === "ghost" ? 0 : 1
    border.color: btn.kind === "filled"
        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
        : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
    Behavior on color { ColorAnimation { duration: Motion.crossfade } }
    Row {
        anchors.centerIn: parent
        spacing: 8
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.icon
            font.pixelSize: 18
            fill: btn.kind === "filled" ? 1 : 0
            color: Theme.onSurface
            visible: btn.icon.length > 0
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr(btn.label)
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm
            font.weight: Font.DemiBold
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.enabledAct ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (btn.enabledAct) btn.act()
    }
}
