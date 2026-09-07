pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"
import Ryoku.Ui.Singletons

/**
 * A live, plain-QML preview of the desktop clock widget for the Desktop Widgets
 * section, so the chosen face, date design, format and accent show at a glance
 * without leaning over the hub window to the wallpaper. It mirrors the live faces
 * in ryoku/shell/quickshell/shell/modules/desktop/clock; the accent follows your real
 * palette (Scheme singleton), the rest is bright ink as on the wallpaper.
 */
Item {
    id: preview

    property string design: "digital"
    property bool is24: true
    property bool seconds: false
    property string accentChoice: "palette"
    property bool dateShow: true
    property string dateDesign: "inline"

    readonly property color ink: "#f5f3ff"
    readonly property color inkSoft: "#d2d7ef"
    readonly property color inkDim: "#9aa3c8"
    readonly property color accent: preview.accentChoice === "brand" ? "#F25623"
        : preview.accentChoice === "mono" ? preview.ink : Scheme.accent

    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: preview.now = new Date() }

    function pad2(n) { return (n < 10 ? "0" : "") + n; }
    readonly property int h: now.getHours()
    readonly property int mins: now.getMinutes()
    readonly property int secs: now.getSeconds()
    readonly property int h12: (h % 12) === 0 ? 12 : (h % 12)
    readonly property string hh: preview.is24 ? pad2(h) : String(h12)
    readonly property string mm: pad2(mins)
    readonly property string ss: pad2(secs)
    readonly property string ampm: h < 12 ? I18n.tr("AM") : I18n.tr("PM")

    readonly property var weekdays: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var weekdaysShort: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property int dow: now.getDay()
    readonly property int dom: now.getDate()
    readonly property int monIdx: now.getMonth()

    Column {
        anchors.centerIn: parent
        spacing: 14

        Loader {
            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: preview.faceFor()
        }
        Loader {
            anchors.horizontalCenter: parent.horizontalCenter
            active: preview.dateShow
            visible: preview.dateShow
            sourceComponent: preview.dateShow ? preview.dateFor() : null
        }
    }

    function faceFor() {
        switch (preview.design) {
        case "minimal": return minimalC;
        case "analog":  return analogC;
        case "flip":    return flipC;
        case "rings":   return ringsC;
        case "bighour": return bighourC;
        case "metal":   return metalC;
        case "goodnight": return goodnightC;
        case "grand":   return grandC;
        case "column":  return columnC;
        case "outline": return outlineC;
        case "banner":  return bannerC;
        default:        return digitalC;
        }
    }
    function dateFor() {
        switch (preview.dateDesign) {
        case "badge":   return badgeC;
        case "stacked": return stackedC;
        default:        return inlineC;
        }
    }

    // --- faces -------------------------------------------------------------
    Component {
        id: digitalC
        Row {
            spacing: preview.seconds || !preview.is24 ? 10 : 0
            Row {
                spacing: 0
                Text { text: preview.hh; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 56; font.weight: Font.Bold }
                Text {
                    text: ":"; color: preview.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 56; font.weight: Font.Bold
                    SequentialAnimation on opacity { loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.3; duration: 620; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.3; to: 1; duration: 620; easing.type: Easing.InOutSine } }
                }
                Text { text: preview.mm; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 56; font.weight: Font.Bold }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text { visible: preview.seconds; text: preview.ss; color: preview.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 17; font.weight: Font.DemiBold }
                Text { visible: !preview.is24; text: preview.ampm; color: preview.inkDim; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; font.weight: Font.DemiBold }
            }
        }
    }

    Component {
        id: minimalC
        Column {
            spacing: 8
            Text { id: mt; text: preview.hh + ":" + preview.mm; color: preview.ink; font.family: "Inter"; font.pixelSize: 54; font.weight: Font.Light; font.letterSpacing: 2 }
            Rectangle { width: mt.implicitWidth * 0.34; height: 3; radius: Theme.radius; color: preview.accent }
            Text {
                visible: preview.seconds || !preview.is24
                text: (preview.seconds ? preview.ss : "") + (preview.seconds && !preview.is24 ? "  " : "") + (!preview.is24 ? preview.ampm.toLowerCase() : "")
                color: preview.inkDim; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.Medium; font.letterSpacing: 3
            }
        }
    }

    Component {
        id: analogC
        Item {
            implicitWidth: 132; implicitHeight: 132
            Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14) }
            Repeater {
                model: 12
                Item {
                    required property int index
                    anchors.fill: parent
                    rotation: index * 30
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter; y: 6
                        width: parent.index % 3 === 0 ? 3 : 2; height: parent.index % 3 === 0 ? 10 : 6
                        radius: width / 2; color: parent.index % 3 === 0 ? preview.ink : preview.inkDim
                    }
                }
            }
            Rectangle { x: (parent.width - width) / 2; y: parent.height / 2 - height; width: 5; height: parent.height * 0.28; radius: Theme.radius; color: preview.ink; antialiasing: true; transformOrigin: Item.Bottom; rotation: (preview.h % 12 + preview.mins / 60) * 30 }
            Rectangle { x: (parent.width - width) / 2; y: parent.height / 2 - height; width: 4; height: parent.height * 0.40; radius: Theme.radius; color: preview.ink; antialiasing: true; transformOrigin: Item.Bottom; rotation: (preview.mins + preview.secs / 60) * 6 }
            Rectangle { x: (parent.width - width) / 2; y: parent.height / 2 - height; width: 2; height: parent.height * 0.44; radius: Theme.radius; color: preview.accent; antialiasing: true; transformOrigin: Item.Bottom; rotation: preview.secs * 6 }
            Rectangle { anchors.centerIn: parent; width: 9; height: 9; radius: 4.5; color: preview.accent; border.width: 1.5; border.color: preview.ink }
        }
    }

    Component {
        id: flipC
        Row {
            spacing: 5
            Repeater {
                model: [preview.is24 ? preview.hh.charAt(0) : preview.pad2(preview.h12).charAt(0),
                        preview.is24 ? preview.hh.charAt(1) : preview.pad2(preview.h12).charAt(1),
                        ":", preview.mm.charAt(0), preview.mm.charAt(1)]
                Item {
                    required property var modelData
                    readonly property bool colon: modelData === ":"
                    width: colon ? 18 : 46
                    height: 64
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        visible: !parent.colon
                        anchors.fill: parent
                        radius: Theme.radius
                        color: Qt.rgba(0, 0, 0, 0.55)
                        border.width: 1
                        border.color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.24)
                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 1; color: Qt.rgba(0, 0, 0, 0.4) }
                    }
                    Text { anchors.centerIn: parent; text: parent.modelData; color: parent.colon ? preview.accent : preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: parent.colon ? 34 : 40; font.weight: Font.Bold }
                }
            }
        }
    }

    Component {
        id: ringsC
        Item {
            implicitWidth: 138; implicitHeight: 138
            Canvas {
                id: rc
                anchors.fill: parent
                readonly property var key: [preview.now, preview.accent]
                onKeyChanged: requestPaint()
                function css(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"; }
                onPaint: {
                    var ctx = getContext("2d"); var w = width; ctx.reset(); ctx.clearRect(0, 0, w, w);
                    var cx = w / 2, lw = w * 0.05, gap = lw * 1.75, r0 = w / 2 - lw * 0.7 - 2;
                    var radii = [r0 - 2 * gap, r0 - gap, r0];
                    var fr = [((preview.h % 12) + preview.mins / 60) / 12, (preview.mins + preview.secs / 60) / 60, preview.secs / 60];
                    var tints = preview.accentChoice === "palette"
                        ? [Scheme.colorAt(0.2), Scheme.colorAt(0.5), Scheme.colorAt(0.85)]
                        : [preview.accent, preview.accent, preview.accent];
                    for (var i = 0; i < 3; i++) {
                        ctx.beginPath(); ctx.lineWidth = lw; ctx.lineCap = "butt"; ctx.strokeStyle = rc.css(preview.ink, 0.12);
                        ctx.arc(cx, cx, radii[i], 0, 2 * Math.PI, false); ctx.stroke();
                        if (fr[i] > 0.0001) {
                            ctx.beginPath(); ctx.lineWidth = lw; ctx.lineCap = "round"; ctx.strokeStyle = rc.css(tints[i], 1);
                            ctx.arc(cx, cx, radii[i], -Math.PI / 2, -Math.PI / 2 + fr[i] * 2 * Math.PI, false); ctx.stroke();
                        }
                    }
                }
            }
            Text { anchors.centerIn: parent; text: preview.hh + ":" + preview.mm; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 22; font.weight: Font.Bold }
        }
    }

    // hollow outlined text via Canvas strokeText (big-hour month + seconds),
    // copied from the tuned preview /tmp/refimg/p1_bighour.qml.
    component Hollow: Canvas {
        property string txt: ""
        property real ps: 90
        property real lw: 2.2
        property real track: 0
        readonly property string fam: "Inter Display"
        implicitWidth: _measure()
        implicitHeight: ps * 1.02
        function _measure() {
            var c = getContext("2d"); if (!c) return ps * txt.length * 0.6;
            c.font = "900 " + ps + "px '" + fam + "'";
            var wd = 0; for (var i = 0; i < txt.length; i++) { wd += c.measureText(txt[i]).width + track; }
            return Math.ceil(wd + lw * 2 + ps * 0.08);
        }
        readonly property var key: [txt, ps, lw, track]
        onKeyChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset(); c.clearRect(0, 0, width, height);
            c.font = "900 " + ps + "px '" + fam + "'";
            c.textBaseline = "alphabetic"; c.lineWidth = lw; c.strokeStyle = preview.ink;
            c.lineJoin = "round";
            var x = 0, y = ps * 0.82;
            for (var i = 0; i < txt.length; i++) { c.strokeText(txt[i], x, y); x += c.measureText(txt[i]).width + track; }
        }
        Component.onCompleted: requestPaint()
    }
    Component {
        id: grandC
        Row {
            spacing: preview.seconds || !preview.is24 ? 8 : 0
            Row {
                id: gHm
                spacing: 0
                Text { text: preview.hh; color: preview.ink; font.family: "Fraunces"; font.weight: Font.Medium; font.pixelSize: 72 }
                Text { text: ":"; color: preview.accent; font.family: "Fraunces"; font.weight: Font.Medium; font.pixelSize: 72 }
                Text { text: preview.mm; color: preview.ink; font.family: "Fraunces"; font.weight: Font.Medium; font.pixelSize: 72 }
            }
            Item {
                height: gHm.height
                width: Math.max(gSec.implicitWidth, gAmpm.implicitWidth)
                visible: preview.seconds || !preview.is24
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text { id: gSec; visible: preview.seconds; text: preview.ss; color: preview.accent; font.family: "Fraunces"; font.pixelSize: 20 }
                    Text { id: gAmpm; visible: !preview.is24; text: preview.ampm; color: preview.inkDim; font.family: "Space Grotesk"; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 2 }
                }
            }
        }
    }
    Component {
        id: columnC
        Column {
            spacing: -14
            Text { text: preview.hh; color: preview.ink; font.family: "Space Grotesk"; font.weight: Font.Bold; font.pixelSize: 66; font.letterSpacing: -1 }
            Text { text: preview.mm; color: preview.accent; font.family: "Space Grotesk"; font.weight: Font.Bold; font.pixelSize: 66; font.letterSpacing: -1 }
            Row {
                spacing: 6
                topPadding: 6
                visible: preview.seconds || !preview.is24
                Text { visible: preview.seconds; text: preview.ss; color: preview.inkDim; font.family: "Space Grotesk"; font.weight: Font.DemiBold; font.pixelSize: 15 }
                Text { visible: !preview.is24; text: preview.ampm; color: preview.inkDim; font.family: "Space Grotesk"; font.weight: Font.DemiBold; font.pixelSize: 15; font.letterSpacing: 2 }
            }
        }
    }
    Component {
        id: outlineC
        Row {
            spacing: 4
            Hollow { anchors.verticalCenter: parent.verticalCenter; txt: preview.hh; ps: 76; lw: 2.4 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ":"; color: preview.accent; font.family: "Space Grotesk"; font.weight: Font.Bold; font.pixelSize: 76 }
            Hollow { anchors.verticalCenter: parent.verticalCenter; txt: preview.mm; ps: 76; lw: 2.4 }
        }
    }

    // banner: NibrasShell's wide readout -- hh:mm AP - MM/DD; the colon carries the accent.
    Component {
        id: bannerC
        Row {
            spacing: 9
            Row {
                id: bHm
                spacing: 0
                anchors.verticalCenter: parent.verticalCenter
                Text { text: preview.hh; color: preview.ink; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 64; font.letterSpacing: -1 }
                Text { text: ":"; color: preview.accent; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 64; font.letterSpacing: -1 }
                Text { text: preview.mm; color: preview.ink; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 64; font.letterSpacing: -1 }
            }
            Text {
                visible: !preview.is24
                anchors.bottom: bHm.bottom
                anchors.bottomMargin: 10
                text: preview.ampm; color: preview.inkDim
                font.family: "Inter"; font.weight: Font.DemiBold
                font.pixelSize: 13; font.letterSpacing: 2
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "\u2013"; color: preview.inkDim; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 64 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: preview.pad2(preview.monIdx + 1) + "/" + preview.pad2(preview.dom); color: preview.ink; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 64; font.letterSpacing: -1 }
        }
    }

    // big-hour: weekday/day + hollow month | giant hour | minute + hollow second
    Component {
        id: bighourC
        Row {
            spacing: 22
            Column {
                anchors.bottom: parent.bottom
                spacing: 2
                Text {
                    text: (preview.weekdaysShort[preview.dow] + ", " + preview.pad2(preview.dom)).toUpperCase()
                    color: preview.ink; font.family: "Inter Display"; font.weight: Font.Bold
                    font.pixelSize: 33; font.letterSpacing: 2
                }
                Hollow { txt: preview.months[preview.monIdx].toUpperCase(); ps: 74; lw: 2.0; track: 1 }
                Item { width: 1; height: 30 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: preview.hh; color: preview.ink
                font.family: "Inter Display"; font.weight: Font.Black
                font.pixelSize: 300; font.letterSpacing: -8
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    text: preview.mm; color: preview.ink
                    font.family: "Inter Display"; font.weight: Font.Black
                    font.pixelSize: 116; font.letterSpacing: -4
                }
                Hollow { visible: preview.seconds; txt: preview.ss; ps: 116; lw: 2.6 }
            }
        }
    }

    // metal: heavy condensed time over a "Weekday | Clear · 23°" sample line
    Component {
        id: metalC
        Column {
            spacing: 12
            Text {
                text: preview.hh + ":" + preview.mm; color: preview.ink
                font.family: "Inter Display"; font.weight: Font.Black
                font.pixelSize: 132; font.letterSpacing: -2
            }
            Text {
                text: (preview.is24 ? "" : preview.ampm + "  |  ")
                    + preview.weekdays[preview.dow] + I18n.tr("  |  Clear  \u00b7  23\u00b0")
                color: preview.ink; font.family: "Inter Display"; font.weight: Font.Bold
                font.pixelSize: 25; font.letterSpacing: 0.5
            }
        }
    }

    // good-night: greeting card with vertical rules; the faux-kana weekday is
    // approximated by a heavy, wide-tracked weekday (exact kana isn't needed in
    // a thumbnail).
    Component {
        id: goodnightC
        Column {
            spacing: 26
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: 70; color: preview.ink; opacity: 0.85 }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("GOOD"); color: preview.ink
                    font.family: "Inter Display"; font.weight: Font.Medium
                    font.pixelSize: 26; font.letterSpacing: 10
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: preview.h >= 5 && preview.h < 12 ? I18n.tr("MORNING")
                        : preview.h >= 12 && preview.h < 17 ? I18n.tr("AFTERNOON")
                        : preview.h >= 17 && preview.h < 21 ? I18n.tr("EVENING") : I18n.tr("NIGHT")
                    color: preview.ink; font.family: "Inter Display"; font.weight: Font.Medium
                    font.pixelSize: 26; font.letterSpacing: 10
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: preview.weekdaysShort[preview.dow].toUpperCase(); color: preview.ink
                font.family: "Inter Display"; font.weight: Font.Black
                font.pixelSize: 54; font.letterSpacing: 12
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: preview.pad2(preview.dom) + " " + preview.months[preview.monIdx].toUpperCase()
                color: preview.ink; font.family: "Inter Display"; font.weight: Font.DemiBold
                font.pixelSize: 22; font.letterSpacing: 4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: preview.hh + ":" + preview.mm + (preview.is24 ? "" : " " + preview.ampm)
                color: preview.ink; font.family: "Inter Display"; font.weight: Font.Medium
                font.pixelSize: 22; font.letterSpacing: 3
            }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: 70; color: preview.ink; opacity: 0.85 }
        }
    }

    // --- date designs ------------------------------------------------------
    Component {
        id: inlineC
        Row {
            spacing: 8
            Text { text: preview.weekdays[preview.dow]; color: preview.accent; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.DemiBold }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "\u00b7"; color: preview.inkDim; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.Bold }
            Text { text: preview.months[preview.monIdx] + " " + preview.dom; color: preview.inkSoft; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.Medium }
        }
    }
    Component {
        id: badgeC
        Rectangle {
            implicitWidth: bi.implicitWidth + 24; implicitHeight: bi.implicitHeight + 14; radius: Theme.radius
            color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.16)
            border.width: 1; border.color: Qt.rgba(preview.accent.r, preview.accent.g, preview.accent.b, 0.42)
            Row {
                id: bi
                anchors.centerIn: parent; spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: preview.dom; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 34; font.weight: Font.Bold }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 1
                    Text { text: preview.weekdaysShort[preview.dow].toUpperCase(); color: preview.accent; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold; font.letterSpacing: 2 }
                    Text { text: preview.months[preview.monIdx]; color: preview.inkSoft; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.Medium }
                }
            }
        }
    }
    Component {
        id: stackedC
        Row {
            spacing: 12
            Text { anchors.verticalCenter: parent.verticalCenter; text: preview.dom; color: preview.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 44; font.weight: Font.Bold }
            Column {
                anchors.verticalCenter: parent.verticalCenter; spacing: 2
                Text { text: preview.weekdays[preview.dow]; color: preview.accent; font.family: "Inter"; font.pixelSize: 19; font.weight: Font.DemiBold }
                Text { text: preview.months[preview.monIdx] + " " + preview.now.getFullYear(); color: preview.inkDim; font.family: "Inter"; font.pixelSize: 15; font.weight: Font.Medium }
            }
        }
    }
}
