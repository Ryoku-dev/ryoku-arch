import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import "Singletons"
import "clock"
import "calendar"
import "music"
import "aio"
import "stats"
import "weather"
import "notes"
import Ryoku.PluginKit
import shell.services as Services
import "../depth"
import "../depth/Singletons" as DepthCfg
import "../parallax"
import "../parallax/Singletons" as ParallaxCfg
import "../visualizer"
import "../visualizer/Singletons" as VizCfg
import "../wallpaper" as WallpaperMod

// desktop widgets layer: WlrLayer.Bottom (below windows), instantiated once per
// monitor by the main shell, carrying the clock. only clicks on bare wallpaper
// land here, so windows above keep their input. drag = move (snaps to the
// fade-in grid), right-click a widget = its menu, right-click empty = global
// menu. every knob is live from Config; drag, menus and Ryoku Settings all
// write the same file, so surfaces retune with no reload.
Scope {
    id: root

    // the monitor this instance renders on, bound by the main shell per screen.
    property var screen
    // controller hook; the desktop layer defaults on.
    property bool active: true
    property string wallpaperUrl: ""
    property string wallpaperPath: ""
    property string wallpaperFit: "Cover"
    property string depthUrl: ""
    property var wallpaperTransition: null
    property string videoUrl: ""
    // The in-shell clip's audio, threaded from the wallpaper bridge to the
    // backdrop's player: muted by default, volume 0-100.
    property bool videoMuted: true
    property int videoVolume: 100
    // The ryogami-live yield flag (default "ryogami" engine): hide the painter
    // while the C player owns the background layer.
    property bool wallpaperLive: false
    Binding {
        target: ParallaxCfg.Config
        property: "activePath"
        value: root.wallpaperPath
    }

    // The parallax background surface (modules/parallax/ParallaxBackground.qml)
    // owns the screen's backdrop while its layers are cut for this wallpaper.
    readonly property bool parallaxOwns: ParallaxCfg.Config.enabled
        && ParallaxCfg.Config.wallActiveForPath(root.wallpaperPath)
        && root.videoUrl === "" && !root.wallpaperLive
    function widgetZ(id) {
        if (ParallaxCfg.Config.enabled && ParallaxCfg.Config.wallActiveForPath(root.wallpaperPath))
            return ParallaxCfg.Config.widgetZForPath(root.wallpaperPath, id);
        return DepthCfg.Config.isFront(id) ? 1 : 0;
    }
    readonly property var depthState: Services.ShellState.forScreen(root.screen)
    // compose mode frees every widget for dragging (like visualiser placement),
    // so a locked clock can still be nestled into the subject; Done restores it.
    readonly property bool depthComposing: root.depthState ? root.depthState.depthComposing : false
    // grab the keyboard while composing so Esc/Enter exit the mode (the bar owns
    // the keys); dropping it hands the keyboard back like any widget edit.
    onDepthComposingChanged: win.kbWanted += root.depthComposing ? 1 : -1
    readonly property bool reloadReady: readiness.ready

    ReloadReadiness {
        id: readiness
        width: win.width
        height: win.height
        configReady: Config.ready
        registryReady: Registry.ready
    }

    // Resolve the placement helper the way Registry resolves discover.sh: in a
    // dev run RYOKU_SHELL_DIR points at the shell tree and the tool is NOT on
    // PATH, so a bare "ryoku-plugins-place" Process silently no-ops and every
    // drag / resize / lock / hide / settings write is lost. Packaged installs
    // (no RYOKU_SHELL_DIR) ship it to /usr/bin, where the bare name resolves.
    readonly property string _shellDir: Quickshell.env("RYOKU_SHELL_DIR")
    readonly property string placeTool: (root._shellDir && root._shellDir.length > 0)
        ? root._shellDir + "/quickshell/plugins/ryoku-plugins-place"
        : "ryoku-plugins-place"

    // hand the keyboard back after a widget text field releases its grab. the
    // widget layer never unmaps, and dropping an exclusive grab on a mapped
    // layer strands the keyboard (the focused app can't type). this 1x1 helper
    // takes the grab and unmaps, which hands the keyboard to a real window.
    // same mechanism as the pill's kbBounce.
    property bool kbBounce: false
    function kbRestore() {
        root.kbBounce = true;
        kbBounceT.restart();
    }
    Timer {
        id: kbBounceT
        interval: 90
        onTriggered: root.kbBounce = false
    }
    PanelWindow {
        visible: root.kbBounce
        screen: root.screen
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "widgets-kbbounce"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; left: true }
    }

    PanelWindow {
        id: win

        screen: root.screen
        visible: root.active
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "ryoku-widgets"
        // None while nothing on this layer wants the keyboard, so this
        // full-screen Bottom layer never holds focus on an empty workspace
        // (which would otherwise leave the next-opened window unfocused).
        // A plugin tile's focused text field bumps `kbWanted`; the layer
        // then grabs the keyboard (the same exclusive grab the pill uses for
        // its launcher) so the field can be typed in, and releases it the
        // moment the field blurs. pointer input is unaffected either way -
        // layer-shell routes clicks by input region, not kb interactivity -
        // so drag and the right-click menu always fire.
        property int kbWanted: 0
        onKbWantedChanged: if (kbWanted === 0) root.kbRestore()
        WlrLayershell.keyboardFocus: kbWanted > 0 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors { top: true; left: true; right: true; bottom: true }

        // enabled desktopWidget-hosted plugins, filtered from the shared
        // Registry. drives the Repeater below so plugin tiles ride the
        // SAME wallpaper layer as the clock: one layer, one input
        // model, no second full-screen surface fighting for input.
        readonly property var desktopPlugins: Registry.plugins.filter(p => p.placement && p.placement.host === "desktopWidget")

        // current persisted desktopWidget block by id. menu handlers use
        // it to round-trip a partial change (lock/scale) without dropping
        // the other coordinates.
        function placementOf(id) {
            const p = win.desktopPlugins.find(pp => pp.id === id);
            return (p && p.placement && p.placement.desktopWidget) || {};
        }

        // the Repeater below is keyed by this id list, not by `desktopPlugins`
        // directly: any placement write (drag, resize, settings) rewrites
        // plugins.json and Registry reparses to a brand-new array, so binding
        // the Repeater to that array would tear down and rebuild every tile -
        // and its service - on every move, throwing away the open search and
        // page. the id list only changes when a plugin is enabled or
        // disabled, so moving a tile keeps its delegate and its live service.
        property var desktopPluginIds: []
        function syncDesktopIds() {
            const ids = win.desktopPlugins.map(p => p.id);
            const same = ids.length === win.desktopPluginIds.length
                && ids.every((id, i) => id === win.desktopPluginIds[i]);
            if (!same)
                win.desktopPluginIds = ids;
        }
        Component.onCompleted: win.syncDesktopIds()
        Connections {
            target: Registry
            function onPluginsChanged() { win.syncDesktopIds(); }
        }

        // the built-in slot currently being dragged (a single pointer, so at most
        // one), for the drag guides: their grid step and centre-snap lighting.
        readonly property var dragSlot: clockSlot.dragging ? clockSlot
            : calendarSlot.dragging ? calendarSlot
            : musicSlot.dragging ? musicSlot
            : aioSlot.dragging ? aioSlot
            : statsSlot.dragging ? statsSlot
            : weatherSlot.dragging ? weatherSlot
            : notesSlot.dragging ? notesSlot : null

        // on release, flash the slot's four edges plus the centre line it snapped
        // to (centre within half a grid step, the window the guides light up).
        function flashDrop(box) {
            const v = [box.x, box.x + box.width];
            const h = [box.y, box.y + box.height];
            const gs = guides.gridSize;
            if (Math.abs(box.x + box.width / 2 - guides.width / 2) < gs / 2)
                v.push(guides.width / 2);
            if (Math.abs(box.y + box.height / 2 - guides.height / 2) < gs / 2)
                h.push(guides.height / 2);
            guides.flash(v, h);
        }

        // The base wallpaper painter: the reveal backdrop composites each new
        // frame over the old one through the preset the daemon attached to the
        // frame (a GPU mask shader), decoding capped at surface resolution.
        // Live clips play inside this same surface (QtMultimedia + optional
        // interpolation), so the backdrop no longer yields to a second Wayland
        // client: it keeps the still decoded and swaps to the video itself.
        WallpaperMod.Backdrop {
            id: backdrop
            anchors.fill: parent
            // cava-bg model: while the parallax surface owns the background
            // layer, this window only carries widgets and chrome.
            visible: !root.parallaxOwns
            readonly property real screenDpr: (root.screen && root.screen.devicePixelRatio) ? root.screen.devicePixelRatio : 1
            dpr: screenDpr
            // Keep the still decoded while a video plays: the frame path is
            // always a paintable still now, and holding it means the reveal
            // off a video has its old texture instead of a black cut.
            url: root.wallpaperUrl
            fit: root.wallpaperFit
            transition: root.wallpaperTransition
            videoUrl: root.videoUrl
            live: root.wallpaperLive
            videoMuted: root.videoMuted
            videoVolume: root.videoVolume
        }

        // Mirror of the same image for glass widgets: Qt cannot sample another
        // scene graph, so ShaderEffectSource captures the pixels beneath a
        // frosted widget from this offscreen copy. WidgetGlass hides this
        // source after taking its crop. Hidden while a video plays: the glass
        // samples the still, and a live clip would freeze the capture.
        Image {
            id: glassBackdrop
            anchors.fill: parent
            source: root.wallpaperUrl
            cache: false
            asynchronous: true
            sourceSize.width: Math.ceil(width * backdrop.screenDpr)
            sourceSize.height: Math.ceil(height * backdrop.screenDpr)
            visible: root.videoUrl === "" && ((Config.calendarEnabled && Config.calendarStyle === "glass")
                || (Config.musicEnabled && Config.musicStyle === "glass"))
            fillMode: {
                switch (root.wallpaperFit) {
                case "Contain": return Image.PreserveAspectFit;
                case "Fill": return Image.Stretch;
                case "ScaleDown":
                    return sourceSize.width <= width && sourceSize.height <= height
                        ? Image.Pad : Image.PreserveAspectFit;
                default: return Image.PreserveAspectCrop;
                }
            }
        }

        // right-click empty desktop = global menu. sits behind the widgets
        // (which own their own right-click) and only takes RightButton, so
        // left-clicks on wallpaper fall through instead of being silently
        // swallowed.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onPressed: (mouse) => menu.openDesktop(mouse.x, mouse.y)
        }

        // click-off for the notes pad: while it holds the keyboard, a press on
        // the bare wallpaper must drop its focus (and the layer's exclusive
        // grab). taking active focus here blurs the pad; it sits above the
        // right-click catcher but below every widget, so a press on a widget
        // still reaches that widget, and it passes the event on (accepted =
        // false) so the right-click desktop menu still opens.
        MouseArea {
            id: notesBlur
            anchors.fill: parent
            enabled: notesSlot.editing
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (mouse) => { notesBlur.forceActiveFocus(); mouse.accepted = false; }
        }

        DesktopGuides {
            id: guides
            anchors.fill: parent
            active: win.dragSlot !== null
            gridSize: win.dragSlot ? win.dragSlot.gridSize : 32
            dragCentreX: win.dragSlot ? win.dragSlot.x + win.dragSlot.width / 2 : 0
            dragCentreY: win.dragSlot ? win.dragSlot.y + win.dragSlot.height / 2 : 0
        }

        WidgetSlot {
            id: clockSlot
            widget: "clock"
            z: root.widgetZ("clock")
            visible: root.reloadReady && Config.clockEnabled
            anchor: Config.clockAnchor
            freeX: Config.clockX
            freeY: Config.clockY
            locked: Config.clockLocked && !root.depthComposing
            bg: Config.clockBg
            radius: Config.clockRadius
            scaleCfg: Config.clockScale
            pad: Config.clockBg === "none" ? 0 : Math.round(24 * Config.clockScale)
            onMenuRequested: (x, y, w) => menu.openFor(w, x, y)
            onDropped: (box) => win.flashDrop(box)
            Clock {}
        }

        WidgetSlot {
            id: calendarSlot
            widget: "calendar"
            z: root.widgetZ("calendar")
            visible: root.reloadReady && Config.calendarEnabled
            anchor: Config.calendarAnchor
            freeX: Config.calendarX
            freeY: Config.calendarY
            locked: Config.calendarLocked && !root.depthComposing
            bg: "none"
            scaleCfg: Config.calendarScale
            onMenuRequested: (x, y, w) => menu.openFor(w, x, y)
            onDropped: (box) => win.flashDrop(box)
            CalendarWidget {
                style: Config.calendarStyle
                weeks: Config.calendarWeeks
                showWeekNumbers: Config.calendarWeekNumbers
                holidayRegion: Config.calendarHolidayRegion
                active: calendarSlot.visible
                s: Config.calendarScale
                wallpaperSource: glassBackdrop
                wallpaperRect: Qt.rect(calendarSlot.x, calendarSlot.y,
                    calendarSlot.width, calendarSlot.height)
            }
        }

        WidgetSlot {
            id: musicSlot
            widget: "music"
            z: root.widgetZ("music")
            visible: root.reloadReady && Config.musicEnabled
            anchor: Config.musicAnchor
            freeX: Config.musicX
            freeY: Config.musicY
            locked: Config.musicLocked && !root.depthComposing
            bg: "none"
            scaleCfg: Config.musicScale
            onMenuRequested: (x, y, w) => menu.openFor(w, x, y)
            onDropped: (box) => win.flashDrop(box)
            MusicWidget {
                style: Config.musicStyle
                showLyrics: Config.musicLyrics
                viz: Config.musicViz
                active: musicSlot.visible
                musicApp: Config.musicApp
                shape: Config.musicShape
                videoMode: Config.musicVideo
                videoFile: Config.musicVideoFile
                s: Config.musicScale
                wallpaperSource: glassBackdrop
                wallpaperRect: Qt.rect(musicSlot.x, musicSlot.y,
                    musicSlot.width, musicSlot.height)
            }
        }

        WidgetSlot {
            id: aioSlot
            widget: "aio"
            z: root.widgetZ("aio")
            visible: root.reloadReady && Config.aioEnabled
            anchor: Config.aioAnchor
            freeX: Config.aioX
            freeY: Config.aioY
            locked: Config.aioLocked && !root.depthComposing
            bg: "none"
            scaleCfg: Config.aioScale
            onMenuRequested: (x, y, w) => menu.openFor(w, x, y)
            onDropped: (box) => win.flashDrop(box)
            AioWidget {
                style: Config.aioStyle
                s: Config.aioScale
                active: aioSlot.visible
            }
        }

        WidgetSlot {
            id: statsSlot
            widget: "stats"
            z: root.widgetZ("stats")
            visible: root.reloadReady && Config.statsEnabled
            anchor: Config.statsAnchor
            freeX: Config.statsX
            freeY: Config.statsY
            locked: Config.statsLocked && !root.depthComposing
            bg: "none"
            scaleCfg: Config.statsScale
            onMenuRequested: (x, y, w) => menu.openFor(w, x, y)
            onDropped: (box) => win.flashDrop(box)
            StatsWidget {
                s: Config.statsScale
                active: statsSlot.visible
            }
        }

        WidgetSlot {
            id: weatherSlot
            widget: "weather"
            z: root.widgetZ("weather")
            visible: root.reloadReady && Config.weatherEnabled
            anchor: Config.weatherAnchor
            freeX: Config.weatherX
            freeY: Config.weatherY
            locked: Config.weatherLocked && !root.depthComposing
            bg: "none"
            scaleCfg: Config.weatherScale
            onMenuRequested: (x, y, w) => menu.openFor(w, x, y)
            onDropped: (box) => win.flashDrop(box)
            WeatherWidget {
                design: Config.weatherDesign
                s: Config.weatherScale
                active: weatherSlot.visible
            }
        }

        WidgetSlot {
            id: notesSlot
            widget: "notes"
            z: root.widgetZ("notes")
            visible: root.reloadReady && Config.notesEnabled
            anchor: Config.notesAnchor
            freeX: Config.notesX
            freeY: Config.notesY
            locked: Config.notesLocked && !root.depthComposing
            bg: "none"
            scaleCfg: Config.notesScale
            onMenuRequested: (x, y, w) => menu.openFor(w, x, y)
            onDropped: (box) => win.flashDrop(box)
            // notes is the first built-in editable widget: while its pad holds
            // focus the layer must grab the keyboard (bump kbWanted), and drop
            // the grab the instant it blurs, or the desktop is stranded.
            onEditingChanged: win.kbWanted += editing ? 1 : -1
            Component.onDestruction: if (editing) win.kbWanted -= 1
            NotesWidget {
                s: Config.notesScale
                active: notesSlot.visible
                wLogical: Config.notesWidth
                hLogical: Config.notesHeight
            }
        }

        // one draggable PluginDesktopSlot per enabled desktopWidget plugin.
        // drag = write free pos. resize bracket = write scale. right-click
        // = per-tile menu. each commit goes through its own Process so a
        // Lock right after a drag can't stomp an in-flight write on
        // `persist`.
        Repeater {
            model: win.desktopPluginIds
            delegate: PluginDesktopSlot {
                id: slot
                required property string modelData
                readonly property string pid: modelData
                // live registry entry for this id, re-resolved whenever
                // Registry reloads. placement (x/y/scale/bg) updates here
                // without rebuilding the delegate, because the model is the
                // stable id list, not the per-write plugin array.
                readonly property var entry: Registry.plugins.find(p => p.id === slot.pid) || null
                readonly property var dw: (entry && entry.placement && entry.placement.desktopWidget) || ({})
                readonly property string dir: entry ? entry.dir : ""
                readonly property string versionQuery: entry && entry.version
                    ? "?v=" + encodeURIComponent(entry.version) : ""

                pluginId: slot.pid
                visible: root.reloadReady
                locked: (slot.dw.locked === true) && !root.depthComposing
                scaleCfg: slot.dw.scale || 0.85
                freeX: slot.dw.x !== undefined ? slot.dw.x : 80
                freeY: slot.dw.y !== undefined ? slot.dw.y : 80
                bg: slot.dw.bg ? slot.dw.bg : ((entry && entry.manifest && entry.manifest.defaults && entry.manifest.defaults.desktopWidget && entry.manifest.defaults.desktopWidget.bg) || "card")
                radius: slot.dw.radius || 26

                onMoved: (x, y) => {
                    persist.command = [root.placeTool, slot.pid, "desktopWidget", "" + x, "" + y];
                    persist.running = true;
                }
                onResized: (sc) => {
                    const x = (slot.dw.x !== undefined) ? slot.dw.x : Math.round(slot.x);
                    const y = (slot.dw.y !== undefined) ? slot.dw.y : Math.round(slot.y);
                    const lk = (slot.dw.locked === true);
                    persist.command = [root.placeTool, slot.pid, "desktopWidget",
                        "" + x, "" + y, "" + sc, "" + lk];
                    persist.running = true;
                }
                onMenuRequested: (mx, my, id) => {
                    pluginMenu.openFor(id, slot.dw.locked === true, mx, my,
                        slot.entry ? slot.entry.manifest : null,
                        slot.entry ? slot.entry.placement : null);
                }

                // when the content exposes `editing` (a focused text field),
                // the wallpaper layer grabs the keyboard for as long as it
                // stays true. the flag falls back to false if the content is
                // ever torn down, so the grab can't leak.
                readonly property bool editing: !!(item && item.editing)
                onEditingChanged: win.kbWanted += editing ? 1 : -1
                Component.onDestruction: if (editing) win.kbWanted -= 1

                property var api: QtObject {
                    property var mainInstance: svc.item
                    property var pluginSettings: (slot.entry && slot.entry.placement && slot.entry.placement.settings) ? slot.entry.placement.settings : ({})
                    property string pluginDir: slot.dir
                    function saveSettings() {}
                    // host image viewer: a real click on a photo tile calls
                    // this to open a dimmed, full-desktop enlarged view of the
                    // image (see photoViewer). Closed by click-away or Esc.
                    function expandImage(url) { photoViewer.open(url); }
                }

                PluginObjectSlot {
                    id: svc
                    source: slot.dir.length > 0 ? "file://" + slot.dir + "/service/Main.qml" + slot.versionQuery : ""
                    configure: (service) => { service.pluginApi = slot.api; }
                }

                contentUrl: slot.dir.length > 0 ? "file://" + slot.dir + "/content/Widget.qml" + slot.versionQuery : ""
                configure: (it) => {
                    it.pluginApi = slot.api;
                    it.screen = win.screen;
                    it.density = "compact";
                    it.s = 1;
                    it.widthBudget = 360;
                    it.active = true;
                }
            }
        }
        // Bands live here so the scene order interleaves them with the
        // widgets; the drift follows the cursor the background polls.
            Repeater {
                id: parallaxBands
                // Gate on parallaxOwns so a video or live wallpaper that owns
                // the surface never renders stray bands over it.
                model: root.parallaxOwns ? ParallaxCfg.Config.layersForPath(root.wallpaperPath).length : 0
                delegate: ParallaxBand {
                    required property int index
                    anchors.fill: parent
                    layerIndex: index + 1
                    wallPath: root.wallpaperPath
                    url: ParallaxCfg.Config.layerUrlForPath(root.wallpaperPath, index + 1)
                    fit: root.wallpaperFit
                    z: ParallaxCfg.Config.sceneZForPath(root.wallpaperPath, "layer:" + (index + 1))
                    mouseNX: ParallaxCfg.Config.cursorNXFor(root.screen.name)
                    mouseNY: ParallaxCfg.Config.cursorNYFor(root.screen.name)
                    energy: VizCfg.Spectrum.energy
                }
            }

        Item {
            id: inlineViz
            anchors.fill: parent
            z: ParallaxCfg.Config.sceneZForPath(root.wallpaperPath, "visualizer")
            visible: root.parallaxOwns && VizCfg.Config.enabled
            InlineVisualizer {
                anchors.fill: parent
            }
        }

        // the wallpaper's subject, drawn in front of the widgets: above the
        // slots (declared later), below the menus and the photo viewer.
        DepthForeground {
            anchors.fill: parent
            url: root.depthUrl
            fit: root.wallpaperFit
            composing: root.depthState ? root.depthState.depthComposing : false
        }

        WidgetMenu { id: menu }

        // per-tile right-click menu, hoisted to PanelWindow level so the
        // click-away catcher covers the whole desktop and a tile that
        // vanishes (Hide) doesn't pull the menu down with it.
        PluginWidgetMenu {
            id: pluginMenu
            onHideRequested: (id) => {
                hide.command = [root.placeTool, id, "enabled", "false"];
                hide.running = true;
                pluginMenu.close();
            }
            onLockToggled: (id) => {
                const dw = win.placementOf(id);
                const x = (dw.x !== undefined) ? dw.x : 80;
                const y = (dw.y !== undefined) ? dw.y : 80;
                const sc = (dw.scale !== undefined) ? dw.scale : 1;
                const lk = !(dw.locked === true);
                lockProc.command = [root.placeTool, id, "desktopWidget",
                    "" + x, "" + y, "" + sc, "" + lk];
                lockProc.running = true;
            }
            onSettingChanged: (id, key, value) => {
                var obj = {};
                obj[key] = value;
                settingsProc.command = [root.placeTool, id, "settings", JSON.stringify(obj)];
                settingsProc.running = true;
            }
        }

        // Shared image viewer for desktop plugin tiles. A tile (e.g. Photo
        // Frame) calls pluginApi.expandImage(url) on a real click; this dims the
        // whole desktop and shows that image large + centered
        // (PreserveAspectFit, capped per axis at min(85% of the screen, the
        // image's own size) so small photos never upscale). Any click on the
        // scrim or the photo, or Esc, closes it. It rides this same wallpaper
        // layer, so it sits above the tiles as a full-desktop overlay.
        Item {
            id: photoViewer
            anchors.fill: parent
            z: 100

            // the image being shown; empty = closed.
            property url src: ""
            // `src` is a url: `src !== ""` is always true for an empty url (strict
            // type mismatch against a string), which opened the viewer on boot and
            // stranded kbWanted (an exclusive keyboard grab). Test length, as open() does.
            readonly property bool shown: String(photoViewer.src).length > 0

            visible: opacity > 0
            opacity: photoViewer.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

            function open(url) { if (url && String(url).length > 0) photoViewer.src = url; }
            function close() { photoViewer.src = ""; }

            // Esc closes. The wallpaper layer only holds the keyboard while
            // something wants it (kbWanted), so bump it exactly like a focused
            // plugin text field and take active focus while shown.
            Keys.onEscapePressed: photoViewer.close()
            onShownChanged: {
                win.kbWanted += photoViewer.shown ? 1 : -1;
                if (photoViewer.shown)
                    photoViewer.forceActiveFocus();
            }
            Component.onDestruction: if (photoViewer.shown) win.kbWanted -= 1

            // dim scrim + click-away. Accepts both buttons so a click or
            // right-click anywhere closes, instead of falling through to a tile
            // or the global desktop menu behind it.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.78)
            }
            MouseArea {
                anchors.fill: parent
                enabled: photoViewer.shown
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: photoViewer.close()
            }

            // the enlarged print: rounded-clipped to match the tile aesthetic.
            // clicks fall through it to the MouseArea above, so tapping the photo
            // closes too.
            ClippingRectangle {
                anchors.centerIn: parent
                radius: Theme.radiusWidget
                color: "transparent"
                width: big.paintedWidth
                height: big.paintedHeight

                Image {
                    id: big
                    anchors.centerIn: parent
                    source: photoViewer.src
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                    width: implicitWidth > 0 ? Math.min(photoViewer.width * 0.85, implicitWidth) : photoViewer.width * 0.85
                    height: implicitHeight > 0 ? Math.min(photoViewer.height * 0.85, implicitHeight) : photoViewer.height * 0.85
                }
            }
        }
        // the depth composing toolbar; the clock is placed with the ordinary
        // widget drag while this carries the few depth knobs.
        DepthEditBar {
            z: 101
            visible: root.depthState ? root.depthState.depthComposing : false
            onDone: if (root.depthState)
                root.depthState.depthComposing = false
        }

        // position/scale writeback for plugin tiles. ryoku-plugins-place
        // merges free x/y (+ optional scale/locked) into plugins.json;
        // Registry's file-watch then retunes every surface.
        Process { id: persist }
        // separate Processes per menu action so a quick Hide-then-Lock or
        // resize-then-Lock doesn't trample an in-flight `persist` command.
        Process { id: hide }
        Process { id: lockProc }
        // settings writeback from the right-click menu.
        Process { id: settingsProc }
    }
}
