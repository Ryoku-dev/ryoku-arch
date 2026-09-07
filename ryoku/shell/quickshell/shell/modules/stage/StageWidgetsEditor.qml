pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"
import "../../components"

// The Edit widgets session (docs/stage.md): the island with its three scopes
// (Depth, Widgets, Visualizer) and the floating panels each scope opens. The
// desktop draws the outlines and runs the drag/resize; this owns the island, the
// second row, and the panels, and reports host-specific actions as signals.
Item {
    id: ed
    anchors.fill: parent

    property string monitor: ""
    property var elements: []
    property bool vizOverlay: false
    property var vizStyles: []
    property string vizStyle: ""
    property rect selectedBox: Qt.rect(0, 0, 0, 0)

    signal done()
    signal widgetLockToggle(string id)
    signal widgetSettings(string id)
    signal widgetRemove(string id)
    signal vizFlip()
    signal vizRemove()
    signal addEnable(string id)
    signal vizStyleChose(string key)

    readonly property var ses: StageSession
    readonly property var sb: StageBackend
    readonly property string effect: ed.sb.effect
    readonly property string sel: ed.ses.selected
    readonly property var selItem: (ed.elements || []).find(e => e.id === ed.sel) || null

    function setEffect(e) { ed.sb.setEffect(e); }
    function setQuality(id) {
        Config.setQuality(id);
        if (ed.sb.qualityInstalled(id) && ed.effect !== "off")
            ed.sb.refresh();
    }

    onVisibleChanged: if (ed.visible) ed.forceActiveFocus()
    Keys.onEscapePressed: e => { if (ed.ses.escapeStep() === "leave") ed.done(); e.accepted = true; }
    Keys.onReturnPressed: e => { ed.done(); e.accepted = true; }

    // A compact action pill for the second row.
    component Act: Rectangle {
        id: ab
        property string icon: ""
        property string label: ""
        property bool on: false
        signal act()
        width: abRow.implicitWidth + 22
        height: 34
        radius: Theme.radiusWidget
        color: ab.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
            : abMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
        border.width: ab.on ? 0 : 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Row {
            id: abRow
            anchors.centerIn: parent
            spacing: 6
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: ab.icon.length > 0
                text: ab.icon
                font.pixelSize: 16
                color: ab.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ab.label
                color: ab.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
                font.weight: Font.DemiBold
            }
        }
        MouseArea { id: abMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ab.act() }
    }

    Component {
        id: depthRow
        Row {
            spacing: 16
            StageSwitch {
                anchors.verticalCenter: parent.verticalCenter
                label: "Depth"; checked: ed.effect !== "off"
                onToggled: ed.setEffect(ed.effect === "off" ? "depth" : "off")
            }
            StageSwitch {
                anchors.verticalCenter: parent.verticalCenter
                label: "Parallax"; checked: ed.effect === "parallax"; switchEnabled: ed.effect !== "off"
                onToggled: ed.setEffect(ed.effect === "parallax" ? "depth" : "parallax")
            }
            StageQuality {
                anchors.verticalCenter: parent.verticalCenter
                width: 400
                current: Config.quality
                onChose: id => ed.setQuality(id)
            }
        }
    }

    Component {
        id: widgetsRow
        Row {
            spacing: 10
            Act {
                anchors.verticalCenter: parent.verticalCenter
                visible: ed.selItem !== null
                icon: (ed.selItem && ed.selItem.locked) ? "lock" : "lock_open"
                label: "Lock"; on: ed.selItem ? ed.selItem.locked === true : false
                onAct: ed.widgetLockToggle(ed.sel)
            }
            Act {
                anchors.verticalCenter: parent.verticalCenter
                visible: ed.selItem !== null
                icon: "tune"; label: "Settings"; onAct: ed.widgetSettings(ed.sel)
            }
            Act {
                anchors.verticalCenter: parent.verticalCenter
                visible: ed.selItem !== null
                icon: "visibility_off"; label: "Hide"
                onAct: { ed.widgetRemove(ed.sel); ed.ses.deselect(); }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: ed.selItem !== null && ed.selectedBox.width > 1
                text: Math.round(ed.selectedBox.width) + " \u00d7 " + Math.round(ed.selectedBox.height)
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 2
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: ed.selItem !== null
                width: 1; height: 24
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
            }
            Act {
                anchors.verticalCenter: parent.verticalCenter
                icon: "add"; label: "Add widget"; on: ed.ses.panel === "add"
                onAct: ed.ses.panel === "add" ? ed.ses.closePanel() : ed.ses.openPanel("add")
            }
        }
    }

    Component {
        id: vizRow
        Row {
            spacing: 12
            StageSeg {
                anchors.verticalCenter: parent.verticalCenter
                width: 240
                options: [{ id: "desktop", label: "On desktop" }, { id: "above", label: "Above windows" }]
                current: ed.vizOverlay ? "above" : "desktop"
                onChose: id => { if ((id === "above") !== ed.vizOverlay) ed.vizFlip(); }
            }
            Act {
                anchors.verticalCenter: parent.verticalCenter
                icon: "palette"; label: "Style"; on: ed.ses.panel === "style"
                onAct: ed.ses.panel === "style" ? ed.ses.closePanel() : ed.ses.openPanel("style")
            }
            Act {
                anchors.verticalCenter: parent.verticalCenter
                icon: "visibility_off"; label: "Hide"; onAct: ed.vizRemove()
            }
        }
    }

    StageIsland {
        id: island
        title: "Edit desktop"
        monitor: ed.monitor
        scopes: [
            { id: "depth", label: "Depth" },
            { id: "widgets", label: "Widgets" },
            { id: "visualizer", label: "Visualizer" }
        ]
        scope: ed.ses.scope
        showReset: ed.ses.dirty
        onScopeChose: id => {
            ed.ses.setScope(id);
            if (id === "depth")
                ed.ses.panel = "depth";
        }
        onReset: ed.ses.reset()
        onDone: ed.done()

        Loader {
            width: implicitWidth
            sourceComponent: ed.ses.scope === "depth" ? depthRow
                : ed.ses.scope === "visualizer" ? vizRow : widgetsRow
        }
    }

    StageDepthPanel {
        monitor: ed.monitor
        visible: ed.ses.scope === "depth" && ed.ses.panel === "depth"
        pinned: ed.ses.panelPinned
        defaultY: island.y + island.height + 16
        onCloseRequested: ed.ses.closePanel()
        onPinToggled: ed.ses.togglePin()
    }

    StageAddPanel {
        monitor: ed.monitor
        visible: ed.ses.panel === "add"
        pinned: ed.ses.panelPinned
        items: ed.elements
        defaultY: island.y + island.height + 16
        onCloseRequested: ed.ses.closePanel()
        onPinToggled: ed.ses.togglePin()
        onEnable: id => ed.addEnable(id)
    }

    StageStylePanel {
        monitor: ed.monitor
        visible: ed.ses.panel === "style"
        pinned: ed.ses.panelPinned
        styles: ed.vizStyles
        current: ed.vizStyle
        defaultY: island.y + island.height + 16
        onCloseRequested: ed.ses.closePanel()
        onPinToggled: ed.ses.togglePin()
        onChose: key => ed.vizStyleChose(key)
    }
}
