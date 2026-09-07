import QtQuick
import Quickshell
import Quickshell.Wayland
import "../modules"
import shell.services
import Ryoku.Ui.Singletons
import "../../../../../services/lib/weather.js" as Wx

// Unified time+weather+calendar dashboard: a bento of frosted islands bound to the
// daemon-fed Weather singleton. Replaces the old clock/weather/calendar popups.
PanelWindow {
    id: dash
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-dashboard"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6

    property real reveal: root.dashboardVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.dashboardVisible ? 220 : 150
            easing.type: root.dashboardVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.dashboardVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── live clock ──
    SystemClock { id: sysClock; precision: SystemClock.Seconds }
    readonly property date now: sysClock.date
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    readonly property string timeMain: {
        if (root.clock12h) { var h = now.getHours() % 12; if (h === 0) h = 12; return h + ":" + pad(now.getMinutes()) }
        return pad(now.getHours()) + ":" + pad(now.getMinutes())
    }
    readonly property string timeSecs: pad(now.getSeconds())
    readonly property string ampm: root.clock12h ? (now.getHours() < 12 ? "AM" : "PM") : ""
    readonly property string weekdayLong: now.toLocaleDateString(Config.formatLoc, "dddd")
    readonly property string dateLong: now.toLocaleDateString(Config.formatLoc, "MMMM d")

    // ── weather (daemon-fed singleton) ──
    readonly property var cur: Weather.current
    readonly property bool wxReady: Weather.available && dash.cur !== null
    readonly property var metrics: dash.wxReady ? [
        { icon: "navigation", rot: (dash.windDeg(dash.cur.windDir) + 180) % 360, label: I18n.tr("WIND"), value: dash.cur.windValue + "" },
        { icon: "humidity_percentage", label: I18n.tr("HUMIDITY"), value: dash.cur.humidity + "%" },
        { icon: "rainy",               label: I18n.tr("RAIN"),  value: dash.cur.precipProb + "%" },
        { icon: "thermostat",          label: I18n.tr("FEELS"), value: dash.cur.feels + "\u00b0" }
    ] : []

    // Tile look (frosted island on the panel): shared tokens.
    readonly property color tileFill: Qt.rgba(root.paper.r, root.paper.g, root.paper.b, 0.05)
    readonly property color tileLine: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.07)
    readonly property int tileRadius: 16

    readonly property bool animate: !Perf.reduceMotion
    readonly property int fxCode: dash.wxReady ? dash.cur.code : 3
    readonly property string fxKind: Wx.glyphFor(dash.fxCode)
    readonly property bool fxDay: dash.wxReady ? dash.cur.isDay : true
    readonly property color fxTint: dash.fxKind === "sun" ? root.seal : root.paper
    // General area only (region/country) -- drop the precise city for privacy.
    function generalArea(loc) {
        var parts = String(loc || "").split(",");
        for (var i = 0; i < parts.length; i++) parts[i] = parts[i].trim();
        parts = parts.filter(function(s) { return s.length > 0; });
        return parts.length >= 2 ? parts.slice(1).join(", ") : (parts.length ? parts[0] : "");
    }
    function windDeg(d) {
        var m = { N: 0, NNE: 22, NE: 45, ENE: 67, E: 90, ESE: 112, SE: 135, SSE: 157, S: 180, SSW: 202, SW: 225, WSW: 247, W: 270, WNW: 292, NW: 315, NNW: 337 };
        var k = String(d || "").toUpperCase();
        return m[k] !== undefined ? m[k] : 0;
    }

    MouseArea { anchors.fill: parent; onClicked: root.dashboardVisible = false }

    Rectangle {
        id: card
        width: 916
        height: 404
        radius: dash.reveal > 0.001 ? root.panelRadius : 0
        color: "transparent"

        PillShadow { theme: dash.root }
        ConnectedPanelSurface {
            root: dash.root
            ownerActive: dash.root.dashboardVisible
            targetX: dash.root.dashboardBarX
            reveal: dash.reveal
        }

        x: Math.round((parent.width - width) / 2)
        y: root.barPosition === "bottom"
            ? (parent.height - dash.barBottom - dash.gap - height) + 6 * (1 - dash.reveal)
            : (dash.barBottom + dash.gap) - 6 * (1 - dash.reveal)
        opacity: dash.reveal
        focus: root.dashboardVisible

        transform: Scale {
            origin.x: card.width / 2
            origin.y: root.barPosition === "bottom" ? card.height : 0
            xScale: 0.975 + 0.025 * dash.reveal
            yScale: 0.975 + 0.025 * dash.reveal
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.dashboardVisible = false; event.accepted = true }
        }
        MouseArea { anchors.fill: parent; onClicked: {} }

        // ═══════════════════════════ bento grid ═══════════════════════════
        Item {
            anchors.fill: parent
            anchors.margins: 18

            readonly property int g: 14
            readonly property int calW: 300

            // ───────────────── calendar island (left, full height) ────────────
            Rectangle {
                id: calTile
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.calW
                radius: dash.tileRadius
                color: dash.tileFill
                border.width: 1; border.color: dash.tileLine

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    Item {
                        width: parent.width
                        height: 22
                        UiText {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            text: "\u2039"
                            color: prevMa.containsMouse ? root.seal : root.sumi
                            font.family: root.mono; font.pixelSize: 18
                            MouseArea { id: prevMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.calendarMonthOffset-- }
                        }
                        UiText {
                            anchors.centerIn: parent
                            text: root.calendarMonthName + "  " + root.calendarYear
                            color: monthMa.containsMouse && root.calendarMonthOffset !== 0 ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 12; font.letterSpacing: 3; font.weight: Font.Medium
                            MouseArea { id: monthMa; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: root.calendarMonthOffset !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.calendarMonthOffset = 0 }
                        }
                        UiText {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: "\u203a"
                            color: nextMa.containsMouse ? root.seal : root.sumi
                            font.family: root.mono; font.pixelSize: 18
                            MouseArea { id: nextMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.calendarMonthOffset++ }
                        }
                    }

                    Row {
                        width: parent.width
                        Repeater {
                            model: ["MO","TU","WE","TH","FR","SA","SU"]
                            delegate: Item {
                                required property string modelData
                                required property int index
                                width: parent.width / 7
                                height: 20
                                UiText {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: index >= 5 ? root.seal : root.inkDeep
                                    opacity: index >= 5 ? 0.8 : 0.6
                                    font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 1.5
                                }
                            }
                        }
                    }

                    Grid {
                        columns: 7
                        rowSpacing: 3
                        columnSpacing: 0
                        width: parent.width
                        Repeater {
                            model: root.calendarCells
                            delegate: Item {
                                required property var modelData
                                required property int index
                                width: parent.width / 7
                                height: 38

                                readonly property int dayOfWeek: index % 7
                                readonly property bool isCurrentMonth: modelData.day !== 0
                                readonly property bool isToday: modelData.today
                                readonly property bool isSelected: isCurrentMonth && root.selectedDay === modelData.day && root.calendarMonthOffset === 0
                                readonly property color textColor: {
                                    if (isToday) return root.seal.hsvValue < 0.5 ? root.paper : root.ink;
                                    if (!isCurrentMonth) return root.inkDeep;
                                    return dayOfWeek >= 5 ? root.seal : root.ink;
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 30; height: 30; radius: 15
                                    color: root.seal
                                    visible: isToday
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 30; height: 30; radius: 15
                                    border.color: root.seal; border.width: 1; color: "transparent"
                                    visible: isSelected && !isToday
                                }
                                UiText {
                                    anchors.centerIn: parent
                                    text: modelData.day === 0 ? "" : modelData.day
                                    color: textColor
                                    opacity: isCurrentMonth ? 1.0 : 0.3
                                    font.family: root.mono; font.pixelSize: 13
                                    font.weight: isToday ? Font.Medium : Font.Light
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: isCurrentMonth
                                    enabled: isCurrentMonth
                                    cursorShape: isCurrentMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.selectedDay = modelData.day
                                }
                            }
                        }
                    }
                }
            }

            // ───────────────── right column: stacked islands ──────────────────
            Item {
                id: rightCol
                anchors { left: calTile.right; leftMargin: parent.g; right: parent.right; top: parent.top; bottom: parent.bottom }

                // clock island
                Rectangle {
                    id: clockTile
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 104
                    radius: dash.tileRadius
                    color: dash.tileFill
                    border.width: 1
                    border.color: clockHov.hovered ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.30) : dash.tileLine
                    clip: true
                    transformOrigin: Item.Center
                    scale: clockHov.hovered && dash.animate ? 1.008 : 1
                    Behavior on scale { enabled: dash.animate; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    HoverHandler { id: clockHov }
                    WeatherFX {
                        anchors.fill: parent
                        anchors.margins: 1
                        kind: dash.fxKind
                        isDay: dash.fxDay
                        tint: dash.fxTint
                        active: dash.reveal > 0.5 && dash.animate
                    }

                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        UiText {
                            anchors.bottom: parent.bottom
                            text: dash.timeMain
                            color: root.ink
                            font.family: root.mono; font.pixelSize: 62; font.weight: Font.Medium
                        }
                        Column {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            spacing: 0
                            UiText { text: dash.ampm; visible: dash.ampm !== ""; color: root.sumiHi; font.family: root.mono; font.pixelSize: 14 }
                            UiText { text: ":" + dash.timeSecs; color: root.seal; font.family: root.mono; font.pixelSize: 20; font.weight: Font.Medium }
                        }
                    }
                    Column {
                        anchors.right: parent.right; anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        UiText { anchors.right: parent.right; text: dash.weekdayLong; color: root.ink; font.family: root.mono; font.pixelSize: 18; font.weight: Font.Medium }
                        UiText { anchors.right: parent.right; text: dash.dateLong; color: root.sumiHi; font.family: root.mono; font.pixelSize: 13 }
                    }
                }

                // weather hero + metrics row
                readonly property int rowY: clockTile.height + 14
                readonly property int rowH: 128
                readonly property int halfW: (width - 14) / 2

                Rectangle {
                    id: heroTile
                    anchors { left: parent.left; top: parent.top; topMargin: rightCol.rowY }
                    width: rightCol.halfW
                    height: rightCol.rowH
                    radius: dash.tileRadius
                    color: dash.tileFill
                    border.width: 1
                    border.color: heroHov.hovered ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.30) : dash.tileLine
                    transformOrigin: Item.Center
                    scale: heroHov.hovered && dash.animate ? 1.01 : 1
                    Behavior on scale { enabled: dash.animate; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    HoverHandler { id: heroHov }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 2
                        Row {
                            spacing: 12
                            IconText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: dash.wxReady ? Wx.symbolFor(dash.cur.code, dash.cur.isDay) : "cloud"
                                color: root.ink
                                font.pixelSize: 46
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0
                                UiText {
                                    text: dash.wxReady ? dash.cur.temperature.replace("\u00b0C", "\u00b0").replace("\u00b0F", "\u00b0") : "\u2014"
                                    color: root.ink
                                    font.family: root.mono; font.pixelSize: 44; font.weight: Font.Medium
                                }
                                UiText {
                                    text: dash.wxReady ? Weather.condition : (Weather.status === "loading" ? I18n.tr("Loading\u2026") : I18n.tr("Offline"))
                                    color: root.seal
                                    font.family: root.mono; font.pixelSize: 13; font.weight: Font.Medium
                                }
                            }
                        }
                        Item { width: 1; height: 4 }
                        UiText {
                            width: parent.width
                            text: dash.generalArea(Weather.location)
                            visible: text !== ""
                            color: root.sumiHi
                            font.family: root.mono; font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    id: metricsTile
                    anchors { right: parent.right; top: parent.top; topMargin: rightCol.rowY }
                    width: rightCol.halfW
                    height: rightCol.rowH
                    radius: dash.tileRadius
                    color: dash.tileFill
                    border.width: 1
                    border.color: metricsHov.hovered ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.30) : dash.tileLine
                    transformOrigin: Item.Center
                    scale: metricsHov.hovered && dash.animate ? 1.01 : 1
                    Behavior on scale { enabled: dash.animate; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    HoverHandler { id: metricsHov }

                    Grid {
                        anchors.centerIn: parent
                        width: parent.width - 28
                        columns: 2
                        rowSpacing: 14
                        columnSpacing: 8
                        visible: dash.wxReady
                        Repeater {
                            model: dash.metrics
                            delegate: Row {
                                required property var modelData
                                width: (parent.width - 8) / 2
                                spacing: 9
                                IconText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.icon
                                    color: root.sumi
                                    font.pixelSize: 20
                                    rotation: modelData.rot ? modelData.rot : 0
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    UiText { text: modelData.value; color: root.ink; font.family: root.mono; font.pixelSize: 17; font.weight: Font.Medium }
                                    UiText { text: I18n.tr(modelData.label); color: root.sumiHi; font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                }
                            }
                        }
                    }
                    UiText {
                        anchors.centerIn: parent
                        visible: !dash.wxReady
                        text: Weather.status === "loading" ? I18n.tr("Loading\u2026") : I18n.tr("Weather offline")
                        color: root.sumiHi; font.family: root.mono; font.pixelSize: 12
                    }
                }

                // temperature area-graph island (coming hours)
                Rectangle {
                    id: graphTile
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: rightCol.rowY + rightCol.rowH + 14; bottom: parent.bottom }
                    radius: dash.tileRadius
                    color: dash.tileFill
                    border.width: 1
                    border.color: graphHov.hovered ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.30) : dash.tileLine
                    transformOrigin: Item.Center
                    scale: graphHov.hovered && dash.animate ? 1.01 : 1
                    Behavior on scale { enabled: dash.animate; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    HoverHandler { id: graphHov }
                    property real graphProg: dash.reveal > 0.9 ? 1 : 0
                    Behavior on graphProg { enabled: dash.animate; NumberAnimation { duration: 640; easing.type: Easing.OutCubic } }
                    onGraphProgChanged: curve.requestPaint()
                    clip: true

                    readonly property int n: Math.min(8, Weather.hourly.length)
                    readonly property int padX: 20
                    // Vertical bands: a top gap so the highest temperature label
                    // clears the tile edge, and a bottom axis strip sized for the
                    // glyph+hour column so neither number clips.
                    readonly property int curveTop: 20
                    readonly property int axisH: 30
                    readonly property int curveBot: height - axisH - 6
                    function tempY(norm) { return curveBot - norm * (curveBot - curveTop) }
                    function px(i) { return padX + (width - 2 * padX) * (n > 1 ? (i + 0.5) / n : 0.5) }

                    Canvas {
                        id: curve
                        anchors.fill: parent
                        visible: dash.wxReady && graphTile.n >= 2
                        Connections { target: dash; function onRevealChanged() { curve.requestPaint() } }
                        Connections { target: Weather; function onHourlyChanged() { curve.requestPaint() } }
                        onWidthChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset();
                            ctx.save(); ctx.beginPath(); ctx.rect(0, 0, width * graphTile.graphProg, height); ctx.clip();
                            var n = graphTile.n; if (n < 2) return;
                            var top = graphTile.curveTop, bot = graphTile.curveBot;
                            var lo = 1e9, hi = -1e9, i;
                            for (i = 0; i < n; i++) { var t = Weather.hourly[i].temp; if (t < lo) lo = t; if (t > hi) hi = t; }
                            if (hi - lo < 1) { hi += 1; lo -= 1; }
                            var pts = [];
                            for (i = 0; i < n; i++) {
                                var norm = (Weather.hourly[i].temp - lo) / (hi - lo);
                                pts.push({ x: graphTile.px(i), y: bot - norm * (bot - top) });
                            }
                            var sr = Math.round(root.seal.r * 255), sg = Math.round(root.seal.g * 255), sb = Math.round(root.seal.b * 255);
                            // filled area under a smooth curve
                            ctx.beginPath(); ctx.moveTo(pts[0].x, pts[0].y);
                            for (i = 0; i < n - 1; i++) {
                                var xm = (pts[i].x + pts[i + 1].x) / 2, ym = (pts[i].y + pts[i + 1].y) / 2;
                                ctx.quadraticCurveTo(pts[i].x, pts[i].y, xm, ym);
                            }
                            ctx.lineTo(pts[n - 1].x, pts[n - 1].y);
                            ctx.lineTo(pts[n - 1].x, bot + 4); ctx.lineTo(pts[0].x, bot + 4); ctx.closePath();
                            var grad = ctx.createLinearGradient(0, top, 0, bot);
                            grad.addColorStop(0, "rgba(" + sr + "," + sg + "," + sb + ",0.30)");
                            grad.addColorStop(1, "rgba(" + sr + "," + sg + "," + sb + ",0.02)");
                            ctx.fillStyle = grad; ctx.fill();
                            // curve stroke
                            ctx.beginPath(); ctx.moveTo(pts[0].x, pts[0].y);
                            for (i = 0; i < n - 1; i++) {
                                var xm2 = (pts[i].x + pts[i + 1].x) / 2, ym2 = (pts[i].y + pts[i + 1].y) / 2;
                                ctx.quadraticCurveTo(pts[i].x, pts[i].y, xm2, ym2);
                            }
                            ctx.lineTo(pts[n - 1].x, pts[n - 1].y);
                            ctx.lineWidth = 2; ctx.lineCap = "round"; ctx.lineJoin = "round";
                            ctx.strokeStyle = "rgba(" + sr + "," + sg + "," + sb + ",0.95)"; ctx.stroke();
                            // "now" marker
                            ctx.beginPath(); ctx.arc(pts[0].x, pts[0].y, 4, 0, 2 * Math.PI);
                            ctx.fillStyle = "rgba(" + sr + "," + sg + "," + sb + ",1)"; ctx.fill();
                            ctx.restore();
                        }
                    }

                    // temperature labels above each point
                    Repeater {
                        model: dash.wxReady ? graphTile.n : 0
                        delegate: UiText {
                            required property int index
                            readonly property var h: Weather.hourly[index]
                            readonly property real norm: {
                                var n = graphTile.n, lo = 1e9, hi = -1e9;
                                for (var i = 0; i < n; i++) { var t = Weather.hourly[i].temp; if (t < lo) lo = t; if (t > hi) hi = t; }
                                if (hi - lo < 1) { hi += 1; lo -= 1; }
                                return (h.temp - lo) / (hi - lo);
                            }
                            x: graphTile.px(index) - width / 2
                            y: graphTile.tempY(norm) - 16
                            text: h.temp + "\u00b0"
                            color: index === 0 ? root.seal : root.inkDeep
                            font.family: root.mono; font.pixelSize: 10; font.weight: index === 0 ? Font.Medium : Font.Normal
                        }
                    }

                    // hour + glyph axis
                    Repeater {
                        model: dash.wxReady ? graphTile.n : 0
                        delegate: Column {
                            required property int index
                            readonly property var h: Weather.hourly[index]
                            x: graphTile.px(index) - width / 2
                            width: 34
                            y: graphTile.height - graphTile.axisH
                            spacing: 0
                            IconText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Wx.symbolFor(h.code, h.isDay)
                                color: index === 0 ? root.ink : root.sumi
                                font.pixelSize: 13
                            }
                            UiText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: h.time
                                color: index === 0 ? root.seal : root.sumiHi
                                font.family: root.mono; font.pixelSize: 9
                            }
                        }
                    }

                    UiText {
                        anchors.centerIn: parent
                        visible: !(dash.wxReady && graphTile.n >= 2)
                        text: Weather.status === "loading" ? I18n.tr("Loading\u2026") : I18n.tr("Hourly forecast unavailable")
                        color: root.sumiHi; font.family: root.mono; font.pixelSize: 12
                    }
                }
            }
        }
    }
}
