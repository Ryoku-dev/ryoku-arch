pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "../Singletons"

// System > Updates (DESIGN.md section 8, SYSTEM). The Ryoku update channel as a
// paper-and-ink instrument: how far the install sits behind origin, the commits
// that would land (or the recent history it already runs), and a one-click
// update that runs `ryoku update` in a terminal and mirrors its progress here.
//
// This is a full-bleed page -- the shell hides its side panel and global action
// bar and keeps the rail -- so it draws its own head, content and action bar.
// The backend is carried verbatim from the old UpdatesPage/UpdateRow/
// UpdateStatus: the Updates singleton (wired to `ryoku status --json`), the
// run-state FileView `ryoku update` publishes, and the same execDetached calls.
// Only the presentation changed: no ember, no boxed banners -- ink on black,
// inversion for emphasis, the shared progress spec (a hairline track + a square
// ink fill) for advancement and the 600ms heartbeat dot for the indeterminate
// wait. Every colour, face, size, radius and duration reads from Tokens.
Item {
    id: pg

    property var hub
    // A full-bleed page owns the whole content region itself.
    readonly property bool fullBleed: true

    // ── automatic-check schedule (persisted in the hub's TOML) ──────────────
    property string interval: "daily"

    readonly property var intervalModel: [
        { "key": "off",    "label": I18n.tr("Off") },
        { "key": "hourly", "label": I18n.tr("Hourly") },
        { "key": "daily",  "label": I18n.tr("Daily") },
        { "key": "weekly", "label": I18n.tr("Weekly") }
    ]
    readonly property var intervalLabels: [I18n.tr("Off"), I18n.tr("Hourly"), I18n.tr("Daily"), I18n.tr("Weekly")]

    function intervalLabel(k) {
        for (var i = 0; i < pg.intervalModel.length; i++)
            if (pg.intervalModel[i].key === k)
                return pg.intervalModel[i].label;
        return I18n.tr("Daily");
    }
    function intervalKey(l) {
        for (var i = 0; i < pg.intervalModel.length; i++)
            if (pg.intervalModel[i].label === l)
                return pg.intervalModel[i].key;
        return "daily";
    }
    function intervalBlurb(k) {
        switch (k) {
        case "off":    return I18n.tr("manual only");
        case "hourly": return I18n.tr("every hour");
        case "weekly": return I18n.tr("once a week");
        default:       return I18n.tr("once a day");
        }
    }
    function setInterval(k) {
        if (pg.interval === k)
            return;
        pg.interval = k;
        saveInterval.command = ["ryoku-hub", "config", "set", "update_interval", k];
        saveInterval.running = true;
    }

    Process {
        id: loadInterval
        command: ["ryoku-hub", "config", "get", "update_interval"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var v = this.text.trim();
                if (v === "off" || v === "hourly" || v === "daily" || v === "weekly")
                    pg.interval = v;
            }
        }
    }

    Process { id: saveInterval }

    // re-check on the configured cadence.
    readonly property int intervalMs: {
        switch (pg.interval) {
        case "hourly": return 3600 * 1000;
        case "weekly": return 7 * 24 * 3600 * 1000;
        default:       return 24 * 3600 * 1000;
        }
    }

    Timer {
        interval: pg.intervalMs
        running: pg.interval !== "off"
        repeat: true
        onTriggered: Updates.check()
    }

    // ── live run state (published by `ryoku update`) ────────────────────────
    property string phase: "idle"   // idle | running | prompt | done | error
    property real progress: 0
    property string label: ""
    property int ownerPid: 0
    property var steps: []
    property var logLines: []
    property string errorMsg: ""
    property string snapshot: ""
    property string promptTitle: ""
    property string promptDetail: ""
    property var promptOptions: []
    readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-update.json"
    readonly property string answerPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-update-answer"

    // the fill fraction for the shared progress track. `ryoku update` may report
    // an explicit progress, but even when it only advances the stage list we can
    // read completion off the stages, so the track never sits dead at 0 while
    // work is plainly happening. done pins it full.
    readonly property real stepFraction: {
        if (pg.steps.length === 0)
            return 0;
        var d = 0;
        for (var i = 0; i < pg.steps.length; i++) {
            var s = pg.steps[i].state;
            if (s === "ok" || s === "skipped")
                d += 1;
            else if (s === "running")
                d += 0.5;
        }
        return d / pg.steps.length;
    }
    readonly property real fillFraction: pg.phase === "done"
        ? 1
        : Math.max(0, Math.min(1, Math.max(pg.progress, pg.stepFraction)))

    function checkOwner() {
        if (pg.phase !== "running" || pg.ownerPid < 2 || ownerProbe.running)
            return;
        ownerProbe.command = ["sh", "-c", "kill -0 \"$1\" 2>/dev/null", "sh", "" + pg.ownerPid];
        ownerProbe.running = true;
    }

    Process {
        id: ownerProbe
        onExited: (code) => {
            if (code !== 0 && pg.phase === "running")
                pg.dismiss();
        }
    }

    Timer {
        interval: 1200
        running: pg.phase === "running" && pg.ownerPid > 1
        repeat: true
        onTriggered: pg.checkOwner()
    }

    FileView {
        id: stateFile
        path: pg.statePath
        watchChanges: true
        atomicWrites: false
        onLoaded: pg.applyState(stateFile.text())
        onFileChanged: stateFile.reload()
        onLoadFailed: pg.phase = "idle"
    }

    function applyState(t) {
        var prev = pg.phase;
        try {
            var o = JSON.parse(t);
            pg.phase = o.phase || "idle";
            pg.progress = (typeof o.progress === "number") ? o.progress : 0;
            pg.label = o.label || "";
            pg.ownerPid = (typeof o.pid === "number") ? Math.floor(o.pid) : 0;
            pg.steps = o.steps || [];
            pg.logLines = o.log || [];
            pg.errorMsg = o.error || "";
            pg.snapshot = o.snapshot || "";
            if (pg.phase === "prompt" && o.prompt) {
                pg.promptTitle = o.prompt.title || "";
                pg.promptDetail = o.prompt.detail || "";
                pg.promptOptions = o.prompt.options || [];
            }
        } catch (e) {
            pg.phase = "idle";
            pg.progress = 0;
            pg.ownerPid = 0;
            pg.steps = [];
            pg.logLines = [];
            pg.errorMsg = "";
        }
        // settled back to idle = finished. refresh so the list clears.
        if (prev !== "idle" && pg.phase === "idle")
            Updates.check();
        pg.checkOwner();
    }

    // answer a prompt phase: write the choice to the back-channel `ryoku update`
    // is polling (positional args, so a quote in the label can't break out),
    // then optimistically resume the running view so the buttons clear.
    function answer(choice) {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", choice, pg.answerPath]);
        pg.phase = "running";
    }

    // guide restoring the pre-update snapshot after a failed run, in a terminal
    // (`ryoku rollback` prints the boot-menu restore steps and exits, so hold
    // the window for the user to read), then clear the error state.
    function rollback() {
        if (pg.snapshot === "")
            return;
        Spawn.run(["kitty", "-e", "sh", "-c", "ryoku rollback \"$1\"; printf '\\npress enter to close '; read -r _", "sh", pg.snapshot]);
        pg.dismiss();
    }

    // dismiss a finished/failed run: clear the run-state file so the page and
    // island return to idle.
    function dismiss() {
        Quickshell.execDetached(["sh", "-c", "printf '%s' '{\"phase\":\"idle\"}' > \"$1\"", "sh", pg.statePath]);
        pg.phase = "idle";
        Updates.check();
    }

    function startUpdate() {
        Spawn.run(["kitty", "-e", "sh", "-c", "exec ryoku update"]);
    }

    // idle list: incoming commits when behind, else the recent history the
    // installed version contains, so the page is informative either way.
    readonly property var sectionModel: Updates.available ? Updates.updates : Updates.recent
    readonly property string sectionLabel: Updates.available ? I18n.tr("INCOMING COMMITS") : I18n.tr("RECENT CHANGES")

    // ── head: eyebrow, Fraunces title, blurb (matches every settings page) ──
    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: Tokens.s6; anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s6
        spacing: Tokens.s2

        Row {
            spacing: Tokens.s2
            Rectangle {
                width: 16; height: 1; color: Tokens.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "力"; color: Tokens.ink; font.family: Tokens.jp
                font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: I18n.tr("SYSTEM"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            text: I18n.tr("Updates"); color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("The Ryoku update channel: how far this install sits behind origin, the commits that would land (or the recent history it already runs), and a one-click update that runs in a terminal and reports its progress here.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // marginalia dressing the head's empty right margin (eyebrow line). Ink only.
    Marginalia {
        anchors { right: parent.right; top: head.top }
        anchors.rightMargin: 150; anchors.topMargin: Tokens.s1  // clear the top-right chips
        kana: "更新"
        glyph: "wave"; glyph2: "column"
    }

    // ── idle: live status + the commit list, in one scroll container ─────────
    Flickable {
        id: idle
        visible: pg.phase === "idle"
        anchors {
            left: parent.left; right: parent.right
            top: head.bottom; bottom: footer.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6
            topMargin: Tokens.s5; bottomMargin: Tokens.s4
        }
        contentWidth: width
        contentHeight: idleCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Column {
            id: idleCol
            width: idle.width - Tokens.s3   // reserve a lane for the scroll rail
            spacing: Tokens.s5

            // ── status readout (left) + automatic-check schedule (right) ──
            Item {
                width: idleCol.width
                implicitHeight: Math.max(status.implicitHeight, autoCol.implicitHeight)

                // editorial status, not a boxed banner. a 2px rule encodes state
                // (an update is available), not style: bright when behind, faint
                // when current -- the ink translation of the old ember bar.
                Item {
                    id: status
                    anchors.left: parent.left
                    anchors.right: autoCol.left
                    anchors.rightMargin: Tokens.s6
                    anchors.top: parent.top
                    implicitHeight: statusCol.implicitHeight

                    Rectangle {
                        id: stateBar
                        anchors.left: parent.left; anchors.top: parent.top
                        width: 2; height: statusCol.implicitHeight
                        color: Tokens.ink
                        opacity: Updates.available ? 1.0 : 0.3
                        antialiasing: false
                    }

                    Column {
                        id: statusCol
                        anchors.left: stateBar.right; anchors.leftMargin: Tokens.s4
                        anchors.top: parent.top
                        spacing: Tokens.s2

                        Text {
                            text: Updates.available ? I18n.tr("UPDATE AVAILABLE") : I18n.tr("UP TO DATE")
                            color: Tokens.ink; font.family: Tokens.ui
                            font.pixelSize: Tokens.fMicro; font.weight: Font.Medium
                            font.letterSpacing: Tokens.trackMark
                        }

                        // the release line this box runs, and the next one when
                        // the channel has moved on ("Onogoro -> Amaterasu").
                        Text {
                            visible: Updates.currentName !== ""
                            text: "Ryoku " + Updates.currentName
                                  + (Updates.available && Updates.latestName !== "" && Updates.latestName !== Updates.currentName
                                     ? "  \u2192  " + Updates.latestName : "")
                            color: Tokens.ink; font.family: Tokens.display
                            font.pixelSize: Tokens.fHero; font.weight: Font.Medium
                        }

                        // installed -> latest bump. a version is file-truth, so mono.
                        Row {
                            spacing: Tokens.s3
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Updates.currentVersion
                                color: Tokens.inkDim; font.family: Tokens.mono
                                font.pixelSize: Tokens.fValue
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: Updates.available && Updates.latestVersion !== "" && Updates.latestVersion !== Updates.currentVersion
                                text: "\u2192"
                                color: Tokens.inkFaint; font.family: Tokens.ui
                                font.pixelSize: Tokens.fValue
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: Updates.available && Updates.latestVersion !== "" && Updates.latestVersion !== Updates.currentVersion
                                text: Updates.latestVersion
                                color: Tokens.ink; font.family: Tokens.mono
                                font.pixelSize: Tokens.fValue
                            }
                        }

                        Text {
                            text: Updates.available
                                ? (Updates.behind === 1
                                    ? I18n.tr("%1 commit behind  \u00b7  checked %2").arg(Updates.behind).arg(Updates.checkedAgo)
                                    : I18n.tr("%1 commits behind  \u00b7  checked %2").arg(Updates.behind).arg(Updates.checkedAgo))
                                : I18n.tr("on %1  \u00b7  checked %2").arg(Updates.branch).arg(Updates.checkedAgo)
                            color: Tokens.inkMuted; font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                        }
                    }
                }

                // automatic checks: a Seg over the cadence + a derived blurb.
                Column {
                    id: autoCol
                    anchors.right: parent.right; anchors.top: parent.top
                    anchors.topMargin: 2
                    spacing: Tokens.s2

                    Text {
                        anchors.right: parent.right
                        text: I18n.tr("AUTOMATIC CHECKS")
                        color: Tokens.inkMuted; font.family: Tokens.ui
                        font.pixelSize: Tokens.fMicro; font.weight: Font.Medium
                        font.letterSpacing: Tokens.trackMark
                    }
                    Seg {
                        anchors.right: parent.right
                        options: pg.intervalLabels
                        current: pg.intervalLabel(pg.interval)
                        onChose: (l) => pg.setInterval(pg.intervalKey(l))
                    }
                    Text {
                        anchors.right: parent.right
                        text: pg.intervalBlurb(pg.interval)
                        color: Tokens.inkMuted; font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                    }
                }
            }

            // ── the commit list ──
            Column {
                width: idleCol.width
                spacing: 0

                // section head: dot + caps + hairline leader. content flips with
                // availability (incoming vs recent).
                Item {
                    width: parent.width
                    height: 30

                    Row {
                        id: secLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s2
                        Rectangle {
                            width: 4; height: 4; color: Tokens.ink
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: pg.sectionLabel; color: Tokens.ink
                            font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                            font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Rectangle {
                        anchors.left: secLabel.right; anchors.leftMargin: Tokens.s3
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1; color: Tokens.lineSoft
                    }
                }

                // one incoming commit: a node on a vertical git rail, the commit
                // subject, and a right-aligned version pair. mirrors
                // `git log <channel>..origin/<channel>`.
                Repeater {
                    model: pg.sectionModel

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index

                        readonly property real railX: 13
                        readonly property real nodeY: height / 2
                        readonly property bool isFirst: index === 0
                        readonly property bool isLast: index === pg.sectionModel.length - 1
                        readonly property string fromVersion: row.modelData.old || ""
                        readonly property string toVersion: row.modelData.new || ""

                        width: idleCol.width
                        height: 44

                        // upper rail, hidden on the first node.
                        Rectangle {
                            x: row.railX; width: 1; y: 0
                            height: row.nodeY - 6
                            color: Tokens.line; visible: !row.isFirst
                        }
                        // lower rail, hidden on the last node.
                        Rectangle {
                            x: row.railX; width: 1; y: row.nodeY + 6
                            height: row.height - (row.nodeY + 6)
                            color: Tokens.line; visible: !row.isLast
                        }
                        // the node: a hollow ink ring (a true circle is allowed).
                        Rectangle {
                            x: row.railX - 4; y: row.nodeY - 4
                            width: 8; height: 8; radius: 4
                            color: "transparent"
                            border.width: Tokens.border; border.color: Tokens.inkDim
                        }

                        // hover highlight (a cell under the pointer takes tint5).
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 28; anchors.topMargin: 3; anchors.bottomMargin: 3
                            radius: Tokens.radius
                            color: rowHover.hovered ? Tokens.tint5 : "transparent"
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                        }

                        Text {
                            id: subj
                            anchors.left: parent.left; anchors.leftMargin: 40
                            anchors.right: ver.left; anchors.rightMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.name
                            color: rowHover.hovered ? Tokens.ink : Tokens.inkDim
                            font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                        }
                        Text {
                            id: ver
                            anchors.right: parent.right; anchors.rightMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.fromVersion !== "" ? (row.fromVersion + "  \u2192  " + row.toVersion) : row.toVersion
                            color: Tokens.inkFaint; font.family: Tokens.mono
                            font.pixelSize: Tokens.fTiny
                        }

                        HoverHandler { id: rowHover }
                    }
                }

                Text {
                    visible: pg.sectionModel.length === 0
                    text: Updates.available
                        ? I18n.tr("No commit details available.")
                        : I18n.tr("You're up to date. Recent changes will appear here once loaded.")
                    color: Tokens.inkFaint; font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    topPadding: Tokens.s2
                    leftPadding: 40
                }
            }

            // ── system packages (pacman -Syu, check-only) ──
            Column {
                width: idleCol.width
                spacing: 0
                visible: Updates.packages.length > 0

                Item {
                    width: parent.width
                    height: 30
                    Row {
                        id: pkgLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s2
                        Rectangle {
                            width: 4; height: 4; color: Tokens.ink
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: I18n.tr("SYSTEM PACKAGES") + "  " + Updates.packages.length
                            color: Tokens.ink; font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                            font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Rectangle {
                        anchors.left: pkgLabel.right; anchors.leftMargin: Tokens.s3
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        height: 1; color: Tokens.lineSoft
                    }
                }

                // These come from Arch or CachyOS, not from Ryoku: `ryoku update`
                // does not move them, so the section has to name what does.
                Text {
                    width: idleCol.width
                    text: I18n.tr("From your distribution, kernel included. Take them with:  sudo pacman -Syu")
                    color: Tokens.inkFaint
                    font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
                    wrapMode: Text.WordWrap
                    bottomPadding: Tokens.s2
                }

                Repeater {
                    model: Updates.packages
                    delegate: Item {
                        id: prow
                        required property var modelData
                        width: idleCol.width
                        height: 34

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 3; anchors.bottomMargin: 3
                            radius: Tokens.radius
                            color: pkgHover.hovered ? Tokens.tint5 : "transparent"
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: Tokens.s3
                            anchors.right: pver.left; anchors.rightMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            text: prow.modelData.name
                            color: pkgHover.hovered ? Tokens.ink : Tokens.inkDim
                            font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; font.weight: Font.Medium
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                        }
                        Text {
                            id: pver
                            anchors.right: parent.right; anchors.rightMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            text: (prow.modelData.old || "") !== ""
                                ? (prow.modelData.old + "  \u2192  " + prow.modelData.new)
                                : (prow.modelData.new || "")
                            color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
                        }
                        HoverHandler { id: pkgHover }
                    }
                }
            }

            // section face: fills the quiet idle column (a short recent-history
            // list leaves a long void), per DESIGN.md section 12. Ink-only poster,
            // no control; it flows after the list so a long incoming set scrolls.
            Decor {
                width: idleCol.width
                height: Tokens.cellH * 2 + Tokens.s5
                title: "更新"; sub: "アップデート"
                tate: "常に最新へ"
                caption: I18n.tr("Ryoku tracks its channel; one command snapshots, pulls, and reloads.")
                readout: ["CHANNEL|main", "METHOD|ryoku update", "SAFETY|snapshot first", "SCOPE|whole system"]
                code: "SYS-07"; seal: "更"; boxId: "updates.channel"; seed: 3; ditherFreq: 1.0
            }
        }
    }

    // ── running / done: the ordered stages, the shared progress track and the
    // streamed log. running and done share one view (the check + "complete"
    // headline is the only difference). ──
    Item {
        visible: pg.phase === "running" || pg.phase === "done"
        anchors {
            left: parent.left; right: parent.right
            top: head.bottom; bottom: footer.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6
        }

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width, 560)
            spacing: Tokens.s5

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.s2

                // heartbeat while running (the indeterminate beat), a check on
                // done. 600ms each way (DESIGN.md section 5), a heartbeat not an
                // alarm -- and the only perpetual animation on the sheet.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pg.phase === "running"
                    width: 8; height: 8; radius: 4
                    color: Tokens.ink
                    SequentialAnimation on opacity {
                        running: pg.phase === "running"
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600 }
                        NumberAnimation { to: 1.0; duration: 600 }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pg.phase === "done"
                    text: "\u2713"
                    color: Tokens.ink; font.family: Tokens.ui
                    font.pixelSize: Tokens.fRow; font.weight: Font.Bold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pg.phase === "done" ? I18n.tr("Update complete")
                        : (pg.label !== "" ? I18n.tr(pg.label) + "\u2026" : I18n.tr("Applying updates\u2026"))
                    color: Tokens.ink; font.family: Tokens.ui
                    font.pixelSize: Tokens.fRow; font.weight: Font.DemiBold
                }
            }

            // the shared progress spec: a hairline track, a square ink fill, a
            // percent read-out. reflects the run's real advancement.
            Item {
                width: parent.width
                height: 12

                Rectangle {
                    anchors.left: parent.left; anchors.right: pct.left
                    anchors.rightMargin: Tokens.s2
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    color: Tokens.lineSoft
                    antialiasing: false

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * pg.fillFraction
                        color: Tokens.ink
                        antialiasing: false
                        Behavior on width { NumberAnimation { duration: Tokens.flap } }
                    }
                }
                Text {
                    id: pct
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(pg.fillFraction * 100) + "%"
                    color: Tokens.ink; font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
                }
            }

            // per-stage detail: one square ink fill per stage, keyed to the
            // state the CLI reports. the running stage pulses on the heartbeat.
            Row {
                id: stageRow
                width: parent.width
                spacing: Tokens.s2

                Repeater {
                    model: pg.steps

                    delegate: Rectangle {
                        required property var modelData
                        width: (stageRow.width - (pg.steps.length - 1) * Tokens.s2) / Math.max(1, pg.steps.length)
                        height: 5
                        radius: 0
                        antialiasing: false
                        color: Tokens.ink
                        opacity: {
                            switch (modelData.state) {
                            case "running": return 1.0;
                            case "ok": return 0.9;
                            case "failed": return 1.0;
                            case "skipped": return 0.35;
                            default: return 0.18;
                            }
                        }
                        SequentialAnimation on opacity {
                            running: modelData.state === "running"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }
                }
            }

            // the update's own narrative, streamed from the run-state log ring.
            Column {
                width: parent.width
                spacing: Tokens.s1
                visible: pg.logLines.length > 0

                Repeater {
                    model: pg.logLines

                    delegate: Text {
                        required property var modelData
                        required property int index
                        width: stageRow.width
                        text: modelData
                        color: index === pg.logLines.length - 1 ? Tokens.inkMuted : Tokens.inkFaint
                        font.family: Tokens.mono; font.pixelSize: Tokens.fMicro
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── error: the update stopped; a bone FAILED tag (an error is inverted text
    // and the word, DESIGN.md section 1) and a one-click rollback. ──
    Item {
        visible: pg.phase === "error"
        anchors {
            left: parent.left; right: parent.right
            top: head.bottom; bottom: footer.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6
        }

        Row {
            anchors.centerIn: parent
            width: Math.min(parent.width, 560)
            spacing: Tokens.s4

            Rectangle {
                width: 2; height: errCol.implicitHeight
                color: Tokens.ink; antialiasing: false
            }

            Column {
                id: errCol
                width: parent.width - 2 - Tokens.s4
                spacing: Tokens.s3

                Rectangle {
                    width: failTag.width + Tokens.s2 * 2
                    height: 18
                    radius: Tokens.radius
                    color: Tokens.bone
                    Text {
                        id: failTag
                        anchors.centerIn: parent
                        text: I18n.tr("FAILED")
                        color: Tokens.inkOnBone; font.family: Tokens.ui
                        font.pixelSize: Tokens.fTiny; font.weight: Font.Medium
                        font.letterSpacing: Tokens.trackLabel
                    }
                }

                Text {
                    width: parent.width
                    text: pg.label !== "" ? I18n.tr("Update failed while %1").arg(pg.label.toLowerCase()) : I18n.tr("Update failed")
                    color: Tokens.ink; font.family: Tokens.ui
                    font.pixelSize: Tokens.fValue; font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    visible: pg.errorMsg !== ""
                    text: pg.errorMsg
                    color: Tokens.inkMuted; font.family: Tokens.mono
                    font.pixelSize: Tokens.fSmall
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    text: pg.snapshot !== ""
                        ? I18n.tr("The system was snapshotted before the update. Roll back to undo every change.")
                        : I18n.tr("Check the terminal for details, then try again.")
                    color: Tokens.inkFaint; font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                Item { width: 1; height: Tokens.s1 }

                Row {
                    spacing: Tokens.s3
                    Btn {
                        visible: pg.snapshot !== ""
                        text: I18n.tr("ROLL BACK")
                        primary: true
                        onAct: pg.rollback()
                    }
                    Btn {
                        text: I18n.tr("DISMISS")
                        onAct: pg.dismiss()
                    }
                }
            }
        }
    }

    // ── prompt: the editorial question `ryoku update` is blocked on -- an ink
    // rule + title + detail, with the option stamps `ryoku update` offers. ──
    Item {
        visible: pg.phase === "prompt"
        anchors {
            left: parent.left; right: parent.right
            top: head.bottom; bottom: footer.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6
        }

        Row {
            anchors.centerIn: parent
            width: Math.min(parent.width, 540)
            spacing: Tokens.s4

            Rectangle {
                width: 2; height: promptCol.implicitHeight
                color: Tokens.ink; antialiasing: false
            }

            Column {
                id: promptCol
                width: parent.width - 2 - Tokens.s4
                spacing: Tokens.s4

                Text {
                    width: parent.width
                    text: pg.promptTitle
                    color: Tokens.ink; font.family: Tokens.ui
                    font.pixelSize: Tokens.fValue; font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: pg.promptDetail
                    color: Tokens.inkMuted; font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                Item { width: 1; height: Tokens.s1 }

                // the option stamps: arbitrary strings from the CLI, uppercased.
                // the first is the armed primary (inverts to bone), the rest are
                // ghosts -- the beta18 button carries both.
                Row {
                    spacing: Tokens.s3
                    Repeater {
                        model: pg.promptOptions
                        delegate: Btn {
                            required property var modelData
                            required property int index
                            text: ("" + modelData).toUpperCase()
                            primary: index === 0
                            onAct: pg.answer(modelData)
                        }
                    }
                }
            }
        }
    }

    // ── action bar, pinned at the bottom (60 tall, one hairline) ─────────────
    Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 60

        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: 1; color: Tokens.line
        }

        // marginalia in the footer's dead centre, between status and verbs.
        Marginalia {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            kana: "更新"
            glyph: "wave"; glyph2: "column"
        }

        Text {
            anchors.left: parent.left; anchors.leftMargin: Tokens.s6
            anchors.verticalCenter: parent.verticalCenter
            text: pg.phase === "running" ? I18n.tr("Update running")
                : pg.phase === "error" ? I18n.tr("Update failed")
                : pg.phase === "done" ? I18n.tr("Update complete")
                : (Updates.branch + (Updates.currentVersion !== "" ? ("  \u00b7  " + Updates.currentVersion) : ""))
            color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fMicro
        }

        Row {
            anchors.right: parent.right; anchors.rightMargin: Tokens.s6
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s3
            visible: pg.phase === "idle"

            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("CHECK AGAIN")
                onAct: Updates.check()
            }
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                visible: Updates.available
                text: I18n.tr("UPDATE NOW")
                primary: true
                onAct: pg.startUpdate()
            }
        }
    }
}
