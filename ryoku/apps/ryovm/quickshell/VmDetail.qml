pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// The LIBRARY lane's right column: the pinned machine stage as the hero, then
// the verb row, then a scrollable sheet of Sections: REACH IT, IDENTITY,
// RESOURCES, SEAL, USB, SNAPSHOTS, TEMPLATE, DANGER, LOG, closed by the engraved
// machine plate. Driven by Vm.selected (the list row) and Vm.detail (the get).
Item {
    id: pane

    readonly property var vm: Vm.selected
    readonly property var det: Vm.detail
    readonly property bool running: pane.vm ? pane.vm.running === true : false
    readonly property string name: pane.vm ? pane.vm.name : ""
    property string launchMode: "window"
    property bool disposableRun: false
    readonly property var sealSnap: {
        var ss = pane.det ? (pane.det.snapshots || []) : [];
        for (var i = 0; i < ss.length; i++)
            if (ss[i].name === "sealed")
                return ss[i];
        return null;
    }
    readonly property var _modeFromDisplay: ({ "gtk": "window", "spice": "spice", "none": "headless" })
    readonly property int capGb: {
        var d = pane.vm ? (pane.vm.disk || "") : "";
        var n = parseInt(d);
        return d.length === 0 ? 0 : (d.indexOf("M") >= 0 ? Math.max(1, Math.round(n / 1024)) : (n || 0));
    }
    property int diskTarget: 64
    readonly property int coresNum: pane.vm && pane.vm.cores !== "auto" ? (parseInt(pane.vm.cores) || Vm.settings.defaultCores) : Vm.settings.defaultCores
    readonly property int ramNum: {
        var r = pane.vm ? pane.vm.ram : "";
        if (!r || r === "auto")
            return Vm.settings.defaultRam;
        var n = parseFloat(r);
        return r.indexOf("M") >= 0 ? Math.max(1, Math.round(n / 1024)) : (n || Vm.settings.defaultRam);
    }
    onVmChanged: {
        pane.launchMode = pane._modeFromDisplay[pane.vm ? pane.vm.display : "gtk"] || "window";
        var d = pane.vm ? (pane.vm.disk || "") : "", n = parseInt(d);
        pane.diskTarget = d.length === 0 ? 64 : (d.indexOf("M") >= 0 ? Math.max(1, Math.round(n / 1024)) : (n || 64));
    }
    onNameChanged: renameField.text = pane.name

    function span(n) {
        var w = lowerCol.width;
        var c = (w - (Spans.cols - 1) * Tokens.s2) / Spans.cols;
        return Math.max(0, n * c + (n - 1) * Tokens.s2);
    }

    // this machine's slice of the yard log, newest first (3.6).
    readonly property var logEvents: {
        var out = [];
        for (var i = Vm.events.length - 1; i >= 0; i--)
            if (Vm.events[i].vm === pane.name)
                out.push(Vm.events[i]);
        return out;
    }

    // empty state.
    Column {
        anchors.centerIn: parent
        spacing: Tokens.s3
        visible: pane.vm === null
        Mark { anchors.horizontalCenter: parent.horizontalCenter; size: 96 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("Pick a machine to manage it")
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: 12
        }
    }

    Item {
        anchors.fill: parent
        visible: pane.vm !== null

        // ---- the stage, pinned (it never scrolls) --------------------------
        VmStage {
            id: stage
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(210, parent.height * 0.36)
            name: pane.name
            installed: pane.det ? pane.det.installed === true : false
            disposable: pane.vm ? pane.vm.disposable === true : false
            sshReady: pane.det ? pane.det.sshReady === true : false
            sealed: pane.det ? pane.det.sealed === true : (pane.vm ? pane.vm.sealed === true : false)
            tpmOn: pane.vm ? pane.vm.tpm === true : false
            uefiOn: pane.vm ? pane.vm.uefi !== false : true
            guest: pane.vm ? (pane.vm.guest || "linux") : "linux"
            os: pane.vm ? (pane.vm.os || "") : ""
            running: pane.running
            mode: pane.vm ? pane.vm.display : "gtk"
            ssh: pane.vm ? (pane.vm.ssh || "") : ""
            spice: pane.vm ? (pane.vm.spice || "") : ""
            cores: pane.vm ? (pane.vm.cores || "auto") : "auto"
            ram: pane.vm ? (pane.vm.ram || "auto") : "auto"
            diskUsed: pane.vm ? (pane.vm.diskUsed || 0) : 0
            diskCap: pane.vm ? (pane.vm.disk || "") : ""
        }

        // ---- the verb row --------------------------------------------------
        Item {
            id: actions
            anchors.top: stage.bottom
            anchors.topMargin: Tokens.s4
            anchors.left: parent.left
            anchors.right: parent.right
            height: 58

            // stopped: Launch + mode seg + disposable switch + honest caption.
            Column {
                visible: !pane.running
                spacing: Tokens.s2
                Row {
                    spacing: Tokens.s3
                    Btn {
                        primary: true
                        text: pane.disposableRun ? I18n.tr("LAUNCH · BURN") : I18n.tr("LAUNCH")
                        armed: !Vm.busy && Vm.caps.quickemu === true
                            && !(pane.launchMode === "spice" && Vm.caps.spice !== true)
                        onAct: Vm.launch(pane.name, pane.launchMode, pane.disposableRun)
                    }
                    Seg {
                        anchors.verticalCenter: parent.verticalCenter
                        options: ["WINDOW", "SPICE", "HEADLESS"]
                        current: pane.launchMode.toUpperCase()
                        onChose: (k) => {
                            var m = k.toLowerCase();
                            pane.launchMode = m;
                            Vm.setConfig(pane.name, "display", ({ "window": "gtk", "spice": "spice", "headless": "none" })[m]);
                        }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s2
                        visible: pane.det && pane.det.installed === true
                        Sw {
                            anchors.verticalCenter: parent.verticalCenter
                            on: pane.disposableRun
                            onToggled: (v) => pane.disposableRun = v
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("DISPOSABLE")
                            color: pane.disposableRun ? Tokens.ink : Tokens.inkFaint
                            font.family: Tokens.ui
                            font.pixelSize: 9
                            font.weight: Font.Medium
                            font.letterSpacing: 2.0
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                        }
                    }
                }
                Text {
                    width: actions.width
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: pane.det && pane.det.installed !== true
                        ? I18n.tr("First launch boots the OS installer: install onto the virtual disk, then power off. After that it boots from disk.")
                        : pane.launchMode === "spice" && Vm.caps.spice !== true
                        ? I18n.tr("SPICE needs its viewer: install the spice-gtk package, then relaunch")
                        : pane.disposableRun
                        ? I18n.tr("Disposable session: every disk write burns up at power-off. The machine boots identical next time")
                        : ({
                            "window": I18n.tr("Plain window · host↔guest clipboard is OFF in this mode"),
                            "spice": I18n.tr("SPICE viewer · shared clipboard, USB redirect, best desktop fidelity"),
                            "headless": I18n.tr("No display · reach it over SSH or attach a console anytime")
                        })[pane.launchMode] || ""
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: 11
                }
            }

            // running: Stop + Console + SSH.
            Row {
                visible: pane.running
                spacing: Tokens.s3
                Btn {
                    text: I18n.tr("STOP")
                    armed: !Vm.busy
                    onAct: Vm.stop(pane.name)
                }
                Btn {
                    primary: true
                    text: I18n.tr("CONSOLE")
                    armed: (pane.vm && (pane.vm.spice || "").length > 0) && Vm.caps.spice === true
                    onAct: Vm.openConsole(pane.name)
                }
                Btn {
                    text: I18n.tr("SSH")
                    armed: (pane.vm && (pane.vm.ssh || "").length > 0)
                    onAct: Vm.openSsh(pane.name)
                }
            }
        }

        // ---- the sheet -----------------------------------------------------
        Flickable {
            anchors.top: actions.bottom
            anchors.topMargin: Tokens.s4
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            contentWidth: width
            contentHeight: lowerCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollRail {}

            Column {
                id: lowerCol
                width: parent.width - 8
                spacing: Tokens.s5

                // ── REACH IT (running, first) ───────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    visible: pane.running
                    Head { text: I18n.tr("REACH IT") }
                    Rectangle {
                        width: parent.width
                        color: "transparent"
                        radius: Tokens.radius
                        border.width: Tokens.border
                        border.color: Tokens.line
                        antialiasing: false
                        implicitHeight: ctrlCol.implicitHeight + 2 * Tokens.s4
                        Column {
                            id: ctrlCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.s4
                            spacing: Tokens.s3

                            // the ssh command, read-only mono face, full honest form.
                            Row {
                                width: parent.width
                                spacing: Tokens.s3
                                visible: pane.vm && (pane.vm.ssh || "").length > 0
                                Rectangle {
                                    width: parent.width - sshBtns.width - Tokens.s3
                                    height: 30
                                    color: "transparent"
                                    radius: Tokens.radius
                                    border.width: Tokens.border
                                    border.color: Tokens.lineSoft
                                    antialiasing: false
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 9
                                        anchors.right: parent.right
                                        anchors.rightMargin: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: I18n.tr("ssh -p ") + (pane.vm ? pane.vm.ssh : "")
                                            + " " + (pane.det && pane.det.sshUser ? pane.det.sshUser + "@" : "") + "localhost"
                                        color: Tokens.ink
                                        font.family: Tokens.mono
                                        font.pixelSize: 12
                                    }
                                }
                                Row {
                                    id: sshBtns
                                    spacing: Tokens.s2
                                    anchors.verticalCenter: parent.verticalCenter
                                    Btn { text: I18n.tr("OPEN"); onAct: Vm.openSsh(pane.name) }
                                    Btn { text: I18n.tr("COPY"); onAct: Vm.copySsh(pane.name) }
                                }
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                visible: pane.vm && (pane.vm.ssh || "").length > 0
                                text: pane.det && pane.det.sshReady === true
                                    ? I18n.tr("Guest is answering: connect away.")
                                    : I18n.tr("Port is forwarded but the guest isn't answering yet: still booting, or no SSH server inside (live ISOs never have one).")
                                color: pane.det && pane.det.sshReady === true ? Tokens.ink : Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: 11
                            }

                            // the account ssh signs in with.
                            Row {
                                width: parent.width
                                spacing: Tokens.s3
                                visible: pane.vm && (pane.vm.ssh || "").length > 0
                                FieldLabel { anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Login as") }
                                Field {
                                    id: sshUserField
                                    width: 170
                                    tabular: true
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pane.det && pane.det.sshUser ? pane.det.sshUser : ""
                                    onCommitted: (v) => {
                                        var u = v.trim();
                                        if (u.length > 0 && pane.det && u !== pane.det.sshUser) {
                                            Vm.setConfig(pane.name, "ryovm_ssh_user", u);
                                            Vm.reselect();
                                        }
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("the guest account ssh signs in with")
                                    color: Tokens.inkFaint
                                    font.family: Tokens.ui
                                    font.pixelSize: 11
                                }
                            }

                            // console: honest about socket AND viewer.
                            Row {
                                spacing: Tokens.s3
                                visible: pane.vm && (pane.vm.spice || "").length > 0
                                Btn {
                                    text: I18n.tr("ATTACH CONSOLE")
                                    armed: Vm.caps.spice === true
                                    onAct: Vm.openConsole(pane.name)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Vm.caps.spice === true
                                        ? I18n.tr("SPICE screen on localhost:") + (pane.vm ? pane.vm.spice : "")
                                        : I18n.tr("needs the SPICE viewer: install the spice-gtk package")
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: 11
                                }
                            }

                            KeyHint {
                                keys: pane.vm && pane.vm.display === "spice" ? "Shift  F12"
                                    : pane.vm && pane.vm.display === "gtk" ? "Ctrl  Alt  G" : ""
                                action: I18n.tr("Release the mouse and keyboard")
                                visible: pane.vm && pane.vm.display !== "none"
                            }
                            KeyHint {
                                keys: pane.vm && pane.vm.display === "spice" ? "F11" : "Ctrl  Alt  F"
                                action: I18n.tr("Toggle fullscreen")
                                visible: pane.vm && pane.vm.display !== "none"
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: pane.vm && pane.vm.display === "none"
                                    ? I18n.tr("Headless: no window exists. This panel is the machine's only door.")
                                    : I18n.tr("Stuck with the cursor grabbed? The Stop button above always powers the machine off.")
                                color: Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                // ── POWER (running, live control) ────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    visible: pane.running
                    Head { text: I18n.tr("POWER") }
                    Rectangle {
                        width: parent.width
                        color: "transparent"
                        radius: Tokens.radius
                        border.width: Tokens.border
                        border.color: Tokens.line
                        antialiasing: false
                        implicitHeight: powerBody.implicitHeight + 2 * Tokens.s4

                        readonly property var mon: Vm.monStats
                        readonly property bool live: mon && mon.running === true
                        property real balloonMB: 0
                        property bool balloonDragging: false
                        Connections {
                            target: Vm
                            function onMonStatsChanged() {
                                if (!powerBody.parent.balloonDragging && Vm.monStats.balloonMB > 0)
                                    powerBody.parent.balloonMB = Vm.monStats.balloonMB;
                            }
                        }

                        Column {
                            id: powerBody
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.s4
                            spacing: Tokens.s4

                            // live readout: host cost, guest reach, topology.
                            Row {
                                width: parent.width
                                Repeater {
                                    model: [
                                        { k: I18n.tr("HOST CPU"), v: powerBody.parent.live ? Math.round(powerBody.parent.mon.hostCpuPct) + "%" : "-" },
                                        { k: I18n.tr("HOST RAM"), v: powerBody.parent.live && powerBody.parent.mon.hostRssMB > 0 ? Vm.human(powerBody.parent.mon.hostRssMB * 1024 * 1024) : "-" },
                                        { k: I18n.tr("GUEST IP"), v: powerBody.parent.live && powerBody.parent.mon.guestIp ? powerBody.parent.mon.guestIp : "-", mono: true },
                                        { k: I18n.tr("VCPUS"), v: powerBody.parent.live && powerBody.parent.mon.vcpus > 0 ? String(powerBody.parent.mon.vcpus) : "-" }
                                    ]
                                    Column {
                                        required property var modelData
                                        width: powerBody.width / 4
                                        spacing: 3
                                        Text {
                                            text: modelData.k; color: Tokens.inkMuted
                                            font.family: Tokens.mono; font.pixelSize: 9; font.letterSpacing: 1.3
                                        }
                                        Text {
                                            width: parent.width - Tokens.s3
                                            elide: Text.ElideRight
                                            text: modelData.v; color: Tokens.ink
                                            font.family: modelData.mono === true ? Tokens.mono : Tokens.ui
                                            font.pixelSize: modelData.mono === true ? 14 : 20
                                            font.weight: Font.Light
                                        }
                                    }
                                }
                            }

                            // verbs: pause/resume toggles on the reported status.
                            Row {
                                spacing: Tokens.s3
                                readonly property bool paused: powerBody.parent.live && powerBody.parent.mon.status === "paused"
                                Btn {
                                    text: parent.paused ? I18n.tr("RESUME") : I18n.tr("PAUSE")
                                    onAct: Vm.power(pane.name, parent.paused ? "resume" : "pause")
                                }
                                ConfirmBtn {
                                    idleText: I18n.tr("RESET")
                                    confirmText: I18n.tr("HARD RESET?")
                                    onConfirmed: Vm.power(pane.name, "reset")
                                }
                            }

                            // live memory: reballoon the guest without a reboot.
                            Column {
                                width: parent.width
                                spacing: Tokens.s2
                                visible: powerBody.parent.live && powerBody.parent.balloonMB > 0
                                Row {
                                    width: parent.width
                                    Text {
                                        text: I18n.tr("LIVE MEMORY"); color: Tokens.inkMuted
                                        font.family: Tokens.mono; font.pixelSize: 9; font.letterSpacing: 1.3
                                    }
                                    Item { width: parent.width - 220; height: 1 }
                                    Text {
                                        text: Vm.human(powerBody.parent.balloonMB * 1024 * 1024) + " / " + Vm.human(pane.ramNum * 1024 * 1024 * 1024)
                                        color: Tokens.ink; font.family: Tokens.mono; font.pixelSize: 11
                                    }
                                }
                                Slid {
                                    width: parent.width
                                    from: 256
                                    to: pane.ramNum * 1024
                                    value: powerBody.parent.balloonMB
                                    onModified: (v) => {
                                        powerBody.parent.balloonDragging = true;
                                        powerBody.parent.balloonMB = v;
                                        balloonCommit.restart();
                                    }
                                }
                                Timer {
                                    id: balloonCommit
                                    interval: 300
                                    onTriggered: { Vm.balloon(pane.name, powerBody.parent.balloonMB); powerBody.parent.balloonDragging = false; }
                                }
                            }

                            // pinning: nail each vCPU to a host core for steady latency.
                            Row {
                                width: parent.width
                                spacing: Tokens.s3
                                Sw {
                                    anchors.verticalCenter: parent.verticalCenter
                                    on: powerBody.parent.live && powerBody.parent.mon.pinned === true
                                    onToggled: (v) => Vm.pin(pane.name, v ? "auto" : "off")
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 70
                                    spacing: 1
                                    Text {
                                        text: I18n.tr("PIN VCPUS"); color: Tokens.ink
                                        font.family: Tokens.ui; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 1.4
                                    }
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: I18n.tr("Nail each vCPU to its own host core: steadier latency for games and real-time work.")
                                        color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: 11
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                visible: !powerBody.parent.live
                                text: I18n.tr("Waiting for the machine's live monitor. If it never arrives, the ryovm-mon helper may not be installed.")
                                color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: 11
                            }
                        }
                    }
                }

                // ── IDENTITY ────────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    Head { text: I18n.tr("IDENTITY") }
                    Note { visible: pane.running; text: I18n.tr("Stop the machine to rename it.") }
                    Row {
                        width: parent.width
                        spacing: Tokens.s3
                        visible: !pane.running
                        Field {
                            id: renameField
                            width: parent.width - renameBtn.width - Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            onEdited: (v) => {
                                var s = v.replace(/[\/\s]+/g, "-");
                                if (s !== v) renameField.text = s;
                            }
                            onCommitted: if (renameBtn.armed) renameBtn.act()
                        }
                        Btn {
                            id: renameBtn
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("RENAME")
                            primary: true
                            armed: !Vm.busy && renameField.text.trim().length > 0 && renameField.text.trim() !== pane.name
                            onAct: Vm.renameVm(pane.name, renameField.text.trim())
                        }
                    }
                }

                // ── RESOURCES ───────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    Head { text: I18n.tr("RESOURCES") }
                    Note {
                        text: pane.running
                            ? I18n.tr("Stop the machine to change its hardware.")
                            : I18n.tr("AUTO means quickemu tunes it to your hardware at launch. Set a number here to pin it.")
                    }
                    Item {
                        width: parent.width
                        height: resFlow.height
                        opacity: pane.running ? 0.35 : 1
                        Flow {
                            id: resFlow
                            width: parent.width
                            spacing: Tokens.s2
                            Cell {
                                width: pane.span(6)
                                controlWidth: Spans.inlineWidth("step", 0, width)
                                label: I18n.tr("CPU cores")
                                value: pane.vm && pane.vm.cores !== "auto" ? String(pane.coresNum) : I18n.tr("AUTO")
                                def: I18n.tr("AUTO")
                                desc: I18n.tr("How many host cores the guest gets.")
                                Column {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.s1
                                    Step {
                                        anchors.right: parent.right
                                        value: pane.coresNum
                                        from: 1; to: 32
                                        onModified: (v) => { if (!pane.running) Vm.setConfig(pane.name, "cpu_cores", Math.round(v)); }
                                    }
                                    Btn {
                                        anchors.right: parent.right
                                        visible: pane.vm && pane.vm.cores !== "auto"
                                        compact: true
                                        text: I18n.tr("AUTO")
                                        armed: !pane.running
                                        onAct: Vm.setConfig(pane.name, "cpu_cores", "auto")
                                    }
                                }
                            }
                            Cell {
                                width: pane.span(6)
                                controlWidth: Spans.inlineWidth("step", 0, width)
                                label: I18n.tr("Memory")
                                unit: "GB"
                                value: pane.vm && pane.vm.ram !== "auto" ? String(pane.ramNum) : I18n.tr("AUTO")
                                def: I18n.tr("AUTO")
                                desc: I18n.tr("RAM handed to the guest.")
                                Column {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.s1
                                    Step {
                                        anchors.right: parent.right
                                        value: pane.ramNum
                                        from: 1; to: 128
                                        onModified: (v) => { if (!pane.running) Vm.setConfig(pane.name, "ram", Math.round(v) + "G"); }
                                    }
                                    Btn {
                                        anchors.right: parent.right
                                        visible: pane.vm && pane.vm.ram !== "auto"
                                        compact: true
                                        text: I18n.tr("AUTO")
                                        armed: !pane.running
                                        onAct: Vm.setConfig(pane.name, "ram", "auto")
                                    }
                                }
                            }
                        }
                    }

                    // disk footprint + explicit grow (reclaim lives in Danger).
                    Column {
                        width: parent.width
                        spacing: Tokens.s2
                        visible: pane.det && pane.det.installed
                        Row {
                            spacing: Tokens.s2
                            FieldLabel { anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Disk") }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("%1 used").arg(pane.vm ? Vm.human(pane.vm.diskUsed || 0) : "0")
                                    + (pane.vm && pane.vm.disk ? "  \u00b7  " + I18n.tr("%1 cap").arg(pane.vm.disk) : "")
                                color: Tokens.ink
                                font.family: Tokens.mono
                                font.pixelSize: 12
                            }
                        }
                        Row {
                            width: parent.width
                            spacing: Tokens.s3
                            Item {
                                width: parent.width - growBtn.width - Tokens.s3
                                height: Tokens.cellH
                                opacity: pane.running ? 0.35 : 1
                                Cell {
                                    anchors.fill: parent
                                    controlWidth: Spans.inlineWidth("step", 0, width)
                                    label: I18n.tr("Disk size")
                                    unit: "GB"
                                    value: String(pane.diskTarget)
                                    Step {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        value: pane.diskTarget
                                        from: 8; to: 2048
                                        stepBy: 8
                                        onModified: (v) => { if (!pane.running) pane.diskTarget = Math.round(v); }
                                    }
                                }
                            }
                            Btn {
                                id: growBtn
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("GROW TO ") + pane.diskTarget + I18n.tr(" GB")
                                primary: true
                                armed: !pane.running && !Vm.busy && pane.diskTarget > pane.capGb
                                onAct: Vm.resizeDisk(pane.name, pane.diskTarget + "G")
                            }
                        }
                        Note { text: I18n.tr("Grow only; the guest extends its partition afterwards.") }
                    }
                }

                // ── SEAL ─────────────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    visible: pane.det && pane.det.installed === true
                    Head { text: I18n.tr("SEAL") }
                    Note { visible: pane.running; text: I18n.tr("Stop the machine to seal or restore it.") }
                    Column {
                        width: parent.width
                        spacing: Tokens.s3
                        visible: !pane.running
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: pane.sealSnap !== null
                                ? I18n.tr("Sealed ") + pane.sealSnap.date + I18n.tr(". Disposable runs never touch the seal; a normal run that dirties the machine can be rolled back to it.")
                                : I18n.tr("Set the machine up the way you want it (packages, users, config) then seal that state. Disposable runs will boot from it forever; restore brings a dirtied machine back.")
                            color: Tokens.inkMuted
                            font.family: Tokens.ui
                            font.pixelSize: 12
                        }
                        Row {
                            spacing: Tokens.s3
                            Btn {
                                visible: pane.sealSnap === null
                                text: I18n.tr("SEAL MACHINE")
                                primary: true
                                armed: !Vm.busy
                                onAct: Vm.seal(pane.name)
                            }
                            ConfirmBtn {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: pane.sealSnap !== null
                                armed: !Vm.busy
                                idleText: I18n.tr("RE-SEAL NOW")
                                confirmText: I18n.tr("OVERWRITE SEAL?")
                                onConfirmed: Vm.seal(pane.name)
                            }
                            GuardSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: pane.sealSnap !== null
                                enabled: !Vm.busy
                                label: I18n.tr("RESTORE SEAL")
                                armedLabel: I18n.tr("ROLL BACK")
                                onFired: Vm.restoreSeal(pane.name)
                            }
                        }
                    }
                }

                // ── USB ──────────────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    Head { text: I18n.tr("USB DEVICES") }
                    Note {
                        text: pane.running
                            ? I18n.tr("Stop the machine to change assignments: devices attach at the next launch.")
                            : I18n.tr("Engaged devices are handed to the guest when it boots.")
                    }
                    Text {
                        visible: Vm.usb.length === 0
                        text: I18n.tr("No USB devices detected on the host.")
                        color: Tokens.inkFaint
                        font.family: Tokens.ui
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: Vm.usb
                        delegate: Rectangle {
                            id: usbRow
                            required property var modelData
                            width: parent ? parent.width : 0
                            height: 40
                            radius: Tokens.radius
                            color: usbRow.modelData.assigned ? Tokens.tint10 : "transparent"
                            border.width: Tokens.border
                            border.color: usbRow.modelData.assigned ? Tokens.line : Tokens.lineSoft
                            antialiasing: false

                            Sw {
                                id: usbSw
                                anchors.left: parent.left
                                anchors.leftMargin: Tokens.s3
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: pane.running ? 0.4 : 1
                                on: usbRow.modelData.assigned === true
                                onToggled: (v) => { if (!pane.running && !Vm.busy) Vm.setUsb(pane.name, usbRow.modelData.id, v); }
                            }
                            Text {
                                anchors.left: usbSw.right
                                anchors.leftMargin: Tokens.s3
                                anchors.right: usbId.left
                                anchors.rightMargin: Tokens.s2
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: usbRow.modelData.name
                                color: usbRow.modelData.assigned ? Tokens.ink : Tokens.inkDim
                                font.family: Tokens.ui
                                font.pixelSize: 13
                            }
                            Text {
                                id: usbId
                                anchors.right: parent.right
                                anchors.rightMargin: Tokens.s3
                                anchors.verticalCenter: parent.verticalCenter
                                text: usbRow.modelData.id
                                color: Tokens.inkFaint
                                font.family: Tokens.mono
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                // ── PORTS ────────────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    Head { text: I18n.tr("PORTS") }
                    Note {
                        text: pane.running
                            ? I18n.tr("Stop the machine to change forwards: they bind at the next launch.")
                            : I18n.tr("Forward a host port to a guest port, reachable at localhost.")
                    }
                    Text {
                        visible: Vm.portfwds.length === 0
                        text: I18n.tr("No port forwards yet.")
                        color: Tokens.inkFaint
                        font.family: Tokens.ui
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: Vm.portfwds
                        delegate: Rectangle {
                            id: fwdRow
                            required property var modelData
                            width: parent ? parent.width : 0
                            height: 36
                            radius: Tokens.radius
                            color: "transparent"
                            border.width: Tokens.border
                            border.color: Tokens.lineSoft
                            antialiasing: false
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Tokens.s3
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("localhost:") + fwdRow.modelData.host + "   \u2192   :" + fwdRow.modelData.guest
                                color: Tokens.ink
                                font.family: Tokens.mono
                                font.pixelSize: 12
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: Tokens.s3
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u2715"
                                visible: !pane.running
                                color: fwdKillH.hovered ? Tokens.ink : Tokens.inkFaint
                                font.family: Tokens.mono; font.pixelSize: 12
                                HoverHandler { id: fwdKillH; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: if (!Vm.busy) Vm.removePortfwd(pane.name, fwdRow.modelData.host + ":" + fwdRow.modelData.guest) }
                            }
                        }
                    }
                    Item {
                        width: parent.width
                        height: 30
                        visible: !pane.running
                        Btn {
                            id: addFwd
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("ADD")
                            primary: true
                            armed: fwdHost.text.trim().length > 0 && fwdGuest.text.trim().length > 0
                            onAct: {
                                Vm.addPortfwd(pane.name, fwdHost.text.trim() + ":" + fwdGuest.text.trim());
                                fwdHost.clear(); fwdGuest.clear();
                            }
                        }
                        Field {
                            id: fwdHost
                            anchors.left: parent.left
                            anchors.right: parent.horizontalCenter
                            anchors.rightMargin: Tokens.s2
                            anchors.verticalCenter: parent.verticalCenter
                            tabular: true
                            placeholder: I18n.tr("host port")
                        }
                        Field {
                            id: fwdGuest
                            anchors.left: parent.horizontalCenter
                            anchors.right: addFwd.left
                            anchors.rightMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            tabular: true
                            placeholder: I18n.tr("guest port")
                            onAccepted: if (addFwd.armed) addFwd.act()
                        }
                    }
                }

                // ── SNAPSHOTS ────────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    Head { text: I18n.tr("SNAPSHOTS") }
                    // no disk yet: a dark annunciator and the exact next step.
                    Rectangle {
                        visible: !(pane.det && pane.det.installed)
                        width: parent.width
                        height: 44
                        color: "transparent"
                        radius: Tokens.radius
                        border.width: Tokens.border
                        border.color: Tokens.lineSoft
                        antialiasing: false
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Tokens.s4
                            anchors.right: parent.right
                            anchors.rightMargin: Tokens.s4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.s3
                            Annunciator { anchors.verticalCenter: parent.verticalCenter; label: I18n.tr("NO DISK"); lit: false; tileW: 60 }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 72
                                wrapMode: Text.WordWrap
                                text: I18n.tr("Snapshots capture the disk: press Launch once to create it, then save states here.")
                                color: Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: 12
                            }
                        }
                    }
                    Note { visible: pane.running; text: I18n.tr("Stop the machine to manage snapshots.") }
                    Row {
                        width: parent.width
                        spacing: Tokens.s3
                        visible: pane.det && pane.det.installed && !pane.running
                        Field {
                            id: snapIn
                            width: parent.width - addSnap.width - Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            placeholder: I18n.tr("Snapshot name (e.g. clean install)")
                            onCommitted: if (addSnap.armed) addSnap.act()
                        }
                        Btn {
                            id: addSnap
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("SAVE")
                            primary: true
                            armed: snapIn.text.trim().length > 0
                            onAct: { Vm.snapshot(pane.name, "create", snapIn.text.trim()); snapIn.clear(); }
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: Tokens.s2
                        visible: pane.det && pane.det.installed
                        Text {
                            visible: pane.det && (!pane.det.snapshots || pane.det.snapshots.length === 0) && !pane.running
                            text: I18n.tr("No snapshots yet.")
                            color: Tokens.inkFaint
                            font.family: Tokens.ui
                            font.pixelSize: 12
                        }
                        Repeater {
                            model: pane.det ? pane.det.snapshots : []
                            delegate: Rectangle {
                                id: snapRow
                                required property var modelData
                                width: parent ? parent.width : 0
                                height: 46
                                radius: Tokens.radius
                                color: "transparent"
                                border.width: Tokens.border
                                border.color: Tokens.line
                                antialiasing: false
                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Tokens.s4
                                    anchors.right: snapActions.left
                                    anchors.rightMargin: Tokens.s2
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: snapRow.modelData.name
                                        color: Tokens.ink
                                        font.family: Tokens.ui
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        text: snapRow.modelData.date
                                        color: Tokens.inkFaint
                                        font.family: Tokens.mono
                                        font.pixelSize: 10
                                    }
                                }
                                Row {
                                    id: snapActions
                                    anchors.right: parent.right
                                    anchors.rightMargin: Tokens.s2
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.s2
                                    GuardSwitch {
                                        anchors.verticalCenter: parent.verticalCenter
                                        enabled: !pane.running && !Vm.busy
                                        label: I18n.tr("RESTORE")
                                        armedLabel: I18n.tr("ROLL BACK")
                                        onFired: Vm.snapshot(pane.name, "restore", snapRow.modelData.name)
                                    }
                                    ConfirmBtn {
                                        anchors.verticalCenter: parent.verticalCenter
                                        armed: !pane.running
                                        idleText: I18n.tr("DELETE")
                                        confirmText: I18n.tr("DELETE?")
                                        onConfirmed: Vm.snapshot(pane.name, "delete", snapRow.modelData.name)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── TEMPLATE ─────────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    visible: pane.det && pane.det.installed === true
                    Head { text: I18n.tr("TEMPLATE") }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: pane.running
                            ? I18n.tr("Stop the machine to template it.")
                            : I18n.tr("Freeze this machine (tools and all) into a golden base, then spawn instant clones off it (ryovm spawn). A disposable spawn boots in seconds with everything already baked.")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: pane.running ? 12 : 11
                    }
                    Btn {
                        text: I18n.tr("SAVE AS TEMPLATE")
                        armed: !pane.running && !Vm.busy
                        onAct: Vm.template(pane.name)
                    }
                }

                // ── DANGER ───────────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    Head { text: I18n.tr("DANGER ZONE") }
                    Row {
                        spacing: Tokens.s3
                        Btn {
                            text: I18n.tr("OPEN FOLDER")
                            onAct: Vm.openFolder(pane.name)
                        }
                        GuardSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pane.det && pane.det.installed === true
                            enabled: !pane.running && !Vm.busy
                            label: I18n.tr("RECLAIM DISK")
                            armedLabel: I18n.tr("WIPE DISK")
                            onFired: Vm.reclaimDisk(pane.name)
                        }
                        GuardSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            enabled: !pane.running && !Vm.busy
                            label: I18n.tr("DELETE MACHINE")
                            armedLabel: I18n.tr("DESTROY")
                            onFired: Vm.deleteVm(pane.name)
                        }
                    }
                    Note { text: I18n.tr("Reclaim deletes the disk image but keeps the machine and its setup, ready to reinstall. Delete removes everything.") }
                }

                // ── LOG (the yard's flight recorder) ─────────────────────────
                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    Head { text: I18n.tr("LOG") }
                    Text {
                        visible: pane.logEvents.length === 0
                        text: I18n.tr("No activity yet.")
                        color: Tokens.inkFaint
                        font.family: Tokens.ui
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: pane.logEvents
                        delegate: Column {
                            id: logRow
                            required property var modelData
                            property bool expanded: false
                            readonly property bool fault: logRow.modelData.kind === "fault"
                            readonly property bool hasDetail: logRow.fault && (logRow.modelData.detail || "").indexOf("\n") >= 0
                            width: parent ? parent.width : 0
                            spacing: 4
                            Row {
                                width: parent.width
                                spacing: Tokens.s2
                                Text {
                                    text: logRow.modelData.time
                                    color: Tokens.inkFaint
                                    font.family: Tokens.mono
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                // faults carry an inverted tag (amendment 5).
                                Rectangle {
                                    visible: logRow.fault
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: fltLab.width + 10
                                    height: 15
                                    color: Tokens.bone
                                    antialiasing: false
                                    Text {
                                        id: fltLab
                                        anchors.centerIn: parent
                                        text: I18n.tr("FAULT")
                                        color: Tokens.inkOnBone
                                        font.family: Tokens.ui
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                        font.letterSpacing: 1.0
                                    }
                                }
                                Text {
                                    width: parent.width - x - (detTag.visible ? detTag.width + Tokens.s2 : 0)
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: logRow.modelData.text
                                    color: logRow.fault ? Tokens.ink : Tokens.inkDim
                                    font.family: Tokens.mono
                                    font.pixelSize: 11
                                }
                                Text {
                                    id: detTag
                                    visible: logRow.hasDetail
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: logRow.expanded ? I18n.tr("LESS") : I18n.tr("DETAIL")
                                    color: dth.hovered ? Tokens.ink : Tokens.inkFaint
                                    font.family: Tokens.mono
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.2
                                    HoverHandler { id: dth; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: logRow.expanded = !logRow.expanded }
                                }
                            }
                            Text {
                                visible: logRow.expanded
                                width: parent.width
                                wrapMode: Text.WrapAnywhere
                                text: logRow.modelData.detail
                                color: Tokens.inkMuted
                                font.family: Tokens.mono
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                // ── the machine plate: engraved, screwed on, flat ────────────
                Rectangle {
                    width: parent.width
                    height: 54
                    color: "transparent"
                    radius: Tokens.radius
                    border.width: Tokens.border
                    border.color: Tokens.line
                    antialiasing: false

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        color: "transparent"
                        border.width: Tokens.border
                        border.color: Tokens.lineSoft
                        antialiasing: false
                    }
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            width: 4; height: 4
                            radius: 2
                            color: Tokens.inkFaint
                            x: index % 2 === 0 ? 7 : parent.width - 11
                            y: index < 2 ? 7 : parent.height - 11
                        }
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 26
                        Text {
                            text: I18n.tr("RYOKU RYOPORT · TYPE V-01")
                            color: Tokens.inkMuted
                            font.family: Tokens.mono
                            font.pixelSize: 10
                            font.letterSpacing: 2
                        }
                        Text {
                            text: I18n.tr("GUEST ") + (pane.vm ? (pane.vm.guest || "linux").toUpperCase() : "-")
                            color: Tokens.inkFaint
                            font.family: Tokens.mono
                            font.pixelSize: 10
                            font.letterSpacing: 2
                        }
                        Text {
                            text: I18n.tr("CARRIER QEMU·KVM")
                            color: Tokens.inkFaint
                            font.family: Tokens.mono
                            font.pixelSize: 10
                            font.letterSpacing: 2
                        }
                    }
                }

                Item { width: 1; height: Tokens.s1 }
            }
        }
    }

    // ---- local helpers -----------------------------------------------------
    component Head: Row {
        id: hd
        property string text: ""
        width: parent ? parent.width : 0
        spacing: Tokens.s2
        Rectangle { width: 4; height: 4; color: Tokens.ink; anchors.verticalCenter: parent.verticalCenter }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hd.text
            color: Tokens.ink
            font.family: Tokens.ui
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: Tokens.trackMark
        }
        Rectangle {
            width: Math.max(0, hd.width - lead.x - 200)
            height: 1
            color: Tokens.lineSoft
            anchors.verticalCenter: parent.verticalCenter
            id: lead
        }
    }
    component Note: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        color: Tokens.inkMuted
        font.family: Tokens.ui
        font.pixelSize: 11
    }
    component FieldLabel: Text {
        color: Tokens.inkMuted
        font.family: Tokens.ui
        font.pixelSize: 10
        font.weight: Font.Medium
        font.letterSpacing: Tokens.trackLabel
        font.capitalization: Font.AllUppercase
    }

    // a keyboard-shortcut row: a mono keycap tag + what it does.
    component KeyHint: Row {
        id: kh
        property string keys: ""
        property string action: ""
        width: parent ? parent.width : 0
        spacing: Tokens.s3
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 112
            height: 24
            radius: Tokens.radius
            color: "transparent"
            border.width: Tokens.border
            border.color: Tokens.line
            antialiasing: false
            Text {
                anchors.centerIn: parent
                text: kh.keys
                color: Tokens.ink
                font.family: Tokens.mono
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: kh.action
            color: Tokens.inkDim
            font.family: Tokens.ui
            font.pixelSize: 13
        }
    }

    // a two-tap destructive confirm on the module button (no red; bone when armed).
    component ConfirmBtn: Btn {
        id: cbtn
        property string idleText: ""
        property string confirmText: ""
        property bool armed2: false
        signal confirmed()
        text: cbtn.armed2 ? cbtn.confirmText : cbtn.idleText
        primary: cbtn.armed2
        onAct: {
            if (cbtn.armed2) { cbtn.armed2 = false; cbtn.confirmed(); }
            else { cbtn.armed2 = true; cbtnDisarm.restart(); }
        }
        Timer { id: cbtnDisarm; interval: 3500; onTriggered: cbtn.armed2 = false }
    }
}
