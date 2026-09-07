import QtQuick
import shell.services
import "../../components"
import Ryoku.Ui.Singletons

// A clickable icon + label + sub row (install prompts, folder actions).
Rectangle {
    id: nav
    property string icon: "circle"
    property string label: ""
    property string sub: ""
    signal activated()
    width: parent ? parent.width : 0
    height: 54
    radius: Theme.radiusWidget
    color: navMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06) : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.crossfade } }
    Row {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 10
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: nav.icon
            font.pixelSize: 18
            color: Theme.onSurfaceVariant
        }
        Column {
            width: parent.width - 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: I18n.tr(nav.label)
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: nav.sub.length > 0
                text: nav.sub
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 3
                wrapMode: Text.WordWrap
            }
        }
    }
    MouseArea {
        id: navMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: nav.activated()
    }
}
