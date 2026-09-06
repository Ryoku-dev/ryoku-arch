pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import shell.services
import "../../../../../components"
import "../../../../parallax/Singletons" as PxCfg
import "../../../../visualizer/Singletons" as VizCfg
import "../../../../desktop/Singletons" as DesktopCfg

// Parallax tab of the Super+Esc quick-settings panel. Plain English on
// purpose (no I18n). Auto cuts the subject and recolours the background;
// manual lists the wallpaper's layer-NN.png folder. Per-layer options
// mirror the depth effect plus the layer model; sliders are drag-only.
Item {
    id: root

    property real s: 1
    property bool open: false
    property var navigate: null
    property var closePanel: null

    readonly property bool checked: PxCfg.ParallaxBackend.checked
    readonly property bool ready: PxCfg.ParallaxBackend.available
    readonly property bool installing: PxCfg.ParallaxBackend.installing
    readonly property int layerCount: PxCfg.Config.layers.length
    readonly property bool hasLayers: root.wallActive && root.layerCount > 0
    readonly property string activePath: PxCfg.Config.activePath
    readonly property string wallMode: PxCfg.Config.wallMode
    readonly property bool manualMode: root.wallMode === "manual"
    readonly property bool autoMode: root.wallMode === "auto"
    readonly property bool wallActive: PxCfg.Config.wallActive

    property bool statusBusy: false
    property bool busyStuck: false
    property string stage: ""
    property int statusPercent: 0

    readonly property bool generating: (root.statusBusy && !root.busyStuck) || minBusy.running

    property string draftCutTier: PxCfg.Config.cutTier()
    readonly property bool detailDirty: root.draftCutTier !== PxCfg.Config.cutTier()
    Connections {
        target: PxCfg.Config
        function onModelChanged() { if (!root.generating) root.draftCutTier = PxCfg.Config.cutTier(); }
        function onAlphaMattingChanged() { if (!root.generating) root.draftCutTier = PxCfg.Config.cutTier(); }
    }
    onOpenChanged: {
        if (root.open) {
            root.draftCutTier = PxCfg.Config.cutTier();
            root.rebuildScene();
        }
    }

    property string expanded: "order"
    property string activePreset: "none"

    Timer {
        id: rescanTimer
        interval: 2500
        onTriggered: {
            if (root.manualMode) PxCfg.Config.refresh();
        }
    }

    Timer { id: minBusy; interval: 900 }
    Timer {
        id: stuckGuard
        interval: 50000
        running: root.statusBusy && !root.busyStuck
        onTriggered: root.busyStuck = true
    }

    function recut() {
        if (root.activePath === "" || !root.ready) return;
        minBusy.restart();
        root.busyStuck = false;
        root.statusBusy = true;
        PxCfg.Config.setWallEnabled(true);
        if (root.draftCutTier !== PxCfg.Config.cutTier())
            PxCfg.Config.setCutTier(root.draftCutTier);
        PxCfg.Config.refresh();
        poll.restart();
    }
    function cancel() { PxCfg.Config.cancel(); }
    function placeVisualizer() {
        const st = ShellState.forActive();
        if (st) st.visualizerPlacing = true;
        if (root.closePanel) root.closePanel();
    }
    function resetScene() {
        PxCfg.Config.setScene([]);
        root.rebuildScene();
    }

    Timer {
        id: poll
        interval: 500
        repeat: true
        running: root.open
        triggeredOnStart: true
        onTriggered: statusProc.running = true
    }
    Process {
        id: statusProc
        command: ["ryoku-shell", "parallax", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(("" + this.text).trim() || "{}"); } catch (e) {}
                const wasBusy = root.statusBusy;
                root.statusBusy = d.busy === true;
                root.stage = (typeof d.stage === "string") ? d.stage : "";
                root.statusPercent = (typeof d.percent === "number") ? d.percent : 0;
                if (!root.statusBusy) {
                    root.busyStuck = false;
                    if (wasBusy) minBusy.stop();
                }
            }
        }
    }

    property var sceneRows: []
    function rebuildScene() {
        const names = {
            "clock": "Clock", "calendar": "Calendar", "music": "Music",
            "aio": "AIO", "stats": "Stats", "weather": "Weather",
            "notes": "Notes"
        };
        const rows = [];
        try {
            // Front-first display: highest scene index is the first row.
            const scene = PxCfg.Config.effectiveScene();
            for (let k = scene.length - 1; k >= 0; k--) {
                const id = scene[k];
                if (id === "wallpaper") continue;
                if (id === "visualizer") {
                    if (VizCfg.Config.enabled)
                        rows.push({ id: id, label: "Visualizer", icon: "graphic_eq", movable: true });
                    continue;
                }
                if (id.indexOf("layer:") === 0) {
                    const i = parseInt(id.slice(6));
                    const lbl = PxCfg.Config.layerLabel(i).toLowerCase();
                    rows.push({
                        id: id,
                        label: PxCfg.Config.layerLabel(i),
                        icon: lbl.indexOf("subject") === 0 ? "person"
                            : lbl.indexOf("object") === 0 ? "category"
                            : "layers",
                        movable: true
                    });
                    continue;
                }
                if (id.indexOf("widget:") !== 0) continue;
                const w = id.slice(7);
                if (!root.widgetOn(w)) continue;
                rows.push({ id: id, label: names[w] || w, icon: "widgets", movable: true });
            }
        } catch (e) {
            rows.length = 0;
        }
        if (rows.length === 0) {
            for (const w of ["clock", "calendar", "music", "aio", "stats", "weather", "notes"]) {
                if (!root.widgetOn(w)) continue;
                rows.push({ id: "widget:" + w, label: names[w] || w, icon: "widgets", movable: true });
            }
            if (VizCfg.Config.enabled)
                rows.push({ id: "visualizer", label: "Visualizer", icon: "graphic_eq", movable: true });
            for (let i = PxCfg.Config.layers.length; i >= 1; i--) {
                rows.push({ id: "layer:" + i, label: PxCfg.Config.layerLabel(i), icon: "layers", movable: true });
            }
        }
        root.sceneRows = rows;
    }
    function widgetOn(id) {
        switch (id) {
        case "clock": return DesktopCfg.Config.clockEnabled;
        case "calendar": return DesktopCfg.Config.calendarEnabled;
        case "music": return DesktopCfg.Config.musicEnabled;
        case "aio": return DesktopCfg.Config.aioEnabled;
        case "stats": return DesktopCfg.Config.statsEnabled;
        case "weather": return DesktopCfg.Config.weatherEnabled;
        case "notes": return DesktopCfg.Config.notesEnabled;
        }
        return true;
    }
    function _sceneRowShown(id) {
        if (id === "wallpaper") return false;
        if (id === "visualizer") return VizCfg.Config.enabled;
        if (id.indexOf("layer:") === 0) return true;
        if (id.indexOf("widget:") === 0) return root.widgetOn(id.slice(7));
        return false;
    }
    function moveOrder(id, dir) {
        const scene = PxCfg.Config.effectiveScene().slice();
        // Reorder only among the rows the editor actually renders; swapping a
        // visible entry with a hidden widget, the wallpaper or a disabled
        // visualizer would read as a dead click or jump past invisible rows.
        const shown = [];
        for (let k = 0; k < scene.length; k++)
            if (root._sceneRowShown(scene[k])) shown.push(k);
        const pos = shown.indexOf(scene.indexOf(id));
        const tpos = pos + dir;
        if (pos < 0 || tpos < 0 || tpos >= shown.length) return;
        const a = shown[pos], b = shown[tpos];
        const tmp = scene[a]; scene[a] = scene[b]; scene[b] = tmp;
        PxCfg.Config.setScene(scene);
        root.rebuildScene();
    }
    function removeLayer(layerIdx) {
        if (layerIdx < 1 || layerIdx > PxCfg.Config.layers.length) return;
        PxCfg.Config.removeManualLayer(PxCfg.Config.layerPath(layerIdx));
    }
    Connections {
        target: PxCfg.Config
        function onWallSceneChanged() { root.rebuildScene(); }
        function onActivePathChanged() { root.rebuildScene(); }
        function onWallBandsChanged() { root.rebuildScene(); }
        function onLayersChanged() { root.rebuildScene(); }
        function onWallModeChanged() { root.rebuildScene(); }
    }
    Connections {
        target: DesktopCfg.Config
        function onClockEnabledChanged() { root.rebuildScene(); }
        function onCalendarEnabledChanged() { root.rebuildScene(); }
        function onMusicEnabledChanged() { root.rebuildScene(); }
        function onAioEnabledChanged() { root.rebuildScene(); }
        function onStatsEnabledChanged() { root.rebuildScene(); }
        function onWeatherEnabledChanged() { root.rebuildScene(); }
        function onNotesEnabledChanged() { root.rebuildScene(); }
    }
    Component.onCompleted: root.rebuildScene()

    component Sec: Text {
        id: sec
        property string title: ""
        text: sec.title.toUpperCase()
        color: Theme.primary
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm - 3
        font.weight: Font.DemiBold
        width: parent ? parent.width : 0
    }

    component PxTile: Rectangle {
        id: tile
        property string icon: "circle"
        property string label: ""
        property string sub: ""
        property bool on: false
        property bool available: true
        signal toggled()
        width: parent ? parent.width : 0
        height: 58
        radius: Theme.radiusWidget
        color: "transparent"
        opacity: tile.available ? 1 : 0.4
        Row {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10
            Rectangle {
                width: 34
                height: 34
                radius: 17
                anchors.verticalCenter: parent.verticalCenter
                color: tile.on ? Theme.primary
                    : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
                MaterialIcon {
                    anchors.centerIn: parent
                    text: tile.icon
                    font.pixelSize: 16
                    color: tile.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                }
            }
            Column {
                width: parent.width - 34 - 10 - 46
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    text: tile.label
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: tile.sub.length > 0
                    text: tile.sub
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 3
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                width: 40
                height: 22
                radius: 11
                anchors.verticalCenter: parent.verticalCenter
                color: tile.on ? Theme.primary : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    x: tile.on ? 19 : 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surface
                    Behavior on x { NumberAnimation { duration: Motion.fast } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.toggled()
                }
            }
        }
    }

    component PxNavRow: Rectangle {
        id: nav
        property string icon: "circle"
        property string label: ""
        property string sub: ""
        signal activated()
        width: parent ? parent.width : 0
        height: 54
        radius: Theme.radiusWidget
        color: navMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.crossfade } }
        Row {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: nav.icon
                font.pixelSize: 18
                color: Theme.onSurfaceVariant
            }
            Column {
                width: parent.width - 28
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    text: nav.label
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: nav.sub.length > 0
                    text: nav.sub
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 3
                    wrapMode: Text.WordWrap
                }
            }
        }
        MouseArea {
            id: navMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.activated()
        }
    }

    component PxSeg: Rectangle {
        id: seg
        property var options: []   // [{ id, label }]
        property string current: ""
        signal chose(string id)
        implicitHeight: 38
        radius: Theme.radiusWidget
        color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.30)
        width: parent ? parent.width : 0
        Row {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 4
            Repeater {
                model: seg.options
                delegate: Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool active: opt.modelData.id === seg.current
                    width: (parent.width - (seg.options.length - 1) * 4) / Math.max(1, seg.options.length)
                    height: parent.height
                    radius: Theme.radiusWidget - 4
                    color: opt.active ? Theme.primary
                        : optMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.crossfade } }
                    Text {
                        anchors.centerIn: parent
                        text: opt.modelData.label
                        color: opt.active ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 1
                        font.weight: opt.active ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: optMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.chose(opt.modelData.id)
                    }
                }
            }
        }
    }

    component Field: Column {
        id: field
        property string title: ""
        property string hint: ""
        property var choices: []
        property string current: ""
        signal chose(string id)
        width: parent ? parent.width : 0
        spacing: 5
        Text {
            text: field.title
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm
            font.weight: Font.DemiBold
        }
        Text {
            width: field.width
            visible: field.hint.length > 0
            text: field.hint
            wrapMode: Text.WordWrap
            color: Qt.rgba(Theme.onSurfaceVariant.r, Theme.onSurfaceVariant.g, Theme.onSurfaceVariant.b, 0.9)
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 3
        }
        PxSeg {
            width: field.width
            options: field.choices
            current: field.current
            onChose: id => field.chose(id)
        }
    }

    // Drag-only: no wheel handler, so scrolling never changes a value.
    component DragSlider: Item {
        id: ds
        property string title: ""
        property real value: 0
        property real min: 0
        property real max: 1
        property int decimals: 2
        property string unit: ""
        signal changed(real v)
        width: parent ? parent.width : 0
        height: 46
        function valueAt(mx) {
            const t = track.width - 14;
            const frac = Math.max(0, Math.min(1, (mx - 7) / Math.max(1, t)));
            return ds.min + frac * (ds.max - ds.min);
        }
        Text {
            id: dsLabel
            anchors.left: parent.left
            anchors.top: parent.top
            text: ds.title
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: Font.DemiBold
        }
        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: ds.value.toFixed(ds.decimals) + ds.unit
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 2
        }
        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 6
            radius: 3
            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
            Rectangle {
                id: fill
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                radius: 3
                color: Theme.primary
                width: 7 + (track.width - 14) * ((ds.value - ds.min) / Math.max(0.0001, ds.max - ds.min))
            }
            Rectangle {
                id: thumb
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(track.width - 14, 7 + (track.width - 14) * ((ds.value - ds.min) / Math.max(0.0001, ds.max - ds.min)) - 7))
                color: Theme.surface
                border.width: 2
                border.color: Theme.primary
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -12
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                onPositionChanged: mouse => {
                    if (mouse.buttons & Qt.LeftButton)
                        ds.changed(ds.valueAt(mouse.x));
                }
                onPressed: mouse => ds.changed(ds.valueAt(mouse.x))
            }
        }
    }

    // Shadow direction dial (0 = right, 90 = down).
    component AngleDial: Item {
        id: dial
        property real angle: 90
        signal changed(real deg)
        width: 88
        height: 88
        readonly property real rad: dial.angle * Math.PI / 180
        readonly property real cx: 44
        readonly property real cy: 44
        readonly property real dotR: 26

        Rectangle {
            anchors.centerIn: parent
            width: 80
            height: 80
            radius: 40
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) }
                GradientStop { position: 1.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) }
            }
            border.width: 1
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
        }
        Repeater {
            model: [0, 90, 180, 270]
            delegate: Rectangle {
                required property int modelData
                readonly property real t: modelData * Math.PI / 180
                width: 2
                height: 5
                radius: 1
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.5)
                x: dial.cx - 1 + Math.cos(t) * 36
                y: dial.cy - 2.5 + Math.sin(t) * 36
            }
        }
        Rectangle {
            id: needle
            width: 2
            height: dial.dotR - 4
            radius: 1
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
            x: dial.cx - 1
            y: dial.cy - (dial.dotR - 4)
            transformOrigin: Item.Bottom
            rotation: dial.angle + 90
            Behavior on rotation { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 8
            radius: 4
            color: Theme.onSurface
        }
        Rectangle {
            id: dot
            width: 20
            height: 20
            radius: 10
            color: Theme.primary
            border.width: 3
            border.color: Theme.surface
            x: dial.cx - 10 + Math.cos(dial.rad) * dial.dotR
            y: dial.cy - 10 + Math.sin(dial.rad) * dial.dotR
            Behavior on x { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function update(mx, my) {
                const dx = mx - dial.cx;
                const dy = my - dial.cy;
                if (Math.abs(dx) < 2 && Math.abs(dy) < 2) return;
                let deg = Math.atan2(dy, dx) * 180 / Math.PI;
                if (deg < 0) deg += 360;
                dial.changed(Math.round(deg));
            }
            onPositionChanged: mouse => {
                if (mouse.buttons & Qt.LeftButton)
                    update(mouse.x, mouse.y);
            }
            onPressed: mouse => update(mouse.x, mouse.y)
        }
    }

    component PxBtn: Rectangle {
        id: btn
        property string icon: ""
        property string label: ""
        property string kind: "outlined"
        property bool enabledAct: true
        signal act()
        width: parent ? parent.width : 0
        height: 44
        radius: Theme.radiusWidget
        opacity: btn.enabledAct ? 1 : 0.4
        color: btn.kind === "filled"
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, ma.containsMouse && btn.enabledAct ? 0.30 : 0.22)
            : (ma.containsMouse && btn.enabledAct) ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
        border.width: btn.kind === "ghost" ? 0 : 1
        border.color: btn.kind === "filled"
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
            : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.crossfade } }
        Row {
            anchors.centerIn: parent
            spacing: 8
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.icon
                font.pixelSize: 18
                fill: btn.kind === "filled" ? 1 : 0
                color: Theme.onSurface
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabledAct ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.enabledAct) btn.act()
        }
    }

    component StopBtn: Rectangle {
        id: sbtn
        signal clicked()
        width: 64
        height: 28
        radius: 14
        color: ma.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.16) : "transparent"
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.30)
        Text {
            anchors.centerIn: parent
            text: "Stop"
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sbtn.clicked()
        }
    }

    component SceneRow: Item {
        id: row
        property var rowData: null
        property int rowIndex: 0
        property int rowCount: 0
        signal move(string id, int dir)
        width: parent ? parent.width : 0
        height: 38
        readonly property string rowLabel: row.rowData ? (row.rowData.label ? row.rowData.label : "") : ""
        readonly property string rowIcon: row.rowData ? (row.rowData.icon ? row.rowData.icon : "") : ""
        readonly property bool canMove: row.rowData ? row.rowData.movable === true : false
        Row {
            id: rowLine
            anchors.fill: parent
            spacing: 10
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: row.rowIcon
                font.pixelSize: 16
                color: Theme.onSurfaceVariant
                width: 18
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: row.rowLabel
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
            }
            Item { width: row.rowCount > 0 ? 74 : 0; height: 26 }
            Item {
                width: 30; height: 26
                visible: row.canMove
                opacity: row.rowIndex > 0 ? 1 : 0.3
                enabled: row.rowIndex > 0
                MaterialIcon {
                    anchors.centerIn: parent
                    text: "keyboard_arrow_up"
                    font.pixelSize: 18
                    color: upMa.containsMouse ? Theme.onSurface : Theme.onSurfaceVariant
                }
                MouseArea {
                    id: upMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: row.move(row.rowData ? row.rowData.id : "", 1)
                }
            }
            Item {
                width: 30; height: 26
                visible: row.canMove
                opacity: row.rowIndex < row.rowCount - 1 ? 1 : 0.3
                enabled: row.rowIndex < row.rowCount - 1
                MaterialIcon {
                    anchors.centerIn: parent
                    text: "keyboard_arrow_down"
                    font.pixelSize: 18
                    color: downMa.containsMouse ? Theme.onSurface : Theme.onSurfaceVariant
                }
                MouseArea {
                    id: downMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: row.move(row.rowData ? row.rowData.id : "", -1)
                }
            }
        }
    }

    component PanelHeader: Item {
        id: ph
        property string icon: "layers"
        property string label: ""
        property bool expanded: false
        property bool showEye: false
        property bool eyeOn: true
        signal toggle()
        signal eye()
        width: parent ? parent.width : 0
        height: 44
        Row {
            anchors.fill: parent
            spacing: 10
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: ph.expanded ? "keyboard_arrow_down" : "keyboard_arrow_right"
                font.pixelSize: 18
                color: Theme.onSurfaceVariant
            }
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: ph.icon
                font.pixelSize: 16
                color: Theme.onSurfaceVariant
                width: 18
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ph.label
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                visible: ph.showEye
                MaterialIcon {
                    anchors.centerIn: parent
                    text: ph.eyeOn ? "visibility" : "visibility_off"
                    font.pixelSize: 16
                    color: ph.eyeOn ? Theme.primary : Theme.onSurfaceVariant
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ph.eye()
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: ph.toggle()
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.surface }

    Flickable {
        anchors.fill: parent
        anchors.margins: 12
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: col
            width: parent.width
            spacing: 12

            Column {
                width: parent.width
                spacing: 2
                Text {
                    text: "Parallax"
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Cut the subject from your wallpaper (auto) or drop numbered PNGs per wallpaper (manual), then tune each layer and the on-screen order."
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                }
            }

            Text {
                width: parent.width
                visible: !root.checked
                text: "Preparing engine..."
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
            }

            PxNavRow {
                width: parent.width
                visible: root.checked && !root.ready
                icon: "download"
                label: PxCfg.ParallaxBackend.installing ? "Installing engine..." : "Install engine"
                sub: PxCfg.ParallaxBackend.installing
                    ? PxCfg.ParallaxBackend.progress
                    : "A one-time download to detect subjects."
                onActivated: if (!PxCfg.ParallaxBackend.installing)
                    PxCfg.ParallaxBackend.install()
            }

            PxTile {
                width: parent.width
                visible: root.checked
                icon: "view_in_ar"
                label: "Parallax layers"
                sub: root.generating
                    ? (root.stage.length > 0 ? root.stage : "Cutting...")
                    : (root.wallActive ? "On" : "Off")
                on: root.wallActive
                onToggled: {
                    if (!root.wallActive) {
                        PxCfg.Config.setEnabledGlobal(true);
                        PxCfg.Config.setWallEnabled(true);
                    } else {
                        PxCfg.Config.setWallEnabled(false);
                    }
                }
            }

            Rectangle {
                id: preview
                width: parent.width
                height: 200
                radius: Theme.radiusWidget
                clip: true
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.04)
                border.width: 1
                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)

                property real demoT: 0
                Timer {
                    interval: 50
                    repeat: true
                    running: preview.visible && !root.generating
                    onTriggered: preview.demoT += 50
                }
                readonly property real demoNX: Math.sin(preview.demoT / 900)
                readonly property real demoNY: Math.cos(preview.demoT / 1100)

                Repeater {
                    model: root.layerCount
                    delegate: Item {
                        id: pvLayer
                        required property int index
                        readonly property int li: index + 1
                        anchors.fill: parent
                        z: PxCfg.Config.sceneZ("layer:" + pvLayer.li)
                        visible: PxCfg.Config.layerEnabled2(index)
                        Image {
                            anchors.fill: parent
                            source: PxCfg.Config.layerUrl(pvLayer.li)
                            cache: false
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            opacity: status === Image.Ready ? PxCfg.Config.opacityFor(pvLayer.index) : 0
                            transform: Translate {
                                x: preview.demoNX * 9
                                    * PxCfg.Config.parallaxFor(pvLayer.index)
                                    * (0.4 + PxCfg.Config.depthFor(pvLayer.index) * 1.2)
                                    * PxCfg.Config.mouseSensitivity
                                    + PxCfg.Config.offsetXFor(pvLayer.index) / 10
                                y: preview.demoNY * 9
                                    * PxCfg.Config.parallaxFor(pvLayer.index)
                                    * (0.4 + PxCfg.Config.depthFor(pvLayer.index) * 1.2)
                                    * PxCfg.Config.mouseSensitivity
                                    + PxCfg.Config.offsetYFor(pvLayer.index) / 10
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.checked && root.activePath !== "" && !root.hasLayers && !root.generating
                    text: root.manualMode
                        ? "Drop layer-NN.png files into the manual folder for this wallpaper."
                        : "No layers for this wallpaper yet."
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    spacing: 6
                    visible: root.generating
                    Text {
                        width: parent.width
                        text: root.stage.length > 0 ? root.stage : "Cutting layer"
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 1
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Row {
                        width: parent.width
                        spacing: 8
                        Rectangle {
                            width: parent.width - 72
                            height: 4
                            radius: 2
                            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                radius: 2
                                color: Theme.primary
                                width: Math.max(0, Math.min(parent.width, parent.width * (root.statusPercent / 100)))
                                Behavior on width { NumberAnimation { duration: Motion.crossfade } }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.statusPercent + "%"
                            color: Theme.onSurfaceVariant
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 3
                            width: 40
                            horizontalAlignment: Text.AlignRight
                        }
                        StopBtn {
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: root.cancel()
                        }
                    }
                }
            }

            Sec { title: "Mode" }
            Field {
                title: "Cutout source"
                hint: "Auto cuts the subject with the engine and recolours the hole. Manual lists the layer files you place in the wallpaper's folder."
                choices: [
                    { id: "auto", label: "Auto (subject)" },
                    { id: "manual", label: "Manual (numbered)" }
                ]
                current: root.wallMode
                onChose: id => {
                    PxCfg.Config.setMode(id);
                    root.rebuildScene();
                }
            }

            Column {
                width: parent.width
                spacing: 10
                visible: root.autoMode

                Sec { title: "Quality" }
                Field {
                    title: "Cutout detail"
                    hint: "Higher detail traces hair and fine edges."
                    choices: PxCfg.ParallaxBackend.hasModel("birefnet-general-lite")
                        ? [{ id: "draft", label: "Draft" }, { id: "standard", label: "Standard" }, { id: "fine", label: "Fine" }]
                        : [{ id: "draft", label: "Draft" }, { id: "standard", label: "Standard" }]
                    current: root.draftCutTier
                    onChose: id => root.draftCutTier = id
                }
                PxBtn {
                    visible: root.ready
                    kind: "filled"
                    icon: root.generating ? "hourglass_top" : "cached"
                    label: root.generating
                        ? (root.stage.length > 0 ? root.stage + "..." : "Cutting...")
                        : "Cut the subject"
                    enabledAct: root.ready && !root.generating
                    onAct: root.recut()
                }
            }

            Column {
                width: parent.width
                spacing: 10
                visible: root.manualMode

                Sec { title: "Layers" }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Drop PNGs named layer-NN.png into the folder for this wallpaper."
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 3
                }
                PxBtn {
                    kind: "filled"
                    icon: "folder_open"
                    label: "Open layers folder"
                    onAct: {
                        PxCfg.ParallaxBackend.openManualFolderFor(root.activePath);
                        rescanTimer.restart();
                    }
                }
                PxBtn {
                    kind: "outlined"
                    icon: "cached"
                    label: "Rescan layers"
                    onAct: PxCfg.Config.refresh()
                }
                Text {
                    width: parent.width
                    text: root.layerCount === 0
                        ? "No layers yet."
                        : root.layerCount + " layers"
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 3
                }
                Repeater {
                    model: root.layerCount
                    delegate: Item {
                        id: manualRow
                        required property int index
                        readonly property int li: index + 1
                        width: parent ? parent.width : 0
                        implicitHeight: 64
                        Row {
                            anchors.fill: parent
                            anchors.rightMargin: 40
                            spacing: 10
                            Rectangle {
                                width: 56
                                height: 56
                                radius: Theme.radiusWidget
                                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06)
                                border.width: 1
                                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.18)
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: PxCfg.Config.layerUrl(manualRow.li)
                                    cache: false
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    sourceSize.width: 56
                                    sourceSize.height: 56
                                    opacity: status === Image.Ready ? 1 : 0
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 56 - 10
                                spacing: 2
                                Text {
                                    text: PxCfg.Config.layerLabel(manualRow.li)
                                    color: Theme.onSurface
                                    font.family: Theme.fontPrimary
                                    font.pixelSize: Theme.fontSm
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: PxCfg.Config.layerPath(manualRow.li).split("/").pop()
                                    color: Theme.onSurfaceVariant
                                    font.family: Theme.fontPrimary
                                    font.pixelSize: Theme.fontSm - 3
                                    elide: Text.ElideMiddle
                                    width: parent.width
                                }
                            }
                        }
                        Item {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "delete"
                                font.pixelSize: 16
                                color: delMa.containsMouse ? Theme.onSurface : Theme.onSurfaceVariant
                            }
                            MouseArea {
                                id: delMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeLayer(manualRow.li)
                            }
                        }
                    }
                }
            }

            Item {
                width: parent.width
                visible: root.checked
                implicitHeight: accordion.implicitHeight
                Column {
                    id: accordion
                    width: parent.width
                    spacing: 6

                    Sec { title: "Layers" }

                    Text {
                        width: parent.width
                        visible: root.layerCount === 0
                        wrapMode: Text.WordWrap
                        text: root.manualMode
                            ? "No layers yet. Drop layer-NN.png files into the wallpaper folder."
                            : "No layers yet. Turn Parallax on and cut the subject."
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 3
                    }

                    Item {
                        width: parent.width
                        implicitHeight: orderPanel.implicitHeight
                        Column {
                            id: orderPanel
                            width: parent.width
                            spacing: 4
                            PanelHeader {
                                icon: "sort"
                                label: "Order"
                                expanded: root.expanded === "order"
                                onToggle: root.expanded = root.expanded === "order" ? "" : "order"
                            }
                            Column {
                                width: parent.width
                                spacing: 4
                                visible: root.expanded === "order"
                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: "The on-screen stack, front first. Move any row: layers, widgets and the visualizer."
                                    color: Theme.onSurfaceVariant
                                    font.family: Theme.fontPrimary
                                    font.pixelSize: Theme.fontSm - 3
                                }
                                Repeater {
                                    model: root.sceneRows.length
                                    delegate: SceneRow {
                                        required property int index
                                        rowData: root.sceneRows[index]
                                        rowIndex: index
                                        rowCount: root.sceneRows.length
                                        onMove: (id, dir) => root.moveOrder(id, dir)
                                    }
                                }
                                Row {
                                    width: parent.width
                                    spacing: 8
                                    PxBtn {
                                        width: (parent.width - 8) / 2
                                        kind: "ghost"
                                        icon: "restart_alt"
                                        label: "Reset order"
                                        onAct: root.resetScene()
                                    }
                                    PxBtn {
                                        width: (parent.width - 8) / 2
                                        kind: "ghost"
                                        icon: "open_with"
                                        label: "Place visualizer"
                                        visible: VizCfg.Config.enabled && PxCfg.Config.sceneIndexOf("visualizer") >= 0
                                        onAct: root.placeVisualizer()
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: root.layerCount
                        delegate: Item {
                            id: layerPanel
                            required property int index
                            readonly property int li: index + 1
                            width: parent ? parent.width : 0
                            implicitHeight: layerCol.implicitHeight
                            Column {
                                id: layerCol
                                width: parent.width
                                spacing: 4
                                PanelHeader {
                                    icon: {
                                        const lbl = PxCfg.Config.layerLabel(layerPanel.li).toLowerCase();
                                        return lbl.indexOf("subject") === 0 ? "person" : "layers";
                                    }
                                    label: PxCfg.Config.layerLabel(layerPanel.li)
                                    expanded: root.expanded === "layer:" + layerPanel.li
                                    showEye: true
                                    eyeOn: PxCfg.Config.layerEnabled2(layerPanel.li - 1)
                                    onToggle: root.expanded = root.expanded === "layer:" + layerPanel.li ? "" : "layer:" + layerPanel.li
                                    onEye: PxCfg.Config.setLayerEnabled2(layerPanel.li - 1, !PxCfg.Config.layerEnabled2(layerPanel.li - 1))
                                }

                                Column {
                                    width: parent.width
                                    spacing: 8
                                    visible: root.expanded === "layer:" + layerPanel.li

                                    Rectangle {
                                        width: parent.width
                                        height: 120
                                        radius: Theme.radiusWidget
                                        clip: true
                                        color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.04)
                                        border.width: 1
                                        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            source: PxCfg.Config.layerUrl(layerPanel.li)
                                            cache: false
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectFit
                                            sourceSize.width: parent.width - 16
                                            sourceSize.height: parent.height - 16
                                            opacity: status === Image.Ready ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: Motion.crossfade } }
                                        }
                                    }

                                    Sec { title: "Depth" }
                                    DragSlider {
                                        title: "Feather"
                                        value: PxCfg.Config.featherFor(layerPanel.li - 1)
                                        min: 0; max: 1; decimals: 2
                                        onChanged: v => PxCfg.Config.setFeatherFor(layerPanel.li - 1, v)
                                    }
                                    DragSlider {
                                        title: "Lift"
                                        value: PxCfg.Config.liftFor(layerPanel.li - 1)
                                        min: 0; max: 1; decimals: 2
                                        onChanged: v => PxCfg.Config.setLiftFor(layerPanel.li - 1, v)
                                    }
                                    DragSlider {
                                        title: "Shadow strength"
                                        value: PxCfg.Config.shadowFor(layerPanel.li - 1)
                                        min: 0; max: 1; decimals: 2
                                        onChanged: v => PxCfg.Config.setShadowFor(layerPanel.li - 1, v)
                                    }
                                    Row {
                                        width: parent.width
                                        spacing: 12
                                        AngleDial {
                                            id: dial
                                            angle: PxCfg.Config.shadowAngleFor(layerPanel.li - 1)
                                            onChanged: deg => PxCfg.Config.setShadowAngleFor(layerPanel.li - 1, deg)
                                        }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 84 - 12
                                            spacing: 2
                                            Text {
                                                text: "Shadow angle"
                                                color: Theme.onSurface
                                                font.family: Theme.fontPrimary
                                                font.pixelSize: Theme.fontSm - 1
                                                font.weight: Font.DemiBold
                                            }
                                            Text {
                                                text: PxCfg.Config.shadowAngleFor(layerPanel.li - 1) + "\u00B0" + " - Drag the dot to set where the shadow falls."
                                                wrapMode: Text.WordWrap
                                                color: Theme.onSurfaceVariant
                                                font.family: Theme.fontPrimary
                                                font.pixelSize: Theme.fontSm - 3
                                                width: parent.width
                                            }
                                        }
                                    }

                                    Sec { title: "Parallax" }
                                    DragSlider {
                                        title: "Parallax speed"
                                        value: PxCfg.Config.parallaxFor(layerPanel.li - 1)
                                        min: 0; max: 2; decimals: 1
                                        onChanged: v => PxCfg.Config.setParallaxFor(layerPanel.li - 1, v)
                                    }
                                    DragSlider {
                                        title: "Depth factor"
                                        value: PxCfg.Config.depthFor(layerPanel.li - 1)
                                        min: 0; max: 1; decimals: 2
                                        onChanged: v => PxCfg.Config.setDepthFor(layerPanel.li - 1, v)
                                    }
                                    DragSlider {
                                        title: "Max drift"
                                        value: PxCfg.Config.mouseMaxFor(layerPanel.li - 1)
                                        min: 0; max: 96; decimals: 0
                                        unit: " px"
                                        onChanged: v => PxCfg.Config.setMouseMaxFor(layerPanel.li - 1, v)
                                    }

                                    Sec { title: "Look" }
                                    DragSlider {
                                        title: "Opacity"
                                        value: PxCfg.Config.opacityFor(layerPanel.li - 1)
                                        min: 0; max: 1; decimals: 2
                                        onChanged: v => PxCfg.Config.setOpacityFor(layerPanel.li - 1, v)
                                    }
                                    DragSlider {
                                        title: "Offset X"
                                        value: PxCfg.Config.offsetXFor(layerPanel.li - 1)
                                        min: -400; max: 400; decimals: 0
                                        unit: " px"
                                        onChanged: v => PxCfg.Config.setOffsetXFor(layerPanel.li - 1, v)
                                    }
                                    DragSlider {
                                        title: "Offset Y"
                                        value: PxCfg.Config.offsetYFor(layerPanel.li - 1)
                                        min: -400; max: 400; decimals: 0
                                        unit: " px"
                                        onChanged: v => PxCfg.Config.setOffsetYFor(layerPanel.li - 1, v)
                                    }

                                    Sec { title: "Motion" }
                                    Field {
                                        title: "Animation"
                                        choices: [
                                            { id: "none", label: "None" },
                                            { id: "float", label: "Float" },
                                            { id: "pulse", label: "Pulse" },
                                            { id: "scale", label: "Scale" },
                                            { id: "wiggle", label: "Wiggle" },
                                            { id: "rotate", label: "Rotate" }
                                        ]
                                        current: PxCfg.Config.animTypeFor(layerPanel.li - 1)
                                        onChose: id => PxCfg.Config.setAnimTypeFor(layerPanel.li - 1, id)
                                    }
                                    DragSlider {
                                        title: "Animation speed"
                                        value: PxCfg.Config.animSpeedFor(layerPanel.li - 1)
                                        min: 0.1; max: 3; decimals: 1
                                        visible: PxCfg.Config.animTypeFor(layerPanel.li - 1) !== "none"
                                        onChanged: v => PxCfg.Config.setAnimSpeedFor(layerPanel.li - 1, v)
                                    }
                                    DragSlider {
                                        title: "Animation amplitude"
                                        value: PxCfg.Config.animAmplitudeFor(layerPanel.li - 1)
                                        min: 0; max: 64; decimals: 0
                                        visible: PxCfg.Config.animTypeFor(layerPanel.li - 1) !== "none"
                                        onChanged: v => PxCfg.Config.setAnimAmpFor(layerPanel.li - 1, v)
                                    }
                                    DragSlider {
                                        title: "Audio reactivity"
                                        value: PxCfg.Config.audioLevelFor(layerPanel.li - 1)
                                        min: 0; max: 1; decimals: 2
                                        onChanged: v => PxCfg.Config.setAudioLevelFor(layerPanel.li - 1, v)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Sec { title: "Motion" }
            PxTile {
                width: parent.width
                icon: "mouse"
                label: "Mouse tracking"
                sub: PxCfg.Config.mouseEnabled ? "On" : "Off"
                on: PxCfg.Config.mouseEnabled
                onToggled: {
                    PxCfg.Config.mouseEnabled = !PxCfg.Config.mouseEnabled;
                    PxCfg.Config.save();
                }
            }
            DragSlider {
                title: "Mouse sensitivity"
                value: PxCfg.Config.mouseSensitivity
                min: 0.05; max: 2; decimals: 2
                onChanged: v => PxCfg.Config.setMouseSensitivity(v)
            }
            DragSlider {
                title: "Drift range"
                value: PxCfg.Config.mouseRange
                min: 0.02; max: 1; decimals: 2
                onChanged: v => PxCfg.Config.setMouseRange(v)
            }
            DragSlider {
                title: "Wallpaper parallax"
                value: PxCfg.Config.wallpaperParallax
                min: 0; max: 1; decimals: 2
                onChanged: v => PxCfg.Config.setWallpaperParallax(v)
            }

            Sec { title: "Presets" }
            Field {
                title: "Preset"
                hint: "Applies a tuning to every layer at once. None restores the defaults."
                choices: [
                    { id: "none", label: "None" },
                    { id: "softdepth", label: "Soft Depth" },
                    { id: "audiopulse", label: "Audio Pulse" },
                    { id: "cinematic", label: "Cinematic" }
                ]
                current: root.activePreset
                onChose: id => {
                    root.activePreset = id;
                    PxCfg.Config.applyPreset(id);
                }
            }

            PxNavRow {
                width: parent.width
                icon: "folder_open"
                label: "Open cutouts folder"
                onActivated: PxCfg.ParallaxBackend.openFolder()
            }

            Rectangle {
                width: parent.width
                height: engCol.implicitHeight + 20
                radius: Theme.radiusWidget
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.04)
                border.width: 1
                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.18)
                Column {
                    id: engCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 5
                    Row {
                        width: parent.width
                        spacing: 10
                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "memory"
                            font.pixelSize: 14
                            color: Theme.onSurfaceVariant
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Engine"
                            color: Theme.onSurfaceVariant
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 3
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: PxCfg.ParallaxBackend.models.length + " models cached"
                            color: Theme.onSurface
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 3
                        }
                    }
                    Text {
                        width: parent.width
                        text: "Mode: " + root.wallMode
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 3
                    }
                    Text {
                        width: parent.width
                        text: "Subject tier: " + PxCfg.Config.cutTier()
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 3
                    }
                    Text {
                        width: parent.width
                        text: "Layers: " + root.layerCount
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 3
                    }
                }
            }
        }
    }
}
