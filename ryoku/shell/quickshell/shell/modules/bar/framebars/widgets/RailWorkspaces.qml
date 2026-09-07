pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../../../components"
import shell.services

// Pill workspaces: each non-special workspace across all monitors is a rounded
// pill showing up to 3 tiny app icons resolved via DesktopEntries (same method
// as RailDock). Active workspace pill is expanded and primary-tinted; inactive
// occupied pills are compact and dimmed; empty workspaces are a small dot.
// Click switches workspace, vertical wheel cycles. Monitor dividers are dropped
// in favour of letting the pill sizes carry the visual weight.
// Caelestia-inspired approach, Ryoku design vocabulary.
// Contract 03 sec 2.3/2.4/4.3/4.4.
Item {
    id: root

    required property string edge
    required property real scale

    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property real cross: 48 * scale

    // Tiny icon size for workspace previews -- non-interactive, informational.
    readonly property real iconPx: 10 * scale
    readonly property int maxIcons: 3

    // Non-special workspaces sorted by (monitor name, id). Fork-safe fallback
    // identical to the original RailWorkspaces.
    readonly property var entries: {
        const list = Hyprland.workspaces ? Hyprland.workspaces.values : [];
        const out = [];
        const seen = {};
        for (let i = 0; i < list.length; ++i) {
            const w = list[i];
            if (!w)
                continue;
            const o = w.lastIpcObject || ({});
            const id = (typeof w.id === "number" && w.id !== 0) ? w.id
                : (typeof o.id === "number" ? o.id : 0);
            if (id <= 0)
                continue;
            const name = (typeof w.name === "string" && w.name.length) ? w.name
                : (o.name || "");
            if (name.indexOf("special") === 0)
                continue;
            if (seen[id])
                continue;
            seen[id] = true;
            const mon = w.monitor;
            const monName = (mon && mon.name) ? mon.name : (o.monitor || "");
            const monId = (mon && typeof mon.id === "number") ? mon.id
                : (typeof o.monitorID === "number" ? o.monitorID : 0);
            out.push({ id: id, monName: monName, monId: monId });
        }
        if (out.length === 0 && Workspaces.activeId > 0)
            out.push({ id: Workspaces.activeId, monName: "", monId: 0 });
        out.sort((a, b) => a.monName < b.monName ? -1 :
            (a.monName > b.monName ? 1 : a.id - b.id));
        return out;
    }

    // Active set is per-monitor (multiple active at once), fork-safe.
    readonly property var activeIds: {
        const s = {};
        const mons = Hyprland.monitors ? Hyprland.monitors.values : [];
        for (let i = 0; i < mons.length; ++i) {
            const m = mons[i];
            if (!m)
                continue;
            const aw = m.activeWorkspace;
            if (aw && typeof aw.id === "number") {
                s[aw.id] = true;
            } else {
                const mo = m.lastIpcObject;
                if (mo && mo.activeWorkspace && typeof mo.activeWorkspace.id === "number")
                    s[mo.activeWorkspace.id] = true;
            }
        }
        if (Workspaces.activeId > 0)
            s[Workspaces.activeId] = true;
        return s;
    }

    // Icon path resolution: same two-step lookup as RailDock.
    function iconFor(className) {
        const desktop = DesktopEntries.heuristicLookup(className);
        const byEntry = (desktop && desktop.icon) ?
            Icons.path(desktop.icon, true) : "";
        return byEntry !== "" ? byEntry :
            Icons.path(className.toLowerCase(), true);
    }

    function focusWorkspace(id) {
        Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })');
    }

    implicitWidth: horizontal ? strip.implicitWidth : Math.max(cross, strip.implicitWidth)
    implicitHeight: horizontal ? Math.max(cross, strip.implicitHeight) : strip.implicitHeight

    Loader {
        id: strip
        anchors.centerIn: parent
        sourceComponent: root.horizontal ? rowComp : colComp
    }

    Component {
        id: rowComp
        Row {
            spacing: 4 * root.scale
            Repeater {
                model: root.entries
                delegate: pillComp
            }
        }
    }
    Component {
        id: colComp
        Column {
            spacing: 4 * root.scale
            Repeater {
                model: root.entries
                delegate: pillComp
            }
        }
    }

    // Each workspace pill. With ComponentBehavior: Bound, outer-scope IDs
    // (root, Theme, Motion) are accessible; modelData must be required.
    Component {
        id: pillComp
        Item {
            id: pill

            required property var modelData

            readonly property int wsId: modelData.id
            readonly property bool isActive: root.activeIds[wsId] === true

            // Re-evaluates when Hyprland.toplevels changes -- exactly on
            // open/close/move events, never per-frame. Up to maxIcons unique
            // class names ordered by pid.
            readonly property var classes: {
                const tls = Hyprland.toplevels ? Hyprland.toplevels.values : [];
                const out = [];
                const seen = {};
                for (let i = 0; i < tls.length; ++i) {
                    if (out.length >= root.maxIcons)
                        break;
                    const t = tls[i];
                    if (!t)
                        continue;
                    const o = t.lastIpcObject || {};
                    const wsIdT = (o.workspace && typeof o.workspace.id === "number")
                        ? o.workspace.id : -1;
                    if (wsIdT !== pill.wsId)
                        continue;
                    const cls = o.class || o.initialClass || "";
                    if (!cls || seen[cls])
                        continue;
                    seen[cls] = true;
                    out.push(cls);
                }
                return out;
            }

            readonly property bool hasIcons: classes.length > 0

            // Pill geometry. For vertical bars, the pill sits across the rail
            // (full 36px width); its height expands when active. For horizontal
            // bars, the pill sits along the rail; its width expands.
            readonly property real gap: 2 * root.scale
            readonly property real padV: 6 * root.scale   // vertical padding (top+bottom)
            readonly property real padH: 5 * root.scale   // horizontal padding (left+right)
            readonly property real dotSize: 6 * root.scale
            readonly property real iconRowWidth: classes.length * root.iconPx
                + Math.max(0, classes.length - 1) * gap
            readonly property real iconColHeight: classes.length * root.iconPx
                + Math.max(0, classes.length - 1) * gap

            // Extent = the along-bar dimension. Every occupied pill sizes to its
            // own app icons, so the active pill matches an inactive one with the
            // same apps and is set apart by its highlight, not by a fixed
            // reserved width that left it a wide near-empty oval beside the
            // compact inactive pills.
            readonly property real occupiedExtent: root.horizontal
                ? (iconRowWidth + 2 * padH)
                : (iconColHeight + 2 * padV)
            readonly property real emptyExtent: dotSize + 2 * (root.horizontal ? padH : padV)
            readonly property real extent: !hasIcons ? emptyExtent : occupiedExtent

            // Cross = the dimension fixed to the rail width.
            readonly property real pillCross: 32 * root.scale

            width: root.horizontal ? extent : pillCross
            height: root.horizontal ? pillCross : extent

            Behavior on width {
                enabled: !Motion.reduce
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Motion.easeStandard
                }
            }
            Behavior on height {
                enabled: !Motion.reduce
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Motion.easeStandard
                }
            }

            // Background: primary-tinted for active, subtle for inactive occupied,
            // transparent for empty (the dot carries the visual weight).
            Rectangle {
                anchors.fill: parent
                radius: Math.min(parent.width, parent.height) / 2
                color: pill.hasIcons
                    ? (pill.isActive
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)
                        : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.07))
                    : "transparent"

                Behavior on color {
                    enabled: !Motion.reduce
                    ColorAnimation { duration: Motion.fast }
                }
            }

            // Empty workspace: a small dot. Active empty gets the primary colour.
            Rectangle {
                visible: !pill.hasIcons
                anchors.centerIn: parent
                width: pill.dotSize
                height: pill.dotSize
                radius: width / 2
                color: pill.isActive ? Theme.primary
                    : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.28)

                Behavior on color {
                    enabled: !Motion.reduce
                    ColorAnimation { duration: Motion.fast }
                }
            }

            // Active indicator: a small primary line along the bar edge.
            Rectangle {
                visible: pill.isActive && pill.hasIcons
                width: root.horizontal
                    ? Math.min(pill.width * 0.5, 16 * root.scale)
                    : 2 * root.scale
                height: root.horizontal
                    ? 2 * root.scale
                    : Math.min(pill.height * 0.5, 16 * root.scale)
                radius: Math.min(width, height) / 2
                color: Theme.primary
                // Placed on the outer edge of the bar.
                anchors.horizontalCenter: root.horizontal ? parent.horizontalCenter : undefined
                anchors.verticalCenter: !root.horizontal ? parent.verticalCenter : undefined
                anchors.bottom: root.edge === "bottom" ? parent.bottom : undefined
                anchors.bottomMargin: root.edge === "bottom" ? 3 * root.scale : 0
                anchors.right: root.edge === "right" ? parent.right : undefined
                anchors.rightMargin: root.edge === "right" ? 3 * root.scale : 0
                anchors.left: root.edge === "left" ? parent.left : undefined
                anchors.leftMargin: root.edge === "left" ? 3 * root.scale : 0
                anchors.top: root.edge === "top" ? parent.top : undefined
                anchors.topMargin: root.edge === "top" ? 3 * root.scale : 0
            }

            // App icon row/column. Icons re-resolve only when classes changes.
            Loader {
                anchors.centerIn: parent
                active: pill.hasIcons
                sourceComponent: root.horizontal ? iconsRowComp : iconsColComp
            }

            // For horizontal bars: icons in a horizontal row inside the pill.
            Component {
                id: iconsRowComp
                Row {
                    spacing: pill.gap
                    opacity: pill.isActive ? 1.0 : 0.5
                    Behavior on opacity {
                        enabled: !Motion.reduce
                        NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
                    }
                    Repeater {
                        model: pill.classes
                        delegate: wsIconComp
                    }
                }
            }

            // For vertical bars: icons in a vertical column inside the pill.
            Component {
                id: iconsColComp
                Column {
                    spacing: pill.gap
                    opacity: pill.isActive ? 1.0 : 0.5
                    Behavior on opacity {
                        enabled: !Motion.reduce
                        NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
                    }
                    Repeater {
                        model: pill.classes
                        delegate: wsIconComp
                    }
                }
            }

            // Each app icon. Falls back to the app-grid glyph if the icon
            // path cannot be resolved (same pattern as RailDock).
            Component {
                id: wsIconComp
                Item {
                    id: wsIconItem
                    required property string modelData
                    width: root.iconPx
                    height: root.iconPx

                    Image {
                        id: wsIcon
                        anchors.fill: parent
                        source: root.iconFor(wsIconItem.modelData)
                        sourceSize.width: root.iconPx
                        sourceSize.height: root.iconPx
                        smooth: true
                        asynchronous: true
                        visible: source !== "" && status === Image.Ready
                    }
                    SymbolIcon {
                        anchors.fill: parent
                        visible: !wsIcon.visible
                        name: "view-app-grid"
                        size: root.iconPx
                        color: Theme.onSurface
                    }
                }
            }

            // Click to focus this workspace.
            HoverHandler { id: hover }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWorkspace(pill.wsId)
            }
        }
    }

    // Hover-gated vertical wheel: up -> r-1, down -> r+1.
    WheelHandler {
        onWheel: event => root.focusWorkspace(event.angleDelta.y > 0 ? "r-1" : "r+1")
    }
}
