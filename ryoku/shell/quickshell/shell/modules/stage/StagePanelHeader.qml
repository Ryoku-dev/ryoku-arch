import QtQuick
import shell.services
import "../../components"
import Ryoku.Ui.Singletons

// A collapsible section header with an optional eye toggle (docs/stage.md).
Item {
    id: ph
    property string icon: "layers"
    property string label: ""
    property bool expanded: false
    property bool showEye: false
    property bool eyeOn: true
    signal toggle()
    signal eye()
    width: parent ? parent.width : 0
    height: 44
    Row {
        anchors.fill: parent
        spacing: 10
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: ph.expanded ? "keyboard_arrow_down" : "keyboard_arrow_right"
            font.pixelSize: 18
            color: Theme.onSurfaceVariant
        }
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: ph.icon
            font.pixelSize: 16
            color: Theme.onSurfaceVariant
            width: 18
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr(ph.label)
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            visible: ph.showEye
            MaterialIcon {
                anchors.centerIn: parent
                text: ph.eyeOn ? "visibility" : "visibility_off"
                font.pixelSize: 16
                color: ph.eyeOn ? Theme.primary : Theme.onSurfaceVariant
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: ph.eye()
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: ph.toggle()
    }
}
