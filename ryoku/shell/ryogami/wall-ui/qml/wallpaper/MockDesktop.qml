import QtQuick
import ".."
import Ryoku.Ui.Singletons

// A miniature of the live desktop under the focused wallpaper, recoloured by
// the candidate matugen palette (from `pv`, the daemon's matugen-preview) so you
// preview the scheme a wallpaper yields before Set. Paper-and-ink: a hairline
// bar, a terminal card carrying the base16 strip, and a cava specimen coloured
// off the picture's own tonal ramps. Folded from ryowalls' MockDesktop, native
// on the wall-ui toolkit and driven by explicit props instead of a singleton.
Item {
    id: mock
    clip: true

    property var pv: null              // PalettePreview: col(i), tones, grid, cols, rows, lstar
    property string wallpaper: ""      // backdrop image (path or file url)

    readonly property real s: Math.max(0.6, height / 300)
    function col(i, fb) { return mock.pv ? mock.pv.col(i, fb) : fb }

    // the candidate scheme, read off the live palette with graceful fallbacks so
    // the mock is never blank while the palette loads.
    readonly property color cBg:     col(0, "#101010")
    readonly property color cFg:     col(15, col(7, "#e8e8e8"))
    readonly property color cRed:    col(1, "#c1564b")
    readonly property color cGreen:  col(2, "#8a9a6b")
    readonly property color cYellow: col(3, "#d6a85f")
    readonly property color cBlue:   col(4, "#5a7a9a")
    readonly property color cMag:    col(5, "#9a6f8a")

    // ── wallpaper backdrop ────────────────────────────────────────────────────
    Image {
        anchors.fill: parent
        asynchronous: true; cache: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.ceil(width * 1.5), Math.ceil(height * 1.5))
        source: {
            var w = "" + mock.wallpaper
            if (!w.length) return ""
            return w.indexOf("://") >= 0 ? w : ("file://" + w)
        }
    }
    // a whisper of shade so light module fills keep their edge on a bright wall.
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.16) }

    // ── hairline top bar (representative, paper-and-ink) ───────────────────────
    Rectangle {
        id: bar
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: Math.round(26 * mock.s)
        z: 1
        color: Qt.rgba(mock.cBg.r, mock.cBg.g, mock.cBg.b, 0.82)
        Behavior on color { ColorAnimation { duration: Style.animNormal } }
        Rectangle {
            anchors.bottom: parent.bottom; width: parent.width; height: 1
            color: Qt.rgba(mock.cFg.r, mock.cFg.g, mock.cFg.b, 0.18)
        }

        Row {
            anchors.left: parent.left; anchors.leftMargin: 10 * mock.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * mock.s
            Repeater {
                model: 5
                delegate: Rectangle {
                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    width: (index === 1 ? 14 : 6) * mock.s; height: 6 * mock.s; radius: 3 * mock.s
                    color: index === 1 ? mock.cBlue : Qt.rgba(mock.cFg.r, mock.cFg.g, mock.cFg.b, 0.3)
                    Behavior on color { ColorAnimation { duration: Style.animNormal } }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            text: "\u9f8d  ryoku"
            color: Qt.rgba(mock.cFg.r, mock.cFg.g, mock.cFg.b, 0.82)
            font.family: Style.fontFamily; font.pixelSize: 10 * mock.s
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 10 * mock.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * mock.s
            Text { text: "\u{f0552}"; font.family: Style.fontFamilyNerdIcons; font.pixelSize: 10 * mock.s; color: mock.cGreen; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "\u{f0028}"; font.family: Style.fontFamilyNerdIcons; font.pixelSize: 10 * mock.s; color: mock.cYellow; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "12:48"; font.family: Style.fontFamilyMono; font.pixelSize: 10 * mock.s; color: mock.cFg; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ── terminal: fastfetch card + the 8-colour base16 strip ───────────────────
    Rectangle {
        id: term
        z: 1
        anchors.left: parent.left; anchors.leftMargin: 14 * mock.s
        anchors.top: parent.top; anchors.topMargin: 40 * mock.s
        width: parent.width * 0.5
        height: parent.height * 0.44
        radius: Style.radiusSmall
        color: Qt.rgba(mock.cBg.r, mock.cBg.g, mock.cBg.b, 0.92)
        border.width: 1; border.color: Qt.rgba(mock.cFg.r, mock.cFg.g, mock.cFg.b, 0.16)
        Behavior on color { ColorAnimation { duration: Style.animNormal } }

        Column {
            anchors.fill: parent; anchors.margins: 10 * mock.s
            spacing: 5 * mock.s

            // the traffic lights are content: a terminal window's dots are round.
            Row {
                spacing: 5 * mock.s
                Repeater {
                    model: [mock.cRed, mock.cYellow, mock.cGreen]
                    delegate: Rectangle {
                        required property var modelData
                        width: 7 * mock.s; height: 7 * mock.s; radius: 4 * mock.s
                        color: modelData
                        Behavior on color { ColorAnimation { duration: Style.animNormal } }
                    }
                }
            }
            Row {
                Text { text: "ryoku"; color: mock.cGreen; font.family: Style.fontFamilyMono; font.pixelSize: 10 * mock.s; font.weight: Font.DemiBold }
                Text { text: I18n.tr("@arch"); color: mock.cMag; font.family: Style.fontFamilyMono; font.pixelSize: 10 * mock.s }
                Text { text: " ~ "; color: mock.cBlue; font.family: Style.fontFamilyMono; font.pixelSize: 10 * mock.s }
                Text { text: I18n.tr("\u276f fastfetch"); color: mock.cFg; font.family: Style.fontFamilyMono; font.pixelSize: 10 * mock.s }
            }
            Repeater {
                model: ["OS    Ryoku Linux", "WM    Hyprland", "SH    fish"]
                delegate: Row {
                    required property var modelData
                    Text { text: modelData.substring(0, 6); color: mock.cYellow; font.family: Style.fontFamilyMono; font.pixelSize: 9 * mock.s }
                    Text { text: modelData.substring(6); color: Qt.rgba(mock.cFg.r, mock.cFg.g, mock.cFg.b, 0.85); font.family: Style.fontFamilyMono; font.pixelSize: 9 * mock.s }
                }
            }
            // the scheme as a neofetch-style colour strip.
            Row {
                spacing: 3 * mock.s
                Repeater {
                    model: 8
                    delegate: Rectangle {
                        required property int index
                        width: 10 * mock.s; height: 8 * mock.s; radius: 2 * mock.s
                        color: mock.col(index + 1, Qt.rgba(mock.cFg.r, mock.cFg.g, mock.cFg.b, 0.2))
                        Behavior on color { ColorAnimation { duration: Style.animNormal } }
                    }
                }
            }
        }
    }

    // ── cava specimen: bars coloured exactly as the desktop visualiser will on
    // Set, each band a tone off the picture's own primary/secondary ramp lit
    // against the patch of image behind it (mirrors visualizer Scheme + Ui.Ink).
    readonly property int cavaN: 48
    property var levels: []
    property real phase: 0
    function retick() {
        var n = mock.cavaN, arr = []
        for (var i = 0; i < n; i++) {
            var base = Math.abs(Math.sin(mock.phase + i * 0.5))
            arr.push(Math.max(0.05, base * (0.5 + 0.5 * Math.random())))
        }
        mock.levels = arr
        mock.phase += 0.32
    }
    readonly property real cavaFieldL: {
        var g = mock.pv ? mock.pv.grid : null, cols = mock.pv ? (mock.pv.cols | 0) : 0, rows = mock.pv ? (mock.pv.rows | 0) : 0
        if (!g || cols <= 0 || rows <= 0 || g.length < cols * rows)
            return mock.pv ? mock.pv.lstar : 50
        var sum = 0
        for (var x = 0; x < cols; x++)
            sum += g[(rows - 1) * cols + x]
        return sum / cols
    }
    readonly property int cavaDir: mock.cavaFieldL >= 50 ? -1 : 1
    function cavaLstar(t) {
        var g = mock.pv ? mock.pv.grid : null, cols = mock.pv ? (mock.pv.cols | 0) : 0, rows = mock.pv ? (mock.pv.rows | 0) : 0
        if (!g || cols <= 0 || rows <= 0 || g.length < cols * rows)
            return mock.cavaFieldL
        var x = Math.max(0, Math.min(cols - 1, Math.floor(t * cols)))
        return g[(rows - 1) * cols + x]
    }
    function cavaTone(ramp, tv) {
        var r = mock.pv && mock.pv.tones ? mock.pv.tones[ramp] : null
        if (!r)
            return ""
        var best = "", bestD = Infinity
        for (var k in r) {
            var d = Math.abs(Number(k) - tv)
            if (d < bestD) { bestD = d; best = r[k] }
        }
        return best
    }
    function bandColor(t) {
        var bgL = mock.cavaLstar(t)
        var tv = Math.max(30, Math.min(88, bgL + mock.cavaDir * 45))
        var edge = Math.abs(t - 0.5) * 2
        var h = mock.cavaTone(edge > 0.75 ? "secondary" : "primary", tv)
        return h.length ? h : mock.cGreen
    }
    Component.onCompleted: retick()
    Timer { interval: 55; running: mock.visible; repeat: true; onTriggered: mock.retick() }

    Item {
        id: cava
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 14 * mock.s; anchors.rightMargin: 14 * mock.s
        anchors.bottom: parent.bottom; anchors.bottomMargin: 10 * mock.s
        height: parent.height * 0.2
        readonly property real slotW: mock.cavaN > 0 ? width / mock.cavaN : width
        readonly property real barW: Math.max(1.5, slotW * 0.72)

        Repeater {
            model: mock.cavaN
            delegate: Rectangle {
                id: barDel
                required property int index
                readonly property color c: mock.bandColor(mock.cavaN > 1 ? index / (mock.cavaN - 1) : 0)
                readonly property real lv: mock.levels.length > index ? mock.levels[index] : 0.1
                width: cava.barW
                x: index * cava.slotW + (cava.slotW - cava.barW) / 2
                height: Math.max(1.5, cava.height * lv)
                y: cava.height - height
                radius: width / 2
                antialiasing: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.lighter(barDel.c, 1.25) }
                    GradientStop { position: 0.55; color: barDel.c }
                    GradientStop { position: 1.0; color: Qt.rgba(barDel.c.r, barDel.c.g, barDel.c.b, 0.35) }
                }
                Behavior on height { NumberAnimation { duration: Style.animFast } }
            }
        }
    }
}
