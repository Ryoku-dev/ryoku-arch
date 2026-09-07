pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// The dock's window-preview strip. Hovering a dock icon that has open windows
// grows this off the rail edge, welded to the icon, with one LIVE tile per
// window (a ScreencopyView of that toplevel). Click a tile to focus its window,
// the corner X to close it. It is purely a hover popout: it rides the shared
// Popout blob's own hover model (triggerHovered + the body-hover close grace),
// driven by the DockPreview singleton the dock writes, so it never enters the
// menu state -- one instance per monitor, hosted by FrameMenuManager, whose
// mask union makes the tiles clickable over the desktop hole.
Popout {
    id: root

    // ---- layout ------------------------------------------------------------
    readonly property real pad: 12 * root.s
    readonly property real tileW: 184 * root.s
    readonly property real previewH: 112 * root.s
    readonly property real titleH: 15 * root.s
    readonly property real headerH: 18 * root.s
    readonly property real tileGap: 8 * root.s
    readonly property real tileH: previewH + 4 * root.s + titleH

    // ---- model: the hovered class's mapped windows -------------------------
    // `cls` is the LIVE hovered class (it drives open/close); `shownClass`
    // latches the last non-empty one so the strip's content and size survive
    // the close grace. Without it, leaving the icon empties the window list and
    // collapses the body -- and its input mask -- out from under a pointer on
    // its way onto the strip, so the popout shuts the instant you reach for it.
    readonly property string cls: DockPreview.hoveredClass
    property string shownClass: ""
    onClsChanged: if (root.cls !== "") root.shownClass = root.cls;
    // Every open window of the hovered class, across all workspaces. We do NOT
    // filter on the surface `mapped` flag: a window on a hidden workspace reports
    // unmapped (no live capture) yet is a real window you want to reach -- it just
    // falls back to the app icon tile and a focus-by-address click.
    readonly property var windows: {
        if (root.shownClass === "")
            return [];
        const out = [];
        const tls = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (let i = 0; i < tls.length; ++i) {
            const o = tls[i] && tls[i].lastIpcObject;
            const c = o && (o.class || o.initialClass);
            if (c === root.shownClass)
                out.push(tls[i]);
        }
        return out;
    }
    readonly property int n: root.windows.length

    // desktop-entry app label + icon for the header / capture fallback.
    readonly property var entry: root.shownClass !== "" ? DesktopEntries.heuristicLookup(root.shownClass) : null
    readonly property string appLabel: (root.entry && root.entry.name) ? root.entry.name : root.shownClass
    readonly property string appIcon: (root.entry && root.entry.icon) ? Icons.path(root.entry.icon, true) : ""

    // ---- shared Popout wiring (hover-driven, welded to the rail edge) -------
    edge: DockPreview.edge
    hoverOpen: false                 // no frame-edge band; the dock icon is the trigger
    closeDelay: 300                  // grace to cross from the icon onto the strip
    edgeGap: DockPreview.margin > 0 ? DockPreview.margin : 10 * root.s
    radius: Theme.radiusWindow
    triggerHovered: root.cls !== ""
    alongCenter: {
        // Hold the last icon's centre through the brief cls-empty tick on
        // icon-exit (so a switch between icons slides rather than snapping to a
        // sentinel); only the truly uninitialised state is -1.
        if (DockPreview.gx < 0)
            return -1;
        const p = root.mapFromGlobal(DockPreview.gx, DockPreview.gy);
        return (root.edge === "left" || root.edge === "right") ? p.y : p.x;
    }
    // Glide along the rail when switching between dock icons, but only while the
    // strip is already open -- a fresh open still appears directly at its icon
    // instead of flying in from the last one's position.
    Behavior on alongCenter {
        enabled: root.heldOpen
        NumberAnimation { duration: Motion.menuSlide; easing.type: Motion.menuSlideCurve }
    }
    openW: root.n > 0 ? (root.pad * 2 + root.n * root.tileW + (root.n - 1) * root.tileGap) : 0
    openH: root.n > 0 ? (root.pad * 2 + root.headerH + 6 * root.s + root.tileH) : 0

    PopoutCard { anchors.fill: parent }

    Column {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 6 * root.s

        // header: app name + window count
        Item {
            width: parent.width
            height: root.headerH
            Text {
                id: nameLbl
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: Math.max(0, parent.width - countLbl.width - 8 * root.s)
                text: root.appLabel
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: 12 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                id: countLbl
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: root.n === 1 ? I18n.tr("1 window") : I18n.tr("%1 windows").arg(root.n)
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: 10 * root.s
            }
        }

        // one live tile per window
        Row {
            spacing: root.tileGap
            Repeater {
                model: root.windows
                delegate: Item {
                    id: tile
                    required property var modelData
                    readonly property var tl: tile.modelData
                    readonly property bool hasCapture: !!(tile.tl && tile.tl.wayland)
                    width: root.tileW
                    height: root.tileH

                    Rectangle {
                        id: frame
                        width: root.tileW
                        height: root.previewH
                        radius: 6 * root.s
                        color: Theme.surfaceContainer
                        border.width: Theme.borderWidth
                        border.color: previewHov.hovered ? Theme.primary : Theme.outline
                        clip: true

                        ScreencopyView {
                            anchors.fill: parent
                            anchors.margins: Theme.borderWidth
                            captureSource: tile.hasCapture ? tile.tl.wayland : null // qmllint disable unresolved-type
                            live: root.prog > 0.004
                            visible: tile.hasCapture
                        }
                        Image {
                            anchors.centerIn: parent
                            width: 40 * root.s
                            height: 40 * root.s
                            visible: !tile.hasCapture && root.appIcon !== ""
                            source: root.appIcon
                            sourceSize.width: width
                            sourceSize.height: height
                            smooth: true
                            asynchronous: true
                        }

                        HoverHandler { id: previewHov; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            // Focus the specific window by address so a tile for a
                            // window on another workspace switches to it; a live
                            // capture can also self-activate, but address focus is
                            // the reliable path for an unmapped (hidden) window.
                            onClicked: {
                                const o = tile.tl ? tile.tl.lastIpcObject : null;
                                if (o && o.address)
                                    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + o.address + '" })');
                                else if (tile.hasCapture)
                                    tile.tl.wayland.activate();
                            }
                        }

                        // close (X), revealed on hover of the tile
                        Rectangle {
                            anchors { top: parent.top; right: parent.right; margins: 5 * root.s }
                            width: 18 * root.s
                            height: 18 * root.s
                            radius: width / 2
                            visible: previewHov.hovered || closeHov.hovered
                            color: closeHov.hovered ? Theme.error : Qt.rgba(0, 0, 0, 0.5)
                            GlyphIcon {
                                anchors.centerIn: parent
                                width: 11 * root.s
                                height: width
                                name: "close"
                                stroke: 2
                                color: "white"
                            }
                            HoverHandler { id: closeHov; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                // Terminate the process, not a polite request.
                                // wayland.close() only ASKS, so an Electron app
                                // declines it and the X looked dead; it was also
                                // gated on a thumbnail existing, so a tile with
                                // no capture did nothing at all.
                                onClicked: {
                                    const o = tile.tl ? tile.tl.lastIpcObject : null;
                                    const pid = o && o.pid ? Number(o.pid) : 0;
                                    if (pid > 0)
                                        Quickshell.execDetached(["kill", "-9", String(pid)]);
                                    else if (tile.hasCapture)
                                        tile.tl.wayland.close();
                                }
                            }
                        }
                    }

                    Text {
                        anchors { top: frame.bottom; topMargin: 4 * root.s; horizontalCenter: frame.horizontalCenter }
                        width: root.tileW
                        text: {
                            const o = tile.tl && tile.tl.lastIpcObject;
                            return (o && o.title) ? o.title : root.appLabel;
                        }
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: 10 * root.s
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
