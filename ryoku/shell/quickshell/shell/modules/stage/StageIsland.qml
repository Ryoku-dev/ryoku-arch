pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "../../components"

// The editor's island (docs/stage.md): a floating bar docked at the top centre
// of the monitor, in Ryoku's own glass. Its first row names the session and the
// monitor, holds the scope tabs, a Reset that appears only once something
// changed, and Done. Its second row belongs to the current selection or scope --
// the caller fills it. Two rows at most; it never wraps at 1366.
Item {
    id: island

    property string title: ""
    property string monitor: ""
    property var scopes: []          // [{ id, label }]
    property string scope: ""
    property bool showReset: false

    // The caller drops the second row's controls in here.
    default property alias secondRow: slot.data

    signal scopeChose(string id)
    signal reset()
    signal done()

    readonly property real pad: 14
    readonly property bool hasSecond: slot.implicitWidth > 1
    x: Math.round(((parent ? parent.width : 0) - width) / 2)
    y: 18
    width: card.width
    height: card.height

    component Pill: Rectangle {
        id: pill
        property string label: ""
        property string icon: ""
        property bool active: false
        property bool emphasized: false
        signal act()
        width: pillRow.implicitWidth + 24
        height: 30
        radius: Theme.radiusWidget
        color: pill.active || pill.emphasized
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, pill.emphasized ? 0.9 : 0.85)
            : pillMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
        border.width: (pill.active || pill.emphasized) ? 0 : 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: pill.icon.length > 0 ? 6 : 0
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.icon.length > 0
                text: pill.icon
                font.pixelSize: 16
                color: (pill.active || pill.emphasized) ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: (pill.active || pill.emphasized) ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
                font.weight: (pill.active || pill.emphasized) ? Font.DemiBold : Font.Normal
            }
        }
        MouseArea { id: pillMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.act() }
    }

    Rectangle {
        id: card
        width: Math.min((island.parent ? island.parent.width : 2000) - 36,
            Math.max(topRow.implicitWidth, slot.implicitWidth) + island.pad * 2)
        height: topRow.height + (island.hasSecond ? divider.height + slot.implicitHeight + 8 : 0) + island.pad * 2
        radius: Theme.radiusWidget
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.96)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.45)

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Row {
            id: topRow
            x: Math.round((card.width - implicitWidth) / 2)
            y: island.pad
            spacing: 16

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: island.title
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontMd
                    font.weight: Font.DemiBold
                }
                Text {
                    text: island.monitor
                    visible: island.monitor.length > 0
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 3
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: island.scopes
                    delegate: Pill {
                        required property var modelData
                        label: modelData.label
                        active: island.scope === modelData.id
                        onAct: island.scopeChose(modelData.id)
                    }
                }
            }

            Pill {
                anchors.verticalCenter: parent.verticalCenter
                visible: island.showReset
                label: "Reset"
                icon: "restart_alt"
                onAct: island.reset()
            }
            Pill {
                anchors.verticalCenter: parent.verticalCenter
                label: "Done"
                icon: "done"
                emphasized: true
                onAct: island.done()
            }
        }

        Rectangle {
            id: divider
            visible: island.hasSecond
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: island.pad
            anchors.rightMargin: island.pad
            y: topRow.y + topRow.height + 6
            height: 1
            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
        }

        // The second row: the caller's controls, centred.
        Item {
            id: slot
            implicitWidth: childrenRect.width
            implicitHeight: island.hasSecond ? 46 : 0
            x: Math.round((card.width - implicitWidth) / 2)
            y: divider.y + 8
        }
    }
}
