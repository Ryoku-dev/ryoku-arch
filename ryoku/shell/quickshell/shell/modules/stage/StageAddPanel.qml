pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "../../components"

// The Add widget drop-down (docs/stage.md, "Edit widgets"): one row per widget
// (the built-ins, every enabled plugin widget, the visualizer), each with its
// icon, name and a switch. On adds it at its default anchor; off removes it. It
// drops from the Add widget button and stays open so several can be toggled in
// a row. Escape closes it (the editor's escapeStep) and a click on bare
// wallpaper closes it (the desktop's catcher).
Item {
    id: ap
    anchors.fill: parent

    // [{ id, label, icon, enabled }].
    property var items: []
    // Top-left corner the card drops to, in the editor's coordinate space.
    property real anchorX: 0
    property real anchorY: 0

    signal closeRequested()
    signal toggle(string id)

    readonly property real cardW: 300

    Rectangle {
        id: card
        width: ap.cardW
        x: Math.round(Math.max(12, Math.min((ap.width > 0 ? ap.width : 2000) - width - 12, ap.anchorX)))
        y: Math.round(ap.anchorY)
        height: col.implicitHeight + 16
        radius: 12
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.98)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)

        // Absorb clicks on the card so they never fall through to a widget or
        // the wallpaper; the rows sit above and keep their own presses.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 2

            Repeater {
                model: ap.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: col.width
                    height: 44
                    radius: 8
                    color: rowMa.containsMouse
                        ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.07)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    MaterialIcon {
                        id: rowIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.icon
                        font.pixelSize: 18
                        color: Theme.onSurface
                    }
                    Text {
                        anchors.left: rowIcon.right
                        anchors.leftMargin: 12
                        anchors.right: track.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.modelData.label
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.DemiBold
                    }
                    // The state switch: on = present, off = removed.
                    Rectangle {
                        id: track
                        readonly property bool on: row.modelData.enabled === true
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42
                        height: 24
                        radius: 12
                        color: track.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                            : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
                        border.width: 1
                        border.color: track.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
                            : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            x: track.on ? parent.width - width - 3 : 3
                            color: track.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                            Behavior on x { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ap.toggle(row.modelData.id)
                    }
                }
            }
        }
    }
}
