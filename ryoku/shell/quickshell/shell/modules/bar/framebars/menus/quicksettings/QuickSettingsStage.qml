pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import shell.services
import Ryoku.Ui.Singletons
import "../../../../../components"
import ".." as Menus
import "../../../../stage"
import "../../../../stage/Singletons" as St

// The Stage tab of the Super+Esc panel (docs/stage.md, "The Stage tab"): every
// Depth and Parallax setting in one scrolling column, ordered by how often it
// is touched, built from the sidebar's own kit so it reads like Home and
// Capture. Everything is live and shows its value; the only second press is for
// what runs the engine (a re-cut, a cut from a picture, a clear).
Item {
    id: root

    property real s: 1
    property bool open: false
    property var navigate: null
    property var closePanel: null

    readonly property var sb: St.StageBackend
    readonly property var cfg: St.Config
    readonly property string effect: root.sb.effect
    readonly property string wall: root.sb.current
    readonly property bool depthOn: root.effect !== "off"
    readonly property bool parallaxOn: root.effect === "parallax"
    readonly property int layerCount: root.sb.layerCountFor(root.wall)

    // A tier chosen but not yet cut with: the segment shows it and the confirm
    // row offers Re-cut (or Download first). Leaving the panel drops it.
    property string pendingTier: ""
    // A picture picked for a new layer, waiting for its Cut.
    property string pickedCut: ""
    property bool clearArmed: false
    property bool pointerOpen: false

    readonly property string shownTier: root.pendingTier !== "" ? root.pendingTier : root.cfg.quality
    readonly property var shownModel: root.sb.modelForQuality(root.shownTier)
    readonly property bool shownInstalled: !!(root.shownModel && root.shownModel.installed === true)

    readonly property color ink: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
    readonly property color inkDim: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
    readonly property color line: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.30)

    onOpenChanged: if (!root.open) root.dropPending()

    function dropPending() {
        root.pendingTier = "";
        root.pickedCut = "";
        root.clearArmed = false;
    }
    function tierLabel(t) { return t === "fine" ? "Fine" : t === "standard" ? "Standard" : "Draft"; }
    // Depth off drops Parallax with it; Parallax on turns Depth on with it.
    function toggleDepth() { root.sb.setEffect(root.depthOn ? "off" : "depth"); }
    function toggleParallax() { root.sb.setEffect(root.parallaxOn ? "depth" : "parallax"); }
    function chooseTier(t) {
        if (t === root.cfg.quality) {
            root.pendingTier = "";
            return;
        }
        root.pendingTier = t;
    }
    function recut() {
        if (root.pendingTier === "")
            return;
        root.cfg.setQuality(root.pendingTier);
        root.pendingTier = "";
        root.sb.refresh();
    }
    function _path(u) {
        const s = "" + u;
        return s.indexOf("file://") === 0 ? decodeURIComponent(s.slice(7)) : s;
    }
    // Presets: one tap sets the whole motion. The row shows a preset only
    // while every knob still matches it; any hand change clears the highlight.
    readonly property var presets: ({
        soft:      { amount: "subtle", idle: "float",   speed: 0.6, music: false },
        cinematic: { amount: "normal", idle: "breathe", speed: 0.4, music: false },
        beat:      { amount: "strong", idle: "sway",    speed: 1.0, music: true }
    })
    readonly property string currentPreset: {
        for (const id in root.presets) {
            const p = root.presets[id];
            if (root.cfg.amount === p.amount && root.cfg.idle === p.idle
                && Math.abs(root.cfg.speed - p.speed) < 0.01 && root.cfg.music === p.music)
                return id;
        }
        return "";
    }
    function applyPreset(id) {
        const p = root.presets[id];
        if (!p) return;
        root.cfg.setAmount(p.amount);
        root.cfg.setIdle(p.idle);
        root.cfg.setSpeed(p.speed);
        root.cfg.setMusic(p.music);
    }
    function resetLook() {
        root.cfg.setEdge(0.15);
        root.cfg.setShadow(0);
        root.cfg.setShadowAngle(90);
        root.cfg.setAmount("normal");
        root.cfg.setIdle("none");
        root.cfg.setMusic(false);
        root.cfg.setMusicLevel(0.6);
        root.cfg.setSpeed(1.0);
        root.cfg.setMouse(true);
        root.cfg.setSensitivity(1.0);
        root.cfg.setRange(1.0);
        root.cfg.setBackdrop(0.0);
    }

    // --- small pieces in the sidebar's language -------------------------------

    // A message with one or two text buttons: the second press for anything
    // that runs the engine. Sits in the column at full width; nothing floats.
    component ConfirmRow: Rectangle {
        id: cr
        property string message: ""
        property string primary: ""
        property string secondary: "Cancel"
        property bool busyLook: false
        signal primaryAct()
        signal secondaryAct()
        width: parent ? parent.width : 0
        implicitHeight: 44
        radius: Theme.radiusWidget
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, cr.busyLook ? 0.10 : 0.16)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: crBtns.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: cr.message
            color: root.ink
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Row {
            id: crBtns
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            TextBtn { visible: cr.secondary !== ""; label: cr.secondary; quiet: true; onAct: cr.secondaryAct() }
            TextBtn { visible: cr.primary !== ""; label: cr.primary; filled: true; onAct: cr.primaryAct() }
        }
    }

    component TextBtn: Rectangle {
        id: tb
        property string label: ""
        property bool filled: false
        property bool quiet: false
        signal act()
        implicitWidth: tbText.implicitWidth + 20
        implicitHeight: 30
        radius: Theme.radiusWidget - 4
        color: tb.filled ? Theme.primary
            : tbTap.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10) : "transparent"
        border.width: tb.filled || tb.quiet ? 0 : 1
        border.color: root.line
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Text {
            id: tbText
            anchors.centerIn: parent
            text: I18n.tr(tb.label)
            color: tb.filled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : tb.quiet ? root.inkDim : root.ink
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: tb.filled ? Font.DemiBold : Font.Medium
        }
        MouseArea {
            id: tbTap
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.act()
        }
    }

    // One switch row: label left, the sidebar's LinkToggle right; the whole
    // row toggles.
    component SwitchRow: Item {
        id: sr
        property string label: ""
        property string sub: ""
        property bool on: false
        signal toggled()
        width: parent ? parent.width : 0
        implicitHeight: sr.sub !== "" ? 44 : 36
        Column {
            anchors.left: parent.left
            anchors.right: srSw.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: I18n.tr(sr.label)
                color: root.ink
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                visible: sr.sub !== ""
                width: parent.width
                text: sr.sub
                color: root.inkDim
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 2
                elide: Text.ElideRight
            }
        }
        LinkToggle {
            id: srSw
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            s: 1.15
            on: sr.on
            onToggled: sr.toggled()
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; z: -1; onClicked: sr.toggled() }
    }

    // A labelled choice: the caption on its own line, the segmented control
    // taking the full width beneath, so four options still breathe at 410 px.
    component ChoiceRow: Column {
        id: chr
        property string label: ""
        property var options: []
        property string current: ""
        signal chose(string id)
        width: parent ? parent.width : 0
        spacing: 5
        Text {
            text: I18n.tr(chr.label)
            color: root.ink
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm
            font.weight: Font.DemiBold
        }
        Menus.QsSeg {
            width: parent.width
            options: chr.options
            current: chr.current
            onChose: id => chr.chose(id)
        }
    }

    // A slider with its name and value on one line above it: the sidebar's
    // fader, without the audio icon, so a look knob does not read as a volume.
    component KnobRow: Item {
        id: kr
        property string label: ""
        property real value: 0
        property string valueLabel: ""
        property real rightInset: 0
        signal moved(real v)
        width: parent ? parent.width : 0
        implicitHeight: 46
        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: I18n.tr(kr.label)
            color: root.ink
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm
            font.weight: Font.DemiBold
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: kr.rightInset
            anchors.top: parent.top
            text: kr.valueLabel
            color: root.inkDim
            font.family: Theme.mono
            font.pixelSize: Theme.fontSm - 2
        }
        HFader {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: kr.rightInset
            anchors.bottom: parent.bottom
            showIcon: false
            lit: root.open
            value: kr.value
            onMoved: v => kr.moved(v)
        }
    }

    component Caption: Text {
        width: parent ? parent.width : 0
        color: root.inkDim
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm - 2
        wrapMode: Text.WordWrap
    }

    component QuietLink: Text {
        id: ql
        property bool danger: false
        signal act()
        color: qlTap.containsMouse ? (ql.danger ? Theme.error : root.ink) : root.inkDim
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm - 1
        font.weight: Font.Medium
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        MouseArea {
            id: qlTap
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ql.act()
        }
    }

    // --- the page ------------------------------------------------------------

    Rectangle { anchors.fill: parent; color: Theme.surface }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: col
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 10

            Text {
                text: I18n.tr("Stage")
                color: root.ink
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontLg
                font.weight: Font.DemiBold
            }

            StagePreviewCard {
                width: parent.width
                wallpaperUrl: root.wall !== "" ? "file://" + root.wall : ""
                subjectUrl: root.sb.layerUrlFor(root.wall, 0)
                busy: root.sb.busy
            }

            // The two switches, side by side like Wi-Fi and Bluetooth on Home.
            Grid {
                id: tiles
                width: parent.width
                columns: 2
                columnSpacing: 8
                readonly property real tileWidth: (width - columnSpacing) / 2
                Menus.QsTile {
                    width: tiles.tileWidth
                    icon: "layers"
                    label: qsTr("Depth")
                    sub: !root.depthOn ? qsTr("Off") : root.sb.busy ? (root.sb.percent + "%") : qsTr("On")
                    on: root.depthOn
                    onToggled: root.toggleDepth()
                }
                Menus.QsTile {
                    width: tiles.tileWidth
                    icon: "animation"
                    label: qsTr("Parallax")
                    sub: root.parallaxOn ? qsTr("On") : qsTr("Off")
                    on: root.parallaxOn
                    onToggled: root.toggleParallax()
                }
            }

            Caption {
                visible: !root.depthOn
                topPadding: 4
                text: qsTr("Turn on Depth to cut the subject out and shape it.")
            }

            // ── Cut quality ────────────────────────────────────────────
            Menus.QsSection { visible: root.depthOn; width: parent.width; label: qsTr("Cut quality") }
            Column {
                visible: root.depthOn
                width: parent.width
                spacing: 8
                Menus.QsSeg {
                    width: parent.width
                    options: [{ id: "draft", label: "Draft" }, { id: "standard", label: "Standard" }, { id: "fine", label: "Fine" }]
                    current: root.shownTier
                    onChose: id => root.chooseTier(id)
                }
                Caption {
                    text: {
                        const m = root.shownModel;
                        if (!m) return "";
                        const st = m.installed === true ? qsTr("installed") : qsTr("not downloaded");
                        return root.tierLabel(root.shownTier) + ": " + (m.size || "") + ", " + st;
                    }
                }
                ConfirmRow {
                    visible: root.sb.busy
                    busyLook: true
                    message: qsTr("Cutting in") + " " + root.tierLabel(root.cfg.quality) + ", " + root.sb.percent + "%"
                    primary: ""
                    secondary: qsTr("Stop")
                    onSecondaryAct: root.sb.cancel()
                }
                ConfirmRow {
                    visible: !root.sb.busy && root.pendingTier !== "" && !root.shownInstalled
                    message: root.sb.installing
                        ? (qsTr("Downloading") + " " + root.tierLabel(root.pendingTier) + "\u2026")
                        : (root.tierLabel(root.pendingTier) + " " + qsTr("needs a") + " " + ((root.shownModel && root.shownModel.size) || "") + " " + qsTr("download"))
                    primary: root.sb.installing ? "" : qsTr("Download")
                    onPrimaryAct: if (root.shownModel) root.sb.install(root.shownModel.id)
                    onSecondaryAct: root.pendingTier = ""
                }
                ConfirmRow {
                    visible: !root.sb.busy && root.pendingTier !== "" && root.shownInstalled
                    message: qsTr("Re-cut in") + " " + root.tierLabel(root.pendingTier)
                    primary: qsTr("Re-cut")
                    onPrimaryAct: root.recut()
                    onSecondaryAct: root.pendingTier = ""
                }
            }

            // ── Layers ─────────────────────────────────────────────────
            Menus.QsSection { visible: root.depthOn; width: parent.width; label: qsTr("Layers") }
            Column {
                visible: root.depthOn
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.layerCount
                    delegate: Column {
                        id: lr
                        required property int index
                        readonly property bool subject: lr.index === 0
                        readonly property bool front: root.sb.layerFront(root.wall, lr.index)
                        width: parent.width
                        spacing: 4
                        Item {
                            width: parent.width
                            implicitHeight: 38
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - lrSeg.width - (lrRemove.visible ? lrRemove.width + 4 : 0) - 8
                                text: root.sb.layerLabel(root.wall, lr.index)
                                color: root.ink
                                font.family: Theme.fontPrimary
                                font.pixelSize: Theme.fontSm
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Menus.QsSeg {
                                id: lrSeg
                                anchors.right: lrRemove.visible ? lrRemove.left : parent.right
                                anchors.rightMargin: lrRemove.visible ? 4 : 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: 196
                                options: [{ id: "behind", label: "Behind" }, { id: "front", label: "In front" }]
                                current: lr.front ? "front" : "behind"
                                onChose: id => root.sb.setLayerFront(lr.index, id === "front")
                            }
                            Rectangle {
                                id: lrRemove
                                visible: !lr.subject
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 30
                                radius: Theme.radiusWidget - 4
                                color: rmTap.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10) : "transparent"
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    font.pixelSize: 16
                                    text: "close"
                                    color: rmTap.containsMouse ? Theme.error : root.inkDim
                                }
                                MouseArea {
                                    id: rmTap
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.sb.removeLayer(lr.index)
                                }
                            }
                        }
                        KnobRow {
                            visible: root.parallaxOn
                            label: qsTr("Drift")
                            value: root.sb.layerDepth(root.wall, lr.index)
                            valueLabel: qsTr("near") + " \u2192 " + qsTr("far") + "  " + root.sb.layerDepth(root.wall, lr.index).toFixed(2)
                            onMoved: v => root.sb.setLayerDepth(lr.index, v)
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    topPadding: 2
                    TextBtn { width: (parent.width - 8) / 2; label: qsTr("Cut a picture\u2026"); onAct: cutDlg.open() }
                    TextBtn { width: (parent.width - 8) / 2; label: qsTr("Add a PNG\u2026"); onAct: pngDlg.open() }
                }
                ConfirmRow {
                    visible: root.pickedCut !== ""
                    message: qsTr("Cut from") + " " + root._path(root.pickedCut).split("/").pop()
                    primary: qsTr("Cut")
                    onPrimaryAct: { root.sb.cutLayer(root._path(root.pickedCut)); root.pickedCut = ""; }
                    onSecondaryAct: root.pickedCut = ""
                }
                ConfirmRow {
                    visible: root.clearArmed
                    message: qsTr("Remove every cut-out for this wallpaper")
                    primary: qsTr("Clear")
                    onPrimaryAct: { root.sb.clear(); root.clearArmed = false; }
                    onSecondaryAct: root.clearArmed = false
                }
                QuietLink {
                    visible: !root.clearArmed
                    danger: true
                    text: qsTr("Clear cut-outs")
                    onAct: root.clearArmed = true
                }
            }

            // ── Look ───────────────────────────────────────────────────
            Menus.QsSection { visible: root.depthOn; width: parent.width; label: qsTr("Look") }
            Column {
                visible: root.depthOn
                width: parent.width
                spacing: 8
                KnobRow {
                    label: qsTr("Edge")
                    value: root.cfg.edge
                    valueLabel: root.cfg.edge.toFixed(2)
                    onMoved: v => root.cfg.setEdge(v)
                }
                Item {
                    width: parent.width
                    implicitHeight: 56
                    KnobRow {
                        anchors.left: parent.left
                        anchors.right: dial.left
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        label: qsTr("Shadow")
                        value: root.cfg.shadow
                        valueLabel: root.cfg.shadow.toFixed(2)
                        onMoved: v => root.cfg.setShadow(v)
                    }
                    StageAngleDial {
                        id: dial
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        dim: 52
                        angle: root.cfg.shadowAngle
                        onChanged: deg => root.cfg.setShadowAngle(deg)
                    }
                }
                Row {
                    width: parent.width
                    Item { width: parent.width - resetLink.implicitWidth; height: 1 }
                    QuietLink { id: resetLink; text: qsTr("Reset to defaults"); onAct: root.resetLook() }
                }
            }

            // ── Motion (Parallax only) ─────────────────────────────────
            Menus.QsSection { visible: root.parallaxOn; width: parent.width; label: qsTr("Motion") }
            Column {
                visible: root.parallaxOn
                width: parent.width
                spacing: 8
                ChoiceRow {
                    label: qsTr("Preset")
                    options: [{ id: "soft", label: "Soft" }, { id: "cinematic", label: "Cinematic" }, { id: "beat", label: "Beat" }]
                    current: root.currentPreset
                    onChose: id => root.applyPreset(id)
                }
                ChoiceRow {
                    label: qsTr("Amount")
                    options: [{ id: "subtle", label: "Subtle" }, { id: "normal", label: "Normal" }, { id: "strong", label: "Strong" }]
                    current: root.cfg.amount
                    onChose: id => root.cfg.setAmount(id)
                }
                ChoiceRow {
                    label: qsTr("Idle")
                    options: [{ id: "none", label: "Still" }, { id: "float", label: "Float" }, { id: "breathe", label: "Breathe" }, { id: "sway", label: "Sway" }]
                    current: root.cfg.idle
                    onChose: id => root.cfg.setIdle(id)
                }
                KnobRow {
                    visible: root.cfg.idle !== "none"
                    label: qsTr("Speed")
                    value: (root.cfg.speed - 0.25) / 1.75
                    valueLabel: root.cfg.speed.toFixed(2) + "\u00d7"
                    onMoved: v => root.cfg.setSpeed(0.25 + v * 1.75)
                }
                SwitchRow {
                    label: qsTr("React to music")
                    sub: qsTr("Near layers pulse with the beat")
                    on: root.cfg.music
                    onToggled: root.cfg.setMusic(!root.cfg.music)
                }
                KnobRow {
                    visible: root.cfg.music
                    label: qsTr("Intensity")
                    value: root.cfg.musicLevel
                    valueLabel: root.cfg.musicLevel.toFixed(2)
                    onMoved: v => root.cfg.setMusicLevel(v)
                }
                SwitchRow {
                    label: qsTr("Follow mouse")
                    sub: qsTr("Layers drift with the pointer")
                    on: root.cfg.followMouse
                    onToggled: root.cfg.setMouse(!root.cfg.followMouse)
                }
                Menus.RevealerButton {
                    visible: root.cfg.followMouse
                    width: parent.width
                    iconName: "tune"
                    label: qsTr("Fine-tune pointer")
                    revealed: root.pointerOpen
                    onToggled: r => root.pointerOpen = r
                    Column {
                        width: parent.width
                        spacing: 8
                        KnobRow {
                            label: qsTr("Sensitivity")
                            value: root.cfg.sensitivity / 2
                            valueLabel: root.cfg.sensitivity.toFixed(2)
                            onMoved: v => root.cfg.setSensitivity(v * 2)
                        }
                        KnobRow {
                            label: qsTr("Range")
                            value: root.cfg.range / 2
                            valueLabel: root.cfg.range.toFixed(2)
                            onMoved: v => root.cfg.setRange(v * 2)
                        }
                        KnobRow {
                            label: qsTr("Backdrop drift")
                            value: root.cfg.backdrop
                            valueLabel: root.cfg.backdrop.toFixed(2)
                            onMoved: v => root.cfg.setBackdrop(v)
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: cutDlg
        title: I18n.tr("Cut a layer from a picture")
        nameFilters: ["Pictures (*.png *.jpg *.jpeg *.webp *.bmp)", "All files (*)"]
        onAccepted: root.pickedCut = "" + cutDlg.selectedFile
    }
    FileDialog {
        id: pngDlg
        title: I18n.tr("Add a PNG layer")
        nameFilters: ["PNG images (*.png)", "All files (*)"]
        onAccepted: root.sb.addLayer(root._path(pngDlg.selectedFile))
    }
}
