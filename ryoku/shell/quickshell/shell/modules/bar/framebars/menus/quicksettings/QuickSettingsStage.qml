pragma ComponentBehavior: Bound

import QtQuick
import shell.services
import "../../../../stage"
import "../../../../stage/Singletons" as St
import "../../../../visualizer/Singletons" as VizCfg
import "../../../../desktop/Singletons" as DesktopCfg
import Ryoku.Ui.Singletons

// Stage tab of the Super+Esc quick-settings panel (docs/stage.md). Three levels:
// Effect (Off / Subject in front / Parallax) with a live preview, Look (quality,
// edge fade, strength, shadow) that every layer inherits, and a collapsed Scene
// holding the layer list, cast order, presets and maintenance. Status and render
// state come from the daemon `stage` topic through StageBackend; nothing polls.
Item {
    id: root

    property real s: 1
    property bool open: false
    property var navigate: null
    property var closePanel: null

    readonly property var sb: St.StageBackend
    readonly property var cfg: St.Config

    readonly property bool checked: root.sb.checked
    readonly property bool ready: root.sb.available
    readonly property bool installing: root.sb.installing
    readonly property string effect: root.sb.effect
    readonly property string wall: root.sb.current
    readonly property int layerCount: root.sb.layerCount
    readonly property bool busy: root.sb.busy
    readonly property bool isParallax: root.effect === "parallax"
    readonly property bool manualMode: root.sb.mode === "manual"
    readonly property string quality: root.cfg.quality

    property bool sceneExpanded: false
    property string expandedLayer: ""
    property string activePreset: root.cfg.preset

    // Model the selected quality tier requires, for the download / footnote.
    readonly property var qModel: root.sb.modelForQuality(root.quality)
    readonly property bool qInstalled: !!(root.qModel && root.qModel.installed === true)

    function editStage() {
        const st = ShellState.forActive();
        if (st)
            st.stageComposing = true;
        if (root.closePanel)
            root.closePanel();
    }

    function setEffect(id) {
        root.sb.setEffect(id);
    }
    function setQuality(id) {
        root.cfg.setQuality(id);
        if (root.sb.qualityInstalled(id) && root.effect !== "off")
            root.sb.refresh();
    }

    // Presets tune every layer at once through set-layer; None re-inherits the
    // global look (null feather/lift/shadow) and clears the extras.
    function applyPreset(id) {
        root.activePreset = id;
        root.cfg.setPreset(id);
        const n = root.layerCount;
        for (var i = 0; i < n; i++) {
            const t = n <= 1 ? 0.5 : i / (n - 1);
            var k;
            switch (id) {
            case "softdepth":
                k = { parallax: 1 - t * 0.4, depthFactor: 0.2 + t * 0.8, audioLevel: 0, animAmplitude: 4, animSpeed: 0.4, feather: 0, lift: 0.1 + t * 0.3, animType: "float", shadow: 0 };
                break;
            case "audiopulse":
                k = { parallax: 0.9, depthFactor: 0.5, audioLevel: 0.6, animAmplitude: 8, animSpeed: 0.8, feather: 0.1, lift: 0.3, animType: "float", shadow: 0 };
                break;
            case "cinematic":
                k = { parallax: 1.4 - t * 0.4, depthFactor: 0.3 + t * 0.4, audioLevel: 0.15, animAmplitude: 16, animSpeed: 0.15, feather: 0.2, lift: 0.5, animType: "float", shadow: 0.5 };
                break;
            default: // none
                k = { parallax: 1, depthFactor: 0.5, audioLevel: 0, animAmplitude: 10, animSpeed: 0.5, feather: null, lift: null, shadow: null, shadowAngle: null, animType: "none", opacity: 1, offsetX: 0, offsetY: 0, mouseMax: 32, enabled: true };
                break;
            }
            root.sb.setLayer(i, k);
        }
    }

    // Cast order, front-first (highest scene z first), for the movers.
    property var sceneRows: []
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
    function _rowShown(id) {
        if (id === "wallpaper") return false;
        if (id === "visualizer") return VizCfg.Config.enabled;
        if (id.indexOf("layer:") === 0) return true;
        if (id.indexOf("widget:") === 0) return root.widgetOn(id.slice(7));
        return false;
    }
    function rebuildScene() {
        const names = { clock: I18n.tr("Clock"), calendar: I18n.tr("Calendar"), music: I18n.tr("Music"), aio: "AIO", stats: I18n.tr("Stats"), weather: I18n.tr("Weather"), notes: I18n.tr("Notes") };
        const rows = [];
        const scene = root.sb.effectiveSceneFor(root.wall);
        for (let k = scene.length - 1; k >= 0; k--) {
            const id = scene[k];
            if (!root._rowShown(id)) continue;
            if (id.indexOf("layer:") === 0) {
                const li = parseInt(id.slice(6)) - 1;
                const lbl = root.sb.layerLabel(root.wall, li).toLowerCase();
                rows.push({ id: id, label: root.sb.layerLabel(root.wall, li), icon: lbl.indexOf("subject") === 0 ? "person" : "layers", movable: true });
            } else if (id === "visualizer") {
                rows.push({ id: id, label: I18n.tr("Visualizer"), icon: "graphic_eq", movable: true });
            } else {
                const w = id.slice(7);
                rows.push({ id: id, label: names[w] || w, icon: "widgets", movable: true });
            }
        }
        root.sceneRows = rows;
    }
    function moveOrder(id, dir) {
        const scene = root.sb.effectiveSceneFor(root.wall).slice();
        const shown = [];
        for (let k = 0; k < scene.length; k++)
            if (root._rowShown(scene[k])) shown.push(k);
        const pos = shown.indexOf(scene.indexOf(id));
        const tpos = pos + dir;
        if (pos < 0 || tpos < 0 || tpos >= shown.length) return;
        const a = shown[pos], b = shown[tpos];
        const tmp = scene[a]; scene[a] = scene[b]; scene[b] = tmp;
        root.sb.setScene(scene);
        root.rebuildScene();
    }

    Connections {
        target: root.sb
        function onFrameChanged() { root.rebuildScene(); }
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
                    text: I18n.tr("Stage")
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: I18n.tr("The desktop as a stage: lift your wallpaper's subject in front of the widgets, or drift the whole scene with the cursor.")
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                }
            }

            // ── 1. Effect ─────────────────────────────────────────────
            StageSection { title: I18n.tr("Effect") }
            StageSeg {
                options: [
                    { id: "off", label: I18n.tr("Off") },
                    { id: "subject", label: I18n.tr("Subject in front") },
                    { id: "parallax", label: I18n.tr("Parallax") }
                ]
                current: root.effect
                onChose: id => root.setEffect(id)
            }
            Text {
                width: parent.width
                visible: !root.checked
                text: I18n.tr("Preparing engine…")
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
            }
            StageNavRow {
                width: parent.width
                visible: root.checked && !root.ready
                icon: "download"
                label: root.installing ? I18n.tr("Installing engine…") : I18n.tr("Install engine")
                sub: root.installing ? root.sb.progress : I18n.tr("A one-time on-device download to detect subjects.")
                onActivated: if (!root.installing) root.sb.install("")
            }

            // Live preview of the current wallpaper's cut.
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
                    running: preview.visible && root.isParallax && !root.busy
                    onTriggered: preview.demoT += 50
                }
                readonly property real demoNX: root.isParallax ? Math.sin(preview.demoT / 900) : 0
                readonly property real demoNY: root.isParallax ? Math.cos(preview.demoT / 1100) : 0

                Repeater {
                    model: root.layerCount
                    delegate: Item {
                        id: pvLayer
                        required property int index
                        anchors.fill: parent
                        z: root.sb.sceneZFor(root.wall, "layer:" + (pvLayer.index + 1))
                        visible: root.sb.layerEnabled(root.wall, pvLayer.index)
                        Image {
                            anchors.fill: parent
                            source: root.sb.layerUrlFor(root.wall, pvLayer.index)
                            cache: false
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            opacity: status === Image.Ready ? root.sb.layerOpacity(root.wall, pvLayer.index) : 0
                            transform: Translate {
                                x: preview.demoNX * 9 * root.sb.layerParallax(root.wall, pvLayer.index) * (0.4 + root.sb.layerDepthFactor(root.wall, pvLayer.index) * 1.2)
                                    + root.sb.layerOffsetX(root.wall, pvLayer.index) / 10
                                y: preview.demoNY * 9 * root.sb.layerParallax(root.wall, pvLayer.index) * (0.4 + root.sb.layerDepthFactor(root.wall, pvLayer.index) * 1.2)
                                    + root.sb.layerOffsetY(root.wall, pvLayer.index) / 10
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.checked && root.layerCount === 0 && !root.busy
                    text: root.ready ? I18n.tr("Turn on an effect to cut your subject.") : I18n.tr("Install the engine to detect your subject.")
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
                    visible: root.busy
                    Text {
                        text: root.sb.stage.length > 0 ? I18n.tr("Cutting the subject… (%1)").arg(root.sb.stage) : I18n.tr("Cutting the subject…")
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 1
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Row {
                        width: parent.width
                        spacing: 8
                        Rectangle {
                            width: parent.width - 100
                            height: 4
                            radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                radius: 2
                                color: Theme.primary
                                width: Math.max(0, Math.min(parent.width, parent.width * (root.sb.percent / 100)))
                                Behavior on width { NumberAnimation { duration: Motion.crossfade } }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.sb.percent + "%"
                            color: Theme.onSurfaceVariant
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 3
                            width: 34
                        }
                        StageBtn {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56
                            height: 26
                            kind: "outlined"
                            label: I18n.tr("Stop")
                            onAct: root.sb.cancel()
                        }
                    }
                }
            }

            // ── 2. Look ───────────────────────────────────────────────
            Item {
                width: parent.width
                visible: root.checked && root.ready
                implicitHeight: look.implicitHeight
                Column {
                    id: look
                    width: parent.width
                    spacing: 12

                    StageSection { title: I18n.tr("Look") }
                    StageField {
                        title: I18n.tr("Quality")
                        hint: I18n.tr("Higher detail traces hair and fine edges, but the cut takes longer.")
                        choices: [
                            { id: "draft", label: I18n.tr("Draft") },
                            { id: "standard", label: I18n.tr("Standard") },
                            { id: "fine", label: I18n.tr("Fine") }
                        ]
                        current: root.quality
                        onChose: id => root.setQuality(id)
                    }
                    StageNavRow {
                        width: parent.width
                        visible: !root.qInstalled && root.qModel !== null
                        icon: "download"
                        label: root.installing ? I18n.tr("Downloading…") : I18n.tr("Download %1 model").arg(root.qModel ? I18n.tr(root.qModel.label) : "")
                        sub: root.installing ? root.sb.progress : (root.qModel ? I18n.tr("One-time download (%1).").arg(root.qModel.size) : "")
                        onActivated: if (!root.installing && root.qModel) root.sb.install(root.qModel.id)
                    }
                    StageBtn {
                        visible: root.qInstalled && root.qModel !== null && root.qModel.tier === "fine"
                        kind: "outlined"
                        icon: "delete"
                        label: root.sb.removing ? I18n.tr("Removing…") : I18n.tr("Remove the Fine model")
                        enabledAct: !root.sb.removing && !root.installing
                        onAct: if (root.qModel) root.sb.remove(root.qModel.id)
                    }
                    Text {
                        width: parent.width
                        visible: root.qModel !== null
                        text: root.qModel ? (root.qModel.licence + " · " + root.qModel.upstream) : ""
                        wrapMode: Text.WrapAnywhere
                        color: Qt.rgba(Theme.onSurfaceVariant.r, Theme.onSurfaceVariant.g, Theme.onSurfaceVariant.b, 0.8)
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 4
                    }

                    StageDragSlider {
                        title: I18n.tr("Edge fade")
                        value: root.cfg.feather
                        min: 0; max: 1; decimals: 2
                        onChanged: v => root.cfg.setFeather(v)
                    }
                    StageDragSlider {
                        title: I18n.tr("Strength")
                        value: root.cfg.lift
                        min: 0.2; max: 1; decimals: 2
                        onChanged: v => root.cfg.setLift(v)
                    }
                    StageDragSlider {
                        title: I18n.tr("Shadow")
                        value: root.cfg.shadow
                        min: 0; max: 1; decimals: 2
                        onChanged: v => root.cfg.setShadow(v)
                    }
                    Row {
                        width: parent.width
                        spacing: 12
                        StageAngleDial {
                            angle: root.cfg.shadowAngle
                            onChanged: deg => root.cfg.setShadowAngle(deg)
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 84 - 12
                            spacing: 2
                            Text {
                                text: I18n.tr("Shadow angle")
                                color: Theme.onSurface
                                font.family: Theme.fontPrimary
                                font.pixelSize: Theme.fontSm - 1
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: I18n.tr("%1\u00B0 - Drag the dot to set where the shadow falls.").arg(root.cfg.shadowAngle)
                                wrapMode: Text.WordWrap
                                color: Theme.onSurfaceVariant
                                font.family: Theme.fontPrimary
                                font.pixelSize: Theme.fontSm - 3
                                width: parent.width
                            }
                        }
                    }
                }
            }

            // ── 3. Scene (collapsed by default) ───────────────────────
            StagePanelHeader {
                width: parent.width
                visible: root.checked && root.ready
                icon: "layers"
                label: I18n.tr("Scene")
                expanded: root.sceneExpanded
                onToggle: root.sceneExpanded = !root.sceneExpanded
            }
            Column {
                width: parent.width
                spacing: 12
                visible: root.sceneExpanded && root.checked && root.ready

                StageField {
                    visible: root.isParallax
                    title: I18n.tr("Cutout source")
                    hint: I18n.tr("Auto cuts the subject and recolours the hole. Manual uses the numbered PNGs you drop in the wallpaper's folder.")
                    choices: [
                        { id: "auto", label: I18n.tr("Auto (subject)") },
                        { id: "manual", label: I18n.tr("Manual (numbered)") }
                    ]
                    current: root.sb.mode
                    onChose: id => root.sb.setMode(id)
                }
                Row {
                    width: parent.width
                    spacing: 8
                    visible: root.isParallax && root.manualMode
                    StageBtn {
                        width: (parent.width - 8) / 2
                        kind: "filled"
                        icon: "folder_open"
                        label: I18n.tr("Open folder")
                        onAct: root.sb.openFolder(root.wall)
                    }
                    StageBtn {
                        width: (parent.width - 8) / 2
                        kind: "outlined"
                        icon: "cached"
                        label: I18n.tr("Rescan")
                        onAct: root.sb.refresh()
                    }
                }

                // Cast order.
                StageSection { title: I18n.tr("Cast order") }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: I18n.tr("The on-screen stack, front first. Move any row to sit it in front of or behind a layer.")
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 3
                }
                Repeater {
                    model: root.sceneRows.length
                    delegate: StageSceneRow {
                        required property int index
                        rowData: root.sceneRows[index]
                        rowIndex: index
                        rowCount: root.sceneRows.length
                        onMove: (id, dir) => root.moveOrder(id, dir)
                    }
                }
                StageBtn {
                    kind: "ghost"
                    icon: "restart_alt"
                    label: I18n.tr("Reset order")
                    onAct: { root.sb.setScene([]); root.rebuildScene(); }
                }

                // Per-layer knobs.
                StageSection { title: I18n.tr("Layers") }
                Text {
                    width: parent.width
                    visible: root.layerCount === 0
                    wrapMode: Text.WordWrap
                    text: I18n.tr("No layers yet. Turn on an effect to cut the subject.")
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 3
                }
                Repeater {
                    model: root.layerCount
                    delegate: StageLayerEditor {
                        required property int index
                        wallPath: root.wall
                        slot: index
                        removable: root.manualMode
                        expanded: root.expandedLayer === "layer:" + index
                        onToggle: root.expandedLayer = root.expandedLayer === "layer:" + index ? "" : "layer:" + index
                        onRemove: root.sb.removeLayer(root.sb.layerOut(root.wall, index))
                    }
                }

                // Presets.
                StageSection { title: I18n.tr("Presets") }
                StageField {
                    title: I18n.tr("Preset")
                    hint: I18n.tr("Applies a tuning to every layer at once. None restores the defaults.")
                    choices: [
                        { id: "none", label: I18n.tr("None") },
                        { id: "softdepth", label: I18n.tr("Soft Depth") },
                        { id: "audiopulse", label: I18n.tr("Audio Pulse") },
                        { id: "cinematic", label: I18n.tr("Cinematic") }
                    ]
                    current: root.activePreset
                    onChose: id => root.applyPreset(id)
                }

                // Maintenance.
                StageSection { title: I18n.tr("Arrange & maintain") }
                StageBtn {
                    kind: "filled"
                    icon: "open_with"
                    label: I18n.tr("Edit stage")
                    onAct: root.editStage()
                }
                StageBtn {
                    kind: "ghost"
                    icon: "folder_open"
                    label: I18n.tr("Open folder")
                    onAct: root.sb.openFolder(root.wall)
                }
                StageBtn {
                    kind: "outlined"
                    icon: "cached"
                    label: I18n.tr("Re-cut")
                    enabledAct: root.ready && !root.busy
                    onAct: root.sb.refresh()
                }
                StageBtn {
                    kind: "ghost"
                    icon: "delete_sweep"
                    label: I18n.tr("Clear cache")
                    onAct: root.sb.clear()
                }
            }
        }
    }
}
