pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"
import "../../components"

// The Edit widgets toolbar (docs/stage.md, "Edit widgets"): one row docked
// top-centre while the desktop is lifted. Title, Add widget (drops a panel
// under the button), Visualizer... (hands off to Customize visualizer), Reset
// (only once something changed) and the filled Done. The desktop draws the
// per-widget frames and runs the drag/resize; this owns the toolbar and the Add
// drop-down and reports its host actions as signals.
Item {
    id: ed
    anchors.fill: parent

    property string monitor: ""
    // The Add drop-down's model: every widget with its current on/off state:
    // [{ id, label, icon, enabled }].
    property var items: []

    signal done()
    signal visualizer()
    signal addToggle(string id)

    readonly property var ses: StageSession

    onVisibleChanged: if (ed.visible) ed.forceActiveFocus()
    // Escape unwinds one level (drop-down, then selection, then leave).
    Keys.onEscapePressed: e => { if (ed.ses.escapeStep() === "leave") ed.done(); e.accepted = true; }
    Keys.onReturnPressed: e => { ed.done(); e.accepted = true; }

    // A compact toolbar button: an optional leading icon, a label, an optional
    // trailing chevron. Quiet by default, a faint fill on hover, the one accent
    // when `on` (a drop-down is open) or `filled` (Done).
    component Tool: Rectangle {
        id: tb
        property string icon: ""
        property string label: ""
        property string trailingIcon: ""
        property bool on: false
        property bool filled: false
        signal act()
        readonly property bool accent: tb.filled || tb.on
        implicitWidth: tbRow.implicitWidth + 24
        width: implicitWidth
        height: 36
        radius: 9
        color: tb.accent
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b,
                tbMa.containsMouse ? 0.95 : (tb.filled ? 0.9 : 0.82))
            : tbMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10) : "transparent"
        border.width: tb.accent ? 0 : 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Row {
            id: tbRow
            anchors.centerIn: parent
            spacing: 7
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: tb.icon.length > 0
                text: tb.icon
                font.pixelSize: 17
                fill: tb.accent ? 1 : 0
                color: tb.accent ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tb.label
                color: tb.accent ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
            }
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: tb.trailingIcon.length > 0
                text: tb.trailingIcon
                font.pixelSize: 16
                color: tb.accent ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurfaceVariant
            }
        }
        MouseArea {
            id: tbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.act()
        }
    }

    // The toolbar bar itself, docked 12 px from the top, centred.
    Rectangle {
        id: bar
        x: Math.round((ed.width - width) / 2)
        y: 12
        height: 52
        width: Math.round(left.implicitWidth + right.implicitWidth + 72)
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)

        // Swallow presses on the bar chrome so a click between buttons never
        // leaks to a widget or the wallpaper beneath the lifted desktop. Sits
        // under the button rows, so the buttons keep their own clicks.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Row {
            id: left
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Edit widgets"
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontMd
                font.weight: Font.DemiBold
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 26
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
            }
            Tool {
                id: addBtn
                anchors.verticalCenter: parent.verticalCenter
                icon: "add"
                label: "Add widget"
                trailingIcon: "expand_more"
                on: ed.ses.panel === "add"
                onAct: ed.ses.togglePanel("add")
            }
            Tool {
                anchors.verticalCenter: parent.verticalCenter
                icon: "graphic_eq"
                label: "Visualizer..."
                onAct: ed.visualizer()
            }
        }

        Row {
            id: right
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            // Reset keeps its slot while clean (faded, inert) so the centred bar
            // never changes width and Done never moves under the pointer.
            Tool {
                anchors.verticalCenter: parent.verticalCenter
                opacity: ed.ses.dirty ? 1 : 0
                enabled: ed.ses.dirty
                icon: "restart_alt"
                label: "Reset"
                onAct: ed.ses.reset()
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            Tool {
                anchors.verticalCenter: parent.verticalCenter
                label: "Done"
                filled: true
                onAct: ed.done()
            }
        }
    }

    // The Add widget drop-down, left-aligned under the Add widget button.
    StageAddPanel {
        visible: ed.ses.panel === "add"
        items: ed.items
        anchorX: Math.round(bar.x + left.x + addBtn.x)
        anchorY: Math.round(bar.y + bar.height + 8)
        onCloseRequested: ed.ses.closePanel()
        onToggle: id => ed.addToggle(id)
    }
}
