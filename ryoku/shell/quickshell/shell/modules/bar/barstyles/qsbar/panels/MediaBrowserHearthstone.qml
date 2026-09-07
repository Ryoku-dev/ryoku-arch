import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "ImagePickerModel.js" as Model
import Ryoku.Ui.Singletons

// Hearthstone (card-deck) variant of the screenshot/video browser. Original felt
// look + fanned cards on the same fast data layer as the Tanzaku media browser
// (cached thumbnails, niced pre-warm, delete/copy). Active only while
// pickerStyle == "hearthstone".
PanelWindow {
    id: panel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-media-browser-hs"
    WlrLayershell.keyboardFocus: panel.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool active: root.pickerStyle === "hearthstone"
    readonly property bool isVideos: root.mediaBrowserMode === "videos"
    readonly property bool ready: root.mediaBrowserVisible && active && loaded && layoutSettled

    property bool loaded:        false
    property bool layoutSettled: false
    property bool closing:       false
    property int  thumbEpoch:    0
    property var  imageArray:    []
    property int  selFilt:       0
    property string filterText:  ""

    visible: root.mediaBrowserVisible && active

    // ── reveal + deal ──
    property real reveal: 0
    Behavior on reveal { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    property real dealT: 0
    Behavior on dealT { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    onReadyChanged: { reveal = ready ? 1 : 0; if (ready) dealT = 1 }

    // ── filtered list ──
    readonly property var filtered: {
        var out = []
        for (var i = 0; i < imageArray.length; i++) {
            if (!Model.itemMatches(imageArray, i, filterText)) continue
            out.push({
                idx:      i,
                filePath: imageArray[i].filePath,
                thumbnailPath: imageArray[i].thumbnailPath,
                label:    panel.mediaLabel(imageArray[i].filePath),
                isVideo:  panel.isVideos
            })
        }
        return out
    }
    onFilteredChanged: if (selFilt >= filtered.length) selFilt = Math.max(0, filtered.length - 1)

    readonly property string currentLabel:
        (filtered.length > 0 && selFilt >= 0 && selFilt < filtered.length)
            ? I18n.tr(filtered[selFilt].label)
            : (filterText ? I18n.tr("No matches") : "")

    // ── open / style gating ──
    function releaseClosedState() {
        panel.closing = true
        cacheProc.running = false
        scanProc.running = false
        warmTimer.stop()
        warmProc.running = false
        panel.loaded        = false
        panel.layoutSettled = false
        panel.filterText    = ""
        panel.imageArray    = []
        panel.selFilt       = 0
        panel.reveal        = 0
        panel.dealT         = 0
    }
    function syncOpen() {
        if (root.mediaBrowserVisible && active) {
            panel.closing = false
            if (!loaded) {
                panel.layoutSettled = false
                panel.filterText    = ""
                panel.imageArray    = []
                panel.selFilt       = 0
                panel.reveal        = 0
                panel.dealT         = 0
                panel.runScan()
            }
        } else {
            panel.releaseClosedState()
        }
    }
    Connections {
        target: root
        function onMediaBrowserVisibleChanged() { panel.syncOpen() }
        function onPickerStyleChanged()          { panel.syncOpen() }
    }
    Component.onCompleted: panel.syncOpen()

    function buildScanCmd() {
        if (isVideos) {
            return ["bash", "-c",
                "D=\"${RYOKU_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings}\"; " +
                "find \"$D\" -maxdepth 1 -type f " +
                "\\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.avi' -o -iname '*.m4v' \\) " +
                "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -100 | cut -f2- | " +
                "while IFS= read -r f; do b=$(basename \"$f\"); printf '%s\\t%s/%s-512.jpg\\n' \"$f\" \"$HOME/.cache/quickshell-media-thumbs\" \"${b%.*}\"; done"]
        } else {
            return ["bash", "-c",
                "D=\"${RYOKU_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots}\"; " +
                "find \"$D\" -maxdepth 1 -type f -iname '*.png' " +
                "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -100 | cut -f2- | " +
                "while IFS= read -r f; do k=$(printf '%s' \"$f\" | md5sum | cut -d' ' -f1); m=$(stat -c %Y \"$f\" 2>/dev/null); printf '%s\\t%s/%s-%s-512.jpg\\n' \"$f\" \"$HOME/.cache/quickshell-img-thumbs\" \"$k\" \"$m\"; done"]
        }
    }

    // scan-result cache → instant (re)open (shared with the Tanzaku media browser)
    readonly property string scanCachePath: Quickshell.env("HOME") + "/.cache/quickshell-scan-" + (isVideos ? "videos" : "screenshots")
    property string _lastScan: ""
    function liveScanCmd() { var c = panel.buildScanCmd(); c[2] = c[2] + " | tee " + panel.shq(panel.scanCachePath); return c }
    function runScan() {
        cacheProc.running = false; cacheProc.running = true
        scanProc.command = panel.liveScanCmd(); scanProc.running = false; scanProc.running = true
    }
    Process {
        id: cacheProc
        command: ["cat", panel.scanCachePath]
        stdout: StdioCollector { onStreamFinished: panel.applyScan(this.text, true) }
    }
    function applyScan(text, fromCache) {
        if (!root.mediaBrowserVisible || !panel.active) return
        var t = String(text || "")
        if (fromCache && (!t.trim() || loaded)) return
        if (!fromCache && t.trim() === _lastScan.trim() && loaded) {
            warmTimer.restart()
            return
        }
        _lastScan = t
        var rows = Model.loadRows(t)
        panel.imageArray = rows
        panel.selFilt    = 0
        panel.loaded     = rows.length > 0
        Qt.callLater(function() {
            if (root.mediaBrowserVisible && panel.active) {
                panel.layoutSettled = true
                if (panel.imageArray.length > 0) hand.forceActiveFocus()   // keep Esc-catcher focused when empty
                if (!fromCache) warmTimer.restart()
            }
        })
    }
    Process {
        id: scanProc
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.applyScan(text, false)
        }
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function cancellableCommand(body, argv0, args) {
        return ["bash", "-c",
            "body=$1; shift; setsid bash -c \"$body\" worker \"$@\" & worker=$!; " +
            "cleanup() { pkill -TERM -s \"$worker\" 2>/dev/null || true; sleep 0.2; pkill -KILL -s \"$worker\" 2>/dev/null || true; }; " +
            "trap 'cleanup; exit 143' TERM INT; wait \"$worker\"",
            argv0 || "manager", body].concat(args || [])
    }

    // ── background pre-warm (nice; after open settles) ──
    Process {
        id: warmProc
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (this.text.trim() && root.mediaBrowserVisible && panel.active)
                panel.thumbEpoch++
        }
    }
    Timer { id: warmTimer; interval: 450; onTriggered: panel.warmAll() }
    function warmAll() {
        var srcs = []
        for (var i = 0; i < imageArray.length; i++)
            if (imageArray[i].filePath) srcs.push(imageArray[i].filePath)
        if (srcs.length === 0) return
        if (panel.isVideos) {
            warmProc.command = panel.cancellableCommand(
                "d=$HOME/.cache/quickshell-media-thumbs; mkdir -p \"$d\"; command -v ffmpegthumbnailer >/dev/null 2>&1 || exit 0; " +
                "tmp=$(mktemp); trap 'rm -f \"$tmp\"' EXIT; " +
                "for s in \"$@\"; do b=$(basename \"$s\"); o=\"$d/${b%.*}-512.jpg\"; [ -s \"$o\" ] && continue; printf '%s\\n%s\\n' \"$s\" \"$o\" >> \"$tmp\"; done; " +
                "if [ -s \"$tmp\" ]; then nice -n 19 xargs -r -d '\\n' -P 2 -n 2 sh -c 'ffmpegthumbnailer -i \"$0\" -o \"$1\" -s 910 -q 6 >/dev/null 2>&1 || true' < \"$tmp\"; made=0; while IFS= read -r _src && IFS= read -r out; do [ -s \"$out\" ] && { made=1; break; }; done < \"$tmp\"; [ \"$made\" -eq 1 ] && echo changed; fi",
                "warm", srcs)
        } else {
            warmProc.command = panel.cancellableCommand(
                "D=$HOME/.cache/quickshell-img-thumbs; mkdir -p \"$D\"; command -v magick >/dev/null 2>&1 || exit 0; " +
                "tmp=$(mktemp); trap 'rm -f \"$tmp\"' EXIT; " +
                "for s in \"$@\"; do k=$(printf '%s' \"$s\" | md5sum | cut -d' ' -f1); m=$(stat -c %Y \"$s\" 2>/dev/null); " +
                "o=\"$D/$k-$m-512.jpg\"; [ -s \"$o\" ] && continue; printf '%s\\n%s\\n' \"$s\" \"$o\" >> \"$tmp\"; done; " +
                "if [ -s \"$tmp\" ]; then nice -n 19 xargs -r -d '\\n' -P 3 -n 2 sh -c 'magick \"$0\" -auto-orient -strip -thumbnail 512x512^ -quality 82 \"$1\" >/dev/null 2>&1' < \"$tmp\"; made=0; while IFS= read -r _src && IFS= read -r out; do [ -s \"$out\" ] && { made=1; break; }; done < \"$tmp\"; [ \"$made\" -eq 1 ] && echo changed; fi",
                "warm", srcs)
        }
        warmProc.running = false; warmProc.running = true
    }

    function openSelected() {
        if (!loaded || filtered.length === 0) return
        if (selFilt < 0 || selFilt >= filtered.length) return
        var path = filtered[selFilt].filePath; if (!path) return
        Spawn.run(["xdg-open", path])
        root.mediaBrowserVisible = false
    }

    function moveSel(delta) {
        if (filtered.length === 0) return
        selFilt = Math.max(0, Math.min(filtered.length - 1, selFilt + delta))
    }

    readonly property var sel: (filtered.length > 0 && selFilt >= 0 && selFilt < filtered.length)
                               ? filtered[selFilt] : null

    // ── delete (two-step confirm) + copy ──
    property bool confirmDelete: false
    onSelFiltChanged: confirmDelete = false

    Process {
        id: deleteProc
        command: []
        onExited: function(code) {       // rescan only on success; on trash failure keep the file + warn (no silent rm)
            if (code !== 0) { console.warn("MediaBrowser: trash failed (gio/trash-put unavailable) - file KEPT, not deleted"); return }
            scanProc.command = panel.liveScanCmd()
            scanProc.running = false; scanProc.running = true
        }
    }
    function deleteFocused() {
        if (!sel || !sel.filePath) return
        deleteProc.command = ["bash", "-c", "f=" + shq(sel.filePath) + "; gio trash -- \"$f\" 2>/dev/null || trash-put -- \"$f\" 2>/dev/null"]
        deleteProc.running = false; deleteProc.running = true
        confirmDelete = false
    }

    Process { id: copyProc; command: [] }
    function copyFocused() {
        if (!sel || !sel.filePath) return
        copyProc.command = panel.isVideos
            ? ["bash", "-c", "printf '%s' " + shq(sel.filePath) + " | wl-copy"]
            : ["bash", "-c", "wl-copy --type image/png < " + shq(sel.filePath)]
        copyProc.running = false; copyProc.running = true
    }

    function mediaLabel(path) {
        var n = String(path || "").split("/").pop().replace(/\.[^.]+$/, "")
        var m = n.match(/(\d{4})-(\d{2})-(\d{2})[_-](\d{2})-(\d{2})-(\d{2})/)
        return m ? (m[1] + "-" + m[2] + "-" + m[3] + "  " + m[4] + ":" + m[5]) : n
    }

    // ── card-hand geometry ──
    readonly property int  cardW:      232
    readonly property int  cardH:      330
    readonly property real focusScale: 1.24
    readonly property real spreadDeg:  6.0
    readonly property real stepX:      128
    readonly property real focusLift:  54
    readonly property int  maxVisible: 5

    // ── felt look ──
    readonly property color feltColor: Qt.rgba(0.035, 0.035, 0.05, 0.975)
    readonly property color frameDark: "#16161c"
    readonly property color textLight: "#ECECEE"
    readonly property color textDim:   Qt.rgba(0.92, 0.92, 0.94, 0.55)

    // ── felt scrim ──
    Rectangle {
        anchors.fill: parent
        color: panel.feltColor
        opacity: panel.reveal
    }
    MouseArea {
        anchors.fill: parent
        enabled: panel.visible
        onClicked: root.mediaBrowserVisible = false
        onWheel: function(wheel) {
            if (!panel.ready) return
            panel.moveSel(wheel.angleDelta.y < 0 ? 1 : -1)
        }
    }

    // ── empty/loading - also catches Esc to close when the hand isn't focused ──
    Item {
        anchors.fill: parent
        focus: panel.visible && !(panel.ready && panel.filtered.length > 0)
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (panel.filterText) panel.filterText = ""
                else root.mediaBrowserVisible = false
                event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
                if (panel.filterText.length > 0) panel.filterText = panel.filterText.slice(0, -1)
                event.accepted = true
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                       && event.text.charCodeAt(0) !== 127
                       && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                if (event.text !== " " || (panel.filterText.length > 0 && !panel.filterText.endsWith(" "))) panel.filterText += event.text;
                event.accepted = true
            }
        }
    }
    // ── loading / empty ──
    Text {
        visible: root.mediaBrowserVisible && panel.active && panel.ready && panel.filtered.length === 0
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("No matches: %1").arg(panel.filterText) + I18n.tr("\n\nBackspace to edit, or Esc to clear")
        color: root.ink
        font.family: root.mono; font.pixelSize: 16; font.letterSpacing: 1
    }
    Text {
        visible: root.mediaBrowserVisible && panel.active && !panel.ready
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: panel.layoutSettled && !panel.loaded
              ? (panel.isVideos ? I18n.tr("No recordings in ~/Videos/Recordings") : I18n.tr("No screenshots in ~/Pictures/Screenshots")) + I18n.tr("\n\nEsc or click to close")
              : I18n.tr("Loading…")
        color: panel.textLight
        font.family: root.mono; font.pixelSize: 16; font.letterSpacing: 1
    }

    // ── header + position (top) ──
    Text {
        visible: panel.ready && panel.filtered.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 40
        opacity: panel.reveal
        text: (panel.isVideos ? I18n.tr("VIDEOS") : I18n.tr("SCREENSHOTS")) + "      " + (panel.selFilt + 1) + " / " + panel.filtered.length
        color: panel.textDim
        font.family: root.mono; font.pixelSize: 12; font.letterSpacing: 2
    }

    // ── the hand ──
    Item {
        id: hand
        visible: panel.ready && panel.filtered.length > 0
        focus: panel.ready && panel.filtered.length > 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -16
        width: parent.width
        height: panel.cardH + panel.focusLift + 40

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (panel.confirmDelete) panel.confirmDelete = false
                else if (panel.filterText) panel.filterText = ""
                else root.mediaBrowserVisible = false
                event.accepted = true
            } else if (event.key === Qt.Key_Delete) {
                if (panel.confirmDelete) panel.deleteFocused()
                else panel.confirmDelete = true
                event.accepted = true
            } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                panel.copyFocused(); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                panel.openSelected(); event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
                if (panel.filterText.length > 0) panel.filterText = panel.filterText.slice(0, -1)
                event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab
                       || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                panel.moveSel(-1); event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                panel.moveSel(1); event.accepted = true
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                       && event.text.charCodeAt(0) !== 127
                       && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                if (event.text !== " " || (panel.filterText.length > 0 && !panel.filterText.endsWith(" "))) panel.filterText += event.text; event.accepted = true
            }
        }

        Repeater {
            model: panel.filtered.length

            delegate: Item {
                id: card
                required property int index
                readonly property var  entry:   panel.filtered[index] || null
                readonly property int  relIdx:  index - panel.selFilt
                readonly property bool focused: relIdx === 0
                readonly property bool nearby:  Math.abs(relIdx) <= panel.maxVisible
                readonly property real dim: focused ? 0.0 : Math.min(0.62, 0.30 + Math.abs(relIdx) * 0.05)

                // lazy cached thumbnail (video poster or screenshot thumb)
                readonly property string thumbPath: {
                    if (!entry) return ""
                    var fp = entry.thumbnailPath || ""
                    if (!fp && !panel.isVideos) fp = entry.filePath
                    if (panel.isVideos && fp === entry.filePath) return ""
                    return fp ? "file://" + fp : ""
                }

                width: panel.cardW; height: panel.cardH
                visible: nearby
                transformOrigin: Item.Bottom

                x: (hand.width  - panel.cardW) / 2 + relIdx * panel.stepX * panel.dealT
                y: (hand.height - panel.cardH)     - (focused ? panel.focusLift * panel.dealT : 0)
                rotation: relIdx * panel.spreadDeg * panel.dealT
                scale: focused ? 1 + (panel.focusScale - 1) * panel.dealT : 1
                z: focused ? 1000 : 500 - Math.min(Math.abs(relIdx), 40)
                opacity: panel.dealT

                Behavior on x        { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on y        { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on rotation { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on scale    { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                // photo/poster (raster) - edges hidden behind the passepartout
                Item {
                    anchors.fill: parent
                    anchors.margins: 6
                    Image {
                        id: thumbImage
                        anchors.fill: parent
                        readonly property string wantedSource: (panel.ready && card.nearby && card.entry && card.thumbPath) ? card.thumbPath : ""
                        source: wantedSource
                        onWantedSourceChanged: source = wantedSource
                        Connections {
                            target: panel
                            function onThumbEpochChanged() {
                                if (thumbImage.wantedSource && (thumbImage.status === Image.Error || thumbImage.status === Image.Null)) {
                                    var s = thumbImage.wantedSource
                                    thumbImage.source = ""
                                    thumbImage.source = s
                                }
                            }
                        }
                        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false; smooth: true
                        sourceSize.width:  panel.cardW * 2
                        sourceSize.height: panel.cardH * 2
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 70
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
                        }
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
                        text: card.entry ? I18n.tr(card.entry.label) : ""
                        color: panel.textLight
                        font.family: root.mono; font.pixelSize: 12; font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    }
                    Rectangle {
                        anchors.fill: parent; color: "black"
                        opacity: card.dim
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }
                }
                // passepartout - crisp rounded outer + inner hole over the photo
                Shape {
                    id: frameShape
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real w:  panel.cardW
                    readonly property real h:  panel.cardH
                    readonly property real ro: 18
                    readonly property real m:  8
                    readonly property real ri: 10
                    ShapePath {
                        fillRule: ShapePath.OddEvenFill
                        fillColor: panel.frameDark
                        strokeColor: "transparent"
                        strokeWidth: 0
                        startX: frameShape.ro; startY: 0
                        PathLine { x: frameShape.w - frameShape.ro; y: 0 }
                        PathArc  { x: frameShape.w; y: frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.w; y: frameShape.h - frameShape.ro }
                        PathArc  { x: frameShape.w - frameShape.ro; y: frameShape.h; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.ro; y: frameShape.h }
                        PathArc  { x: 0; y: frameShape.h - frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: 0; y: frameShape.ro }
                        PathArc  { x: frameShape.ro; y: 0; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathMove { x: frameShape.m + frameShape.ri; y: frameShape.m }
                        PathLine { x: frameShape.w - frameShape.m - frameShape.ri; y: frameShape.m }
                        PathArc  { x: frameShape.w - frameShape.m; y: frameShape.m + frameShape.ri; radiusX: frameShape.ri; radiusY: frameShape.ri }
                        PathLine { x: frameShape.w - frameShape.m; y: frameShape.h - frameShape.m - frameShape.ri }
                        PathArc  { x: frameShape.w - frameShape.m - frameShape.ri; y: frameShape.h - frameShape.m; radiusX: frameShape.ri; radiusY: frameShape.ri }
                        PathLine { x: frameShape.m + frameShape.ri; y: frameShape.h - frameShape.m }
                        PathArc  { x: frameShape.m; y: frameShape.h - frameShape.m - frameShape.ri; radiusX: frameShape.ri; radiusY: frameShape.ri }
                        PathLine { x: frameShape.m; y: frameShape.m + frameShape.ri }
                        PathArc  { x: frameShape.m + frameShape.ri; y: frameShape.m; radiusX: frameShape.ri; radiusY: frameShape.ri }
                    }
                    // focus accent - OUTER outline only (one border, not two)
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: card.focused ? root.seal : "transparent"
                        strokeWidth: card.focused ? 2 : 0
                        Behavior on strokeColor { ColorAnimation { duration: 160 } }
                        startX: frameShape.ro; startY: 0
                        PathLine { x: frameShape.w - frameShape.ro; y: 0 }
                        PathArc  { x: frameShape.w; y: frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.w; y: frameShape.h - frameShape.ro }
                        PathArc  { x: frameShape.w - frameShape.ro; y: frameShape.h; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.ro; y: frameShape.h }
                        PathArc  { x: 0; y: frameShape.h - frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: 0; y: frameShape.ro }
                        PathArc  { x: frameShape.ro; y: 0; radiusX: frameShape.ro; radiusY: frameShape.ro }
                    }
                }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: card.focused ? panel.openSelected() : (panel.selFilt = index)
                }
            }
        }
    }

    // ── label + delete-confirm + hint (bottom) ──
    Column {
        visible: panel.ready && panel.filtered.length > 0
        opacity: panel.reveal
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 28
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 820
            text: (panel.isVideos ? I18n.tr("Videos · ") : I18n.tr("Screenshots · ")) + panel.currentLabel
            color: panel.textLight
            font.family: root.mono; font.pixelSize: 24; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }

        Text {
            visible: panel.filterText.length > 0 && !panel.confirmDelete
            anchors.horizontalCenter: parent.horizontalCenter
            text: panel.filterText
            color: root.seal; opacity: 0.95
            font.family: root.mono; font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            visible: panel.confirmDelete
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("Delete this %1?   Del again to confirm   ·   Esc cancel").arg(panel.isVideos ? I18n.tr("video") : I18n.tr("screenshot"))
            color: root.seal
            font.family: root.mono; font.pixelSize: 11; font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            visible: !panel.confirmDelete
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("← →  scroll navigate     Enter open     Del delete     Ctrl+C copy     Esc")
            color: panel.textDim
            font.family: root.mono; font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
