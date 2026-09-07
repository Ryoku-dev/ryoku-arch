pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"
import "../stage/Singletons" as Stage
import "../../components"

// The Edit shell ribbon (docs/stage.md): an MS Paint style toolbar docked to the
// top of the screen, full width, two rows. Row one is the tabs (with Reset and
// Done); row two is the active tab's controls in labelled groups. It parks under
// the bar's top rail when the bar is at the top, else 12 px from the edge. One
// accent (the filled Done); everything else is quiet.
Item {
    id: ribbon

    property string monitor: ""
    property real uiScale: 1
    property Item overlay: null

    readonly property var ses: Stage.StageSession
    readonly property string tabId: ribbon.ses.tab
    readonly property bool barTop: Layout.edgeOf("bar") === "top"
    readonly property real railSize: {
        const rails = Config.normalizedFrameBars ? Config.normalizedFrameBars.rails : null;
        const r = rails ? rails.top : null;
        return (r && typeof r.size === "number") ? r.size : 0;
    }
    readonly property real topInset: ribbon.barTop ? Math.max(14, ribbon.railSize * ribbon.uiScale + 10) : 12
    readonly property bool narrow: ribbon.width < 1500

    readonly property int pad: 12
    readonly property int row1H: 44
    readonly property int rowGap: 8
    readonly property int row2H: 66

    anchors.left: parent.left
    anchors.right: parent.right
    y: ribbon.topInset
    implicitHeight: card.height
    height: implicitHeight

    // Where drop-down panels start, in the overlay's (window) coordinates.
    readonly property real dropY: ribbon.y + card.height + 8

    readonly property var tabs: [
        { id: "bar", label: "Bar" }, { id: "dock", label: "Dock" },
        { id: "menus", label: "Menus" }, { id: "depth", label: "Depth" },
        { id: "parallax", label: "Parallax" }
    ]

    component TabPill: Rectangle {
        id: tp
        property string label: ""
        property bool active: false
        signal act()
        width: tpText.implicitWidth + 26
        height: 32
        radius: Theme.radiusWidget
        color: tp.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
            : tpMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Text {
            id: tpText
            anchors.centerIn: parent
            text: tp.label
            color: tp.active ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: tp.active ? Font.DemiBold : Font.Normal
        }
        MouseArea { id: tpMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tp.act() }
    }

    component ActionPill: Rectangle {
        id: ap
        property string label: ""
        property string icon: ""
        property bool filled: false
        signal act()
        width: apRow.implicitWidth + 24
        height: 32
        radius: Theme.radiusWidget
        color: ap.filled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, apMa.containsMouse ? 0.95 : 0.85)
            : apMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
        border.width: ap.filled ? 0 : 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Row {
            id: apRow
            anchors.centerIn: parent
            spacing: 6
            MaterialIcon { anchors.verticalCenter: parent.verticalCenter; visible: ap.icon.length > 0; text: ap.icon; font.pixelSize: 16; color: ap.filled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ap.label; color: ap.filled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface; font.family: Theme.fontPrimary; font.pixelSize: Theme.fontSm - 1; font.weight: Font.DemiBold }
        }
        MouseArea { id: apMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ap.act() }
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        height: ribbon.pad * 2 + ribbon.row1H + ribbon.rowGap + 1 + ribbon.rowGap + ribbon.row2H
        radius: 12
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.97)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)

        // Backstop so a click on empty ribbon never falls to the canvas.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        // Row one: title, tabs, Reset, Done.
        Item {
            id: row1
            x: ribbon.pad
            y: ribbon.pad
            width: card.width - ribbon.pad * 2
            height: ribbon.row1H

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Edit shell"
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontMd
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Repeater {
                        model: ribbon.tabs
                        delegate: TabPill {
                            required property var modelData
                            label: modelData.label
                            active: ribbon.tabId === modelData.id
                            onAct: ribbon.ses.setTab(modelData.id)
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                ActionPill {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ribbon.ses.dirty
                    label: "Reset"; icon: "restart_alt"
                    onAct: ribbon.ses.reset()
                }
                ActionPill {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Done"; icon: "done"; filled: true
                    onAct: ribbon.ses.leave()
                }
            }
        }

        Rectangle {
            id: divider
            x: ribbon.pad
            y: ribbon.pad + ribbon.row1H + ribbon.rowGap
            width: card.width - ribbon.pad * 2
            height: 1
            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
        }

        // Row two: the active tab's control groups.
        Item {
            id: row2
            x: ribbon.pad
            y: ribbon.pad + ribbon.row1H + ribbon.rowGap + 1 + ribbon.rowGap
            width: card.width - ribbon.pad * 2
            height: ribbon.row2H

            BarTab { anchors.fill: parent; visible: ribbon.tabId === "bar"; overlay: ribbon.overlay; dropY: ribbon.dropY; monitor: ribbon.monitor; narrow: ribbon.narrow }
            DockTab { anchors.fill: parent; visible: ribbon.tabId === "dock"; overlay: ribbon.overlay; dropY: ribbon.dropY; monitor: ribbon.monitor; narrow: ribbon.narrow }
            MenusTab { anchors.fill: parent; visible: ribbon.tabId === "menus"; overlay: ribbon.overlay; dropY: ribbon.dropY; monitor: ribbon.monitor; narrow: ribbon.narrow }
            DepthTab { anchors.fill: parent; visible: ribbon.tabId === "depth"; overlay: ribbon.overlay; dropY: ribbon.dropY; monitor: ribbon.monitor; narrow: ribbon.narrow }
            ParallaxTab { anchors.fill: parent; visible: ribbon.tabId === "parallax"; overlay: ribbon.overlay; dropY: ribbon.dropY; monitor: ribbon.monitor; narrow: ribbon.narrow }
        }
    }
}
