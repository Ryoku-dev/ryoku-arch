import QtQuick
import "../modules"
import Quickshell
import Quickshell.Wayland
import shell.services
import Ryoku.Ui.Singletons

// Themed system-tray context menu, rendered from the daemon's dbusmenu tree so
// it matches the bar. The daemon (Tray) is the StatusNotifier host: it streams
// each item's `menu` tree and drives clicks via Tray.menuEvent, so this file is
// only the surface. It keeps qsbar's anchor/state model (Theme.trayMenu* +
// setPanelAnchor + trayMenuVisible) and discloses submenus inline.
PanelWindow {
    id: trayMenu
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-traymenu"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 8

    // Relocate the live item by its stable service key so the card re-renders
    // when the daemon republishes (e.g. aboutToShow fills a lazy submenu).
    readonly property string service: root.trayMenuService
    readonly property var currentItem: {
        var svc = trayMenu.service
        if (!svc) return null
        var its = Tray.items
        for (var i = 0; i < its.length; i++)
            if (its[i] && its[i].service === svc) return its[i]
        return null
    }
    readonly property var menu: currentItem ? currentItem.menu : null

    // id -> true for every disclosed submenu parent (inline expansion).
    property var expanded: ({})

    Connections {
        target: root
        function onTrayMenuVisibleChanged() {
            if (root.trayMenuVisible) {
                trayMenu.expanded = ({})
                Tray.aboutToShow(root.trayMenuService)
            }
        }
    }

    // The app quit or dropped its menu while the card was open.
    onMenuChanged: if (root.trayMenuVisible && !menu) root.trayMenuVisible = false

    function isExpanded(id) { return !!trayMenu.expanded[id] }
    function toggleExpand(id) {
        var e = {}
        for (var k in trayMenu.expanded) e[k] = trayMenu.expanded[k]
        if (e[id]) delete e[id]; else e[id] = true
        trayMenu.expanded = e
    }
    function activate(id) { Tray.menuEvent(trayMenu.service, id); root.trayMenuVisible = false }

    // dbusmenu labels carry '_' accelerators; show the plain text.
    function cleanLabel(s) {
        if (!s) return ""
        return String(s).replace(/_([^_])/g, "$1").replace(/__/g, "_")
    }

    // Flatten the visible tree into rows carrying depth, so a disclosed submenu
    // appears inline beneath its parent.
    function rowsFor(node, depth, out) {
        var kids = (node && node.children) ? node.children : []
        for (var i = 0; i < kids.length; i++) {
            var c = kids[i]
            if (!c || c.visible === false) continue
            var sep = c.type === "separator"
            var hasKids = !sep && Array.isArray(c.children) && c.children.length > 0
            out.push({ node: c, depth: depth, sep: sep, hasKids: hasKids })
            if (hasKids && trayMenu.isExpanded(c.id)) trayMenu.rowsFor(c, depth + 1, out)
        }
        return out
    }
    readonly property var rows: (root.trayMenuVisible && menu) ? rowsFor(menu, 0, []) : []

    property real reveal: root.trayMenuVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: root.trayMenuVisible ? 140 : 100; easing.type: Easing.OutCubic }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.trayMenuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.trayMenuVisible = false }

    Rectangle {
        id: card
        width: 220
        height: col.implicitHeight + 16
        radius: reveal > 0.001 ? root.panelRadius : 0
        color: root.bg
        border.color: root.panelOuterBorderColor
        border.width: root.panelOuterBorderW
        PillShadow { theme: root }

        x: parent ? Math.max(6, Math.min(root.trayMenuX, parent.width - width - 6)) : 6
        y: root.barPosition === "bottom" ? (parent.height - barBottom - gap - height) : (barBottom + gap)
        opacity: trayMenu.reveal
        focus: root.trayMenuVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.trayMenuVisible = false; event.accepted = true }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 8
            spacing: 1

            // App identity stays visible while its menu is open.
            Item {
                width: parent.width
                height: 28

                Image {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.trayMenuIcon !== ""
                    source: root.trayMenuIcon
                    sourceSize.width: 16
                    sourceSize.height: 16
                    width: visible ? 16 : 0
                    height: 16
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                UiText {
                    anchors.left: appIcon.right
                    anchors.leftMargin: appIcon.visible ? 8 : 0
                    anchors.right: closeX.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.trayMenuTitle !== "" ? root.trayMenuTitle : I18n.tr("App Menu")
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                UiText {
                    id: closeX
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2715"
                    color: closeMa.containsMouse ? root.seal : root.sumi
                    font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.trayMenuVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Repeater {
                model: trayMenu.rows

                delegate: Item {
                    id: entry
                    required property var modelData
                    readonly property var node: modelData.node
                    readonly property int depth: modelData.depth
                    readonly property bool sep: modelData.sep
                    readonly property bool hasKids: modelData.hasKids
                    readonly property bool rowEnabled: node.enabled !== false
                    readonly property string toggleType: node.toggleType || ""
                    readonly property bool toggled: (node.toggleState || 0) === 1
                    readonly property string iconName: node.iconName || ""
                    readonly property string label: trayMenu.cleanLabel(node.label)
                    readonly property real indent: 6 + entry.depth * 14

                    width: col.width
                    height: entry.sep ? 7 : 26

                    // separator
                    Rectangle {
                        visible: entry.sep
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: entry.indent
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        height: 1
                        color: root.sep
                    }

                    // entry row
                    Rectangle {
                        visible: !entry.sep
                        anchors.fill: parent
                        radius: root.panelButtonRadius
                        color: (entryMa.containsMouse && entry.rowEnabled) ? root.fillActive : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        // check / radio indicator (mono ✓, matching qsbar's minimal style)
                        UiText {
                            id: check
                            anchors.left: parent.left
                            anchors.leftMargin: entry.indent
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            text: (entry.toggleType.length > 0 && entry.toggled) ? "✓" : ""
                            color: root.seal
                            font.family: root.mono; font.pixelSize: 11
                        }

                        Image {
                            id: entryIcon
                            anchors.left: check.right; anchors.leftMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entry.iconName.length > 0
                            source: entry.iconName.length > 0 ? Icons.path(entry.iconName, "") : ""
                            sourceSize.width: 14; sourceSize.height: 14
                            width: visible ? 14 : 0; height: 14
                            fillMode: Image.PreserveAspectFit; smooth: true
                        }

                        UiText {
                            anchors.left: entryIcon.right; anchors.leftMargin: 6
                            anchors.right: arrow.left; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr(entry.label)
                            color: entry.rowEnabled ? root.ink
                                 : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.35)
                            font.family: root.mono; font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        // submenu chevron (rotates down when disclosed)
                        UiText {
                            id: arrow
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entry.hasKids
                            text: "›"
                            rotation: trayMenu.isExpanded(entry.node.id) ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            color: root.sumiHi
                            font.family: root.mono; font.pixelSize: 13
                        }

                        MouseArea {
                            id: entryMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: entry.rowEnabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (entry.hasKids)
                                    trayMenu.toggleExpand(entry.node.id)
                                else
                                    trayMenu.activate(entry.node.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
