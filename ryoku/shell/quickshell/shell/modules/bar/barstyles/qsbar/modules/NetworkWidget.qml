import QtQuick
import Quickshell
import Quickshell.Io
import "../IconMap.js" as IconMap
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root
    readonly property color contentColor: root.widgetContentColor("G11", root.widgetIconColor)

    property string mode:   "none"  // "wifi" | "ethernet" | "none"
    property string ssid:   ""
    property int    signal: 0
    property string iface:  ""

    // ── speed tracking ──
    property real prevRx:  -1
    property real prevTx:  -1
    property real prevMs:   0
    property real dlRate:   0
    property real ulRate:   0

    function formatSpeed(bps) {
        var mb = bps / 1048576
        var s = mb < 10 ? mb.toFixed(2) : mb.toFixed(1)
        return s.padStart(5) + "M"  // always 6 chars: " 0.00M" … "100.0M"
    }

    function formatBarRate(bps) {
        var value = Math.max(0, Number(bps) || 0)
        if (value >= 1073741824) {
            var gib = value / 1073741824
            return (gib < 10 ? gib.toFixed(1) : gib.toFixed(0)) + "G"
        }
        if (value >= 1048576) {
            var mib = value / 1048576
            return (mib < 10 ? mib.toFixed(1) : mib.toFixed(0)) + "M"
        }
        if (value >= 1024) {
            var kib = value / 1024
            return (kib < 10 ? kib.toFixed(1) : kib.toFixed(0)) + "K"
        }
        return "0K"
    }

    function trafficLevel(bps) {
        var value = Math.max(0, Number(bps) || 0)
        if (value <= 0) return 0
        // Log scale keeps ordinary KiB traffic visible while still leaving
        // headroom up to roughly a saturated gigabit link.
        return Math.min(1, Math.log(1 + value / 1024) / Math.log(1 + 102400))
    }

    function updateSpeeds(rx, tx, now) {
        if (prevRx >= 0 && prevMs > 0) {
            var dt = (now - prevMs) / 1000
            if (dt > 0) {
                dlRate = Math.max(0, (rx - prevRx) / dt)
                ulRate = Math.max(0, (tx - prevTx) / dt)
            }
        }
        prevRx = rx; prevTx = tx; prevMs = now
    }

    readonly property var wifiIcons: [
        "signal_wifi_0_bar", "network_wifi_1_bar", "network_wifi_2_bar",
        "network_wifi_3_bar", "signal_wifi_4_bar"
    ]
    readonly property string wifiIconName: signal > 0
        ? wifiIcons[Math.min(4, Math.floor(signal / 22))]
        : "signal_wifi_off"

    readonly property string tooltipText: {
        if (mode === "none") return I18n.tr("Offline")
        var rate = "↓ " + formatSpeed(dlRate) + "/s  ↑ " + formatSpeed(ulRate) + "/s"
        return mode === "wifi" ? (ssid + " · " + signal + "%  ·  " + rate) : rate
    }

    // The widget's own toggle is authoritative. It used to lose to `mode === "wifi"`,
    // which meant a user on wifi could never take the widget off the bar.
    implicitWidth: root.modNetwork ? (row.implicitWidth + 18) : 0
    // mirror the connection type so the ControlPanel can gate the Network toggle
    Binding { target: rootMod.root; property: "networkMode"; value: rootMod.mode }
    implicitHeight: 28

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        // ── wifi: icon ──
        IconText {
            anchors.verticalCenter: parent.verticalCenter
            visible: rootMod.mode === "wifi"
            text: IconMap.icon(rootMod.wifiIconName)
            color: rootMod.contentColor
            font.pixelSize: 15
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        IconText {
            anchors.verticalCenter: parent.verticalCenter
            visible: rootMod.mode !== "wifi"
            text: IconMap.icon(rootMod.mode === "ethernet" ? "lan" : "signal_wifi_off")
            color: rootMod.mode === "ethernet"
                ? rootMod.contentColor
                : Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, 0.65)
            font.pixelSize: rootMod.mode === "ethernet" ? 14 : 15
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        // The SSID, capped at 88px. Its width is measured off to the side rather
        // than read from the label's own implicitWidth: with elide set that is
        // circular, and Qt breaks the loop by leaving the label at zero width,
        // which is why the network name never appeared at full density.
        TextMetrics {
            id: ssidMetrics
            font: ssidLabel.font
            text: ssidLabel.text
        }
        UiText {
            id: ssidLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: rootMod.mode === "wifi" && !root.iconOnly("G11")
            width: visible ? Math.min(88, Math.ceil(ssidMetrics.width)) : 0
            text: rootMod.ssid !== "" ? rootMod.ssid : I18n.tr("Wi-Fi")
            color: rootMod.contentColor
            font.family: root.mono
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Item {
            id: trafficMeter
            anchors.verticalCenter: parent.verticalCenter
            // Throughput is read off the default route whatever the link is, so
            // the meter belongs on wifi too: full density means icon, label, stats.
            visible: rootMod.mode !== "none" && !root.iconOnly("G11")
            width: visible ? 16 : 0
            height: 20

            readonly property real rxLevel: rootMod.trafficLevel(rootMod.dlRate)
            readonly property real txLevel: rootMod.trafficLevel(rootMod.ulRate)

            UiText {
                x: 0; y: 0
                width: 8; height: 8
                text: "RX"
                color: Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, 0.72)
                font.family: root.mono
                font.pixelSize: 7
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            Column {
                x: 2; y: 8
                spacing: 1
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        width: 4; height: 2; radius: 1
                        color: trafficMeter.rxLevel > index / 4
                            ? rootMod.contentColor
                            : Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, 0.18)
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                }
            }

            Column {
                x: 10; y: 1
                spacing: 1
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        width: 4; height: 2; radius: 1
                        color: trafficMeter.txLevel > (3 - index) / 4
                            ? rootMod.contentColor
                            : Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, 0.18)
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                }
            }
            UiText {
                x: 8; y: 13
                width: 8; height: 8
                text: "TX"
                color: Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, 0.72)
                font.family: root.mono
                font.pixelSize: 7
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

    }

    Process {
        id: netProc
        command: ["bash", "-c",
            "IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}'); " +
            "if [ -z \"$IFACE\" ]; then echo NONE; exit; fi; " +
            "RX=$(awk -v i=\"$IFACE:\" '$1==i{print $2}' /proc/net/dev 2>/dev/null); " +
            "TX=$(awk -v i=\"$IFACE:\" '$1==i{print $10}' /proc/net/dev 2>/dev/null); " +
            "if [ -d \"/sys/class/net/$IFACE/wireless\" ]; then " +
            "  LINK=$(iw dev \"$IFACE\" link 2>/dev/null); " +
            "  SSID=$(printf '%s\\n' \"$LINK\" | sed -n 's/^\\s*SSID: //p' | head -1); " +
            "  if [[ \"$SSID\" =~ \\\\(x[0-9A-Fa-f]{2}|[0-7]{3}) ]]; then SSID=$(printf '%b' \"$SSID\"); fi; " +
            "  SIG=$(printf '%s\\n' \"$LINK\" | awk '/signal:/ {print int($2); exit}'); " +
            "  QUAL=$(awk -v s=\"$SIG\" 'BEGIN{q=int((s+110)*100/70);if(q<0)q=0;if(q>100)q=100;print q}'); " +
            "  printf 'WIFI\\t%s\\t%s\\t%s\\t%s\\n' \"$SSID\" \"$QUAL\" \"$RX\" \"$TX\"; " +
            "else " +
            "  printf 'ETHERNET\\t%s\\t%s\\t%s\\n' \"$IFACE\" \"$RX\" \"$TX\"; " +
            "fi"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var line  = this.text.trim()
                var parts = line.split("\t")
                var now   = Date.now()

                if (parts[0] === "WIFI" && parts.length >= 5) {
                    rootMod.mode   = "wifi"
                    rootMod.ssid   = parts[1] || ""
                    rootMod.signal = parseInt(parts[2]) || 0
                    rootMod.updateSpeeds(parseFloat(parts[3]) || 0, parseFloat(parts[4]) || 0, now)
                } else if (parts[0] === "ETHERNET" && parts.length >= 4) {
                    rootMod.mode  = "ethernet"
                    rootMod.iface = parts[1] || ""
                    rootMod.updateSpeeds(parseFloat(parts[2]) || 0, parseFloat(parts[3]) || 0, now)
                } else {
                    rootMod.mode  = "none"
                    rootMod.prevRx = -1; rootMod.prevTx = -1
                }
            }
        }
    }

    // Dynamic poll cadence. Fast (2 s) whenever something needs fresh data: the pill is shown
    // (root.modNetwork), the panel is open (root.networkVisible - also covers a running speed
    // test, which keeps the panel open), or we're on Wi-Fi (signal % moves; the Wi-Fi branch is
    // also the only one that spawns `iw`). Slow (15 s) ONLY when the module is hidden AND the
    // panel is closed AND we're on Ethernet or offline - so the saving (fewer idle bash/ip/awk
    // spawns) is limited to a hidden Ethernet module or the offline state; Wi-Fi always polls
    // fast. When hidden on Ethernet/offline, poll only once per minute to catch a later Wi-Fi
    // connection without keeping the old high-rate hidden poller alive. Changing a Timer's
    // interval does not force a tick, so refresh once immediately on becoming relevant.
    readonly property bool fastPoll: root.modNetwork || root.networkVisible || mode === "wifi"
    onFastPollChanged: if (fastPoll) { netProc.running = false; netProc.running = true }

    Timer {
        interval: rootMod.fastPoll ? 2000 : 60000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: { netProc.running = false; netProc.running = true }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    Process { id: clickRunner; command: ["bash", "-c", root.launchWifiCmd] }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tip.show()
        onExited:  { tip.hide() }
        onClicked: (e) => {
            tip.hide()
            if (e.button === Qt.RightButton) { clickRunner.running = false; clickRunner.running = true }
            else root.networkVisible = !root.networkVisible
        }
    }
}
