pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import shell.services
import "../../components"
import Ryoku.Ui.Singletons

// In-shell context menu for a system-tray item. Right-clicking a tray icon draws
// the item's own dbusmenu here, rendered and driven by the shell, instead of
// asking the app to raise it. The SNI ContextMenu method hands the app a screen
// point and lets it show its menu, which a Wayland client cannot honour: the menu
// lands wherever the compositor puts it (never under the icon), and an app with no
// ContextMenu answers by raising its main window. The daemon already streams the
// full dbusmenu tree (the item's `menu`) and drives clicks (Tray.menuEvent), so
// this file is purely the surface.
//
// One instance lives inside each bar's tray widget; the widget passes the `edge`
// the bar sits on (the card grows away from it) and the monitor `scale`, then
// calls openFor(item, iconCell) to anchor the card under that icon. The card is a
// screen overlay: an outside press or Escape dismisses it, submenus disclose in
// place, and a leaf activation sends its id and closes.
Item {
    id: root

    property string edge: "top"
    property real scale: 1

    // openFor snapshots these: the service key relocates the live item in
    // Tray.items so the card re-renders when the daemon republishes (e.g. after
    // aboutToShow fills a lazily built submenu), and the anchor geometry pins the
    // card even if the icon strip later shifts.
    property string service: ""
    property real aX: 0
    property real aY: 0
    property real aW: 0
    property real aH: 0
    property real sW: 0
    property real sH: 0

    property bool open: false
    // id -> true for every expanded submenu parent (inline disclosure).
    property var expanded: ({})

    readonly property var currentItem: {
        const its = Tray.items;
        for (let i = 0; i < its.length; ++i)
            if (its[i] && its[i].service === root.service)
                return its[i];
        return null;
    }
    readonly property var menu: root.currentItem ? root.currentItem.menu : null

    // The app quit, or dropped its menu, while the card was open.
    onMenuChanged: if (root.open && !root.menu) root.close();

    readonly property real m: 8 * root.scale         // keep-clear screen margin
    readonly property real gap: 6 * root.scale        // icon-to-card gap

    function openFor(item, iconCell) {
        if (!item || !iconCell || !root.QsWindow || !root.QsWindow.window)
            return;
        const p = root.QsWindow.mapFromItem(iconCell, 0, 0);
        root.aX = p.x;
        root.aY = p.y;
        root.aW = iconCell.width;
        root.aH = iconCell.height;
        root.sW = root.QsWindow.window.width;
        root.sH = root.QsWindow.window.height;
        root.service = item.service;
        root.expanded = ({});
        Tray.aboutToShow(item.service);
        root.open = true;
    }
    function close() { root.open = false; }
    function activate(id) { Tray.menuEvent(root.service, id); root.close(); }
    function isExpanded(id) { return !!root.expanded[id]; }
    function toggleExpand(id) {
        const e = {};
        for (const k in root.expanded)
            e[k] = root.expanded[k];
        if (e[id])
            delete e[id];
        else
            e[id] = true;
        root.expanded = e;
    }

    // dbusmenu labels carry '_' accelerators; show the plain text.
    function cleanLabel(s) {
        if (!s)
            return "";
        return String(s).replace(/_([^_])/g, "$1").replace(/__/g, "_");
    }

    // Flatten the visible tree into rows carrying their depth, so an expanded
    // submenu discloses inline beneath its parent.
    function rowsFor(node, depth, out) {
        const kids = (node && node.children) ? node.children : [];
        for (let i = 0; i < kids.length; ++i) {
            const c = kids[i];
            if (!c || c.visible === false)
                continue;
            const sep = c.type === "separator";
            const hasKids = !sep && Array.isArray(c.children) && c.children.length > 0;
            out.push({ node: c, depth: depth, sep: sep, hasKids: hasKids });
            if (hasKids && root.isExpanded(c.id))
                root.rowsFor(c, depth + 1, out);
        }
        return out;
    }
    readonly property var rows: (root.open && root.menu) ? root.rowsFor(root.menu, 0, []) : []

    function placeX(w) {
        let x;
        if (root.edge === "left")
            x = root.aX + root.aW + root.gap;
        else if (root.edge === "right")
            x = root.aX - w - root.gap;
        else
            x = root.aX + root.aW / 2 - w / 2;
        return Math.max(root.m, Math.min(x, root.sW - w - root.m));
    }
    function placeY(h) {
        let y;
        if (root.edge === "bottom")
            y = root.aY - h - root.gap;
        else if (root.edge === "top")
            y = root.aY + root.aH + root.gap;
        else
            y = root.aY + root.aH / 2 - h / 2;   // left/right rails: centre on the icon
        return Math.max(root.m, Math.min(y, root.sH - h - root.m));
    }

    Loader {
        active: root.open
        sourceComponent: overlayComp
    }

    Component {
        id: overlayComp

        PanelWindow {
            id: menuWin
            color: "transparent"
            screen: (root.QsWindow && root.QsWindow.window) ? root.QsWindow.window.screen : null
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            WlrLayershell.namespace: "ryoku-tray-menu"

            anchors { top: true; bottom: true; left: true; right: true }

            // Outside press dismisses; the card swallows its own presses.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: root.close()
            }

            Rectangle {
                id: card
                readonly property real bw: Theme.borderWidth
                readonly property real minW: 160 * root.scale
                readonly property real maxW: Math.min(360 * root.scale, menuWin.width - 2 * root.m)
                readonly property real maxH: menuWin.height - 2 * root.m
                readonly property real innerW: Math.max(Math.min(bodyCol.implicitWidth, maxW), minW)
                property bool grown: false

                width: innerW + bw * 2
                height: Math.min(bodyCol.implicitHeight + bw * 2, maxH)
                x: root.placeX(width)
                y: root.placeY(height)

                radius: Theme.radiusWindow
                color: Theme.surface
                border.width: Theme.borderWidth
                border.color: Theme.outline
                focus: true
                Keys.onEscapePressed: root.close()
                Component.onCompleted: {
                    card.forceActiveFocus();
                    card.grown = true;
                }

                // Melt open: a quick scale + fade out of the anchored corner.
                opacity: card.grown ? Theme.windowOpacity : 0
                Behavior on opacity {
                    enabled: !Motion.reduce
                    NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
                }
                transform: Scale {
                    origin.x: root.edge === "right" ? card.width : 0
                    origin.y: root.edge === "bottom" ? card.height : 0
                    xScale: card.grown ? 1 : 0.94
                    yScale: card.grown ? 1 : 0.94
                    Behavior on xScale { enabled: !Motion.reduce; NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                    Behavior on yScale { enabled: !Motion.reduce; NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                }

                // Swallow presses on card chrome so they never reach the backdrop.
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

                Flickable {
                    anchors.fill: parent
                    anchors.margins: card.bw
                    contentWidth: width
                    contentHeight: bodyCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    Column {
                        id: bodyCol
                        width: parent.width
                        topPadding: 6 * root.scale
                        bottomPadding: 6 * root.scale

                        Repeater {
                            model: root.rows

                            delegate: Item {
                                id: row
                                required property var modelData
                                readonly property var node: modelData.node
                                readonly property int depth: modelData.depth
                                readonly property bool sep: modelData.sep
                                readonly property bool hasKids: modelData.hasKids
                                readonly property bool rowEnabled: row.node.enabled !== false
                                readonly property string toggleType: row.node.toggleType || ""
                                readonly property bool toggled: (row.node.toggleState || 0) === 1
                                readonly property string iconName: row.node.iconName || ""
                                readonly property bool hasLead: row.toggleType.length > 0 || row.iconName.length > 0
                                readonly property string label: root.cleanLabel(row.node.label)
                                readonly property real indent: (10 + row.depth * 14) * root.scale
                                readonly property real leadW: (Theme.iconSm + 8) * root.scale
                                readonly property real chevW: (Theme.iconSm + 12) * root.scale

                                width: parent.width
                                implicitHeight: row.sep ? 9 * root.scale : 30 * root.scale
                                height: implicitHeight
                                implicitWidth: row.sep ? 0
                                    : row.indent + (row.hasLead ? row.leadW : 0)
                                      + label.implicitWidth + (row.hasKids ? row.chevW : 10 * root.scale)
                                      + 10 * root.scale

                                // separator
                                Rectangle {
                                    visible: row.sep
                                    x: row.indent
                                    width: Math.max(0, row.width - row.indent - 10 * root.scale)
                                    height: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.outlineVariant
                                }

                                // hover wash
                                Rectangle {
                                    visible: !row.sep
                                    anchors.fill: parent
                                    anchors.leftMargin: 4 * root.scale
                                    anchors.rightMargin: 4 * root.scale
                                    anchors.topMargin: 1
                                    anchors.bottomMargin: 1
                                    radius: Theme.radiusWidget
                                    color: (hover.hovered && row.rowEnabled)
                                        ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                                        : "transparent"
                                    Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                                }

                                // toggle indicator (checkmark / radio)
                                MaterialIcon {
                                    visible: !row.sep && row.toggleType.length > 0
                                    anchors.left: parent.left
                                    anchors.leftMargin: row.indent
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.toggleType === "radio"
                                        ? (row.toggled ? I18n.tr("radio_button_checked") : I18n.tr("radio_button_unchecked"))
                                        : (row.toggled ? "check_box" : I18n.tr("check_box_outline_blank"))
                                    fill: row.toggled ? 1 : 0
                                    font.pixelSize: Theme.iconSm * root.scale
                                    color: !row.rowEnabled
                                        ? Qt.rgba(Theme.onSurfaceVariant.r, Theme.onSurfaceVariant.g, Theme.onSurfaceVariant.b, 0.38)
                                        : (row.toggled ? Theme.primary : Theme.onSurfaceVariant)
                                }

                                // item icon (freedesktop icon name)
                                Image {
                                    visible: !row.sep && row.toggleType.length === 0 && row.iconName.length > 0
                                    anchors.left: parent.left
                                    anchors.leftMargin: row.indent
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.iconSm * root.scale
                                    height: Theme.iconSm * root.scale
                                    sourceSize.width: width
                                    sourceSize.height: height
                                    smooth: true
                                    asynchronous: true
                                    source: row.iconName.length > 0 ? Icons.path(row.iconName, "") : ""
                                    opacity: row.rowEnabled ? 1 : 0.38
                                }

                                Text {
                                    id: label
                                    visible: !row.sep
                                    anchors.left: parent.left
                                    anchors.leftMargin: row.indent + (row.hasLead ? row.leadW : 0)
                                    anchors.right: parent.right
                                    anchors.rightMargin: row.hasKids ? row.chevW : 10 * root.scale
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr(row.label)
                                    elide: Text.ElideRight
                                    color: row.rowEnabled ? Theme.onSurface
                                        : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.38)
                                    font.family: Theme.fontPrimary
                                    font.pixelSize: 13 * root.scale
                                }

                                // submenu chevron (rotates when disclosed)
                                MaterialIcon {
                                    visible: !row.sep && row.hasKids
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8 * root.scale
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "chevron_right"
                                    rotation: root.isExpanded(row.node.id) ? 90 : 0
                                    Behavior on rotation { enabled: !Motion.reduce; NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                                    font.pixelSize: Theme.iconSm * root.scale
                                    color: row.rowEnabled ? Theme.onSurfaceVariant
                                        : Qt.rgba(Theme.onSurfaceVariant.r, Theme.onSurfaceVariant.g, Theme.onSurfaceVariant.b, 0.38)
                                }

                                HoverHandler { id: hover; enabled: row.rowEnabled && !row.sep; cursorShape: Qt.PointingHandCursor }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: row.rowEnabled && !row.sep
                                    acceptedButtons: Qt.LeftButton
                                    onClicked: {
                                        if (row.hasKids)
                                            root.toggleExpand(row.node.id);
                                        else
                                            root.activate(row.node.id);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
