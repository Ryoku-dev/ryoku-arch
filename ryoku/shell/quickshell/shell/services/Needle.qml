pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

// Needle: resident state of the Super+S chat, held in a singleton (not the
// sidebar body) so the thread and any in-flight answer survive a close/reopen;
// a new chat starts only after idleResetMs away. Turns run `ryoku-rashin chat`,
// streaming the shared hermes session as JSONL.
Singleton {
    id: root

    // How long the sidebar must be gone before reopening starts a new chat.
    readonly property int idleResetMs: 10 * 60 * 1000

    readonly property alias convo: messages
    property bool busy: false
    // Index of the agent bubble the live stream is filling.
    property int liveIdx: -1
    // Wall-clock ms of the last open/close/turn; drives the idle reset.
    property double lastSeen: 0
    // Session model picker: the models hermes offers, and the current one.
    property var models: []
    property string currentModel: ""

    // Emitted whenever the transcript changes so the view can scroll to end.
    signal touched()

    function noteOpened() {
        if (!busy && messages.count > 0 && lastSeen > 0 && (Date.now() - lastSeen) > root.idleResetMs)
            root.newChat();
        root.lastSeen = Date.now();
        root.loadModels();
    }

    function noteClosed() {
        root.lastSeen = Date.now();
    }

    // A new chat clears the transcript AND resets the hermes session, so the
    // next turn starts with no memory of the last one.
    function newChat() {
        if (root.busy)
            root.cancel();
        Quickshell.execDetached(["ryoku-rashin", "chat", "--new"]);
        messages.clear();
        root.liveIdx = -1;
        root.lastSeen = Date.now();
        root.touched();
    }

    function send(text, imagePaths) {
        var q = String(text).trim();
        var imgs = imagePaths || [];
        if ((q.length === 0 && imgs.length === 0) || root.busy)
            return;
        messages.append({ who: "user", body: q, imagesJson: JSON.stringify(imgs),
            working: "", streaming: false, failed: false, activityJson: "[]", permJson: "" });
        root._run(q, imgs);
    }

    // Re-run the last question, replacing its answer (regenerate / retry).
    function regenerate() {
        if (root.busy || messages.count < 2)
            return;
        var lastIdx = messages.count - 1;
        if (messages.get(lastIdx).who !== "agent")
            return;
        var uIdx = -1;
        for (var i = lastIdx - 1; i >= 0; i--) {
            if (messages.get(i).who === "user") { uIdx = i; break; }
        }
        if (uIdx < 0)
            return;
        var u = messages.get(uIdx);
        var imgs = [];
        try { imgs = JSON.parse(u.imagesJson) || []; } catch (e) {}
        messages.remove(lastIdx);
        root._run(String(u.body), imgs);
    }

    // Append the agent bubble and start the turn (shared by send + regenerate).
    function _run(q, imgs) {
        messages.append({ who: "agent", body: "", imagesJson: "[]",
            working: I18n.tr("waking the needle"), streaming: true, failed: false, activityJson: "[]", permJson: "" });
        root.liveIdx = messages.count - 1;
        root.busy = true;
        root.lastSeen = Date.now();
        var cmd = ["ryoku-rashin", "chat"];
        for (var i = 0; i < imgs.length; i++) {
            cmd.push("--image");
            cmd.push(String(imgs[i]));
        }
        if (q.length > 0)
            cmd.push(q);
        chatProc.command = cmd;
        chatProc.running = true;
        root.touched();
    }

    function cancel() {
        chatProc.running = false;
        Quickshell.execDetached(["ryoku-rashin", "chat", "--cancel"]);
        if (root.liveIdx >= 0 && root.liveIdx < messages.count && messages.get(root.liveIdx).streaming) {
            messages.setProperty(root.liveIdx, "working", "");
            messages.setProperty(root.liveIdx, "streaming", false);
            if (messages.get(root.liveIdx).body.length === 0) {
                messages.setProperty(root.liveIdx, "failed", true);
                messages.setProperty(root.liveIdx, "body", I18n.tr("cancelled"));
            }
        }
        root.busy = false;
        root.liveIdx = -1;
        root.lastSeen = Date.now();
    }

    function copyText(t) {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", String(t)]);
    }

    function openDashboard() {
        Spawn.run(["xdg-open", "http://127.0.0.1:3600/#/chat"]);
    }

    function loadModels() { modelsProc.running = true; }

    function setModel(id) {
        if (!id || id === root.currentModel)
            return;
        root.currentModel = String(id);
        Quickshell.execDetached(["ryoku-rashin", "chat", "--set-model", String(id)]);
    }

    // Answer the approval hermes is waiting on; an empty option declines it.
    function answerPermission(optionId) {
        var i = root.liveIdx;
        if (i < 0 || i >= messages.count || messages.get(i).permJson.length === 0)
            return;
        var req;
        try { req = JSON.parse(messages.get(i).permJson); } catch (e) { return; }
        messages.setProperty(i, "permJson", "");
        messages.setProperty(i, "working", optionId ? I18n.tr("approved, continuing") : I18n.tr("declined"));
        Quickshell.execDetached(["ryoku-rashin", "chat", "--perm", String(req.id), String(optionId || "")]);
    }

    // Append or update (tools are keyed by id) an activity item on message i.
    function _pushActivity(i, item) {
        var arr = [];
        try { arr = JSON.parse(messages.get(i).activityJson) || []; } catch (e) { arr = []; }
        if (item.k === "tool" && item.id.length > 0) {
            for (var j = 0; j < arr.length; j++) {
                if (arr[j].k === "tool" && arr[j].id === item.id) {
                    arr[j] = item;
                    messages.setProperty(i, "activityJson", JSON.stringify(arr));
                    return;
                }
            }
        }
        if (item.k === "thought" && arr.length > 0 && arr[arr.length - 1].k === "thought") {
            arr[arr.length - 1].text += item.text;
            messages.setProperty(i, "activityJson", JSON.stringify(arr));
            return;
        }
        arr.push(item);
        messages.setProperty(i, "activityJson", JSON.stringify(arr));
    }

    // A finished turn: any tool still pending really did complete.
    function _finishActivity(i) {
        var arr = [];
        try { arr = JSON.parse(messages.get(i).activityJson) || []; } catch (e) { return; }
        var changed = false;
        for (var j = 0; j < arr.length; j++) {
            if (arr[j].k === "tool" && arr[j].status !== "completed" && arr[j].status !== "failed") {
                arr[j].status = "completed";
                changed = true;
            }
        }
        if (changed)
            messages.setProperty(i, "activityJson", JSON.stringify(arr));
    }

    ListModel { id: messages }

    Process {
        id: chatProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (root.liveIdx < 0 || root.liveIdx >= messages.count)
                    return;
                var i = root.liveIdx;
                var f;
                try {
                    f = JSON.parse(String(line));
                } catch (e) {
                    return;
                }
                if (!f || !f.type)
                    return;
                switch (f.type) {
                case "working":
                    messages.setProperty(i, "working", String(f.label || ""));
                    break;
                case "thought":
                    root._pushActivity(i, { k: "thought", text: String(f.text || "") });
                    if (messages.get(i).working.length > 0)
                        messages.setProperty(i, "working", "");
                    root.touched();
                    break;
                case "tool":
                    root._pushActivity(i, { k: "tool", id: String(f.id || ""), title: String(f.title || ""), kind: String(f.kind || ""), status: String(f.status || "") });
                    if (messages.get(i).working.length > 0)
                        messages.setProperty(i, "working", "");
                    root.touched();
                    break;
                case "delta":
                    messages.setProperty(i, "body", messages.get(i).body + String(f.text || ""));
                    if (messages.get(i).working.length > 0)
                        messages.setProperty(i, "working", "");
                    root.touched();
                    break;
                case "perm":
                    messages.setProperty(i, "working", I18n.tr("waiting for approval: %1").arg(String(f.title || "")));
                    messages.setProperty(i, "permJson", JSON.stringify({ id: String(f.requestId || ""), title: String(f.title || ""), options: f.options || [] }));
                    root.touched();
                    break;
                case "models":
                    root.models = f.models || [];
                    if (f.current)
                        root.currentModel = String(f.current);
                    break;
                case "done":
                    var imgs = f.images || [];
                    if (imgs.length > 0)
                        messages.setProperty(i, "imagesJson", JSON.stringify(imgs));
                    if (messages.get(i).body.length === 0 && imgs.length === 0) {
                        messages.setProperty(i, "body", I18n.tr("(no response)"));
                        messages.setProperty(i, "failed", true);
                    }
                    root._finishActivity(i);
                    messages.setProperty(i, "working", "");
                    messages.setProperty(i, "streaming", false);
                    root.busy = false;
                    root.liveIdx = -1;
                    root.lastSeen = Date.now();
                    root.touched();
                    break;
                case "error":
                    if (messages.get(i).body.length === 0)
                        messages.setProperty(i, "body", String(f.message || I18n.tr("failed")));
                    messages.setProperty(i, "failed", true);
                    messages.setProperty(i, "working", "");
                    messages.setProperty(i, "streaming", false);
                    root.busy = false;
                    root.liveIdx = -1;
                    root.lastSeen = Date.now();
                    root.touched();
                    break;
                }
            }
        }
        onExited: (code) => {
            if (root.liveIdx >= 0 && root.liveIdx < messages.count && messages.get(root.liveIdx).streaming) {
                messages.setProperty(root.liveIdx, "working", "");
                messages.setProperty(root.liveIdx, "streaming", false);
                if (messages.get(root.liveIdx).body.length === 0) {
                    messages.setProperty(root.liveIdx, "failed", true);
                    messages.setProperty(root.liveIdx, "body", code === 0 ? I18n.tr("no answer") : I18n.tr("chat failed"));
                }
            }
            root.busy = false;
            root.liveIdx = -1;
            root.lastSeen = Date.now();
            root.touched();
        }
    }

    Process {
        id: modelsProc
        command: ["ryoku-rashin", "chat", "--models"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                var f;
                try { f = JSON.parse(String(line)); } catch (e) { return; }
                if (f && f.type === "models") {
                    root.models = f.models || [];
                    if (f.current) root.currentModel = String(f.current);
                }
            }
        }
    }

    // Restore the conversation the persistent daemon session still holds, so a
    // shell reload lands the sidebar back on its thread. Text only; new turns
    // carry full activity. Only runs while the transcript is still empty.
    Process {
        id: historyProc
        command: ["ryoku-rashin", "chat", "--history"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                var f;
                try { f = JSON.parse(String(line)); } catch (e) { return; }
                if (!f || f.type !== "history" || !f.messages || messages.count > 0)
                    return;
                for (var i = 0; i < f.messages.length; i++) {
                    var m = f.messages[i];
                    messages.append({ who: String(m.who), body: String(m.body),
                        imagesJson: "[]", working: "", streaming: false, failed: false, activityJson: "[]", permJson: "" });
                }
                root.touched();
            }
        }
    }
    function loadHistory() { if (messages.count === 0 && !historyProc.running) historyProc.running = true; }

    // Past conversations, for the session drawer. `--sessions` lists them;
    // switching loads one server-side, then loadHistory rebuilds the view.
    property var sessions: []
    Process {
        id: sessionsProc
        command: ["ryoku-rashin", "chat", "--sessions"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                var f;
                try { f = JSON.parse(String(line)); } catch (e) { return; }
                if (f && f.type === "sessions" && f.sessions)
                    root.sessions = f.sessions;
            }
        }
    }
    function loadSessions() { if (!sessionsProc.running) sessionsProc.running = true; }

    Process {
        id: loadProc
        onExited: {
            root.busy = false;
            root.liveIdx = -1;
            historyProc.running = true; // repopulate from the now-current session
        }
    }
    function switchSession(id) {
        if (root.busy)
            root.cancel();
        messages.clear();
        root.liveIdx = -1;
        loadProc.command = ["ryoku-rashin", "chat", "--load", String(id)];
        loadProc.running = true;
        root.lastSeen = Date.now();
        root.touched();
    }

    Component.onCompleted: root.loadHistory()
}
