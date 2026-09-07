pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../kit"
import "../../modules"
import Ryoku.Ui
import Ryoku.Ui.Singletons
import shell.services as Services

// Dock route (台). The first-class app dock that lives on the edge opposite the
// bar. Restyled to the same section grammar as the Bar route: it opens with a
// live dock silhouette, then numbered sections carry the surface, behaviour and
// look knobs, and the pinned apps sit as chips you remove or add to. Every knob
// and the pin list read and write through the services Dock singleton's `dock`
// store (shell.json top-level `dock`), so persistence is the same path the dock
// surface and Bar Studio use. Reorder is the dock's own job (drag).
Item {
    id: page
    property var root
    property var cc
    readonly property var tk: cc.tokens
    readonly property real colW: Math.min(page.width, tk.contentW)
    implicitHeight: col.implicitHeight

    property bool pickerOpen: false

    function removePin(cls) {
        const cur = Services.Dock.pinnedOrStarter();
        const next = [];
        for (let i = 0; i < cur.length; i++)
            if (cur[i] !== cls)
                next.push(cur[i]);
        Services.Dock.setPinned(next);
    }
    function addPin(cls) {
        const cur = Services.Dock.pinnedOrStarter();
        if (cur.indexOf(cls) < 0)
            Services.Dock.setPinned(cur.concat(cls));
    }
    // The installed apps not already pinned, as AppPicker's [{name,cmd}] where the
    // command is the desktop id we pin by.
    function appList() {
        const src = (DesktopEntries.applications) ? DesktopEntries.applications.values : [];
        const pinned = Services.Dock.pinnedOrStarter();
        const out = [];
        for (let i = 0; i < src.length; i++) {
            const e = src[i];
            if (!e || e.noDisplay) continue;
            const cls = e.id ? String(e.id) : String(e.name || "");
            if (cls === "" || pinned.indexOf(cls) >= 0) continue;
            out.push({ name: e.name || cls, cmd: cls });
        }
        out.sort((a, b) => String(a.name).toLowerCase().localeCompare(String(b.name).toLowerCase()));
        return out;
    }

    // Presentable captions for the Style chips: Chips render the option string,
    // so the caption lives in `options` and maps back to the stored key here.
    function styleCap(key) {
        const opts = Services.Dock.styleOptions;
        for (let i = 0; i < opts.length; i++)
            if (opts[i].key === key)
                return opts[i].label;
        return "";
    }
    function styleKey(label) {
        const opts = Services.Dock.styleOptions;
        for (let i = 0; i < opts.length; i++)
            if (opts[i].label === label)
                return opts[i].key;
        return label;
    }

    // one pinned class as a chip: its icon, its name, and a remove mark.
    component PinChip: Rectangle {
        id: pc
        property string cls: ""
        readonly property string iconSrc: Services.Dock.iconFor(pc.cls)
        readonly property string appName: {
            const e = DesktopEntries.heuristicLookup(pc.cls);
            return (e && e.name) ? e.name : pc.cls;
        }
        implicitWidth: pcRow.implicitWidth + page.tk.gap * 1.5
        width: implicitWidth
        height: Tokens.ctlH + page.tk.gap / 2
        radius: Tokens.radius
        color: pcMa.containsMouse ? Tokens.tint10 : Tokens.tint5
        border.width: Tokens.border
        border.color: pcMa.containsMouse ? Tokens.lineStrong : Tokens.line
        Behavior on color { ColorAnimation { duration: Tokens.snap } }

        Row {
            id: pcRow
            anchors.centerIn: parent
            spacing: page.tk.gap / 2
            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Tokens.fRow
                height: Tokens.fRow
                source: pc.iconSrc
                visible: pc.iconSrc !== ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }
            UiText {
                anchors.verticalCenter: parent.verticalCenter
                text: pc.appName
                color: Tokens.inkDim
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
            }
            IconText {
                anchors.verticalCenter: parent.verticalCenter
                text: "close"
                color: pcMa.containsMouse ? Tokens.ink : Tokens.inkFaint
                font.pixelSize: Tokens.fSmall
            }
        }
        MouseArea {
            id: pcMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.removePin(pc.cls)
        }
    }

    // A live schematic of the screen with the dock on it: the panel plate covers
    // the real dock, so without this a click on an edge chip changes something you
    // cannot see. It draws the resolved edge, the icon run, and the picked style.
    component DockPreview: Rectangle {
        id: dp
        readonly property string edge: {
            const e = String(Services.Dock.cfg("edge", "auto"));
            if (e !== "auto")
                return e;
            return page.root && page.root.barPosition === "bottom" ? "top" : "bottom";
        }
        readonly property bool vertical: dp.edge === "left" || dp.edge === "right"
        readonly property bool live: Services.Dock.cfg("enabled", false)
        readonly property int pins: Math.max(3, Math.min(6, Services.Dock.pinnedOrStarter().length))
        readonly property string style: Services.Dock.cfg("style", "islands")

        height: Tokens.px(96)
        radius: Tokens.radius
        color: Tokens.paperLift
        border.width: 1
        border.color: Tokens.line

        // the bar, so the "opposite the bar" rule is visible rather than asserted
        Rectangle {
            width: parent.width - Tokens.s4 * 2
            height: 4
            radius: 2
            color: Tokens.inkFaint
            opacity: 0.5
            x: Tokens.s4
            y: page.root && page.root.barPosition === "bottom" ? parent.height - Tokens.s3 - height : Tokens.s3
        }

        // the dock itself, drawn in the picked style so a Style change shows in
        // the diagram, not only on the real dock hidden behind this panel.
        Item {
            id: island
            readonly property int marks: dp.pins
            readonly property int cell: Tokens.s4
            readonly property int run: island.marks * island.cell + Tokens.s2
            // tanzaku strips hang from the screen edge: flush, and a step deeper.
            readonly property bool strips: dp.style === "tanzaku"
            readonly property int depth: island.strips ? Tokens.s6 : Tokens.s5
            readonly property int inset: island.strips ? 0 : Tokens.s2
            // rail, ledger and seal share one plate; islands and tanzaku give
            // each mark its own.
            readonly property bool onePlate: dp.style === "rail" || dp.style === "ledger" || dp.style === "seal"

            width: dp.vertical ? island.depth : island.run
            height: dp.vertical ? island.run : island.depth
            opacity: dp.live ? 1 : 0.35
            Behavior on opacity { NumberAnimation { duration: Tokens.snap } }

            x: dp.edge === "left" ? island.inset
                : dp.edge === "right" ? dp.width - width - island.inset
                : Math.round((dp.width - width) / 2)
            y: dp.edge === "top" ? island.inset
                : dp.edge === "bottom" ? dp.height - height - island.inset
                : Math.round((dp.height - height) / 2)
            Behavior on x { NumberAnimation { duration: Tokens.move; easing.bezierCurve: Tokens.curveEmphasized; easing.type: Easing.Bezier } }
            Behavior on y { NumberAnimation { duration: Tokens.move; easing.bezierCurve: Tokens.curveEmphasized; easing.type: Easing.Bezier } }

            Rectangle {
                anchors.fill: parent
                visible: island.onePlate
                radius: dp.style === "seal" ? 0 : Tokens.radius
                color: Tokens.tint10
                border.width: Tokens.border
                border.color: dp.live ? Tokens.line : Tokens.lineSoft
            }

            Grid {
                anchors.centerIn: parent
                columns: dp.vertical ? 1 : island.marks
                Repeater {
                    model: island.marks
                    delegate: Item {
                        id: slot
                        required property int index
                        readonly property bool lastCell: slot.index === island.marks - 1
                        width: dp.vertical ? island.depth : island.cell
                        height: dp.vertical ? island.cell : island.depth

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Tokens.px(2)
                            visible: island.strips
                            radius: Tokens.radius
                            color: Tokens.tint10
                            border.width: Tokens.border
                            border.color: dp.live ? Tokens.line : Tokens.lineSoft
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            visible: dp.style === "islands"
                            width: Tokens.s3
                            height: Tokens.s3
                            radius: Tokens.radius
                            color: Tokens.tint10
                            border.width: Tokens.border
                            border.color: dp.live ? Tokens.line : Tokens.lineSoft
                        }
                        Rectangle {
                            visible: dp.style === "ledger" && !slot.lastCell
                            color: dp.live ? Tokens.line : Tokens.lineSoft
                            width: dp.vertical ? parent.width : Tokens.border
                            height: dp.vertical ? Tokens.border : parent.height
                            x: dp.vertical ? 0 : parent.width - width
                            y: dp.vertical ? parent.height - height : 0
                        }
                        // seal fills only the running apps; the rest stay hollow
                        // silhouettes, so colour alone reads as running.
                        Rectangle {
                            anchors.centerIn: parent
                            width: Tokens.s2
                            height: Tokens.s2
                            radius: dp.style === "seal" ? 0 : Tokens.px(2)
                            color: dp.style !== "seal" || slot.index % 2 === 0 ? Tokens.inkMuted : "transparent"
                            border.width: dp.style === "seal" && slot.index % 2 !== 0 ? Tokens.border : 0
                            border.color: Tokens.inkMuted
                        }
                    }
                }
            }
        }
    }

    // what is still below the plate's edge; the stage reads it for the fade.
    readonly property real scrollRemaining: Math.max(0, flick.contentHeight - flick.height - flick.contentY)

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        // a page that overflows gets a tail, so its last row can scroll clear
        // of the bottom fade instead of living inside it.
        contentHeight: col.implicitHeight + (col.implicitHeight > height && page.tk ? page.tk.tailPad : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: page.colW
            spacing: page.tk.sectionGap

            // the preview rides above the sections, like the bar's silhouette does
            // on the Bar route: one glance answers "where will it be".
            DockPreview { width: page.colW }

            // ── 01 DOCK ──
            Entrance {
                width: page.colW
                index: 0
                SettingCard {
                    width: page.colW
                    title: I18n.tr("01 DOCK")
                    kana: "\u53f0"

                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        controlWidth: 54
                        label: I18n.tr("Dock")
                        desc: I18n.tr("Its own surface, any bar style")
                        source: "shell.json"
                        Sw {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: Services.Dock.cfg("enabled", false)
                            onToggled: (v) => Services.Dock.setCfg("enabled", v)
                        }
                    }
                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        divider: true
                        block: true
                        label: I18n.tr("Edge")
                        desc: I18n.tr("Auto: opposite the bar")
                        source: "shell.json"
                        enabled: Services.Dock.cfg("enabled", false)
                        Seg {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            options: ["auto", "top", "bottom", "left", "right"]
                            current: Services.Dock.cfg("edge", "auto")
                            onChose: (k) => Services.Dock.setCfg("edge", k)
                        }
                    }
                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        divider: true
                        block: true
                        label: I18n.tr("Style")
                        desc: I18n.tr("How it is drawn")
                        source: "shell.json"
                        enabled: Services.Dock.cfg("enabled", false)
                        Chips {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            options: Services.Dock.styleOptions.map(o => o.label)
                            current: page.styleCap(Services.Dock.cfg("style", "islands"))
                            onChose: (label) => Services.Dock.setCfg("style", page.styleKey(label))
                        }
                    }
                }
            }

            // ── 02 BEHAVIOUR ──
            Entrance {
                width: page.colW
                index: 1
                SettingCard {
                    width: page.colW
                    title: I18n.tr("02 BEHAVIOUR")
                    kana: "\u632f\u821e"

                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        controlWidth: 54
                        label: I18n.tr("Auto-hide")
                        desc: I18n.tr("A peek strip until hovered")
                        source: "shell.json"
                        enabled: Services.Dock.cfg("enabled", false)
                        Sw {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: Services.Dock.cfg("autohide", true)
                            onToggled: (v) => Services.Dock.setCfg("autohide", v)
                        }
                    }
                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        divider: true
                        controlWidth: 54
                        label: I18n.tr("Magnify")
                        desc: I18n.tr("Grow the icon under the pointer")
                        source: "shell.json"
                        enabled: Services.Dock.cfg("enabled", false)
                        Sw {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: Services.Dock.cfg("magnify", true)
                            onToggled: (v) => Services.Dock.setCfg("magnify", v)
                        }
                    }
                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        divider: true
                        controlWidth: 54
                        label: I18n.tr("Media chip")
                        desc: I18n.tr("Only while audio plays")
                        source: "shell.json"
                        enabled: Services.Dock.cfg("enabled", false)
                        Sw {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: Services.Dock.cfg("media", false)
                            onToggled: (v) => Services.Dock.setCfg("media", v)
                        }
                    }
                }
            }

            // ── 03 SURFACE ──
            Entrance {
                width: page.colW
                index: 2
                SettingCard {
                    width: page.colW
                    title: I18n.tr("03 SURFACE")
                    kana: "\u8868\u9762"

                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        controlWidth: 54
                        label: I18n.tr("Frost")
                        source: "shell.json"
                        enabled: Services.Dock.cfg("enabled", false)
                        Sw {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: Services.Dock.cfg("frost", true)
                            onToggled: (v) => Services.Dock.setCfg("frost", v)
                        }
                    }
                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        divider: true
                        controlWidth: 54
                        label: I18n.tr("Depth")
                        desc: I18n.tr("Soft shadow")
                        source: "shell.json"
                        enabled: Services.Dock.cfg("enabled", false)
                        Sw {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: Services.Dock.cfg("shadow", true)
                            onToggled: (v) => Services.Dock.setCfg("shadow", v)
                        }
                    }
                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        divider: true
                        controlWidth: 54
                        label: I18n.tr("Hover labels")
                        source: "shell.json"
                        enabled: Services.Dock.cfg("enabled", false)
                        Sw {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: Services.Dock.cfg("labels", true)
                            onToggled: (v) => Services.Dock.setCfg("labels", v)
                        }
                    }
                }
            }

            // ── 04 PINNED APPS ──
            Entrance {
                width: page.colW
                index: 3
                SettingCard {
                    width: page.colW
                    title: I18n.tr("04 PINNED APPS")
                    kana: "\u56fa\u5b9a"

                    // A fact the title cannot carry: the dock owns the ordering.
                    UiText {
                        width: parent.width
                        leftPadding: page.tk.pad
                        rightPadding: page.tk.pad
                        topPadding: page.tk.gap
                        text: I18n.tr("The dock reorders these by drag.")
                        color: Tokens.inkFaint
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }

                    Flow {
                        width: parent.width - page.tk.pad * 2
                        x: page.tk.pad
                        topPadding: page.tk.gap
                        bottomPadding: page.tk.gap
                        spacing: page.tk.gap / 2

                        Repeater {
                            model: Services.Dock.pinnedOrStarter()
                            delegate: PinChip {
                                required property var modelData
                                cls: modelData
                            }
                        }

                        // the add affordance, in the chip vocabulary.
                        Rectangle {
                            height: Tokens.ctlH + page.tk.gap / 2
                            implicitWidth: addRow.implicitWidth + page.tk.gap * 1.5
                            width: implicitWidth
                            radius: Tokens.radius
                            color: addMa.containsMouse ? Tokens.tint10 : "transparent"
                            border.width: Tokens.border
                            border.color: addMa.containsMouse ? Tokens.lineStrong : Tokens.line
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                            Row {
                                id: addRow
                                anchors.centerIn: parent
                                spacing: page.tk.gap / 2
                                UiText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "+"
                                    color: Tokens.inkDim
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fRow
                                }
                                UiText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("ADD")
                                    color: addMa.containsMouse ? Tokens.ink : Tokens.inkDim
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fTiny
                                    font.letterSpacing: Tokens.trackLabel
                                }
                            }
                            MouseArea {
                                id: addMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.pickerOpen = true
                            }
                        }
                    }
                }
            }
        }
    }

    CcScrollRail { root: page.root; tk: page.tk; flick: flick; z: 5 }

    // ── add-app picker: a filterable desktop-entry list, centred over the body ──
    Item {
        anchors.fill: parent
        visible: opacity > 0.001
        opacity: page.pickerOpen ? 1 : 0
        z: 60
        Behavior on opacity { NumberAnimation { duration: page.tk.fade } }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Tokens.ink.r, Tokens.ink.g, Tokens.ink.b, 0.32)
            MouseArea { anchors.fill: parent; onClicked: page.pickerOpen = false }
        }
        Loader {
            anchors.centerIn: parent
            active: page.pickerOpen
            sourceComponent: AppPicker {
                title: I18n.tr("Pin an app")
                apps: page.appList()
                onPicked: (cmd) => { page.addPin(cmd); page.pickerOpen = false }
                onDismissed: page.pickerOpen = false
                Component.onCompleted: open()
            }
        }
    }
}
