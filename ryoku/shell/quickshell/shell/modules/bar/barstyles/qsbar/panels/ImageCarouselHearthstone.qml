import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "ImagePickerModel.js" as Model
import Ryoku.Ui.Singletons

// Hearthstone (card-deck) variant - original felt look (dark table, dark card
// frame, fanned cards dealt via GPU transforms) on top of the SAME fast data
// layer as the Tanzaku picker: fast glob scan, cached 512px thumbnails, niced
// pre-warm, lazy author/palette meta. Active only while pickerStyle=="hearthstone".
PanelWindow {
    id: panel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-image-carousel-hs"
    WlrLayershell.keyboardFocus: panel.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool active: root.pickerStyle === "hearthstone"
    readonly property bool isThemeMode: root.imagePickerMode === "theme"
    readonly property bool ready: root.imagePickerVisible && active && imagesLoaded && layoutSettled

    property bool imagesLoaded:  false
    property bool layoutSettled: false
    property bool scanDone:      false   // a scan finished (distinguishes "loading" from "nothing found")
    property var  imageArray:    []
    property int  selFilt:       0
    property string filterText:  ""
    property string currentImage: ""
    property int thumbEpoch:      0
    property string readyThumbUrl: ""

    visible: root.imagePickerVisible && active

    // ── reveal + deal ──
    property real reveal: 0
    Behavior on reveal { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    property real dealT: 0
    readonly property int dealDuration: isThemeMode ? 260 : 180
    readonly property int cardMotionDuration: isThemeMode ? 220 : 180
    readonly property bool dealSettled: dealT >= 0.999
    Behavior on dealT { NumberAnimation { duration: panel.dealDuration; easing.type: Easing.OutCubic } }
    onReadyChanged: { reveal = ready ? 1 : 0; if (ready) dealT = 1 }

    // ── filtered list ──
    readonly property var filtered: {
        var out = []
        for (var i = 0; i < imageArray.length; i++) {
            if (!Model.itemMatches(imageArray, i, filterText)) continue
            out.push({
                idx:      i,
                filePath: imageArray[i].filePath,
                thumb:    panel.thumbUrlFor(imageArray[i]),
                label:    Model.labelForPath(imageArray[i].filePath),
                dir:      imageArray[i].dir || "",
                current:  imageArray[i].filePath === panel.currentImage
            })
        }
        return out
    }
    onFilteredChanged: if (selFilt >= filtered.length) selFilt = Math.max(0, filtered.length - 1)

    readonly property string currentLabel:
        (filtered.length > 0 && selFilt >= 0 && selFilt < filtered.length)
            ? I18n.tr(filtered[selFilt].label)
            : (filterText ? I18n.tr("No matches") : "")
    function thumbUrlFor(img) {
        if (!img || !img.thumbnailPath || img.thumbnailPath === img.filePath) return ""
        return "file://" + img.thumbnailPath
    }

    // ── open / style gating ──
    function syncOpen() {
        if (root.imagePickerVisible && active) {
            if (!imagesLoaded) {
                panel.layoutSettled = false
                panel.filterText    = ""
                panel.imageArray    = []
                panel.selFilt       = 0
                panel.reveal        = 0
                panel.dealT         = 0
                currentProc.running = false; currentProc.running = true
            }
        } else {
            panel.imagesLoaded  = false; panel.scanDone = false
            panel.layoutSettled = false
            panel.reveal        = 0
            panel.dealT         = 0
        }
    }
    Connections {
        target: root
        function onImagePickerVisibleChanged() { panel.syncOpen() }
        function onPickerStyleChanged()         { panel.syncOpen() }
    }
    Component.onCompleted: panel.syncOpen()

    // step 1: current image
    Process {
        id: currentProc
        command: panel.isThemeMode
            ? ["bash", "-c",
               "CACHE=$HOME/.cache/quickshell-theme-picker; " +
               "name=$(cat " + panel.shq(root.themeNamePath) + " 2>/dev/null || true); " +
               "for ext in png jpg jpeg webp; do f=\"$CACHE/$name.$ext\"; [ -L \"$f\" ] && echo \"$f\" && exit 0; done; echo ''"]
            : ["bash", "-c", "readlink -f " + panel.shq(root.currentBackgroundPath) + " 2>/dev/null || true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                panel.currentImage = this.text.trim()
                cacheProc.running = false; cacheProc.running = true   // instant from cache
                var cmd = panel.buildScanCmd()
                cmd[2] = cmd[2] + " | tee " + panel.shq(panel.scanCachePath)
                scanProc.command = cmd
                scanProc.running = false; scanProc.running = true
            }
        }
    }

    // step 2: scan images (live refresh; writes the cache via tee)
    Process {
        id: scanProc
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.applyScan(text, false)
        }
    }

    // scan-result cache → instant (re)open (shared cache file with the other theme styles)
    readonly property string scanCachePath: Quickshell.env("HOME") + "/.cache/quickshell-scan-" + (isThemeMode ? "theme" : "wallpaper")
    property string _lastScan: ""
    function scanHasOriginalThumbs(text) {
        var rows = String(text || "").split("\n")
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]
            if (!row) continue
            var cols = row.split("\t")
            if (cols.length < 2 || !cols[1] || cols[0] === cols[1]) return true
        }
        return false
    }
    Process {
        id: cacheProc
        command: ["cat", panel.scanCachePath]
        stdout: StdioCollector { onStreamFinished: panel.applyScan(this.text, true) }
    }
    function applyScan(text, fromCache) {
        var t = String(text || "")
        if (fromCache && !t.trim()) return   // cache empty → wait for live scan; live empty → fall through to empty-state
        if (fromCache && scanHasOriginalThumbs(t)) return
        if (fromCache && imagesLoaded) return
        if (!fromCache && t.trim() === _lastScan.trim() && imagesLoaded) { panel.warmVisible(); warmTimer.restart(); return }
        _lastScan = t
        var images = Model.loadRows(t)
        panel.imageArray   = images
        panel.selFilt      = Model.indexForSelectedImage(images, panel.currentImage)
        panel.imagesLoaded = images.length > 0; panel.scanDone = true
        Qt.callLater(function() {
            if (root.imagePickerVisible && panel.active) {
                panel.layoutSettled = true
                if (panel.imageArray.length > 0) hand.forceActiveFocus()   // keep Esc-catcher focused when empty
                panel.fetchMeta()
                if (!fromCache) { panel.warmMeta(); panel.warmVisible(); warmTimer.restart() }
            }
        })
    }

    function buildScanCmd() {
        if (isThemeMode) {
            return ["bash", "-c", [
                "shopt -s nullglob nocaseglob;",
                "CACHE=$HOME/.cache/quickshell-theme-picker; mkdir -p \"$CACHE\";",
                "D=$HOME/.cache/quickshell-img-thumbs; mkdir -p \"$D\";",
                "HASHCACHE=$HOME/.cache/quickshell-img-thumb-hashes.tsv; touch \"$HASHCACHE\";",
                "hash_for() { local s=\"$1\" r m key h tmp; r=$(readlink -f \"$s\" 2>/dev/null || printf '%s' \"$s\"); m=$(stat -Lc '%s:%Y:%Z' \"$s\" 2>/dev/null) || return 1; key=\"$r|$m\"; h=$(awk -F '\\t' -v k=\"$key\" '$1 == k { v=$2 } END { print v }' \"$HASHCACHE\" 2>/dev/null); if [ -z \"$h\" ]; then h=$(sha256sum \"$s\" 2>/dev/null | cut -d' ' -f1); [ -n \"$h\" ] || return 1; tmp=\"$HASHCACHE.$$\"; { awk -F '\\t' -v k=\"$key\" '$1 != k' \"$HASHCACHE\" 2>/dev/null; printf '%s\\t%s\\n' \"$key\" \"$h\"; } > \"$tmp\" && mv -f \"$tmp\" \"$HASHCACHE\"; fi; printf '%s' \"$h\"; };",
                "thumb_for() { local s=\"$1\" k; k=$(hash_for \"$s\") || return 1; printf '%s/%s-512.jpg' \"$D\" \"$k\"; };",
                "for d in ~/.local/share/ryoku/themes/* ~/.config/ryoku/themes/*; do",
                "  [ -d \"$d\" ] || continue;",
                "  name=$(basename \"$d\");",
                "  prev=\"\";",
                "  for c in \"$d\"/preview.png \"$d\"/preview.jpg \"$d\"/preview.jpeg; do [ -f \"$c\" ] && { prev=\"$c\"; break; }; done;",
                "  if [ -z \"$prev\" ]; then bgs=(\"$d\"/backgrounds/*.jpg \"$d\"/backgrounds/*.jpeg \"$d\"/backgrounds/*.png \"$d\"/backgrounds/*.webp); prev=\"${bgs[0]}\"; fi;",
                "  [ -z \"$prev\" ] && continue;",
                "  ext=\"${prev##*.}\"; link=\"$CACHE/$name.$ext\";",
                "  [ -L \"$link\" ] || ln -sf \"$prev\" \"$link\";",
                "  thumb=$(thumb_for \"$link\") || continue;",
                "  printf '%s\\t%s\\t%s\\n' \"$link\" \"$thumb\" \"$d\";",
                "done | sort -u"
            ].join(" ")]
        } else {
            return ["bash", "-c", [
                "D=$HOME/.cache/quickshell-img-thumbs; mkdir -p \"$D\";",
                "HASHCACHE=$HOME/.cache/quickshell-img-thumb-hashes.tsv; touch \"$HASHCACHE\";",
                "hash_for() { local s=\"$1\" r m key h tmp; r=$(readlink -f \"$s\" 2>/dev/null || printf '%s' \"$s\"); m=$(stat -Lc '%s:%Y:%Z' \"$s\" 2>/dev/null) || return 1; key=\"$r|$m\"; h=$(awk -F '\\t' -v k=\"$key\" '$1 == k { v=$2 } END { print v }' \"$HASHCACHE\" 2>/dev/null); if [ -z \"$h\" ]; then h=$(sha256sum \"$s\" 2>/dev/null | cut -d' ' -f1); [ -n \"$h\" ] || return 1; tmp=\"$HASHCACHE.$$\"; { awk -F '\\t' -v k=\"$key\" '$1 != k' \"$HASHCACHE\" 2>/dev/null; printf '%s\\t%s\\n' \"$key\" \"$h\"; } > \"$tmp\" && mv -f \"$tmp\" \"$HASHCACHE\"; fi; printf '%s' \"$h\"; };",
                "thumb_for() { local s=\"$1\" k; k=$(hash_for \"$s\") || return 1; printf '%s/%s-512.jpg' \"$D\" \"$k\"; };",
                "find -L " + wallpaperFindRoots() + " -maxdepth 1 -type f " +
                "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \\) " +
                "2>/dev/null | sort | while IFS= read -r f; do thumb=$(thumb_for \"$f\") || continue; printf '%s\\t%s\\n' \"$f\" \"$thumb\"; done"
            ].join(" ")]
        }
    }

    Process { id: applyThemeProc; command: [] }
    Process { id: applyBgProc;    command: [] }

    function applySelected() {
        if (!imagesLoaded || filtered.length === 0) return
        if (selFilt < 0 || selFilt >= filtered.length) return
        var path = filtered[selFilt].filePath; if (!path) return
        if (isThemeMode) {
            var name = Model.nameForPath(path)
            applyThemeProc.command = ["env", "RYOKU_PATH=" + root.omarchyInstallRoot, "true", name]
            applyThemeProc.running = false; applyThemeProc.running = true
        } else {
            applyBgProc.command = ["ryogami", "wallpaper", "set", path]
            applyBgProc.running = false; applyBgProc.running = true
        }
        root.imagePickerVisible = false
    }

    function moveSel(delta) {
        if (filtered.length === 0) return
        selFilt = Math.max(0, Math.min(filtered.length - 1, selFilt + delta))
    }

    readonly property var sel: (filtered.length > 0 && selFilt >= 0 && selFilt < filtered.length)
                               ? filtered[selFilt] : null

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function wallpaperFindRoots() {
        var paths = root.wallpaperSourcePaths || []
        var args = []
        for (var i = 0; i < paths.length; i++)
            if (paths[i]) args.push(panel.shq(paths[i]))
        return args.join(" ")
    }
    function paletteReadCmd(pathExpr) {
        return "awk -F'\"' 'function valid(v){ return v ~ /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/ } { k=$1; gsub(/[[:space:]=]/,\"\",k); if (valid($2)) c[k]=$2 } END { split(\"color1 red color2 green color3 yellow color4 blue color5 magenta color6 cyan\", a, \" \"); for (i=1; i<=6; i++) { p=a[i*2-1]; q=a[i*2]; v=c[p]; if (v == \"\") v=c[q]; if (v != \"\") { if (out != \"\") out=out \",\"; out=out v } } print out }' " + pathExpr + " 2>/dev/null"
    }

    // ── pre-warm: visible entries first, the rest after the open settles ──
    Process {
        id: priorityWarmProc
        command: []
        stdout: SplitParser {
            onRead: function(line) { panel.noteThumbReady(line) }
        }
    }
    Process {
        id: warmProc
        command: []
        stdout: SplitParser {
            onRead: function(line) { panel.noteThumbReady(line) }
        }
    }
    Timer { id: warmTimer; interval: 450; onTriggered: panel.warmAll() }
    function noteThumbReady(line) {
        var path = String(line || "").trim()
        if (!path) return
        panel.readyThumbUrl = "file://" + path
        panel.thumbEpoch++
    }
    function warmCommand(srcs, niceLevel) {
        var nice = niceLevel === 10 ? 10 : 19
        return ["bash", "-c",
            "D=$HOME/.cache/quickshell-img-thumbs; mkdir -p \"$D\"; command -v magick >/dev/null 2>&1 || exit 0; " +
            "HASHCACHE=$HOME/.cache/quickshell-img-thumb-hashes.tsv; touch \"$HASHCACHE\"; " +
            "tmp=$(mktemp); trap 'rm -f \"$tmp\"' EXIT; " +
            "hash_for() { local s=\"$1\" r m key h t; r=$(readlink -f \"$s\" 2>/dev/null || printf '%s' \"$s\"); m=$(stat -Lc '%s:%Y:%Z' \"$s\" 2>/dev/null) || return 1; key=\"$r|$m\"; h=$(awk -F '\\t' -v k=\"$key\" '$1 == k { v=$2 } END { print v }' \"$HASHCACHE\" 2>/dev/null); if [ -z \"$h\" ]; then h=$(sha256sum \"$s\" 2>/dev/null | cut -d' ' -f1); [ -n \"$h\" ] || return 1; t=\"$HASHCACHE.$$\"; { awk -F '\\t' -v k=\"$key\" '$1 != k' \"$HASHCACHE\" 2>/dev/null; printf '%s\\t%s\\n' \"$key\" \"$h\"; } > \"$t\" && mv -f \"$t\" \"$HASHCACHE\"; fi; printf '%s' \"$h\"; }; " +
            "for s in \"$@\"; do k=$(hash_for \"$s\") || continue; " +
            "o=\"$D/$k-512.jpg\"; [ -s \"$o\" ] && continue; printf '%s\\n%s\\n' \"$s\" \"$o\" >> \"$tmp\"; done; " +
            "if [ -s \"$tmp\" ]; then nice -n " + nice + " xargs -d '\\n' -P 3 -n 2 sh -c 'magick -define jpeg:size=1024x1024 \"$0[0]\" -auto-orient -strip -thumbnail 512x512^ -quality 82 \"$1\" >/dev/null 2>&1 || true; [ -s \"$1\" ] && printf \"%s\\n\" \"$1\"; exit 0' < \"$tmp\"; fi",
            "warm"].concat(srcs)
    }
    function startWarm(proc, srcs, niceLevel) {
        if (srcs.length === 0) return
        proc.command = panel.warmCommand(srcs, niceLevel)
        proc.running = false; proc.running = true
    }
    function visibleSourcePaths() {
        var srcs = [], seen = {}
        for (var distance = 0; distance <= maxVisible; distance++) {
            var indices = distance === 0 ? [selFilt] : [selFilt - distance, selFilt + distance]
            for (var j = 0; j < indices.length; j++) {
                var i = indices[j]
                if (i < 0 || i >= filtered.length) continue
                var p = filtered[i].filePath
                if (p && !seen[p]) { seen[p] = true; srcs.push(p) }
            }
        }
        return srcs
    }
    function backgroundSourcePaths() {
        var visible = {}, priority = visibleSourcePaths(), srcs = [], seen = {}
        for (var i = 0; i < priority.length; i++) visible[priority[i]] = true
        for (var j = 0; j < imageArray.length; j++) {
            var p = imageArray[j].filePath
            if (p && !visible[p] && !seen[p]) { seen[p] = true; srcs.push(p) }
        }
        return srcs
    }
    function warmVisible() { panel.startWarm(priorityWarmProc, panel.visibleSourcePaths(), 10) }
    function warmAll() { panel.startWarm(warmProc, panel.backgroundSourcePaths(), 19) }

    // ── lazy meta (author/repo/palette) for the focused theme, cached by dir ──
    property var metaCache: ({})
    property string _metaDir: ""
    readonly property var selMeta: (sel && sel.dir && metaCache[sel.dir]) ? metaCache[sel.dir] : null

    Timer { id: metaTimer; interval: 60; onTriggered: panel.fetchMeta() }
    onSelChanged: if (isThemeMode && sel && sel.dir && !metaCache[sel.dir]) metaTimer.restart()

    function fetchMeta() {
        if (!isThemeMode || !sel || !sel.dir || metaCache[sel.dir]) return
        panel._metaDir = sel.dir
        metaProc.command = ["bash", "-c",
            "d=" + shq(sel.dir) + "; repo=''; author='';" +
            "if [ -f \"$d/.git/config\" ]; then " +
            "  repo=$(sed -nE 's#^[[:space:]]*url = (.*)$#\\1#p' \"$d/.git/config\" | head -1);" +
            "  author=$(printf '%s' \"$repo\" | sed -nE 's#.*github\\.com[:/]+([^/]+)/.*#\\1#p');" +
            "fi;" +
            "pal=$(" + paletteReadCmd("\"$d/colors.toml\"") + ");" +
            "printf '%s\\t%s\\t%s\\n' \"$author\" \"$repo\" \"$pal\""]
        metaProc.running = false; metaProc.running = true
    }
    Process {
        id: metaProc
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = String(this.text || "").replace(/\n+$/, "").split("\t")
                var m = panel.metaCache
                m[panel._metaDir] = { author: parts[0] || "", repo: parts[1] || "", palette: parts[2] || "" }
                panel.metaCache = m
            }
        }
    }

    function openRepo() {
        if (!selMeta || !selMeta.repo) return
        var url = String(selMeta.repo)
            .replace(/^git@github\.com:/, "https://github.com/")
            .replace(/\.git$/, "")
        Spawn.run(["xdg-open", url])
    }

    // ── bulk meta pre-warm: read author/repo/palette for ALL themes in one
    // background pass so the info is instant for every card (no lazy timing) ──
    Process {
        id: metaWarmProc
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = String(this.text || "").split("\n")
                var m = panel.metaCache
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue
                    var p = lines[i].split("\t")
                    if (p[0] && !m[p[0]]) m[p[0]] = { author: p[1] || "", repo: p[2] || "", palette: p[3] || "" }
                }
                panel.metaCache = m
            }
        }
    }
    function warmMeta() {
        if (!isThemeMode) return
        var dirs = []
        for (var i = 0; i < imageArray.length; i++)
            if (imageArray[i].dir) dirs.push(imageArray[i].dir)
        if (dirs.length === 0) return
        metaWarmProc.command = ["bash", "-c",
            "for d in \"$@\"; do repo=''; author='';" +
            "if [ -f \"$d/.git/config\" ]; then repo=$(sed -nE 's#^[[:space:]]*url = (.*)$#\\1#p' \"$d/.git/config\" | head -1);" +
            "author=$(printf '%s' \"$repo\" | sed -nE 's#.*github\\.com[:/]+([^/]+)/.*#\\1#p'); fi;" +
            "pal=$(" + paletteReadCmd("\"$d/colors.toml\"") + ");" +
            "printf '%s\\t%s\\t%s\\t%s\\n' \"$d\" \"$author\" \"$repo\" \"$pal\"; done",
            "warm"].concat(dirs)
        metaWarmProc.running = false; metaWarmProc.running = true
    }

    // ── card-hand geometry ──
    readonly property int  cardW:      232
    readonly property int  cardH:      330
    readonly property real focusScale: 1.24
    readonly property real spreadDeg:  6.0
    readonly property real stepX:      128
    readonly property real focusLift:  54
    readonly property int  maxVisible: 5

    // ── felt look (original) ──
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
        onClicked: root.imagePickerVisible = false
        onWheel: function(wheel) {
            if (!panel.ready) return
            panel.moveSel(wheel.angleDelta.y < 0 ? 1 : -1)
        }
    }

    // ── loading ──
    Item {
        anchors.fill: parent
        focus: panel.visible && !(panel.ready && panel.filtered.length > 0)
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (panel.filterText) panel.filterText = ""
                else root.imagePickerVisible = false
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
    Text {
        visible: root.imagePickerVisible && panel.active && panel.ready && panel.filtered.length === 0
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("No matches: %1").arg(panel.filterText) + I18n.tr("\n\nBackspace to edit, or Esc to clear")
        color: root.ink
        font.family: root.mono; font.pixelSize: 16; font.letterSpacing: 1
    }
    Text {
        visible: root.imagePickerVisible && panel.active && !panel.ready
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: panel.scanDone
              ? (panel.isThemeMode ? I18n.tr("No themes found") : I18n.tr("No wallpapers found")) + I18n.tr("\n\nEsc or click to close")
              : I18n.tr("Loading…")
        color: panel.textLight
        font.family: root.mono; font.pixelSize: 16; font.letterSpacing: 1
    }

    // ── position indicator (top) ──
    Text {
        visible: panel.ready && panel.filtered.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 40
        opacity: panel.reveal
        text: (panel.isThemeMode ? I18n.tr("THEME") : I18n.tr("WALLPAPER")) + "      " + (panel.selFilt + 1) + " / " + panel.filtered.length
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
                if (panel.filterText) panel.filterText = ""
                else root.imagePickerVisible = false
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                panel.applySelected(); event.accepted = true
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

                // Cached thumbnails are resolved by the scan/warm worker, so
                // visible delegates don't start shell processes or briefly
                // switch from an empty source to a generated path.
                readonly property string thumbPath: entry ? entry.thumb : ""

                width: panel.cardW; height: panel.cardH
                visible: nearby
                transformOrigin: Item.Bottom

                x: (hand.width  - panel.cardW) / 2 + relIdx * panel.stepX * panel.dealT
                y: (hand.height - panel.cardH)     - (focused ? panel.focusLift * panel.dealT : 0)
                rotation: relIdx * panel.spreadDeg * panel.dealT
                scale: focused ? 1 + (panel.focusScale - 1) * panel.dealT : 1
                z: focused ? 1000 : 500 - Math.min(Math.abs(relIdx), 40)
                opacity: panel.dealT

                Behavior on x        { enabled: panel.dealSettled; NumberAnimation { duration: panel.cardMotionDuration; easing.type: Easing.OutCubic } }
                Behavior on y        { enabled: panel.dealSettled; NumberAnimation { duration: panel.cardMotionDuration; easing.type: Easing.OutCubic } }
                Behavior on rotation { enabled: panel.dealSettled; NumberAnimation { duration: panel.cardMotionDuration; easing.type: Easing.OutCubic } }
                Behavior on scale    { enabled: panel.dealSettled; NumberAnimation { duration: panel.cardMotionDuration; easing.type: Easing.OutCubic } }

                // photo (raster) - its edges are hidden behind the passepartout's
                // crisp Shape inner edge, so no rotated raster edge ever shows
                Item {
                    anchors.fill: parent
                    anchors.margins: 6
                    Image {
                        id: thumbImage
                        anchors.fill: parent
                        readonly property string wantedSource: (panel.ready && card.nearby && card.thumbPath) ? card.thumbPath : ""
                        source: wantedSource
                        onWantedSourceChanged: source = wantedSource
                        Connections {
                            target: panel
                            function onThumbEpochChanged() {
                                if (thumbImage.wantedSource === panel.readyThumbUrl
                                        && thumbImage.status !== Image.Ready) {
                                    var s = thumbImage.wantedSource
                                    thumbImage.source = ""
                                    thumbImage.source = s
                                }
                            }
                        }
                        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; smooth: true
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
                        font.family: root.mono; font.pixelSize: 13; font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    }
                    Rectangle {
                        anchors.fill: parent; color: "black"
                        opacity: card.dim
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }
                }
                // passepartout - rounded outer + rounded inner hole (OddEven), drawn
                // OVER the photo; only its CurveRenderer edges are visible → crisp
                // rounded card AND crisp rounded photo cut-out, even when rotated
                Shape {
                    id: frameShape
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real w:  panel.cardW
                    readonly property real h:  panel.cardH
                    readonly property real ro: 18    // outer radius
                    readonly property real m:  8     // mat width
                    readonly property real ri: 10    // inner (photo) radius
                    ShapePath {
                        fillRule: ShapePath.OddEvenFill
                        fillColor: panel.frameDark
                        strokeColor: "transparent"
                        strokeWidth: 0
                        // outer rounded rect
                        startX: frameShape.ro; startY: 0
                        PathLine { x: frameShape.w - frameShape.ro; y: 0 }
                        PathArc  { x: frameShape.w; y: frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.w; y: frameShape.h - frameShape.ro }
                        PathArc  { x: frameShape.w - frameShape.ro; y: frameShape.h; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.ro; y: frameShape.h }
                        PathArc  { x: 0; y: frameShape.h - frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: 0; y: frameShape.ro }
                        PathArc  { x: frameShape.ro; y: 0; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        // inner rounded hole (photo cut-out)
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
                // "current" marker
                Rectangle {
                    visible: card.entry && card.entry.current === true
                    width: 9; height: 9; radius: 4.5
                    x: 14; y: 14; z: 5
                    color: root.seal
                    border.color: Qt.rgba(0, 0, 0, 0.35); border.width: 1
                }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: card.focused ? panel.applySelected() : (panel.selFilt = index)
                }
            }
        }
    }

    // ── label + palette + meta + hint (bottom) ──
    Column {
        visible: panel.ready && panel.filtered.length > 0
        opacity: panel.reveal
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 28
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 820; text: panel.currentLabel
            color: panel.textLight
            font.family: root.mono; font.pixelSize: 26; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }

        // palette swatch (lazy, theme mode)
        Row {
            visible: panel.isThemeMode && panel.selMeta && panel.selMeta.palette.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Repeater {
                model: (panel.selMeta && panel.selMeta.palette.length > 0)
                       ? panel.selMeta.palette.split(",") : []
                delegate: Rectangle {
                    required property var modelData
                    width: 13; height: 13; radius: 6.5
                    color: modelData
                    border.color: Qt.rgba(1, 1, 1, 0.18); border.width: 1
                }
            }
        }

        // current badge · author
        Row {
            visible: (panel.sel && panel.sel.current)
                     || (panel.isThemeMode && panel.selMeta && panel.selMeta.author.length > 0)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Text {
                visible: panel.sel && panel.sel.current
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("● current")
                color: root.seal
                font.family: root.mono; font.pixelSize: 11
            }
            Text {
                visible: panel.isThemeMode && panel.selMeta && panel.selMeta.author.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("by %1  ↗").arg(panel.selMeta ? panel.selMeta.author : "")
                color: authorMa.containsMouse ? root.seal : panel.textDim
                font.family: root.mono; font.pixelSize: 11
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea {
                    id: authorMa
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.openRepo()
                }
            }
        }

        Text {
            visible: panel.filterText.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            text: panel.filterText
            color: root.seal; opacity: 0.95
            font.family: root.mono; font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("← →  scroll navigate     Enter apply     Esc cancel     type to filter")
            color: panel.textDim
            font.family: root.mono; font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
