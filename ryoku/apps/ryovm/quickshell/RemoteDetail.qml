pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// The berth: one remote read in full. The address and rolled-up state up top, a
// live health readout from the last probe (uptime, load, cpu, memory, disk,
// failed units) in the yard's big-numeral grammar, the watched services, and the
// verbs -- connect, probe again, deploy a key, forget. The probe is the QoL the
// hub exists for: know the box before you land on it.
Item {
    id: berth

    property string alias: ""
    signal edit(string alias)

    readonly property var host: {
        for (var i = 0; i < Remotes.hosts.length; i++)
            if (Remotes.hosts[i].alias === berth.alias) return Remotes.hosts[i];
        return null;
    }
    readonly property var health: berth.alias.length > 0 ? Remotes.healthOf(berth.alias) : null
    readonly property var reach: berth.alias.length > 0 ? Remotes.reachOf(berth.alias) : null
    readonly property string state: berth.alias.length > 0 ? Remotes.stateOf(berth.alias) : "unknown"
    readonly property bool probed: berth.health && berth.health.ok === true

    // a label + big value + unit readout, the yard's spec-grid grammar.
    component Readout: Column {
        id: ro
        property string label: ""
        property string value: ""
        property string unit: ""
        property bool warn: false
        width: (berth.width - Tokens.s3 - Tokens.s5 * 2) / 3
        spacing: 3
        Text {
            text: I18n.tr(ro.label); color: ro.warn ? Tokens.ink : Tokens.inkMuted
            font.family: Tokens.mono; font.pixelSize: 9; font.letterSpacing: 1.3
        }
        Text {
            text: ro.value.length > 0 ? ro.value : "-"
            color: Tokens.ink
            font.family: Tokens.ui; font.pixelSize: 24; font.weight: ro.warn ? Font.DemiBold : Font.Light
        }
        Text {
            visible: ro.unit.length > 0
            text: ro.unit; color: Tokens.inkFaint
            font.family: Tokens.mono; font.pixelSize: 10
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + Tokens.s5
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Column {
            id: col
            width: parent.width - Tokens.s3
            spacing: Tokens.s4

            // ── header ──
            Item {
                width: parent.width
                height: nameCol.implicitHeight
                Column {
                    id: nameCol
                    anchors.left: parent.left
                    anchors.right: stateCol.left
                    anchors.rightMargin: Tokens.s4
                    spacing: 4
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: berth.alias
                        color: Tokens.ink
                        font.family: Tokens.display; font.pixelSize: Tokens.fHero
                    }
                    Text {
                        text: (berth.host ? (berth.host.user ? berth.host.user + "@" : "") : "")
                            + (berth.host ? (berth.host.hostName || berth.alias) : "")
                            + (berth.host && berth.host.port && berth.host.port !== 22 ? ":" + berth.host.port : "")
                        color: Tokens.inkMuted
                        font.family: Tokens.mono; font.pixelSize: 12
                    }
                    Text {
                        visible: berth.host && berth.host.auth === "password"
                        text: I18n.tr("saved password · used for probes and connect")
                        color: Tokens.inkFaint
                        font.family: Tokens.mono; font.pixelSize: 10
                    }
                    Text {
                        visible: berth.host && (berth.host.group || (berth.host.tags && berth.host.tags.length > 0))
                        text: (berth.host && berth.host.group ? berth.host.group : "")
                            + (berth.host && berth.host.group && berth.host.tags && berth.host.tags.length > 0 ? "  ·  " : "")
                            + (berth.host && berth.host.tags ? berth.host.tags.join(" · ") : "")
                        color: Tokens.inkFaint
                        font.family: Tokens.mono; font.pixelSize: 10
                    }
                    Text {
                        visible: berth.host && berth.host.notes && berth.host.notes.length > 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: berth.host ? (berth.host.notes || "") : ""
                        color: Tokens.inkDim
                        font.family: Tokens.ui; font.pixelSize: 11
                        topPadding: 2
                    }
                }
                Column {
                    id: stateCol
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 4
                    Annunciator {
                        anchors.right: parent.right
                        label: ({ "up": I18n.tr("UP"), "warn": I18n.tr("DEGRADED"), "down": I18n.tr("DOWN"), "unknown": I18n.tr("UNKNOWN") })[berth.state] || I18n.tr("UNKNOWN")
                        lit: berth.state === "up" || berth.state === "warn"
                        warn: berth.state === "warn"
                        tileW: 74
                    }
                    Text {
                        anchors.right: parent.right
                        visible: berth.reach && berth.reach.up === true
                        text: berth.reach ? berth.reach.rttMs + I18n.tr(" ms round trip") : ""
                        color: Tokens.inkFaint
                        font.family: Tokens.mono; font.pixelSize: 10
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Tokens.line }

            // ── distro line ──
            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: berth.probed
                text: (berth.health && berth.health.distro ? berth.health.distro : "")
                    + (berth.health && berth.health.kernel ? "   ·   " + berth.health.kernel : "")
                color: Tokens.inkDim
                font.family: Tokens.mono; font.pixelSize: 11
            }

            // ── health grid ──
            Column {
                width: parent.width
                spacing: Tokens.s4
                visible: berth.probed
                Row {
                    spacing: Tokens.s5
                    Readout {
                        label: I18n.tr("UPTIME")
                        value: berth.probed ? Remotes.uptimeShort(berth.health.uptimeS) : ""
                    }
                    Readout {
                        label: I18n.tr("LOAD")
                        value: berth.probed ? Number(berth.health.load1).toFixed(2) : ""
                        unit: berth.probed ? Number(berth.health.load5).toFixed(2) + " · " + Number(berth.health.load15).toFixed(2) : ""
                        warn: berth.probed && berth.health.cpus > 0 && berth.health.load1 > berth.health.cpus
                    }
                    Readout {
                        label: I18n.tr("CPU")
                        value: berth.probed ? String(berth.health.cpus) : ""
                        unit: I18n.tr("cores")
                    }
                }
                Row {
                    spacing: Tokens.s5
                    Readout {
                        label: I18n.tr("MEMORY")
                        value: berth.probed && berth.health.memTotalKb > 0
                            ? Math.round(100 * (berth.health.memTotalKb - berth.health.memAvailKb) / berth.health.memTotalKb) + "%"
                            : ""
                        unit: berth.probed ? Remotes.human((berth.health.memTotalKb - berth.health.memAvailKb) * 1024) + " / " + Remotes.human(berth.health.memTotalKb * 1024) : ""
                        warn: berth.probed && berth.health.memTotalKb > 0
                            && (berth.health.memTotalKb - berth.health.memAvailKb) / berth.health.memTotalKb >= 0.9
                    }
                    Readout {
                        label: I18n.tr("DISK /")
                        value: berth.probed ? berth.health.diskPct + "%" : ""
                        unit: berth.probed ? Remotes.human(berth.health.diskUsedKb * 1024) + " / " + Remotes.human(berth.health.diskTotalKb * 1024) : ""
                        warn: berth.probed && berth.health.diskPct >= 90
                    }
                    Readout {
                        label: I18n.tr("FAILED")
                        value: berth.probed ? String(berth.health.failedUnits) : ""
                        unit: I18n.tr("units")
                        warn: berth.probed && berth.health.failedUnits > 0
                    }
                }
            }

            // ── apps: web services on this host, opened + live http-monitored ──
            Column {
                width: parent.width
                spacing: Tokens.s2
                visible: berth.host && berth.host.apps && berth.host.apps.length > 0
                Row {
                    spacing: Tokens.s2
                    Text { text: "//"; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fMicro; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: I18n.tr("APPS_"); color: Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                        font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text { text: "卓"; color: Tokens.inkFaint; font.family: Tokens.jp; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                }
                Flow {
                    width: parent.width
                    spacing: Tokens.s2
                    Repeater {
                        model: berth.host && berth.host.apps ? berth.host.apps : []
                        Rectangle {
                            id: appTile
                            required property var modelData
                            readonly property var st: (Remotes.appRev, Remotes.appStatusOf(berth.alias, modelData.name))
                            readonly property string svcState: appTile.st ? appTile.st.state : "unknown"
                            readonly property bool up: appTile.svcState === "up"
                            height: 30
                            width: appRow.implicitWidth + Tokens.s3 * 2
                            radius: Tokens.radius
                            color: appMa.containsMouse ? Tokens.tint10 : "transparent"
                            border.width: Tokens.border
                            border.color: appMa.containsMouse ? Tokens.lineStrong : Tokens.line
                            antialiasing: false
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                            Behavior on border.color { ColorAnimation { duration: Tokens.snap } }
                            MouseArea {
                                id: appMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Remotes.openApp(appTile.modelData.url)
                            }
                            Row {
                                id: appRow
                                anchors.centerIn: parent
                                spacing: Tokens.s2
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 7; height: 7; radius: 3.5
                                    antialiasing: true
                                    color: appTile.up ? Tokens.bone : "transparent"
                                    border.width: appTile.up ? 0 : Tokens.border
                                    border.color: appTile.svcState === "warn" ? Tokens.bone : Tokens.inkFaint
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: appTile.modelData.name
                                    color: Tokens.ink
                                    font.family: Tokens.ui; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: appTile.st && appTile.svcState !== "down"
                                    text: appTile.st ? appTile.st.ms + "ms" : ""
                                    color: Tokens.inkFaint
                                    font.family: Tokens.mono; font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }

            // ── proxmox guests: the cluster's VMs and containers, with power ──
            Column {
                width: parent.width
                spacing: Tokens.s2
                visible: Remotes.isProxmox(berth.host)
                Row {
                    spacing: Tokens.s2
                    Text { text: "//"; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fMicro; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: I18n.tr("GUESTS_"); color: Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                        font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text { text: "客"; color: Tokens.inkFaint; font.family: Tokens.jp; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                }
                Repeater {
                    model: (Remotes.guestsRev, Remotes.guestsOf(berth.alias))
                    Rectangle {
                        id: guestRow
                        required property var modelData
                        readonly property bool running: modelData.status === "running"
                        readonly property bool busy: (Remotes.guestBusyRev, Remotes.guestBusyOf(berth.alias, modelData.vmid))
                        width: parent.width
                        height: 44
                        radius: Tokens.radius
                        color: "transparent"
                        border.width: Tokens.border
                        border.color: Tokens.line
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.s3
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8; height: 8; radius: 4
                                antialiasing: true
                                color: guestRow.running ? Tokens.bone : "transparent"
                                border.width: guestRow.running ? 0 : Tokens.border
                                border.color: Tokens.inkFaint
                                SequentialAnimation on opacity {
                                    running: guestRow.busy
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 600 }
                                    NumberAnimation { to: 1.0; duration: 600 }
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Text {
                                    text: guestRow.modelData.name || I18n.tr("guest %1").arg(guestRow.modelData.vmid)
                                    color: Tokens.ink
                                    font.family: Tokens.ui; font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                                Text {
                                    text: "#" + guestRow.modelData.vmid + "  ·  " + guestRow.modelData.type + "  ·  " + guestRow.modelData.node
                                    color: Tokens.inkFaint
                                    font.family: Tokens.mono; font.pixelSize: 9
                                }
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.s3
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: guestRow.running && guestRow.modelData.maxmem > 0
                                text: Remotes.human(guestRow.modelData.mem) + " / " + Remotes.human(guestRow.modelData.maxmem)
                                color: Tokens.inkMuted
                                font.family: Tokens.mono; font.pixelSize: 10
                            }
                            Btn {
                                anchors.verticalCenter: parent.verticalCenter
                                compact: true
                                armed: !guestRow.busy
                                text: guestRow.busy ? "···" : (guestRow.running ? I18n.tr("STOP") : I18n.tr("START"))
                                primary: !guestRow.running && !guestRow.busy
                                onAct: Remotes.pveAct(berth.alias, guestRow.modelData.node, guestRow.modelData.type, guestRow.modelData.vmid, guestRow.running ? "shutdown" : "start")
                            }
                        }
                    }
                }
                Text {
                    visible: Remotes.isProxmox(berth.host) && Remotes.guestsOf(berth.alias).length === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: I18n.tr("No guests yet, or the API token can't read the cluster.")
                    color: Tokens.inkFaint
                    font.family: Tokens.mono; font.pixelSize: 11
                }
            }

            // ── watched services ──
            Column {
                width: parent.width
                spacing: Tokens.s2
                visible: berth.probed && berth.health.services && Object.keys(berth.health.services).length > 0
                Text {
                    text: I18n.tr("// SERVICES_"); color: Tokens.inkMuted
                    font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                    font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                }
                Flow {
                    width: parent.width
                    spacing: Tokens.s2
                    Repeater {
                        model: berth.probed && berth.health.services ? Object.keys(berth.health.services) : []
                        Rectangle {
                            required property string modelData
                            readonly property string st: berth.health.services[modelData]
                            height: 24
                            width: svcRow.implicitWidth + Tokens.s3 * 2
                            radius: Tokens.radius
                            color: st === "active" ? Tokens.bone : "transparent"
                            border.width: Tokens.border
                            border.color: st === "active" ? Tokens.bone : Tokens.line
                            Row {
                                id: svcRow
                                anchors.centerIn: parent
                                spacing: Tokens.s2
                                Text {
                                    text: parent.parent.modelData
                                    color: parent.parent.st === "active" ? Tokens.inkOnBone : Tokens.inkDim
                                    font.family: Tokens.ui; font.pixelSize: 11; font.weight: Font.Medium
                                }
                                Text {
                                    text: parent.parent.st.toUpperCase()
                                    color: parent.parent.st === "active" ? Tokens.inkOnBoneDim : Tokens.inkFaint
                                    font.family: Tokens.mono; font.pixelSize: 8; font.letterSpacing: 1
                                }
                            }
                        }
                    }
                }
            }

            // ── unprobed / error note ──
            Rectangle {
                width: parent.width
                visible: !berth.probed
                height: noteCol.implicitHeight + Tokens.s4 * 2
                radius: Tokens.radius
                color: "transparent"
                border.width: Tokens.border
                border.color: Tokens.line
                Column {
                    id: noteCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.s4
                    spacing: Tokens.s2
                    Text {
                        text: berth.state === "down" ? I18n.tr("Not reachable") : I18n.tr("No health reading yet")
                        color: Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: berth.health && berth.health.error
                            ? berth.health.error
                            : (berth.state === "down"
                                ? I18n.tr("The host did not answer on its SSH port. Check it is up and the address is right.")
                                : I18n.tr("Run a probe to read uptime, load, memory and disk. A key-authenticated login is needed for the full reading; use COPY KEY to deploy one."))
                        color: Tokens.inkMuted
                        font.family: Tokens.mono; font.pixelSize: 11
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Tokens.line }

            // ── quick look: one-tap ops in a held terminal ───────────────
            Column {
                width: parent.width
                spacing: Tokens.s2
                Row {
                    spacing: Tokens.s2
                    Text { text: "//"; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fMicro; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: I18n.tr("LOOK_"); color: Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                        font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text { text: "覗"; color: Tokens.inkFaint; font.family: Tokens.jp; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                }
                Flow {
                    width: parent.width
                    spacing: Tokens.s2
                    Btn { height: 24; text: I18n.tr("HTOP"); onAct: Remotes.runOn(berth.alias, "htop") }
                    Btn { height: 24; text: I18n.tr("LOGS"); onAct: Remotes.runOn(berth.alias, "journalctl -n 200 -f") }
                    Btn { height: 24; text: I18n.tr("DISK"); onAct: Remotes.runOn(berth.alias, "df -h") }
                    Btn { height: 24; text: I18n.tr("PORTS"); onAct: Remotes.runOn(berth.alias, "ss -tulpn") }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Tokens.line }

            // ── tunnels: local (-L), remote (-R), dynamic SOCKS (-D) ─────
            Column {
                id: tun
                width: parent.width
                spacing: Tokens.s2
                property string kind: "LOCAL"
                readonly property var list: berth.alias.length > 0 ? Remotes.tunnelsFor(berth.alias) : []
                function doOpen() {
                    if (tunSpec.text.trim().length === 0) return;
                    var K = ({ "LOCAL": "L", "REMOTE": "R", "SOCKS": "D" })[tun.kind];
                    Remotes.openTunnel(berth.alias, K + ":" + tunSpec.text.trim());
                    tunSpec.text = "";
                }

                Row {
                    spacing: Tokens.s2
                    Text { text: "//"; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fMicro; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: I18n.tr("TUNNELS_"); color: Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                        font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text { text: "経路"; color: Tokens.inkFaint; font.family: Tokens.jp; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                }

                Repeater {
                    model: tun.list
                    Item {
                        required property var modelData
                        width: tun.width
                        height: 24
                        Text {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: 58
                            text: ({ "local": "LOCAL", "remote": "REMOTE", "dynamic": "SOCKS" })[modelData.kind] || modelData.kind
                            color: Tokens.inkMuted; font.family: Tokens.mono; font.pixelSize: 9; font.letterSpacing: 1.2
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 64
                            anchors.right: killTun.left; anchors.rightMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: modelData.spec
                            color: Tokens.ink; font.family: Tokens.mono; font.pixelSize: 11
                        }
                        Text {
                            id: killTun
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: "\u2715"
                            color: killH.hovered ? Tokens.ink : Tokens.inkFaint
                            font.family: Tokens.mono; font.pixelSize: 11
                            HoverHandler { id: killH; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Remotes.closeTunnel(modelData.id) }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 28
                    Seg {
                        id: kseg
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        options: ["LOCAL", "REMOTE", "SOCKS"]
                        current: tun.kind
                        onChose: (k) => tun.kind = k
                    }
                }
                Item {
                    width: parent.width
                    height: 28
                    Btn {
                        id: openTun
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("OPEN")
                        armed: tunSpec.text.trim().length > 0
                        onAct: tun.doOpen()
                    }
                    Field {
                        id: tunSpec
                        anchors.left: parent.left
                        anchors.right: openTun.left; anchors.rightMargin: Tokens.s2
                        anchors.verticalCenter: parent.verticalCenter
                        tabular: true
                        placeholder: tun.kind === "SOCKS" ? I18n.tr("1080  (a local SOCKS proxy)") : I18n.tr("9090:localhost:5432")
                        onAccepted: tun.doOpen()
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Tokens.line }

            // ── verbs ──
            Flow {
                width: parent.width
                spacing: Tokens.s2
                Btn { text: I18n.tr("CONNECT"); primary: true; onAct: Remotes.connect(berth.alias) }
                Btn { text: I18n.tr("PROBE"); onAct: Remotes.probe(berth.alias) }
                Btn { text: I18n.tr("FILES"); onAct: Remotes.openFiles(berth.host) }
                Btn { text: I18n.tr("COPY KEY"); onAct: Remotes.copyId(berth.alias) }
                Btn { text: I18n.tr("EDIT"); onAct: berth.edit(berth.alias) }
                Btn { text: I18n.tr("FORGET"); onAct: forget.armed ? Remotes.removeHost(berth.alias) : forget.arm() }
            }
            Text {
                id: forget
                property bool armed: false
                function arm() { armed = true; forgetDisarm.restart(); }
                visible: armed
                text: I18n.tr("Tap FORGET again to remove %1 (its ~/.ssh/config entry stays).").arg(berth.alias)
                color: Tokens.inkMuted
                font.family: Tokens.ui; font.pixelSize: 11
                Timer { id: forgetDisarm; interval: 3000; onTriggered: forget.armed = false }
            }
        }
    }
}
