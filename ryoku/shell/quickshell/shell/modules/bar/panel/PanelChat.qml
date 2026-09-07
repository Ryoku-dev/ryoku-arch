pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// Chat: the Super+S sidebar's view onto the Needle singleton (which owns the
// thread and the running turn). Renders streamed Markdown over a growing input;
// images attach via the picker, Ctrl+V, or drop.
Item {
    id: root

    property real s: 1
    property bool open: false

    // Paths queued to send with the next message (max 3, like the dashboard).
    property var pendingImages: []
    readonly property int maxImages: 3

    // Slash-command palette: the session's built-in commands (/tools, /steer,
    // /compress, ...) fetched from the daemon; typing "/" filters them.
    property var commands: []
    property var skills: []
    property int paletteIdx: 0
    property bool paletteDismissed: false
    readonly property bool slashMode: input.text.length > 0 && input.text.charAt(0) === "/" && input.text.indexOf(" ") === -1 && !root.paletteDismissed
    readonly property var slashMatches: {
        if (!root.slashMode)
            return [];
        var pre = input.text.slice(1).toLowerCase();
        var cmds = (root.commands || []).map(c => ({ name: String(c.name), description: String(c.description || ""), skill: false }));
        if (pre === "")
            return cmds;
        var sk = (root.skills || []).map(s => ({ name: String(s.name), description: String(s.description || ""), skill: true }));
        return cmds.concat(sk).filter(e => e.name.toLowerCase().indexOf(pre) === 0);
    }
    readonly property bool paletteOpen: root.slashMode && root.slashMatches.length > 0
    function acceptSlash() {
        if (root.slashMatches.length === 0)
            return;
        var idx = Math.max(0, Math.min(root.paletteIdx, root.slashMatches.length - 1));
        input.text = "/" + root.slashMatches[idx].name + " ";
        input.cursorPosition = input.text.length;
    }

    implicitHeight: 648 * root.s

    readonly property real minInputH: 20 * root.s
    readonly property real maxInputH: 132 * root.s

    function scrollEnd() { Qt.callLater(list.positionViewAtEnd); }

    function isImagePath(p) {
        return /\.(png|jpe?g|webp|gif|bmp|avif|svg)$/i.test(String(p));
    }
    function addImage(p) {
        var path = String(p).replace(/^file:\/\//, "");
        if (path.length === 0 || root.pendingImages.length >= root.maxImages)
            return;
        if (root.pendingImages.indexOf(path) >= 0)
            return;
        root.pendingImages = root.pendingImages.concat([path]);
    }
    function removeImage(i) {
        root.pendingImages = root.pendingImages.filter((_, idx) => idx !== i);
    }
    property bool modelMenuOpen: false
    property bool historyDrawerOpen: false
    function shortModel(id) {
        var t = String(id);
        var c = t.lastIndexOf(":");
        return c >= 0 ? t.slice(c + 1) : t;
    }
    // Markdown collapses single newlines, so line-structured output (a /tools
    // list, terse notes) renders as one run-on paragraph. Turn each non-blank
    // newline into a hard break so the line structure survives; blank-line
    // paragraph breaks stay, and fenced code is already split out by msgBlocks.
    function hardBreaks(s) {
        return String(s).replace(/([^\n])\n(?!\n)/g, "$1  \n");
    }
    // Split an agent answer into text and fenced-code segments so code renders
    // in a wrapped, copyable box instead of overflowing (mirrors iNiR).
    function msgBlocks(md) {
        if (!md) return [];
        var re = /```(\w+)?\n([\s\S]*?)```/g;
        var out = [];
        var last = 0, m;
        function pushText(t) { if (t && t.trim().length) out.push({ type: "text", content: t }); }
        while ((m = re.exec(md)) !== null) {
            if (m.index > last) pushText(md.slice(last, m.index));
            if (m[2] && m[2].trim().length)
                out.push({ type: "code", lang: m[1] || "", content: m[2].replace(/\n+$/, "") });
            last = re.lastIndex;
        }
        if (last < md.length) {
            var tail = md.slice(last);
            var cs = tail.indexOf("```");
            if (cs !== -1) {
                pushText(tail.slice(0, cs));
                var after = tail.slice(cs + 3);
                var lm = after.match(/^(\w+)?\n/);
                var lang = "", cstart = 0;
                if (lm) { lang = lm[1] || ""; cstart = lm[0].length; }
                var code = after.slice(cstart);
                if (code.trim().length) out.push({ type: "code", lang: lang, content: code.replace(/\n+$/, "") });
            } else {
                pushText(tail);
            }
        }
        if (out.length === 0) pushText(md);
        return out;
    }

    function submit() {
        var q = input.text.trim();
        if ((q.length === 0 && root.pendingImages.length === 0) || Needle.busy)
            return;
        Needle.send(q, root.pendingImages);
        input.text = "";
        root.pendingImages = [];
    }

    // Fetch the session's slash commands (available once a session exists).
    Process {
        id: cmdsProc
        command: ["ryoku-rashin", "chat", "--commands"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                try {
                    var f = JSON.parse(String(line));
                    if (f && f.type === "commands" && f.commands)
                        root.commands = f.commands;
                } catch (e) {}
            }
        }
    }
    Process {
        id: skillsProc
        command: ["ryoku-rashin", "chat", "--skills"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                try {
                    var f = JSON.parse(String(line));
                    if (f && f.type === "skills" && f.skills)
                        root.skills = f.skills;
                } catch (e) {}
            }
        }
    }
    function loadCommands() {
        if (!cmdsProc.running)
            cmdsProc.running = true;
        if (!skillsProc.running)
            skillsProc.running = true;
    }

    Component.onCompleted: {
        Needle.noteOpened();
        root.loadCommands();
        Qt.callLater(input.forceActiveFocus);
        root.scrollEnd();
    }
    Component.onDestruction: Needle.noteClosed()
    onOpenChanged: {
        if (root.open) {
            Qt.callLater(input.forceActiveFocus);
            if (root.commands.length === 0)
                root.loadCommands();
        }
    }

    Connections {
        target: Needle
        function onTouched() { root.scrollEnd(); }
    }

    // File picker (paperclip): zenity returns the chosen path on stdout.
    Process {
        id: pickProc
        command: ["zenity", "--file-selection", "--title=Attach an image",
            "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.avif",
            "--file-filter=All files | *"]
        stdout: StdioCollector {
            id: pickOut
            onStreamFinished: {
                var p = ("" + pickOut.text).trim();
                if (p.length > 0 && root.isImagePath(p))
                    root.addImage(p);
            }
        }
    }

    // Ctrl+V image: if the clipboard holds an image, save it to a temp file and
    // attach it. Text paste is left to the TextArea (this prints nothing then).
    Process {
        id: pasteImgProc
        command: ["sh", "-c",
            't=$(wl-paste --list-types 2>/dev/null | grep -m1 -E "^image/"); [ -z "$t" ] && exit 0; ' +
            'd="${XDG_RUNTIME_DIR:-/tmp}/ryoku-chat"; mkdir -p "$d"; ext=${t#image/}; ' +
            'case "$ext" in jpeg) ext=jpg;; svg+xml) ext=svg;; esac; ' +
            'f="$d/paste-$(date +%s%N).$ext"; wl-paste --type "$t" > "$f" 2>/dev/null && printf "%s" "$f"']
        stdout: StdioCollector {
            id: pasteOut
            onStreamFinished: {
                var p = ("" + pasteOut.text).trim();
                if (p.length > 0)
                    root.addImage(p);
            }
        }
    }

    // Drop image files anywhere on the panel to attach them.
    DropArea {
        anchors.fill: parent
        onDropped: (drop) => {
            if (!drop.hasUrls)
                return;
            for (var i = 0; i < drop.urls.length; i++) {
                if (root.isImagePath(drop.urls[i]))
                    root.addImage(drop.urls[i]);
            }
            drop.accept();
        }
    }

    // ── header ──
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 14 * root.s
        height: 20 * root.s

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("RASHIN")
            color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
            font.family: Theme.mono
            font.pixelSize: 9 * root.s
            font.letterSpacing: 1.5
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.s
            Rectangle {
                id: modelChip
                anchors.verticalCenter: parent.verticalCenter
                height: 18 * root.s
                width: chipRow.implicitWidth + 12 * root.s
                radius: 9 * root.s
                visible: Needle.currentModel.length > 0
                color: chipArea.containsMouse || root.modelMenuOpen
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                    : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 3 * root.s
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.shortModel(Needle.currentModel)
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                        font.family: Theme.mono
                        font.pixelSize: 8 * root.s
                    }
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "expand_more"
                        font.pixelSize: 10 * root.s
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                    }
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.modelMenuOpen = !root.modelMenuOpen
                }
            }

            Repeater {
                model: [
                    { icon: "history", act: "history" },
                    { icon: "add_comment", act: "new" },
                    { icon: "open_in_new", act: "dash" }
                ]
                delegate: Rectangle {
                    id: hbtn
                    required property var modelData
                    width: 24 * root.s
                    height: 24 * root.s
                    radius: width / 2
                    color: hArea.containsMouse
                        ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    MaterialIcon {
                        anchors.centerIn: parent
                        font.pixelSize: 13 * root.s
                        text: hbtn.modelData.icon
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                    }
                    MouseArea {
                        id: hArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (hbtn.modelData.act === "new") {
                                Needle.newChat();
                                root.pendingImages = [];
                                Qt.callLater(input.forceActiveFocus);
                            } else if (hbtn.modelData.act === "history") {
                                root.historyDrawerOpen = !root.historyDrawerOpen;
                                if (root.historyDrawerOpen)
                                    Needle.loadSessions();
                            } else {
                                Needle.openDashboard();
                            }
                        }
                    }
                }
            }
        }
    }
    // model picker dropdown; the scrim behind it closes on an outside click.
    MouseArea {
        anchors.fill: parent
        visible: root.modelMenuOpen
        z: 20
        onClicked: root.modelMenuOpen = false
    }
    Rectangle {
        visible: root.modelMenuOpen
        z: 21
        anchors.top: header.bottom
        anchors.right: parent.right
        anchors.topMargin: 4 * root.s
        anchors.rightMargin: 14 * root.s
        width: 220 * root.s
        height: Math.min(260 * root.s, modelList.contentHeight + 8 * root.s)
        radius: Theme.radiusWidget
        color: Theme.surfaceContainer
        border.width: Theme.borderWidth
        border.color: Theme.outline
        SumiEdge { radius: Theme.radiusWidget }
        ListView {
            id: modelList
            anchors.fill: parent
            anchors.margins: 4 * root.s
            clip: true
            model: Needle.models
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: mrow
                required property int index
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                height: 30 * root.s
                radius: 6 * root.s
                readonly property bool current: Needle.currentModel === mrow.modelData.id
                color: mrowArea.containsMouse
                    ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                    : mrow.current ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                    : "transparent"
                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8 * root.s
                    anchors.rightMargin: 8 * root.s
                    text: mrow.modelData.name || mrow.modelData.id
                    elide: Text.ElideRight
                    color: mrow.current ? Theme.primary : Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                    font.family: Theme.fontPrimary
                    font.pixelSize: 10 * root.s
                }
                MouseArea {
                    id: mrowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Needle.setModel(mrow.modelData.id);
                        root.modelMenuOpen = false;
                    }
                }
            }
        }
    }

    // session history drawer: past conversations, resume on click.
    MouseArea {
        anchors.fill: parent
        visible: root.historyDrawerOpen
        z: 22
        onClicked: root.historyDrawerOpen = false
    }
    Rectangle {
        id: historyDrawer
        visible: root.historyDrawerOpen
        z: 23
        anchors.top: header.bottom
        anchors.right: parent.right
        anchors.topMargin: 4 * root.s
        anchors.rightMargin: 14 * root.s
        width: 260 * root.s
        height: Math.min((Needle.sessions.length + 1) * 34 * root.s + 8 * root.s, 340 * root.s)
        radius: 10 * root.s
        color: Qt.rgba(Theme.effectiveSurface.r, Theme.effectiveSurface.g, Theme.effectiveSurface.b, 0.98)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
        clip: true
        Column {
            anchors.fill: parent
            anchors.margins: 4 * root.s
            Rectangle {
                width: parent.width
                height: 32 * root.s
                radius: 6 * root.s
                color: ncArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : "transparent"
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.s
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "add_comment"
                        font.pixelSize: 12 * root.s
                        color: Theme.primary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("New chat")
                        color: Theme.primary
                        font.family: Theme.mono
                        font.pixelSize: 9.5 * root.s
                    }
                }
                MouseArea {
                    id: ncArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Needle.newChat();
                        root.pendingImages = [];
                        root.historyDrawerOpen = false;
                        Qt.callLater(input.forceActiveFocus);
                    }
                }
            }
            ListView {
                width: parent.width
                height: parent.height - 34 * root.s
                clip: true
                model: Needle.sessions
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    id: sRow
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    height: 32 * root.s
                    radius: 6 * root.s
                    color: sArea.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10) : "transparent"
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10 * root.s
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: (sRow.modelData.title && sRow.modelData.title.length) ? sRow.modelData.title : I18n.tr("untitled")
                        elide: Text.ElideRight
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                        font.family: Theme.fontPrimary
                        font.pixelSize: 10.5 * root.s
                    }
                    MouseArea {
                        id: sArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Needle.switchSession(sRow.modelData.id);
                            root.historyDrawerOpen = false;
                        }
                    }
                }
            }
        }
    }

    // ── transcript ──
    ListView {
        id: list
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: inputWrap.top
        anchors.leftMargin: 14 * root.s
        anchors.rightMargin: 14 * root.s
        anchors.topMargin: 8 * root.s
        anchors.bottomMargin: 8 * root.s
        clip: true
        spacing: 12 * root.s
        model: Needle.convo
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 4000

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        onCountChanged: root.scrollEnd()

        delegate: Column {
            id: msg
            required property int index
            required property string who
            required property string body
            required property string imagesJson
            required property string working
            required property bool streaming
            required property bool failed
            required property string activityJson
            required property string permJson

            width: ListView.view ? ListView.view.width : 0
            spacing: 5 * root.s

            readonly property bool isUser: msg.who === "user"

            // role tag
            Text {
                text: msg.isUser ? I18n.tr("YOU") : I18n.tr("NEEDLE")
                color: msg.isUser
                    ? Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                    : Theme.primary
                font.family: Theme.mono
                font.pixelSize: 7.5 * root.s
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
                anchors.right: msg.isUser ? parent.right : undefined
            }

            // bubble
            Rectangle {
                width: msg.isUser ? Math.min(parent.width, Math.max(bubbleText.implicitWidth + 24 * root.s, imgCol.implicitWidth + 16 * root.s)) : parent.width
                anchors.right: msg.isUser ? parent.right : undefined
                implicitHeight: bodyCol.implicitHeight + 16 * root.s
                radius: Theme.radiusWidget
                color: msg.isUser
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                    : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05)
                border.width: 1
                border.color: msg.isUser
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.28)
                    : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.30)

                Column {
                    id: bodyCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8 * root.s
                    spacing: 6 * root.s

                    readonly property var permReq: {
                        try { return msg.permJson.length > 0 ? JSON.parse(msg.permJson) : null; }
                        catch (e) { return null; }
                    }

                    // working indicator (agent, pre-answer); the approval card replaces it
                    Row {
                        visible: !msg.isUser && msg.streaming && msg.body.length === 0 && bodyCol.permReq === null
                        spacing: 6 * root.s
                        Rectangle {
                            width: 6 * root.s; height: 6 * root.s; radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.primary
                            SequentialAnimation on opacity {
                                running: !msg.isUser && msg.streaming && msg.body.length === 0
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.3; to: 1; duration: 520 }
                                NumberAnimation { from: 1; to: 0.3; duration: 520 }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: msg.working
                            color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                            font.family: Theme.fontPrimary
                            font.pixelSize: 11 * root.s
                        }
                    }

                    // approval: hermes paused on a tool and waits for a pick. A
                    // card in the accent, not a status line: this is the one thing
                    // the turn cannot continue without.
                    Rectangle {
                        id: permCard
                        width: parent.width
                        visible: !msg.isUser && msg.streaming && bodyCol.permReq !== null
                        height: visible ? permCol.implicitHeight + 20 * root.s : 0
                        radius: 9 * root.s
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
                        Column {
                            id: permCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10 * root.s
                            spacing: 8 * root.s
                            Row {
                                spacing: 6 * root.s
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "shield"
                                    font.pixelSize: 13 * root.s
                                    color: Theme.primary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("NEEDS YOUR OK")
                                    color: Theme.primary
                                    font.family: Theme.mono
                                    font.pixelSize: 8 * root.s
                                    font.letterSpacing: 1.2
                                    font.weight: Font.DemiBold
                                }
                            }
                            Text {
                                width: parent.width
                                text: bodyCol.permReq ? String(bodyCol.permReq.title || "") : ""
                                color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                                font.family: Theme.mono
                                font.pixelSize: 10.5 * root.s
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: 3
                                elide: Text.ElideMiddle
                            }
                            Flow {
                                width: parent.width
                                spacing: 6 * root.s
                                Repeater {
                                    // hermes usually offers its own reject option; add one only when it did not
                                    model: {
                                        var req = bodyCol.permReq;
                                        if (!req) return [];
                                        var opts = req.options.slice();
                                        var hasReject = opts.some((o) => String(o.kind || "").indexOf("reject") >= 0);
                                        return hasReject ? opts : opts.concat([{ id: "", name: I18n.tr("Decline"), kind: "reject" }]);
                                    }
                                    delegate: Rectangle {
                                        id: permBtn
                                        required property var modelData
                                        readonly property bool allow: modelData.id !== "" && String(modelData.kind || "").indexOf("reject") < 0
                                        height: 28 * root.s
                                        width: permBtnRow.implicitWidth + 22 * root.s
                                        radius: 7 * root.s
                                        color: allow
                                            ? (pbArea.containsMouse ? Qt.lighter(Theme.primary, 1.12) : Theme.primary)
                                            : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, pbArea.containsMouse ? 0.14 : 0.06)
                                        border.width: allow ? 0 : 1
                                        border.color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.18)
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                                        Row {
                                            id: permBtnRow
                                            anchors.centerIn: parent
                                            spacing: 5 * root.s
                                            MaterialIcon {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: permBtn.allow ? "check" : "close"
                                                font.pixelSize: 13 * root.s
                                                color: permBtn.allow ? Theme.inkOn(Theme.primary, Theme.onPrimary)
                                                    : Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: String(permBtn.modelData.name || permBtn.modelData.id)
                                                color: permBtn.allow ? Theme.inkOn(Theme.primary, Theme.onPrimary)
                                                    : Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                                font.family: Theme.fontPrimary
                                                font.pixelSize: 11 * root.s
                                                font.weight: permBtn.allow ? Font.DemiBold : Font.Normal
                                            }
                                        }
                                        MouseArea {
                                            id: pbArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Needle.answerPermission(permBtn.modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // live activity: the tools the agent runs and its reasoning. A
                    // long run collapses to its last few steps behind a count, so a
                    // twenty-file read does not push the answer off the panel.
                    Column {
                        id: activityCol
                        width: parent.width
                        spacing: 3 * root.s
                        visible: !msg.isUser && activityCol.items.length > 0
                        property bool expanded: false
                        readonly property int tail: 3
                        readonly property var items: {
                            try { return JSON.parse(msg.activityJson) || []; }
                            catch (e) { return []; }
                        }
                        readonly property bool folded: !expanded && items.length > tail + 1
                        readonly property string summary: {
                            var byKind = {}, running = 0, failed = 0, tools = 0;
                            for (var i = 0; i < items.length; i++) {
                                var it = items[i];
                                if (it.k !== "tool") continue;
                                tools++;
                                var kind = it.kind || "tool";
                                byKind[kind] = (byKind[kind] || 0) + 1;
                                if (it.status === "failed") failed++;
                                else if (it.status !== "completed") running++;
                            }
                            var parts = [];
                            for (var k in byKind)
                                parts.push(byKind[k] + " " + k + (byKind[k] > 1 ? "s" : ""));
                            var s = tools === 1 ? I18n.tr("%1 step").arg(tools) : I18n.tr("%1 steps").arg(tools);
                            if (parts.length) s += " · " + parts.join(", ");
                            if (running) s += " · " + I18n.tr("%1 running").arg(running);
                            if (failed) s += " · " + I18n.tr("%1 failed").arg(failed);
                            return s;
                        }

                        Item {
                            width: parent.width
                            height: 18 * root.s
                            visible: activityCol.items.length > activityCol.tail + 1
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4 * root.s
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: activityCol.expanded ? "expand_less" : "expand_more"
                                    font.pixelSize: 13 * root.s
                                    color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: activityCol.summary
                                    color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                    font.family: Theme.mono
                                    font.pixelSize: 8.5 * root.s
                                    font.letterSpacing: 0.4
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: activityCol.expanded = !activityCol.expanded
                            }
                        }
                        Repeater {
                            id: actRepeater
                            model: activityCol.folded ? activityCol.items.slice(activityCol.items.length - activityCol.tail) : activityCol.items
                            delegate: Item {
                                id: actRow
                                required property var modelData
                                width: activityCol.width
                                height: Math.max(actIcon.implicitHeight, actText.implicitHeight)
                                readonly property bool isTool: actRow.modelData.k === "tool"
                                readonly property bool running: actRow.isTool && actRow.modelData.status !== "completed" && actRow.modelData.status !== "failed"
                                readonly property bool failedTool: actRow.isTool && actRow.modelData.status === "failed"
                                readonly property string kindIcon: {
                                    if (!actRow.isTool)
                                        return "psychology";
                                    switch (actRow.modelData.kind) {
                                    case "read": return "description";
                                    case "edit": return "edit_note";
                                    case "execute": return "terminal";
                                    case "search": return "search";
                                    case "fetch": return "public";
                                    case "delete": return "delete";
                                    case "move": return "drive_file_move";
                                    case "think": return "psychology";
                                    default: return "build";
                                    }
                                }
                                MaterialIcon {
                                    id: actIcon
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    font.pixelSize: 12 * root.s
                                    text: actRow.kindIcon
                                    color: actRow.failedTool ? Theme.vermLit
                                        : actRow.isTool ? Theme.primary
                                        : Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                    opacity: actRow.isTool ? 0.95 : 0.7
                                }
                                MaterialIcon {
                                    id: actStatus
                                    visible: actRow.isTool
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    font.pixelSize: 12 * root.s
                                    text: actRow.running ? "pending" : actRow.failedTool ? "error" : "check"
                                    color: actRow.failedTool ? Theme.vermLit : Theme.primary
                                    opacity: actRow.running ? 0.5 : 0.85
                                }
                                Text {
                                    id: actText
                                    anchors.left: actIcon.right
                                    anchors.leftMargin: 6 * root.s
                                    anchors.right: actRow.isTool ? actStatus.left : parent.right
                                    anchors.rightMargin: 6 * root.s
                                    anchors.top: parent.top
                                    text: actRow.isTool
                                        ? ((actRow.modelData.title && actRow.modelData.title.length) ? actRow.modelData.title : (actRow.modelData.kind || I18n.tr("tool")))
                                        : (actRow.modelData.text || "")
                                    wrapMode: actRow.isTool ? Text.NoWrap : Text.Wrap
                                    maximumLineCount: actRow.isTool ? 1 : 3
                                    elide: actRow.isTool ? Text.ElideMiddle : Text.ElideRight
                                    textFormat: actRow.isTool ? Text.PlainText : Text.MarkdownText
                                    color: actRow.isTool ? Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                                        : Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                    font.family: actRow.isTool ? Theme.mono : Theme.fontPrimary
                                    font.pixelSize: 10.5 * root.s
                                    font.italic: !actRow.isTool
                                    opacity: actRow.isTool ? 0.92 : 0.66
                                }
                            }
                        }
                    }

                    // attached / produced images
                    Column {
                        id: imgCol
                        width: parent.width
                        spacing: 6 * root.s
                        Repeater {
                            model: {
                                try { return JSON.parse(msg.imagesJson) || []; }
                                catch (e) { return []; }
                            }
                            delegate: Rectangle {
                                id: imgCell
                                required property string modelData
                                width: Math.min(parent.width, 200 * root.s)
                                height: Math.min(160 * root.s, width * (thumb.implicitHeight > 0 ? thumb.implicitHeight / Math.max(1, thumb.implicitWidth) : 0.6))
                                radius: 6 * root.s
                                color: "transparent"
                                clip: true
                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    horizontalAlignment: Image.AlignLeft
                                    source: "file://" + imgCell.modelData
                                    asynchronous: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Spawn.run(["xdg-open", imgCell.modelData])
                                }
                            }
                        }
                    }

                    // message body: user stays plain; the agent's Markdown is
                    // split into text and wrapped, copyable code blocks.
                    TextEdit {
                        id: bubbleText
                        width: parent.width
                        visible: msg.isUser && msg.body.length > 0
                        text: msg.isUser ? msg.body : ""
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        color: msg.failed ? Theme.vermLit : Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                        selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                        selectedTextColor: color
                        font.family: Theme.fontPrimary
                        font.pixelSize: 12.5 * root.s
                    }

                    Column {
                        id: blockCol
                        width: parent.width
                        spacing: 6 * root.s
                        visible: !msg.isUser && msg.body.length > 0
                        Repeater {
                            model: root.msgBlocks(msg.body)
                            delegate: Item {
                                id: blk
                                required property var modelData
                                readonly property bool isCode: blk.modelData.type === "code"
                                width: blockCol.width
                                implicitHeight: blk.isCode ? codeBox.implicitHeight : txt.implicitHeight

                                TextEdit {
                                    id: txt
                                    visible: !blk.isCode
                                    width: blk.width
                                    text: blk.isCode ? "" : root.hardBreaks(blk.modelData.content)
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.Wrap
                                    textFormat: TextEdit.MarkdownText
                                    color: msg.failed ? Theme.vermLit : Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                                    selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                    selectedTextColor: color
                                    font.family: Theme.fontPrimary
                                    font.pixelSize: 12.5 * root.s
                                    onLinkActivated: (url) => Spawn.run(["xdg-open", url])
                                }

                                Rectangle {
                                    id: codeBox
                                    visible: blk.isCode
                                    width: blk.width
                                    implicitHeight: codeInner.implicitHeight
                                    radius: 6 * root.s
                                    color: Qt.rgba(0, 0, 0, 0.30)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
                                    property bool copied: false

                                    Column {
                                        id: codeInner
                                        width: parent.width

                                        Item {
                                            width: parent.width
                                            height: 24 * root.s

                                            Text {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 10 * root.s
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: (blk.modelData.lang && blk.modelData.lang.length) ? blk.modelData.lang : I18n.tr("code")
                                                color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                                font.family: Theme.mono
                                                font.pixelSize: 8 * root.s
                                                font.letterSpacing: 0.8
                                            }

                                            Rectangle {
                                                anchors.right: parent.right
                                                anchors.rightMargin: 5 * root.s
                                                anchors.verticalCenter: parent.verticalCenter
                                                height: 18 * root.s
                                                width: copyRow.implicitWidth + 10 * root.s
                                                radius: 5 * root.s
                                                color: cpArea.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12) : "transparent"

                                                Row {
                                                    id: copyRow
                                                    anchors.centerIn: parent
                                                    spacing: 3 * root.s
                                                    MaterialIcon {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: codeBox.copied ? "check" : "content_copy"
                                                        font.pixelSize: 11 * root.s
                                                        color: codeBox.copied ? Theme.primary : Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                                    }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: codeBox.copied ? I18n.tr("COPIED") : I18n.tr("COPY")
                                                        color: codeBox.copied ? Theme.primary : Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                                        font.family: Theme.mono
                                                        font.pixelSize: 7.5 * root.s
                                                        font.letterSpacing: 0.8
                                                    }
                                                }
                                                MouseArea {
                                                    id: cpArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        Needle.copyText(blk.modelData.content);
                                                        codeBox.copied = true;
                                                        copiedTimer.restart();
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            height: 1
                                            color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)
                                        }

                                        TextEdit {
                                            id: codeText
                                            width: parent.width
                                            leftPadding: 10 * root.s
                                            rightPadding: 10 * root.s
                                            topPadding: 6 * root.s
                                            bottomPadding: 8 * root.s
                                            text: blk.isCode ? blk.modelData.content : ""
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: TextEdit.Wrap
                                            textFormat: TextEdit.PlainText
                                            color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                                            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                            selectedTextColor: color
                                            font.family: Theme.mono
                                            font.pixelSize: 11 * root.s
                                            Loader {
                                                active: blk.isCode
                                                source: "../../../components/CodeHighlight.qml"
                                                onLoaded: {
                                                    item.textEdit = codeText;
                                                    item.lang = (blk.modelData.lang && blk.modelData.lang.length) ? blk.modelData.lang : "plaintext";
                                                }
                                            }
                                        }
                                    }

                                    Timer { id: copiedTimer; interval: 1400; onTriggered: codeBox.copied = false }
                                }
                            }
                        }
                    }
                    // agent answer actions: regenerate + copy the whole answer
                    Row {
                        visible: !msg.isUser && !msg.streaming && msg.body.length > 0
                        spacing: 2 * root.s
                        Repeater {
                            model: [ { icon: "refresh", label: "RETRY" }, { icon: "content_copy", label: "COPY" } ]
                            delegate: Rectangle {
                                id: actBtn
                                required property var modelData
                                height: 20 * root.s
                                width: actBtnRow.implicitWidth + 12 * root.s
                                radius: 5 * root.s
                                color: abArea.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12) : "transparent"
                                Row {
                                    id: actBtnRow
                                    anchors.centerIn: parent
                                    spacing: 3 * root.s
                                    MaterialIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: actBtn.modelData.icon
                                        font.pixelSize: 11 * root.s
                                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: I18n.tr(actBtn.modelData.label)
                                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                        font.family: Theme.mono
                                        font.pixelSize: 7.5 * root.s
                                        font.letterSpacing: 0.8
                                    }
                                }
                                MouseArea {
                                    id: abArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: actBtn.modelData.label === "RETRY" ? Needle.regenerate() : Needle.copyText(msg.body)
                                }
                            }
                        }
                    }
                }

            }
        }
    }

    // empty state
    Column {
        anchors.centerIn: list
        width: list.width - 40 * root.s
        spacing: 8 * root.s
        visible: Needle.convo.count === 0

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "cognition"
            font.pixelSize: 30 * root.s
            fill: 0
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("Ask the needle anything. It knows this machine, your desktop, and the Ryoku source. Drop or paste an image to ask about it.")
            wrapMode: Text.WordWrap
            color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
            font.family: Theme.fontPrimary
            font.pixelSize: 11.5 * root.s
            lineHeight: 1.25
        }
    }

    // ── input ──
    // Slash-command palette, floating just above the input.
    Rectangle {
        id: palette
        visible: root.paletteOpen
        clip: true
        anchors.left: inputWrap.left
        anchors.right: inputWrap.right
        anchors.bottom: inputWrap.top
        anchors.bottomMargin: 6 * root.s
        height: Math.min(root.slashMatches.length * 30 * root.s, 180 * root.s) + 8 * root.s
        radius: 10 * root.s
        color: Qt.rgba(Theme.effectiveSurface.r, Theme.effectiveSurface.g, Theme.effectiveSurface.b, 0.98)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
        ListView {
            id: paletteList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 4 * root.s
            clip: true
            model: root.slashMatches
            currentIndex: root.paletteIdx
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            onCurrentIndexChanged: paletteList.positionViewAtIndex(paletteList.currentIndex, ListView.Contain)
            delegate: Rectangle {
                id: pRow
                required property var modelData
                required property int index
                width: paletteList.width
                height: 30 * root.s
                radius: 6 * root.s
                color: root.paletteIdx === pRow.index ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : "transparent"
                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8 * root.s
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s
                    MaterialIcon {
                        text: pRow.modelData.skill ? "extension" : "bolt"
                        font.pixelSize: 12 * root.s
                        color: pRow.modelData.skill ? Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0) : Theme.primary
                    }
                    Text {
                        text: "/" + pRow.modelData.name
                        color: Theme.primary
                        font.family: Theme.mono
                        font.pixelSize: 11 * root.s
                        width: 82 * root.s
                        elide: Text.ElideRight
                    }
                    Text {
                        text: pRow.modelData.description || ""
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                        font.family: Theme.fontPrimary
                        font.pixelSize: 10.5 * root.s
                        width: paletteList.width - 128 * root.s
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.paletteIdx = pRow.index
                    onClicked: {
                        root.paletteIdx = pRow.index;
                        root.acceptSlash();
                        input.forceActiveFocus();
                    }
                }
            }
        }
    }

    Rectangle {
        id: inputWrap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12 * root.s
        radius: Theme.radiusWidget
        color: Theme.surface
        border.width: Theme.borderWidth
        border.color: input.activeFocus ? Theme.primary : Theme.outline
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        implicitHeight: inputCol.implicitHeight + 14 * root.s
        SumiEdge { radius: Theme.radiusWidget }

        Column {
            id: inputCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 7 * root.s
            spacing: 7 * root.s

            // pending attachments strip
            Flow {
                width: parent.width
                spacing: 6 * root.s
                visible: root.pendingImages.length > 0
                Repeater {
                    model: root.pendingImages
                    delegate: Rectangle {
                        id: pend
                        required property int index
                        required property string modelData
                        width: 46 * root.s
                        height: 46 * root.s
                        radius: 6 * root.s
                        color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06)
                        clip: true
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: "file://" + pend.modelData
                            asynchronous: true
                        }
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            width: 16 * root.s
                            height: 16 * root.s
                            radius: width / 2
                            color: Qt.rgba(0, 0, 0, 0.6)
                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "close"
                                font.pixelSize: 11 * root.s
                                color: "white"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeImage(pend.index)
                            }
                        }
                    }
                }
            }

            // input row: attach | field | send
            Item {
                width: parent.width
                height: Math.max(26 * root.s, inputScroll.height)

                Rectangle {
                    id: attachBtn
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: 26 * root.s
                    height: 26 * root.s
                    radius: width / 2
                    enabled: root.pendingImages.length < root.maxImages
                    opacity: enabled ? 1 : 0.4
                    color: attachArea.containsMouse
                        ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "add_photo_alternate"
                        font.pixelSize: 15 * root.s
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                    }
                    MouseArea {
                        id: attachArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (attachBtn.enabled) pickProc.running = true
                    }
                }

                ScrollView {
                    id: inputScroll
                    anchors.left: attachBtn.right
                    anchors.right: sendBtn.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 6 * root.s
                    anchors.rightMargin: 6 * root.s
                    height: Math.min(root.maxInputH, Math.max(root.minInputH, input.implicitHeight))
                    clip: true

                    TextArea {
                        id: input
                        background: null
                        padding: 0
                        wrapMode: TextArea.Wrap
                        placeholderText: I18n.tr("Message the needle")
                        placeholderTextColor: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                        selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                        selectByMouse: true
                        font.family: Theme.fontPrimary
                        font.pixelSize: 12.5 * root.s
                        onTextChanged: {
                            root.paletteIdx = 0;
                            root.paletteDismissed = false;
                        }
                        // Ctrl+V: let the text paste happen, and also check the
                        // clipboard for an image to attach (harmless for text).
                        Keys.onPressed: (e) => {
                            if (root.paletteOpen && e.key === Qt.Key_Down) {
                                root.paletteIdx = Math.min(root.paletteIdx + 1, root.slashMatches.length - 1);
                                e.accepted = true;
                            } else if (root.paletteOpen && e.key === Qt.Key_Up) {
                                root.paletteIdx = Math.max(root.paletteIdx - 1, 0);
                                e.accepted = true;
                            } else if (root.paletteOpen && (e.key === Qt.Key_Tab || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                root.acceptSlash();
                                e.accepted = true;
                            } else if (root.slashMode && e.key === Qt.Key_Escape) {
                                root.paletteDismissed = true;
                                e.accepted = true;
                            } else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                root.submit();
                                e.accepted = true;
                            } else if (e.key === Qt.Key_Escape && Needle.busy) {
                                Needle.cancel();
                                e.accepted = true;
                            } else if (e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier)) {
                                pasteImgProc.running = true;
                            }
                        }
                    }
                }

                // send / cancel
                Rectangle {
                    id: sendBtn
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: 26 * root.s
                    height: 26 * root.s
                    radius: width / 2
                    readonly property bool ready: input.text.trim().length > 0 || root.pendingImages.length > 0
                    color: Needle.busy ? Qt.rgba(Theme.vermLit.r, Theme.vermLit.g, Theme.vermLit.b, 0.18)
                        : ready ? Theme.primary
                        : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    MaterialIcon {
                        anchors.centerIn: parent
                        font.pixelSize: 15 * root.s
                        text: Needle.busy ? "stop" : "arrow_upward"
                        color: Needle.busy ? Theme.vermLit
                            : sendBtn.ready ? Theme.inkOn(Theme.primary, Theme.onPrimary)
                            : Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Needle.busy ? Needle.cancel() : root.submit()
                    }
                }
            }
        }
    }
}
