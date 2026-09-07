pragma ComponentBehavior: Bound

import QtQuick
import ".."
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// Network popout: a frame-edge card (shared PopoutCard, so it opens and melts
// like the music card) leading with the current link (wired or the joined
// Wi-Fi), then the available networks as compact rows -- tap an open or saved
// one to join, or expand a secured one for its password. Wi-Fi power and scan
// ride the head. All live off the daemon `network` topic via the Network
// singleton; the surface takes on-demand keyboard only while a password field
// is focused, and dismisses on an outside click.
Item {
    id: root

    property real s: 1
    property bool open: false

    readonly property real pad: 11 * root.s
    readonly property color ink: Theme.ink(Theme.effectiveSurface)
    readonly property color inkDim: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
    readonly property color line: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.14)

    readonly property bool wifiOn: Network.wifiRadio
    readonly property bool wiredUp: Network.kind === "ethernet"
    readonly property bool wifiUp: Network.kind === "wifi"
    readonly property string activeSsid: Network.activeSsid
    readonly property bool anyLink: root.wifiOn || root.wiredUp
    property bool scanning: false

    // available networks: one row per SSID+band, the strongest AP kept and the
    // list sorted by signal descending. keying by SSID alone dropped a dual-band
    // SSID's 5 GHz BSS; only the connected band row is filtered, so a link on
    // 2.4 GHz still leaves the same SSID's 5 GHz row pickable.
    readonly property var availableNets: {
        const aps = Network.accessPoints;
        let activeBand = "";
        for (let a = 0; a < aps.length; a++) {
            if (aps[a] && aps[a].active) {
                activeBand = aps[a].band || "";
                break;
            }
        }
        const best = ({});
        for (let i = 0; i < aps.length; i++) {
            const ap = aps[i];
            if (!ap || !ap.ssid)
                continue;
            if (ap.ssid === root.activeSsid && (activeBand === "" || (ap.band || "") === activeBand))
                continue;
            const key = ap.ssid + "\u0000" + (ap.band || "");
            const prev = best[key];
            if (!prev || (ap.strength || 0) > (prev.strength || 0))
                best[key] = ap;
        }
        const out = [];
        for (const k in best)
            out.push(best[k]);
        out.sort((x, y) => (y.strength || 0) - (x.strength || 0));
        return out;
    }

    // SSIDs seen on more than one band in the scan: a row shows its band chip
    // only for these, so single-band networks read exactly as before. Counted
    // over every scanned AP, not the rendered list, so the 5 GHz row of the
    // SSID you are already on (whose 2.4 GHz row is filtered out) stays chipped.
    readonly property var multiBandSsids: {
        const bands = ({});
        const aps = Network.accessPoints;
        for (let i = 0; i < aps.length; i++) {
            const ap = aps[i];
            if (!ap || !ap.ssid || !ap.band)
                continue;
            if (!bands[ap.ssid])
                bands[ap.ssid] = ({});
            bands[ap.ssid][ap.band] = true;
        }
        const multi = ({});
        for (const s in bands)
            if (Object.keys(bands[s]).length > 1)
                multi[s] = true;
        return multi;
    }
    onAvailableNetsChanged: if (root.availableNets.length > 0) root.scanning = false

    function secured(ap) { return ap && ap.security && ap.security !== "None"; }

    onOpenChanged: {
        Network.setVpnPolling(root, root.open);
        if (root.open) {
            root.scanning = true;
            Network.refresh();
            scanClear.restart();
        } else {
            root.scanning = false;
            scanClear.stop();
        }
    }
    Component.onDestruction: Network.setVpnPolling(root, false)

    Timer { id: rescan; interval: 30000; repeat: true; running: root.open && root.wifiOn; onTriggered: Network.refresh() }
    Timer { id: scanClear; interval: 15000; onTriggered: root.scanning = false }

    function toggleWifi() { Network.setWifiEnabled(!root.wifiOn); }
    function scan() {
        if (!root.wifiOn)
            return;
        root.scanning = true;
        Network.refresh();
        scanClear.restart();
    }

    implicitWidth: 250 * root.s
    implicitHeight: content.implicitHeight + root.pad * 2

    PopoutCard { anchors.fill: parent }

    // an available-network row: signal + SSID (+ lock), tap to join or, when a
    // password is needed, expand an inline field.
    component ApRow: Column {
        id: apr
        required property var ap
        property bool expanded: false
        property bool connecting: false
        property bool errorShown: false
        property int pendingId: -1
        readonly property bool sec: root.secured(apr.ap)
        readonly property bool needsPw: apr.sec && !apr.ap.saved

        width: parent ? parent.width : 0
        spacing: 4 * root.s

        function doConnect() {
            apr.errorShown = false;
            apr.connecting = true;
            apr.pendingId = Network.connectWifi(apr.ap.ssid, apr.needsPw ? pwField.text : "", apr.ap.bssid);
        }
        Connections {
            target: Network
            function onReplied(id, ok, error) {
                if (id !== apr.pendingId)
                    return;
                apr.connecting = false;
                apr.pendingId = -1;
                if (ok) {
                    apr.expanded = false;
                    pwField.text = "";
                } else {
                    apr.errorShown = true;
                    pwField.text = "";
                }
            }
        }

        Item {
            width: parent.width
            height: 26 * root.s
            Rectangle {
                anchors.fill: parent
                radius: 3 * root.s
                color: apTap.pressed ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)
                    : (apHover.hovered ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent")
                border.width: Theme.borderWidth
                border.color: root.line
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
            GlyphIcon {
                id: apIcon
                anchors.left: parent.left
                anchors.leftMargin: 7 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * root.s
                height: width
                name: "wifi"
                stroke: 1.6
                color: root.inkDim
                opacity: 0.4 + 0.6 * Math.max(0, Math.min(1, (apr.ap.strength || 0) / 100))
            }
            Text {
                anchors.left: apIcon.right
                anchors.leftMargin: 7 * root.s
                anchors.right: apMeta.left
                anchors.rightMargin: 6 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: apr.ap.ssid
                color: root.ink
                font.family: Theme.fontPrimary
                font.pixelSize: 11 * root.s
                elide: Text.ElideRight
            }
            Row {
                id: apMeta
                anchors.right: parent.right
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5 * root.s
                Text {
                    visible: (apr.ap.band || "") !== "" && !!root.multiBandSsids[apr.ap.ssid]
                    anchors.verticalCenter: parent.verticalCenter
                    text: apr.ap.band || ""
                    color: root.inkDim
                    font.family: Theme.mono
                    font.pixelSize: 9.5 * root.s
                }
                GlyphIcon {
                    visible: apr.sec
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11 * root.s
                    height: width
                    name: "lock"
                    stroke: 1.6
                    color: root.inkDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: apr.connecting ? "…" : Math.round(apr.ap.strength || 0) + "%"
                    color: root.inkDim
                    font.family: Theme.mono
                    font.pixelSize: 9.5 * root.s
                }
            }
            HoverHandler { id: apHover; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                id: apTap
                anchors.fill: parent
                onClicked: {
                    if (apr.needsPw) {
                        apr.expanded = !apr.expanded;
                        if (apr.expanded)
                            pwField.forceActiveFocus();
                    } else {
                        apr.doConnect();
                    }
                }
            }
        }

        // inline password (secured, unsaved).
        Column {
            width: parent.width
            spacing: 4 * root.s
            visible: apr.needsPw && apr.expanded

            Rectangle {
                width: parent.width
                height: 26 * root.s
                radius: 3 * root.s
                color: "transparent"
                border.width: Theme.borderWidth
                border.color: root.line
                TextInput {
                    id: pwField
                    anchors.left: parent.left
                    anchors.right: eye.left
                    anchors.leftMargin: 8 * root.s
                    anchors.rightMargin: 4 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.ink
                    font.family: Theme.fontPrimary
                    font.pixelSize: 11 * root.s
                    echoMode: eye.show ? TextInput.Normal : TextInput.Password
                    clip: true
                    onAccepted: apr.doConnect()
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: I18n.tr("Password")
                        color: root.inkDim
                        font: pwField.font
                        visible: pwField.text.length === 0 && !pwField.activeFocus
                    }
                }
                GlyphIcon {
                    id: eye
                    property bool show: false
                    anchors.right: parent.right
                    anchors.rightMargin: 7 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13 * root.s
                    height: width
                    name: eye.show ? "close" : "info"
                    stroke: 1.6
                    color: root.inkDim
                    TapHandler { onTapped: eye.show = !eye.show }
                }
            }
            Text {
                width: parent.width
                visible: apr.errorShown
                text: I18n.tr("Wrong password or connection failed")
                color: Theme.error
                wrapMode: Text.WordWrap
                font.family: Theme.fontPrimary
                font.pixelSize: 9.5 * root.s
            }
            PopoutAction {
                width: parent.width
                s: root.s
                enabled: !apr.connecting
                label: apr.connecting ? I18n.tr("Connecting…") : I18n.tr("Connect")
                onClicked: apr.doConnect()
            }
        }
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        spacing: 8 * root.s

        // head: label, wifi toggle, scan.
        Item {
            width: parent.width
            height: 20 * root.s
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("NETWORK")
                color: root.inkDim
                font.family: Theme.mono
                font.pixelSize: 9 * root.s
                font.letterSpacing: 1.6
                font.weight: Font.Medium
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5 * root.s
                PopoutHeadButton {
                    visible: root.wifiOn
                    s: root.s
                    glyph: "reboot"
                    active: root.scanning
                    spin: root.scanning
                    onClicked: root.scan()
                }
                PopoutHeadButton {
                    s: root.s
                    glyph: "wifi"
                    active: root.wifiOn
                    onClicked: root.toggleWifi()
                }
            }
        }

        // OFF plate (wifi off and no wired link).
        Column {
            width: parent.width
            spacing: 7 * root.s
            visible: !root.wifiOn && !root.wiredUp
            topPadding: 6 * root.s
            bottomPadding: 4 * root.s
            GlyphIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 27 * root.s
                height: width
                name: "wifi"
                stroke: 1.6
                color: root.inkDim
                opacity: 0.5
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("Wi-Fi is off")
                color: root.ink
                font.family: Theme.fontPrimary
                font.pixelSize: 12 * root.s
                font.weight: Font.DemiBold
            }
            PopoutAction {
                anchors.horizontalCenter: parent.horizontalCenter
                s: root.s
                label: I18n.tr("Turn on")
                onClicked: root.toggleWifi()
            }
        }

        // HERO: the current link.
        Item {
            width: parent.width
            height: 36 * root.s
            visible: root.anyLink
            Rectangle {
                id: netTile
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 30 * root.s
                height: width
                radius: 4 * root.s
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                border.width: Theme.borderWidth
                border.color: root.line
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 16 * root.s
                    height: width
                    name: root.wiredUp ? "ethernet" : "wifi"
                    stroke: 1.7
                    color: (root.wiredUp || root.wifiUp) ? root.ink : root.inkDim
                }
            }
            PopoutAction {
                id: disc
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.wifiUp
                s: root.s
                destructive: true
                label: I18n.tr("Disconnect")
                onClicked: Network.disconnectWifi()
            }
            Column {
                anchors.left: netTile.right
                anchors.leftMargin: 9 * root.s
                anchors.right: disc.visible ? disc.left : parent.right
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s
                Text {
                    width: parent.width
                    text: root.wiredUp ? I18n.tr("Wired")
                        : root.wifiUp ? root.activeSsid
                        : I18n.tr("Not connected")
                    color: root.ink
                    font.family: Theme.fontPrimary
                    font.pixelSize: 12.5 * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: {
                        if (root.wiredUp) return I18n.tr("Connected");
                        if (root.wifiUp) {
                            const s = Math.round(Network.wifi.strength || 0);
                            const base = I18n.tr("Connected · %1%").arg(s);
                            return Network.vpnActive ? base + " · " + Network.vpnName : base;
                        }
                        return Network.wifiConnectivity === "Connecting" ? I18n.tr("Connecting…") : I18n.tr("Choose a network");
                    }
                    color: root.inkDim
                    font.family: Theme.mono
                    font.pixelSize: 9 * root.s
                    elide: Text.ElideRight
                }
            }
        }

        // available networks.
        Text {
            width: parent.width
            visible: root.wifiOn
            text: root.scanning ? I18n.tr("NETWORKS · SCANNING") : I18n.tr("NETWORKS")
            color: root.inkDim
            font.family: Theme.mono
            font.pixelSize: 8.5 * root.s
            font.letterSpacing: 1.5
        }
        Column {
            width: parent.width
            spacing: 5 * root.s
            visible: root.wifiOn
            Repeater {
                model: root.availableNets
                delegate: ApRow {
                    required property var modelData
                    ap: modelData
                }
            }
        }
        Text {
            width: parent.width
            visible: root.wifiOn && root.availableNets.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: root.scanning ? I18n.tr("Scanning…") : I18n.tr("No networks found")
            color: root.inkDim
            font.family: Theme.fontPrimary
            font.pixelSize: 10 * root.s
            topPadding: 2 * root.s
        }
    }
}
