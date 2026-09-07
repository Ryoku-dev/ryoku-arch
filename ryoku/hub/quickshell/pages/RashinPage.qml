pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Rashin (DESIGN.md section 11, ADVANCED). The optional, fully local agent OS
// (羅針, the system needle). This page is the Hub's welcome to Rashin, wearing
// the Rashin/Hermes dashboard's own identity rather than the Hub's: the warm
// bone-on-black poster palette and Archivo Black + JetBrains Mono type of the
// web dashboard at 127.0.0.1:3600 (mirrored from ryoku/rashin/backend/web). It
// leads with the samurai hero banner and the live model Hermes runs on, lays
// out what Rashin does (the vault, memory, skills, agents, chat, code), shows
// how to use it, and keeps the master switch, one-click Hermes setup and the
// dashboard link. Live state comes from `ryoku-rashin status --json`; setup
// progress is mirrored from the daemon's setup.json. Everything stays on the
// machine; Rashin is off until you switch it on.
Item {
    id: pg

    property var hub
    readonly property bool fullBleed: true

    // ── the Rashin/Hermes palette, mirrored from the dashboard's base.css
    // (:root). Deliberately not the Hub's Tokens: this section wears the
    // product's own warm poster identity so it reads as Rashin, not Settings.
    QtObject {
        id: hx
        readonly property color paper: "#0e0d0b"
        readonly property color paper2: "#14120f"
        readonly property color ink: "#e8d8c9"
        readonly property color inkDim: "#8f8378"
        readonly property color red: "#c94e44"
        readonly property color redDeep: "#9f4125"
        readonly property color teal: "#3e6868"
        readonly property color orange: "#f3701e"
        readonly property color slate: "#4b607f"
        readonly property color tan: "#cda47b"
        readonly property color line: Qt.rgba(232 / 255, 216 / 255, 201 / 255, 0.18)
        readonly property color lineSoft: Qt.rgba(232 / 255, 216 / 255, 201 / 255, 0.09)
    }

    // Archivo Black rides display, bundled beside the Hub (converted from the
    // dashboard's woff2) so it ships with the config tree, no font package. The
    // rest is JetBrains Mono, the dashboard's body face, hard-depended by the
    // desktop package; kanji is Noto CJK.
    FontLoader { id: archivo; source: Qt.resolvedUrl("../fonts/archivo-black.ttf") }
    readonly property string fDisplay: archivo.name || "sans-serif"
    readonly property string fMono: "JetBrainsMono Nerd Font"
    readonly property string fJp: "Noto Sans CJK JP"

    // centered body column; the hero and every section share this measure.
    readonly property real bodyW: Math.min(pg.width - Tokens.s5 * 2, 1080)

    // ── status snapshot (page readouts, not stored config) ───────────────────
    property bool installed: true
    property bool daemonEnabled: false
    property bool running: false
    // the port the daemon reports, not a literal: a user who changed it in
    // ~/.config/ryoku/rashin.json still gets a link that resolves.
    property int port: 3600
    property bool vaultExists: false
    property int vaultFiles: 0
    property bool hermesInstalled: false
    property bool hermesConfigured: false
    property string hermesModel: ""
    property string hermesProvider: ""
    property string hermesVersion: ""
    property int agentsPresent: 0
    property int agentsWired: 0

    readonly property string wiredSummary: pg.agentsPresent > 0
        ? I18n.tr("%1 / %2 wired").arg(pg.agentsWired).arg(pg.agentsPresent)
        : I18n.tr("none yet")

    // live Hermes setup progress, mirrored from the daemon's setup.json.
    property string setupPhase: ""
    property string setupDetail: ""
    property bool setupOk: true

    Component.onCompleted: pg.refresh()
    function refresh() { statusProc.running = true; }

    Process {
        id: statusProc
        // sh-wrapped so a missing ryoku-rashin still closes stdout and fires
        // onStreamFinished; empty/unparseable output reads as "not installed".
        command: ["sh", "-c", "ryoku-rashin status --json"]
        stderr: StdioCollector {}
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(this.text);
                    pg.installed = true;
                    pg.daemonEnabled = o.enabled === true;
                    pg.running = o.running === true;
                    if (typeof o.port === "number" && o.port > 0)
                        pg.port = o.port;
                    var v = o.vault || ({});
                    pg.vaultExists = v.exists === true;
                    pg.vaultFiles = (typeof v.files === "number") ? v.files : 0;
                    var h = o.hermes || ({});
                    pg.hermesInstalled = h.installed === true;
                    pg.hermesConfigured = h.configured === true;
                    pg.hermesModel = h.model || "";
                    pg.hermesProvider = h.provider || "";
                    pg.hermesVersion = h.version || "";
                    var ags = o.agents || [];
                    var present = 0, wired = 0;
                    for (var i = 0; i < ags.length; i++) {
                        if (ags[i].present) {
                            present++;
                            if (ags[i].wired)
                                wired++;
                        }
                    }
                    pg.agentsPresent = present;
                    pg.agentsWired = wired;
                    return;
                } catch (e) {
                    // empty output (binary missing) or malformed JSON.
                }
                pg.installed = false;
                pg.daemonEnabled = false;
                pg.running = false;
            }
        }
    }

    Process { id: enableProc; onExited: pg.refresh() }
    Process { id: disableProc; onExited: pg.refresh() }
    function setEnabled(on) {
        var p = on ? enableProc : disableProc;
        p.command = ["ryoku-rashin", on ? "enable" : "disable"];
        p.running = true;
    }

    FileView {
        id: setupFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-rashin/setup.json"
        watchChanges: true
        printErrors: false
        onLoaded: pg.applySetup(setupFile.text())
        onFileChanged: setupFile.reload()
        onLoadFailed: {}
    }
    function applySetup(t) {
        try {
            var o = JSON.parse(t);
            pg.setupPhase = o.phase || "";
            pg.setupDetail = o.detail || "";
            pg.setupOk = o.ok !== false;
            if (pg.setupPhase === "done")
                pg.refresh();
        } catch (e) {}
    }
    function runSetup() {
        Spawn.run(["kitty", "--class", "ryoku-rashin-setup", "-e", "ryoku-rashin", "setup"]);
    }
    // Open the dashboard the daemon actually serves. Two things used to send a
    // user to a browser error they read as a 404: the port was hardcoded here
    // while the daemon reads it from its own config, and the button opened the
    // URL even with nothing listening. Take the port from `status --json` and
    // start the daemon first when it is down; `ryoku-rashin serve` returns once
    // the socket is up, so the browser never races it.
    function openDashboard() {
        var url = "http://127.0.0.1:" + pg.port;
        if (pg.running) {
            Spawn.run(["xdg-open", url]);
            return;
        }
        openProc.command = ["sh", "-c",
            "ryoku-rashin serve --if-enabled >/dev/null 2>&1 & "
            + "for i in 1 2 3 4 5 6 7 8 9 10; do "
            + "ryoku-rashin status --json 2>/dev/null | grep -q '\"running\":true' && break; sleep 0.3; done; "
            + "xdg-open " + url];
        openProc.running = true;
    }
    Process { id: openProc; onExited: pg.refresh() }

    // ── reusable poster parts ────────────────────────────────────────────────

    // a stamped-ink status chip: hairline box, tracked mono caps, tinted.
    component Stamp: Rectangle {
        id: stamp
        property string label: ""
        property color tint: hx.inkDim
        implicitWidth: stampT.implicitWidth + 18
        implicitHeight: 22
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(stamp.tint.r, stamp.tint.g, stamp.tint.b, 0.55)
        Text {
            id: stampT
            anchors.centerIn: parent
            text: I18n.tr(stamp.label)
            color: stamp.tint
            font.family: pg.fMono
            font.pixelSize: 9
            font.letterSpacing: 2
        }
    }

    // a section header: kanji + tracked caps title + hairline leader.
    component Head: Item {
        id: hd
        property string kanji: ""
        property string title: ""
        width: parent ? parent.width : 0
        height: 20
        Row {
            id: hdRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s2
            Text {
                text: hd.kanji; color: hx.red; font.family: pg.fJp
                font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: hd.title; color: hx.ink; font.family: pg.fMono
                font.pixelSize: 11; font.letterSpacing: 3; font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Rectangle {
            anchors.left: hdRow.right; anchors.leftMargin: Tokens.s3
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            height: 1; color: hx.line
        }
    }

    // a function poster card: accent tab, index + kanji, name, one-liner, and an
    // optional live stat brightening to the accent.
    component FnCard: Rectangle {
        id: fc
        property string index: ""
        property string kanji: ""
        property string name: ""
        property string desc: ""
        property string stat: ""
        property color accent: hx.teal
        height: 128
        color: hx.paper2
        border.width: 1
        border.color: hx.line

        Rectangle { x: 0; y: 0; width: 34; height: 3; color: fc.accent }

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 7
            Row {
                spacing: Tokens.s2
                Text {
                    text: fc.index; color: fc.accent; font.family: pg.fDisplay
                    font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: fc.kanji; color: hx.inkDim; font.family: pg.fJp
                    font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                text: fc.name; color: hx.ink; font.family: pg.fDisplay; font.pixelSize: 21
            }
            Text {
                width: parent.width
                text: I18n.tr(fc.desc); color: hx.inkDim; font.family: pg.fMono; font.pixelSize: 12
                wrapMode: Text.WordWrap; lineHeight: 1.25
            }
        }
        Text {
            visible: fc.stat !== ""
            anchors { right: parent.right; top: parent.top; margins: 16 }
            text: fc.stat; color: fc.accent; font.family: pg.fMono; font.pixelSize: 11
        }
    }

    // an example row: a mono command in red, then what it does.
    component TryRow: Row {
        id: tr
        property string cmd: ""
        property string note: ""
        width: parent ? parent.width : 0
        spacing: Tokens.s3
        Text {
            width: Math.round(tr.width * 0.34)
            text: tr.cmd; color: hx.red; font.family: pg.fMono; font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text {
            width: tr.width - Math.round(tr.width * 0.34) - tr.spacing
            text: tr.note; color: hx.inkDim; font.family: pg.fMono; font.pixelSize: 13
            wrapMode: Text.WordWrap
        }
    }

    // a poster button: filled ink primary, hairline ghost otherwise.
    component PosterBtn: Item {
        id: bt
        property string label: ""
        property bool primary: false
        property bool on: true
        signal act()
        implicitWidth: btT.implicitWidth + Tokens.s5 * 2
        implicitHeight: 42
        opacity: bt.on ? 1 : 0.4
        Rectangle {
            anchors.fill: parent
            color: bt.primary ? hx.ink : "transparent"
            border.width: 1
            border.color: bt.primary ? hx.ink : hx.line
        }
        Text {
            id: btT
            anchors.centerIn: parent
            text: I18n.tr(bt.label); color: bt.primary ? hx.paper : hx.ink
            font.family: pg.fMono; font.pixelSize: 11; font.letterSpacing: 2; font.weight: Font.Medium
        }
        MouseArea {
            anchors.fill: parent; enabled: bt.on
            cursorShape: Qt.PointingHandCursor
            onClicked: bt.act()
        }
    }

    // ── the page: warm paper, one scrolling poster column ────────────────────
    Rectangle { anchors.fill: parent; color: hx.paper }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.height + Tokens.s6 * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Column {
            id: body
            anchors.horizontalCenter: parent.horizontalCenter
            y: Tokens.s6
            width: pg.bodyW
            spacing: Tokens.s6

            // ── HERO: the samurai banner, title + live state overlaid ────────
            Item {
                width: parent.width
                height: Math.round(Math.min(width / 2.357, 320))
                clip: true

                Image {
                    id: heroImg
                    anchors.fill: parent
                    source: Ryodecors.dir + "rashin-hero.png"
                    fillMode: Image.PreserveAspectCrop
                    verticalAlignment: Image.AlignVCenter
                    asynchronous: true
                    cache: true
                }
                // procedural fallback if the banner is missing.
                Rectangle {
                    anchors.fill: parent
                    visible: heroImg.status !== Image.Ready
                    color: hx.paper2
                }
                Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: hx.line }

                // bottom scrim so the cap stays legible over the art.
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.height * 0.7
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Qt.rgba(hx.paper.r, hx.paper.g, hx.paper.b, 0.92) }
                    }
                }

                // title cap, bottom-left.
                Column {
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: Tokens.s5; bottomMargin: Tokens.s4 }
                    spacing: 3
                    Text {
                        text: I18n.tr("RYOKU RASHIN"); color: hx.ink; font.family: pg.fDisplay
                        font.pixelSize: Math.round(Math.min(pg.bodyW * 0.05, 40))
                    }
                    Row {
                        spacing: Tokens.s2
                        Text {
                            text: "羅針"; color: hx.red; font.family: pg.fJp; font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: I18n.tr("THE SYSTEM NEEDLE"); color: hx.inkDim; font.family: pg.fMono
                            font.pixelSize: 10; font.letterSpacing: 3
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // live state stamp, top-right.
                Stamp {
                    anchors { right: parent.right; top: parent.top; rightMargin: Tokens.s4; topMargin: Tokens.s4 }
                    label: !pg.installed ? I18n.tr("NOT INSTALLED")
                        : (pg.running ? I18n.tr("RUNNING") : (pg.daemonEnabled ? I18n.tr("STARTING") : I18n.tr("OFF")))
                    tint: pg.running ? hx.teal : (pg.installed ? hx.inkDim : hx.redDeep)
                }
            }

            // ── tagline ──────────────────────────────────────────────────────
            Text {
                width: parent.width
                text: I18n.tr("The optional local agent OS. A resident Hermes agent keeps a living map of this machine - hardware, packages, every config beside the binary that owns it - so your coding agents read the terrain instead of rediscovering it. Nothing ever leaves the box.")
                color: hx.ink; font.family: pg.fMono; font.pixelSize: 14
                wrapMode: Text.WordWrap; lineHeight: 1.5
            }

            // ── MASTER SWITCH + MODEL: what is running, and the control ───────
            Row {
                width: parent.width
                spacing: Tokens.s4
                readonly property bool wide: pg.bodyW >= 640
                property real colW: wide ? (width - Tokens.s4) / 2 : width

                // service switch
                Rectangle {
                    width: parent.colW
                    height: 96
                    color: hx.paper2
                    border.width: 1
                    border.color: pg.daemonEnabled ? Qt.rgba(hx.ink.r, hx.ink.g, hx.ink.b, 0.35) : hx.line
                    opacity: pg.installed ? 1 : 0.5

                    Column {
                        anchors { left: parent.left; right: sw.left; verticalCenter: parent.verticalCenter; leftMargin: 18; rightMargin: 14 }
                        spacing: 6
                        Row {
                            spacing: Tokens.s2
                            Text { text: "羅針"; color: hx.ink; font.family: pg.fJp; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: I18n.tr("RASHIN SERVICE"); color: hx.ink; font.family: pg.fDisplay
                                font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            width: parent.width
                            text: pg.installed
                                ? (pg.running ? I18n.tr("Running \u00b7 127.0.0.1:%1").arg(pg.port)
                                   : (pg.daemonEnabled ? I18n.tr("Enabled \u00b7 starting\u2026") : I18n.tr("Off \u00b7 switch on to start it with the desktop")))
                                : I18n.tr("Not installed \u00b7 install ryoku-rashin")
                            color: hx.inkDim; font.family: pg.fMono; font.pixelSize: 11; elide: Text.ElideRight
                        }
                    }
                    Sw {
                        id: sw
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        enabled: pg.installed
                        on: pg.daemonEnabled
                        onToggled: (c) => { pg.daemonEnabled = c; pg.setEnabled(c); }
                    }
                }

                // the model Hermes runs on -- the headline fact.
                Rectangle {
                    width: parent.colW
                    height: 96
                    color: hx.paper2
                    border.width: 1
                    border.color: hx.line
                    Rectangle { x: 0; y: 0; width: 34; height: 3; color: hx.red }

                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 18; rightMargin: 18 }
                        spacing: 4
                        Row {
                            spacing: Tokens.s2
                            Text { text: "模型"; color: hx.red; font.family: pg.fJp; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: I18n.tr("MODEL"); color: hx.inkDim; font.family: pg.fMono
                                font.pixelSize: 10; font.letterSpacing: 3; anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            width: parent.width
                            text: pg.hermesConfigured ? (pg.hermesModel || I18n.tr("configured")) : "-"
                            color: hx.ink; font.family: pg.fDisplay
                            font.pixelSize: pg.hermesConfigured ? 30 : 26
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: pg.hermesConfigured
                                ? (I18n.tr("via %1").arg(pg.hermesProvider || "hermes") + (pg.hermesVersion ? I18n.tr("  \u00b7  Hermes v%1").arg(pg.hermesVersion) : ""))
                                : (pg.hermesInstalled ? I18n.tr("run setup to choose a model") : I18n.tr("set up Hermes to choose a model"))
                            color: hx.inkDim; font.family: pg.fMono; font.pixelSize: 11; elide: Text.ElideRight
                        }
                    }
                }
            }

            // ── FUNCTIONS: the numbered poster index of what Rashin does ──────
            Column {
                width: parent.width
                spacing: Tokens.s4
                Head { kanji: "\u6a5f\u80fd"; title: I18n.tr("FUNCTIONS") }

                Grid {
                    id: fnGrid
                    width: parent.width
                    columns: pg.bodyW >= 860 ? 3 : (pg.bodyW >= 560 ? 2 : 1)
                    columnSpacing: Tokens.s4
                    rowSpacing: Tokens.s4
                    readonly property real cellW: (width - columnSpacing * (columns - 1)) / columns

                    FnCard {
                        width: fnGrid.cellW; index: "01"; kanji: "\u66f8\u5eab"; name: I18n.tr("VAULT"); accent: hx.teal
                        desc: I18n.tr("The living map your agents read - every config beside the binary that owns it.")
                        stat: pg.vaultExists ? I18n.tr("%1 files").arg(pg.vaultFiles) : ""
                    }
                    FnCard {
                        width: fnGrid.cellW; index: "02"; kanji: "\u8a18\u61b6"; name: I18n.tr("MEMORY"); accent: hx.orange
                        desc: I18n.tr("What Hermes remembers, carried across every session.")
                    }
                    FnCard {
                        width: fnGrid.cellW; index: "03"; kanji: "\u6280"; name: I18n.tr("SKILLS"); accent: hx.slate
                        desc: I18n.tr("Toolsets Hermes wields on demand - search, files, the web, more.")
                    }
                    FnCard {
                        width: fnGrid.cellW; index: "04"; kanji: "\u4e94\u4eba\u8846"; name: I18n.tr("AGENTS"); accent: hx.tan
                        desc: I18n.tr("Your coding agents, wired to one shared map of the machine.")
                        stat: pg.agentsPresent > 0 ? pg.wiredSummary : ""
                    }
                    FnCard {
                        width: fnGrid.cellW; index: "05"; kanji: "\u5bfe\u8a71"; name: I18n.tr("CHAT"); accent: hx.red
                        desc: I18n.tr("Talk to Hermes - in the dashboard, or run it in any terminal.")
                    }
                    FnCard {
                        width: fnGrid.cellW; index: "06"; kanji: "\u7f85\u91dd"; name: I18n.tr("CODE"); accent: hx.teal
                        desc: I18n.tr("prowl-agent code intelligence - cited answers over your repos.")
                    }
                }
            }

            // ── TRY: example uses ────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: Tokens.s3
                Head { kanji: "\u4f8b"; title: I18n.tr("TRY") }
                TryRow { cmd: "hermes"; note: I18n.tr("chat in the vault, from any terminal") }
                TryRow { cmd: "hermes gateway"; note: I18n.tr("connect Telegram / Discord / WhatsApp / Slack") }
                TryRow { cmd: "hermes model"; note: I18n.tr("switch the default model") }
                TryRow { cmd: "hermes tools"; note: I18n.tr("enable toolsets") }
                TryRow { cmd: "prowl-agent overview"; note: I18n.tr("code intelligence on any repo") }
            }

            // ── SET UP + DASHBOARD: the controls ─────────────────────────────
            Column {
                width: parent.width
                spacing: Tokens.s4
                Head { kanji: "\u8d77\u52d5"; title: I18n.tr("GET STARTED") }

                Text {
                    width: parent.width
                    text: I18n.tr("Set up Hermes once: it installs the agent if you don't have it, wires it to the vault, and points your other coding agents at the same map. An existing Hermes install is left untouched.")
                    color: hx.inkDim; font.family: pg.fMono; font.pixelSize: 12; wrapMode: Text.WordWrap; lineHeight: 1.4
                }

                Row {
                    width: parent.width
                    spacing: Tokens.s3
                    PosterBtn {
                        label: pg.hermesConfigured ? I18n.tr("RE-RUN HERMES SETUP") : I18n.tr("SET UP HERMES AGENT")
                        primary: !pg.hermesConfigured
                        on: pg.installed
                        onAct: pg.runSetup()
                    }
                    PosterBtn {
                        label: I18n.tr("OPEN DASHBOARD")
                        primary: pg.hermesConfigured
                        on: pg.installed
                        onAct: pg.openDashboard()
                    }
                }

                // live setup console, mirrored from setup.json. a failed phase
                // brightens to ink rather than shouting in red.
                Text {
                    width: parent.width
                    visible: pg.setupPhase !== ""
                    text: "\u2192 " + pg.setupPhase + (pg.setupDetail !== "" ? ": " + pg.setupDetail : "")
                    color: pg.setupOk ? hx.inkDim : hx.ink
                    font.family: pg.fMono; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
            }

            // ── privacy footer ───────────────────────────────────────────────
            Item { width: parent.width; height: Tokens.s2 }
            Row {
                width: parent.width
                spacing: Tokens.s3
                Rectangle { width: 8; height: 8; radius: 4; color: hx.red; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    width: parent.width - Tokens.s3 - 8
                    text: I18n.tr("Everything runs on this machine. The daemon binds 127.0.0.1 only - nothing you do here leaves the box.")
                    color: hx.inkDim; font.family: pg.fMono; font.pixelSize: 11; wrapMode: Text.WordWrap
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
