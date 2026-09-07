pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"

// The Stage editor's one inspector (docs/stage.md): a single compact dock at the
// bottom of the live desktop, a fixed height that never wraps at any width. A tab
// row -- Effect, Look, Motion, Add, the selected element's name, and Done -- over
// one content row. Selection drives it: pick an element on the desktop and its
// tab appears with its own actions, so the same control is never shown twice and
// nothing floats across the desktop. One Escape drops the selection, a second (or
// Enter / Done) leaves.
Item {
    id: bar
    anchors.fill: parent
    signal done()

    // [{ id, label, icon, enabled, locked, kind }] for the Add tab and to resolve
    // a selected widget's name/lock; the host owns widget/visualizer mutations.
    property var elements: []
    property bool vizOverlay: false

    signal widgetLockToggle(string id)
    signal widgetSettings(string id)
    signal widgetRemove(string id)
    signal vizFlip()
    signal vizRemove()
    signal addEnable(string id)

    readonly property var sb: StageBackend
    readonly property var ses: StageSession
    readonly property bool parallax: bar.sb.effect === "parallax"

    readonly property string sel: bar.ses.selected
    readonly property string selKind: bar.sel === "" ? ""
        : bar.ses.isLayer(bar.sel) ? "layer"
        : bar.sel === "visualizer" ? "viz" : "widget"
    readonly property int selSlot: bar.ses.layerIndex(bar.sel)
    readonly property var selWidget: {
        const list = bar.elements || [];
        for (var i = 0; i < list.length; i++)
            if (list[i].id === bar.sel) return list[i];
        return null;
    }
    readonly property string selName: {
        if (bar.sel === "") return "";
        if (bar.selKind === "layer") return bar.sb.layerLabel(bar.sb.current, bar.selSlot);
        if (bar.selKind === "viz") return "Visualizer";
        return bar.selWidget ? bar.selWidget.label : bar.sel;
    }

    onVisibleChanged: if (bar.visible) bar.forceActiveFocus()
    Keys.onEscapePressed: e => {
        if (!bar.ses.escapeUnwinds())
            bar.done();
        e.accepted = true;
    }
    Keys.onReturnPressed: e => { bar.done(); e.accepted = true; }

    // A tab button: a pill lit when active; dimmed when disabled-but-shown.
    component Tab: Rectangle {
        id: tb
        property string label: ""
        property bool active: false
        property bool dim: false
        signal act()
        width: tbTxt.implicitWidth + 26
        height: 30
        radius: 15
        color: tb.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
            : tbMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Text {
            id: tbTxt
            anchors.centerIn: parent
            text: tb.label
            color: tb.active ? Theme.inkOn(Theme.primary, Theme.onPrimary)
                : tb.dim ? Theme.onSurfaceVariant : Theme.onSurface
            opacity: tb.dim && !tb.active ? 0.6 : 1
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: tb.active ? Font.DemiBold : Font.Normal
        }
        MouseArea { id: tbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.act() }
    }

    Rectangle {
        id: dock
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        height: 108
        radius: Theme.radiusWidget
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)

        // Absorb clicks on the dock itself so nothing falls through to widgets.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        // ── tab row ───────────────────────────────────────────────────────
        Row {
            id: tabs
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 14
            anchors.topMargin: 8
            spacing: 6
            Tab { label: "Effect"; active: bar.ses.tab === "effect"; onAct: bar.ses.showTab("effect") }
            Tab { label: "Look"; active: bar.ses.tab === "look"; onAct: bar.ses.showTab("look") }
            Tab { label: "Motion"; active: bar.ses.tab === "motion"; dim: !bar.parallax; onAct: bar.ses.showTab("motion") }
            Tab { label: "Add"; active: bar.ses.tab === "add"; onAct: bar.ses.showTab("add") }
            Tab {
                visible: bar.sel !== ""
                label: bar.selName
                active: bar.ses.tab === "element"
                onAct: bar.ses.showTab("element")
            }
        }
        Tab {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 14
            anchors.topMargin: 8
            label: "Done"
            onAct: bar.done()
        }

        // ── content row ─────────────────────────────────────────────────
        Item {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: tabs.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 6
            anchors.bottomMargin: 8

            StageEffectTab { anchors.fill: parent; visible: bar.ses.tab === "effect" }
            StageLookTab { anchors.fill: parent; visible: bar.ses.tab === "look" }
            StageMotionTab { anchors.fill: parent; visible: bar.ses.tab === "motion" }
            StageAddTab {
                anchors.fill: parent
                visible: bar.ses.tab === "add"
                items: bar.elements
                onEnable: id => bar.addEnable(id)
            }
            StageElementTab {
                anchors.fill: parent
                visible: bar.ses.tab === "element" && bar.sel !== ""
                kind: bar.selKind
                slot: bar.selSlot
                parallax: bar.parallax
                isFront: bar.selKind === "layer" ? bar.sb.layerFront(bar.sb.current, bar.selSlot)
                    : bar.selKind === "viz" ? bar.vizOverlay : false
                depth: bar.selKind === "layer" ? bar.sb.layerDepth(bar.sb.current, bar.selSlot) : 0.5
                canRemove: bar.selKind === "layer" ? bar.selSlot > 0 : true
                locked: bar.selWidget ? bar.selWidget.locked === true : false
                onWidgetLock: bar.widgetLockToggle(bar.sel)
                onWidgetSettings: bar.widgetSettings(bar.sel)
                onWidgetRemove: { bar.widgetRemove(bar.sel); bar.ses.deselect(); }
                onVizFlip: bar.vizFlip()
                onVizRemove: { bar.vizRemove(); bar.ses.deselect(); }
            }
        }
    }
}
