pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Singletons"
import Ryoku.Ui.Singletons

// Quick-ask body panel for the "\" prefix: a terse question to the Rashin
// agent (hermes), answered inline. `ryoku-rashin ask` streams marker lines;
// while the agent works a pulsing dot names the step (tool title / thinking /
// writing) and two live options sit under it: CONTINUE IN DASHBOARD (watch the
// same turn there while it keeps running) and CANCEL. The finished answer is
// selectable text over action chips: COPY, every entity the daemon detected
// (files edit in nvim, folders open, URLs browse, commands and colors copy),
// then DASHBOARD. "\resume" lists recent asks and recalls a cached answer with
// its chips intact, no model call. Chips and the resume list walk with the
// arrow keys and fire with ENTER.
Item {
    id: root

    property real s: 1
    property string question: ""

    // idle -> working -> done | failed ; resume is a separate list mode
    property string phase: "idle"
    property bool resumeMode: false
    property var recent: []      // [{q,a,at,images,actions}]

    property string working: ""
    property string answerText: ""
    property var answerImages: []
    property var answerActions: []
    property string errorText: ""
    property bool permPending: false
    property bool fromHistory: false
    property string askedQuestion: ""
    property int selectedChip: 0
    property int selectedRecent: 0
    property string flash: ""

    readonly property bool busy: phase === "working"
    readonly property bool answerCurrent: phase === "done" && (fromHistory || question.trim() === askedQuestion)

    // Working-phase actions and answer chips share the selection model.
    readonly property var workChips: [
        { kind: "dash", value: "", label: I18n.tr("CONTINUE IN DASHBOARD") },
        { kind: "cancel", value: "", label: I18n.tr("CANCEL") }
    ]
    readonly property var chips: {
        if (busy)
            return workChips;
        if (permPending)
            return [{ kind: "dash", value: "", label: I18n.tr("APPROVE IN DASHBOARD") }];
        if (phase !== "done")
            return [];
        var c = [{ kind: "copy", value: answerText, label: I18n.tr("COPY") }];
        for (var i = 0; i < answerActions.length; i++)
            c.push(answerActions[i]);
        c.push({ kind: "dash", value: "", label: I18n.tr("DASHBOARD") });
        return c;
    }

    signal finished()

    implicitHeight: col.implicitHeight

    function reset() {
        askProc.running = false;
        phase = "idle";
        resumeMode = false;
        recent = [];
        working = "";
        answerText = "";
        answerImages = [];
        answerActions = [];
        errorText = "";
        permPending = false;
        fromHistory = false;
        askedQuestion = "";
        selectedChip = 0;
        selectedRecent = 0;
        flash = "";
    }

    // run() decides: "\resume" (or "\resume <text>") opens the recall list;
    // anything else asks.
    function run() {
        if (busy)
            return;
        var q = question.trim();
        if (q === "resume" || q === "recent") {
            openResume();
            return;
        }
        if (q.length === 0)
            return;
        answerText = "";
        answerImages = [];
        answerActions = [];
        errorText = "";
        permPending = false;
        fromHistory = false;
        flash = "";
        selectedChip = 0;
        resumeMode = false;
        askedQuestion = q;
        working = I18n.tr("waking the needle");
        phase = "working";
        askProc.command = ["ryoku-rashin", "ask", q];
        askProc.running = true;
    }

    function openResume() {
        resumeMode = true;
        phase = "idle";
        selectedRecent = 0;
        recentProc.command = ["ryoku-rashin", "ask", "--recent"];
        recentProc.running = true;
    }

    // recall a stored ask into the normal answer view, chips and all
    function loadRecent(rec) {
        answerText = String(rec.a || "");
        answerImages = rec.images || [];
        answerActions = rec.actions || [];
        askedQuestion = String(rec.q || "");
        fromHistory = true;
        resumeMode = false;
        permPending = false;
        selectedChip = 0;
        phase = "done";
    }

    function move(d) {
        if (resumeMode) {
            if (recent.length === 0)
                return;
            selectedRecent = Math.max(0, Math.min(recent.length - 1, selectedRecent + d));
            return;
        }
        if (chips.length === 0)
            return;
        selectedChip = Math.max(0, Math.min(chips.length - 1, selectedChip + d));
    }

    function activate() {
        if (resumeMode) {
            if (recent[selectedRecent])
                loadRecent(recent[selectedRecent]);
            return;
        }
        var chip = chips[selectedChip];
        if (chip)
            root.fire(chip);
    }

    function cancel() {
        askProc.running = false;
        Quickshell.execDetached(["ryoku-rashin", "ask", "--cancel"]);
    }

    function fire(chip) {
        switch (chip.kind) {
        case "copy":
        case "cmd":
        case "color":
            Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", String(chip.value)]);
            root.flash = chip.kind + "\u0000" + chip.value;
            flashTimer.restart();
            return;
        case "cancel":
            root.cancel();
            root.finished();
            return;
        case "file":
            Spawn.run(["kitty", "-e", "nvim", String(chip.value)]);
            break;
        case "dir":
        case "url":
            Spawn.run(["xdg-open", String(chip.value)]);
            break;
        case "dash":
            // Leave the turn running on the daemon; just go watch it.
            Spawn.run(["xdg-open", "http://127.0.0.1:3600/#/chat"]);
            break;
        }
        root.finished();
    }

    function chipCaption(chip) {
        if (root.flash === chip.kind + "\u0000" + chip.value)
            return I18n.tr("COPIED");
        switch (chip.kind) {
        case "file": return "nvim " + chip.label;
        case "dir": return I18n.tr("open %1").arg(chip.label);
        case "url": return chip.label;
        case "cmd": return "$ " + chip.label;
        case "color": return chip.label;
        default: return chip.label;
        }
    }

    Timer {
        id: flashTimer
        interval: 1400
        onTriggered: root.flash = ""
    }

    Process {
        id: recentProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.recent = JSON.parse(this.text) || [];
                } catch (e) {
                    root.recent = [];
                }
            }
        }
    }

    Process {
        id: askProc
        stdout: SplitParser {
            onRead: (line) => {
                line = String(line);
                if (line.indexOf("@working ") === 0) {
                    root.working = line.slice(9);
                } else if (line.indexOf("@perm ") === 0) {
                    root.permPending = true;
                    root.working = I18n.tr("waiting for approval: %1").arg(line.slice(6));
                } else if (line.indexOf("@answer ") === 0) {
                    try {
                        var a = JSON.parse(line.slice(8));
                        root.answerText = String(a.text || "");
                        root.answerImages = a.images || [];
                        root.answerActions = a.actions || [];
                        root.fromHistory = false;
                        root.phase = "done";
                        root.selectedChip = 0;
                    } catch (e) {
                        root.errorText = I18n.tr("unreadable answer");
                        root.phase = "failed";
                    }
                } else if (line.indexOf("@error ") === 0) {
                    root.errorText = line.slice(7);
                    root.phase = "failed";
                }
            }
        }
        onExited: (code) => {
            if (root.phase === "working" && !root.permPending) {
                root.errorText = code === 0 ? I18n.tr("no answer") : I18n.tr("ask failed");
                root.phase = "failed";
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 8 * root.s

        Text {
            width: parent.width
            text: root.resumeMode ? I18n.tr("RASHIN \u00b7 RECENT ASKS") : I18n.tr("RASHIN")
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: Metrics.fontEyebrow * root.s
            font.letterSpacing: 1
        }

        // idle hint (not in resume mode)
        Text {
            width: parent.width
            visible: root.phase === "idle" && !root.resumeMode
            text: root.question.trim().length === 0
                ? I18n.tr("Ask the needle anything. ENTER sends; \\resume recalls recent asks.")
                : I18n.tr("ENTER to ask: %1").arg(root.question.trim())
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: Metrics.fontSubtitle * root.s
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // resume list
        Column {
            width: parent.width
            visible: root.resumeMode
            spacing: 3 * root.s

            Text {
                visible: root.recent.length === 0
                text: I18n.tr("no recent asks yet")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Metrics.fontSubtitle * root.s
            }

            Repeater {
                model: root.resumeMode ? root.recent : []
                delegate: Rectangle {
                    id: recRow
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: recCol.implicitHeight + 10 * root.s
                    radius: Theme.radius
                    color: index === root.selectedRecent ? Theme.tileBg : "transparent"

                    Column {
                        id: recCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10 * root.s
                        anchors.rightMargin: 10 * root.s
                        spacing: 1 * root.s

                        Text {
                            width: parent.width
                            text: String(recRow.modelData.q || "")
                            color: recRow.index === root.selectedRecent ? Theme.bright : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: Metrics.fontSubtitle * root.s
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: String(recRow.modelData.a || "").replace(/\n/g, " ")
                            color: Theme.faint
                            font.family: Theme.mono
                            font.pixelSize: Metrics.fontEyebrow * root.s
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.loadRecent(recRow.modelData) }
                }
            }
        }

        // working strip: pulsing dot + live activity
        Row {
            visible: root.busy
            spacing: 8 * root.s

            Rectangle {
                width: 8 * root.s
                height: 8 * root.s
                radius: width / 2
                color: root.permPending ? Theme.verm : Theme.flameGlow
                anchors.verticalCenter: parent.verticalCenter

                SequentialAnimation on opacity {
                    running: root.busy
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 550; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 550; easing.type: Easing.InOutQuad }
                }
            }

            Text {
                text: root.working
                color: Theme.subtle
                font.family: Theme.mono
                font.pixelSize: Metrics.fontSubtitle * root.s
                font.letterSpacing: 1
                elide: Text.ElideRight
            }
        }

        // answer: selectable
        TextEdit {
            width: parent.width
            visible: root.phase === "done"
            text: root.answerText
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: Metrics.fontSubtitle * root.s
            wrapMode: TextEdit.Wrap
            readOnly: true
            selectByMouse: true
            selectionColor: Theme.vermDimDeep
            selectedTextColor: Theme.bright
        }

        Text {
            visible: root.phase === "done" && root.fromHistory
            text: I18n.tr("from history")
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: Metrics.fontEyebrow * root.s
        }

        // image results preview inline; click opens
        Row {
            visible: root.phase === "done" && root.answerImages.length > 0
            spacing: 8 * root.s

            Repeater {
                model: root.answerImages
                delegate: Image {
                    id: thumb
                    required property string modelData
                    source: "file://" + modelData
                    width: 96 * root.s
                    height: 96 * root.s
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            Spawn.run(["xdg-open", thumb.modelData]);
                            root.finished();
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.phase === "failed"
            text: root.errorText
            color: Theme.verm
            font.family: Theme.mono
            font.pixelSize: Metrics.fontSubtitle * root.s
            wrapMode: Text.WordWrap
            maximumLineCount: 3
        }

        // action chips (working actions or answer chips)
        Flow {
            width: parent.width
            visible: root.chips.length > 0 && !root.resumeMode
            spacing: 6 * root.s

            Repeater {
                model: root.chips
                delegate: Rectangle {
                    id: chipBox
                    required property var modelData
                    required property int index

                    readonly property bool current: index === root.selectedChip
                    readonly property bool danger: modelData.kind === "cancel"
                    width: chipRow.implicitWidth + 18 * root.s
                    height: chipRow.implicitHeight + 10 * root.s
                    radius: Theme.radius
                    color: current || chipHover.hovered ? (danger ? Theme.vermDeep : Theme.verm) : "transparent"
                    border.color: current || chipHover.hovered ? (danger ? Theme.vermDeep : Theme.verm) : Theme.border
                    border.width: 1

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6 * root.s

                        Rectangle {
                            visible: chipBox.modelData.kind === "color"
                            width: 10 * root.s
                            height: 10 * root.s
                            radius: Theme.radius
                            color: String(chipBox.modelData.value)
                            border.color: Theme.hair
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.chipCaption(chipBox.modelData)
                            color: chipBox.current || chipHover.hovered ? Theme.cardTop : Theme.subtle
                            font.family: Theme.mono
                            font.pixelSize: Metrics.fontEyebrow * root.s
                            font.letterSpacing: 1
                        }
                    }

                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.fire(chipBox.modelData) }
                }
            }
        }

        // key hints
        Text {
            visible: (root.chips.length > 0 && !root.permPending) || root.resumeMode
            text: root.resumeMode
                ? I18n.tr("\u2191\u2193 pick \u00b7 ENTER recall \u00b7 ESC back")
                : (root.busy
                    ? I18n.tr("\u2191\u2193 pick \u00b7 ENTER fires \u00b7 ESC cancels")
                    : I18n.tr("\u2191\u2193 walk chips \u00b7 ENTER fires \u00b7 type to re-ask \u00b7 ESC dismisses"))
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: Metrics.fontEyebrow * root.s
        }
    }
}
