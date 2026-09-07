pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "../../components"

// Add widget panel (docs/stage.md): the widgets and the visualizer that are off
// right now, each with an Add. Enabling one drops it on the desktop; the panel
// stays open so several can be added in a row.
StagePanel {
    id: ap
    title: "Add widget"
    kind: "add"
    bodyWidth: 300

    property var items: []
    signal enable(string id)

    readonly property var off: (ap.items || []).filter(e => e.enabled !== true)

    Text {
        visible: ap.off.length === 0
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Everything is already on the desktop."
        color: Theme.onSurfaceVariant
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm - 1
    }

    Repeater {
        model: ap.off
        delegate: Rectangle {
            id: row
            required property var modelData
            width: parent.width
            height: 44
            radius: Theme.radiusWidget
            color: rowMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06) : "transparent"
            Row {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 10
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 15
                    color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
                    MaterialIcon { anchors.centerIn: parent; text: row.modelData.icon; font.pixelSize: 16; color: Theme.onSurface }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 30 - 10 - 54
                    elide: Text.ElideRight
                    text: row.modelData.label
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54; height: 28; radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                    Text {
                        anchors.centerIn: parent
                        text: "Add"
                        color: Theme.inkOn(Theme.primary, Theme.onPrimary)
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 2
                        font.weight: Font.DemiBold
                    }
                }
            }
            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ap.enable(row.modelData.id)
            }
        }
    }
}
