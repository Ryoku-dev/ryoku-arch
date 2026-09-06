pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "../../components"

// The edit-mode chip for a desktop widget or the visualizer (docs/stage.md): a
// soft outline around the element and a pill carrying its front/behind flip,
// lock, per-widget settings (the existing right-click menu) and remove. The chip
// is a full-screen overlay positioned from the element's on-screen `box`, so the
// pill is always clickable even when it floats past a small widget's edge.
// The caller wires every action; this stays a dumb, reusable control.
Item {
    id: chip
    anchors.fill: parent

    property rect box: Qt.rect(0, 0, 0, 0)
    property string title: ""
    property bool isFront: false
    property string frontLabel: "In front"
    property string behindLabel: "Behind"
    property bool locked: false
    property bool canLock: true
    property bool canRemove: true
    property bool canSettings: true
    property bool selected: false

    signal flip()
    signal toggleLock()
    signal removeEl()
    signal openSettings()
    signal picked()

    visible: chip.box.width > 1 && chip.box.height > 1

    // Soft outline around the element.
    Rectangle {
        x: chip.box.x
        y: chip.box.y
        width: chip.box.width
        height: chip.box.height
        radius: Theme.radiusWidget
        color: "transparent"
        border.width: 2
        border.color: chip.selected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
            : chip.isFront ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
            : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.35)
    }

    // The chip pill, above the box (or below when the box hugs the top edge).
    Rectangle {
        id: pill
        x: Math.round(Math.max(8, Math.min(chip.width - width - 8, chip.box.x + chip.box.width / 2 - width / 2)))
        y: Math.round(chip.box.y > 56 ? chip.box.y - height - 8 : chip.box.y + chip.box.height + 8)
        width: row.implicitWidth + 20
        height: 36
        radius: 18
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
        border.width: 1
        border.color: chip.selected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
            : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.45)

        // Background tap selects the element.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.title
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
                font.weight: Font.DemiBold
            }

            // Front/behind flip.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: flipRow.implicitWidth + 16
                height: 26
                radius: 13
                color: chip.isFront ? Theme.primary : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Row {
                    id: flipRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "swap_vert"
                        font.pixelSize: 14
                        color: chip.isFront ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.isFront ? chip.frontLabel : chip.behindLabel
                        color: chip.isFront ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 2
                        font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chip.flip()
                }
            }

            // Icon actions: lock, settings, remove.
            component IconBtn: Rectangle {
                id: ib
                property string icon: ""
                property bool on: false
                signal act()
                width: 26
                height: 26
                radius: 13
                color: ib.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                    : ibMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12) : "transparent"
                MaterialIcon {
                    anchors.centerIn: parent
                    text: ib.icon
                    font.pixelSize: 15
                    color: ib.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurfaceVariant
                }
                MouseArea {
                    id: ibMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ib.act()
                }
            }

            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.canLock
                icon: chip.locked ? "lock" : "lock_open"
                on: chip.locked
                onAct: chip.toggleLock()
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.canSettings
                icon: "tune"
                onAct: chip.openSettings()
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.canRemove
                icon: "close"
                onAct: chip.removeEl()
            }
        }
    }
}
