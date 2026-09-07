import QtQuick
import shell.services
import "../../components"
import Ryoku.Ui.Singletons

// One cast-order row: a layer, widget or the visualizer, with up/down movers
// that reorder the whole front-first stack (docs/stage.md).
Item {
    id: row
    property var rowData: null
    property int rowIndex: 0
    property int rowCount: 0
    signal move(string id, int dir)
    width: parent ? parent.width : 0
    height: 38
    readonly property string rowLabel: row.rowData ? (row.rowData.label ? I18n.tr(row.rowData.label) : "") : ""
    readonly property string rowIcon: row.rowData ? (row.rowData.icon ? row.rowData.icon : "") : ""
    readonly property bool canMove: row.rowData ? row.rowData.movable === true : false
    Row {
        id: rowLine
        anchors.fill: parent
        spacing: 10
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: row.rowIcon
            font.pixelSize: 16
            color: Theme.onSurfaceVariant
            width: 18
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: row.rowLabel
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
        }
        Item { width: row.rowCount > 0 ? 74 : 0; height: 26 }
        Item {
            width: 30; height: 26
            visible: row.canMove
            opacity: row.rowIndex > 0 ? 1 : 0.3
            enabled: row.rowIndex > 0
            MaterialIcon {
                anchors.centerIn: parent
                text: "keyboard_arrow_up"
                font.pixelSize: 18
                color: upMa.containsMouse ? Theme.onSurface : Theme.onSurfaceVariant
            }
            MouseArea {
                id: upMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: row.move(row.rowData ? row.rowData.id : "", 1)
            }
        }
        Item {
            width: 30; height: 26
            visible: row.canMove
            opacity: row.rowIndex < row.rowCount - 1 ? 1 : 0.3
            enabled: row.rowIndex < row.rowCount - 1
            MaterialIcon {
                anchors.centerIn: parent
                text: "keyboard_arrow_down"
                font.pixelSize: 18
                color: downMa.containsMouse ? Theme.onSurface : Theme.onSurfaceVariant
            }
            MouseArea {
                id: downMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: row.move(row.rowData ? row.rowData.id : "", -1)
            }
        }
    }
}
