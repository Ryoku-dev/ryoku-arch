import QtQuick
import "../kit"
import "../kit/Widgets.js" as Widgets
import "../../modules"
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Widgets route (部品): the shipped widgets (every built-in and Ryoku's own
// plugins) as one CcWidgetList sheet: show, size, colour and tune each. The
// launcher's mark and the workspaces' count/marker (the old Logo and Spaces
// routes) are just those two widgets' settings now, and the workspaces row keeps
// its live marker preview. Community plugins have their own route. A `select`
// arg (Layout's SETTINGS link) opens the panel on a chosen widget.
Item {
    id: page
    property var root: null
    property var cc: null
    readonly property var tk: page.cc ? page.cc.tokens : null
    readonly property real colW: page.width
    implicitHeight: contentCol.implicitHeight

    property alias selId: wlist.selId   // the expanded widget row
    property string colorGid: ""   // the widget whose colour popover is open
    property string colorLabel: ""

    // Per-widget colour is gated on widgetHasFill so the page stays error-free if
    // the live Theme (or the offscreen probe) does not expose the helpers.
    readonly property bool colorSupported: !!(page.root && page.root.widgetHasFill)

    // The shipped set: every built-in and Ryoku's own plugins. A plugin from
    // outside Ryoku lives on the Community route instead.
    readonly property var ownEntries: {
        var c = (page.root && page.root.barCatalog) ? page.root.barCatalog : []
        var out = []
        for (var i = 0; i < c.length; i++) if (c[i].official === true) out.push(c[i])
        return out
    }

    // Layout's SETTINGS link lands here on a chosen widget: read the pending arg
    // once, then clear it so a later plain open does not re-expand it.
    function consumeArg() {
        if (page.cc && page.cc.routeArg !== null && page.cc.routeArg !== undefined) {
            page.selId = String(page.cc.routeArg)
            page.cc.routeArg = null
        }
    }
    Component.onCompleted: page.consumeArg()
    Connections {
        target: page.cc
        ignoreUnknownSignals: true
        function onRouteArgChanged() { page.consumeArg() }
    }

    // what is still below the plate's edge; the stage reads it for the fade.
    readonly property real scrollRemaining: Math.max(0, flick.contentHeight - flick.height - flick.contentY)

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        // a page that overflows gets a tail, so its last row can scroll clear
        // of the bottom fade instead of living inside it.
        contentHeight: contentCol.implicitHeight + (contentCol.implicitHeight > height && page.tk ? page.tk.tailPad : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: contentCol
            width: page.colW
            spacing: page.tk ? page.tk.sectionGap : 24

            Entrance {
                width: page.colW
                index: 0
                CcWidgetList {
                    id: wlist
                    width: page.colW
                    title: I18n.tr("WIDGETS")
                    kana: "\u90e8\u54c1"
                    root: page.root
                    tk: page.tk
                    entries: page.ownEntries
                    colorGid: page.colorGid
                    onColorRequested: (gid, label) => {
                        if (page.colorGid === gid) { page.colorGid = ""; page.colorLabel = "" }
                        else { page.colorGid = gid; page.colorLabel = label }
                    }
                }
            }
        }
    }

    CcScrollRail { root: page.root; tk: page.tk; flick: flick; z: 5 }

    // ── per-widget colour popover, floated above the body ──
    Component {
        id: colorPopComp
        CcWidgetColorPopover {
            root: page.root
            tk: page.tk
            gid: page.colorGid
            label: page.colorLabel
            onDismissed: { page.colorGid = ""; page.colorLabel = "" }
        }
    }
    Loader {
        anchors.fill: parent
        z: 60
        active: page.colorSupported && page.colorGid !== ""
        sourceComponent: colorPopComp
    }
}
