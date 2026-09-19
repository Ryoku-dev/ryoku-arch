pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.WindowManager
import Quickshell.Wayland
import "../lib/wmstate.js" as WmState

// Capability-shaped view of the window manager. Presentation lists come from the
// Wayland protocols (ext-workspace-v1 windowsets, foreign-toplevel toplevels);
// the residue they cannot answer (focused output, per-window workspace, focus
// order, geometry, output geometry, caps, workspace model) rides the daemon `wm`
// topic. Consumers ask caps.*, never which compositor is running.
Singleton {
    id: root

    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-shell.sock"

    // Separate properties keep a window-only update from invalidating every model.
    QtObject {
        id: state
        property bool ready: false
        property var caps: ({})
        property string workspaceModel: "fixed"
        property string focusedOutput: ""
        property var outputs: []
        property var configFiles: []
        property string keyboardLayout: ""
        property var keyboardLayouts: []
        property var windows: []
        property var workspaces: []
    }
    readonly property bool ready: state.ready === true

    // Every capability key is always present as a boolean, so read Wm.caps.<name>
    // directly with no undefined guard.
    readonly property var caps: state.caps || ({})
    readonly property string workspaceModel: state.workspaceModel || "fixed"

    readonly property string focusedOutput: state.focusedOutput || ""
    readonly property var outputs: state.outputs || []
    readonly property var configFiles: state.configFiles || []

    // Active xkb layout name (human string) and the configured layout list.
    readonly property string keyboardLayout: state.keyboardLayout || ""
    readonly property var keyboardLayouts: state.keyboardLayouts || []

    readonly property var _winResidue: state.windows || []
    readonly property var _wsResidue: state.workspaces || []

    // Bound at declaration so the Wayland registry binds early; the lists fill in
    // asynchronously after connect.
    readonly property var _windowsets: WindowManager.windowsets
    property var _toplevelModel: ToplevelManager.toplevels
    readonly property var toplevels: root._toplevelModel ? root._toplevelModel.values : []

    function outputByName(name) {
        const outs = root.outputs;
        for (let i = 0; i < outs.length; i++)
            if (outs[i].name === name)
                return outs[i];
        return null;
    }

    // ext-workspace-v1 windowsets joined with the daemon's occupancy residue by
    // name (windowset.id is empty on Hyprland; name is the stable key).
    readonly property var workspaces: {
        const res = {};
        for (let i = 0; i < root._wsResidue.length; i++) {
            const w = root._wsResidue[i];
            res[w.name] = w;
        }
        const sets = root._windowsets || [];
        const out = [];
        for (let i = 0; i < sets.length; i++) {
            const s = sets[i];
            const r = res[s.name] || ({});
            out.push({
                name: s.name,
                active: s.active === true,
                urgent: s.urgent === true,
                canActivate: s.canActivate === true,
                windows: r.windows || 0,
                occupied: (r.windows || 0) > 0,
                fullscreen: r.fullscreen === true,
                special: r.special === true,
                output: r.output || "",
                layout: r.layout || ""
            });
        }
        return out;
    }

    function workspaceByName(name) {
        const list = root.workspaces;
        for (let i = 0; i < list.length; i++)
            if (list[i].name === name)
                return list[i];
        return null;
    }

    // The workspace shown on the focused output.
    readonly property var focusedWorkspace: {
        const list = root.workspaces;
        for (let i = 0; i < list.length; i++)
            if (list[i].active && list[i].output === root.focusedOutput)
                return list[i];
        for (let i = 0; i < list.length; i++)
            if (list[i].active)
                return list[i];
        return null;
    }

    // True when the workspace shown on `name` holds a fullscreen window.
    function outputHasFullscreen(name) {
        const o = root.outputByName(name);
        if (!o || !o.activeWorkspace)
            return false;
        const ws = root.workspaceByName(o.activeWorkspace);
        return !!ws && ws.fullscreen === true;
    }

    // Daemon window residue (identity, workspace, focus order, geometry) joined to
    // the foreign-toplevel handle for capture and activate. Keyed on
    // (appId, title, output); tied same-key windows pair in list order. Two
    // identical-title windows of one app on one output can swap handles.
    readonly property var windows: {
        const tls = root.toplevels;
        const buckets = ({});
        for (let i = 0; i < tls.length; i++) {
            const t = tls[i];
            const k = (t.appId || "") + "\u0000" + (t.title || "") + "\u0000"
                + (t.screens && t.screens.length ? t.screens[0].name : "");
            (buckets[k] || (buckets[k] = [])).push(t);
        }
        const cursor = ({});
        const out = [];
        for (let i = 0; i < root._winResidue.length; i++) {
            const w = root._winResidue[i];
            const k = (w.appId || "") + "\u0000" + (w.title || "") + "\u0000" + (w.output || "");
            const arr = buckets[k];
            const at = cursor[k] || 0;
            const tl = (arr && at < arr.length) ? arr[at] : null;
            cursor[k] = at + 1;
            out.push({
                id: w.id,
                appId: w.appId || "",
                title: w.title || "",
                workspace: w.workspace || "",
                output: w.output || "",
                focusOrder: (typeof w.focusOrder === "number" ? w.focusOrder : -1),
                floating: w.floating === true,
                x: w.x || 0,
                y: w.y || 0,
                width: w.width || 0,
                height: w.height || 0,
                toplevel: tl
            });
        }
        return out;
    }

    // The foreign-toplevel activated flag marks the focused window on every
    // compositor; focusOrder is only meaningful where caps.focusHistory is set,
    // so it is the fallback.
    readonly property var focusedWindow: {
        const list = root.windows;
        for (let i = 0; i < list.length; i++)
            if (list[i].toplevel && list[i].toplevel.activated)
                return list[i];
        for (let i = 0; i < list.length; i++)
            if (list[i].focusOrder === 0)
                return list[i];
        return null;
    }

    function windowsOnWorkspace(name) {
        const list = root.windows;
        const out = [];
        for (let i = 0; i < list.length; i++)
            if (list[i].workspace === name)
                out.push(list[i]);
        return out;
    }

    // ---- actions ----
    // Each names a neutral action, gates on the capability action.go maps it to
    // (empty capability = always allowed), and rides the daemon `wm.act` call.
    function _act(action, cap, args) {
        if (cap !== "" && root.caps[cap] !== true)
            return;
        root._call("wm.act", { action: action, args: args });
    }

    // Request/response variant: cb receives the wm.act result string, "" on a
    // gated-out call or failure. Used where an action reports state to restore.
    property var _pending: ({})
    property int _nextId: 0
    function _actResult(action, cap, args, cb) {
        if (cap !== "" && root.caps[cap] !== true) {
            if (cb) cb("");
            return;
        }
        const id = ++root._nextId;
        root._pending[id] = cb;
        root._call("wm.act", { action: action, args: args, id: id });
    }

    function focusWindow(id) { root._act("window.focus", "", [String(id)]); }
    function closeWindow(id) { root._act("window.close", "", [String(id)]); }
    function focusApp(appId) { root._act("app.focus", "", [String(appId)]); }
    function floatWindow(id) { root._act("window.float", "windowFloat", [String(id)]); }
    function moveWindowToWorkspace(id, ws) { root._act("window.moveToWorkspace", "workspaces", [String(id), String(ws)]); }

    function focusWorkspace(ws) { root._act("workspace.focus", "workspaces", [String(ws)]); }
    function cycleWorkspace(delta) { root._act("workspace.cycle", "workspaces", [String(delta)]); }
    function moveWorkspaceToOutput(ws, output) { root._act("workspace.moveToOutput", "workspaceMoveToOutput", [String(ws), String(output)]); }
    function toggleSpecialWorkspace(name) { root._act("workspace.toggleSpecial", "specialWorkspace", [String(name || "")]); }

    function cycleKeyboardLayout() { root._act("keyboard.cycleLayout", "keyboardLayoutSwitch", []); }
    function setCursor(theme, size) { root._act("cursor.set", "cursorSet", [String(theme), String(size)]); }
    function reloadConfig(scope) { root._act("config.reload", "configReload", [String(scope || "")]); }
    function setOutputPower(output, on) { root._act("output.power", "outputPower", [String(output), on ? "on" : "off"]); }
    function toggleOverview() { root._act("overview.toggle", "nativeOverview", []); }
    function enterSubmap(name) { root._act("submap.enter", "submap", [String(name)]); }
    function resetSubmap() { root._act("submap.reset", "submap", []); }

    // Live exclusive tweaks. screenShader takes a shader name; focusFollowsMouse
    // sets a follow mode and reports the previous one to cb for the caller to
    // restore.
    function setScreenShader(name) { root._act("decoration.screenShader", "screenShader", [String(name || "")]); }
    function setFocusFollowsMouse(mode, cb) { root._actResult("input.focusFollowsMouse", "liveConfigEval", [String(mode)], cb); }
    function setWorkspaceLayout(ws, layout) { root._act("workspace.layout", "tiledLayout", [String(ws), String(layout)]); }

    // ---- transport ----
    function _apply(line) {
        try {
            const frame = JSON.parse(line);
            if (frame && typeof frame === "object" && !Array.isArray(frame))
                WmState.applyFrame(state, frame);
        } catch (e) {
        }
    }

    function _call(method, args) {
        ctl.queued += "call " + method + " " + JSON.stringify(args) + "\n";
        if (ctl.connected)
            ctl.flushQueued();
        else
            ctl.connected = true;
    }

    function _reply(line) {
        try {
            const r = JSON.parse(line);
            if (r && r.id !== undefined && root._pending[r.id] !== undefined) {
                const cb = root._pending[r.id];
                delete root._pending[r.id];
                if (cb) cb((r.ok && typeof r.result === "string") ? r.result : "");
            }
        } catch (e) {
        }
    }

    Socket {
        id: sub
        path: root.sockPath
        parser: SplitParser { onRead: line => root._apply(line) }
        Component.onCompleted: connected = true
        onConnectionStateChanged: {
            if (connected) {
                write("subscribe wm\n");
                flush();
            } else {
                retry.restart();
            }
        }
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: if (!sub.connected) sub.connected = true
    }

    Socket {
        id: ctl
        path: root.sockPath
        property string queued: ""
        parser: SplitParser { onRead: line => root._reply(line) }
        function flushQueued() {
            if (queued.length === 0)
                return;
            write(queued);
            flush();
            queued = "";
        }
        onConnectionStateChanged: if (connected) flushQueued()
    }
}
