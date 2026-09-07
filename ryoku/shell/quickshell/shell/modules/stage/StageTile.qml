import QtQuick
import shell.services
import "../../components"
import Ryoku.Ui.Singletons

// A toggle tile: round icon, label + sub, and a switch (docs/stage.md).
Rectangle {
    id: tile
    property string icon: "circle"
    property string label: ""
    property string sub: ""
    property bool on: false
    property bool available: true
    signal toggled()
    width: parent ? parent.width : 0
    height: 58
    radius: Theme.radiusWidget
    color: "transparent"
    opacity: tile.available ? 1 : 0.4
    Row {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 10
        Rectangle {
            width: 34
            height: 34
            radius: 17
            anchors.verticalCenter: parent.verticalCenter
            color: tile.on ? Theme.primary
                : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
            MaterialIcon {
                anchors.centerIn: parent
                text: tile.icon
                font.pixelSize: 16
                color: tile.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
            }
        }
        Column {
            width: parent.width - 34 - 10 - 46
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: I18n.tr(tile.label)
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: tile.sub.length > 0
                text: tile.sub
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 3
                elide: Text.ElideRight
            }
        }
        Rectangle {
            width: 40
            height: 22
            radius: 11
            anchors.verticalCenter: parent.verticalCenter
            color: tile.on ? Theme.primary : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
            Rectangle {
                width: 18
                height: 18
                radius: 9
                x: tile.on ? 19 : 2
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surface
                Behavior on x { NumberAnimation { duration: Motion.fast } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.toggled()
            }
        }
    }
}
