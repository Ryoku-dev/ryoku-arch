import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Hyprland
import Ryoku.Ui.Singletons
import "../../Singletons"
import "../../lib/fuzzy.js" as Fuzzy
import ".."
import shell.services as Svc

// Open-window switcher: lists Hyprland toplevels, fuzzy-matched by title and
// class, and focuses the picked one. Default-ranked just below apps so "fire"
// surfaces a running Firefox window under the app entry.
Provider {
    id: windows

    providerId: "windows"

    // Hyprland events keep the model live after one initial snapshot. Refreshing
    // from every query creates a revision loop: query -> refresh -> valuesChanged
    // -> dispatcher revision -> query. That loop makes the whole launcher redraw
    // while the user types.
    property bool initialSnapshotRequested: false
    property bool notifyQueued: false
    property string publishedSignature: ""

    function requestInitialSnapshot() {
        if (initialSnapshotRequested)
            return;
        initialSnapshotRequested = true;
        Hyprland.refreshToplevels();
    }

    function queueLiveUpdate() {
        if (notifyQueued)
            return;
        notifyQueued = true;
        Qt.callLater(function () {
            notifyQueued = false;
            var signature = windows.windowSignature();
            if (signature === publishedSignature)
                return;
            publishedSignature = signature;
            Dispatcher.notifyAsync();
        });
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { windows.queueLiveUpdate(); }
    }

    Instantiator {
        model: Hyprland.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { windows.queueLiveUpdate(); }
            function onTitleChanged() { windows.queueLiveUpdate(); }
            function onWorkspaceChanged() { windows.queueLiveUpdate(); }
        }
    }

    // Focusing must wait until the palette's close morph unmaps its exclusive-
    // focus layer: focusing earlier gets overridden when the unmap hands focus
    // to the window under the cursor (input:mouse_refocus).
    property var pendingFocus: null
    Timer {
        id: focusDelay
        interval: Motion.close + 110
        repeat: false
        onTriggered: {
            var e = windows.pendingFocus;
            windows.pendingFocus = null;
            if (!e)
                return;
            var w = e.toplevel ? e.toplevel.wayland : null;
            if (w)
                w.activate();
            else
                windows.focusWindow(e.address);
        }
    }

    function normAddr(addr) {
        var a = String(addr || "");
        return a.indexOf("0x") === 0 ? a : "0x" + a;
    }

    function focusWindow(addr) {
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + normAddr(addr) + '" })');
    }

    function entries() {
        var out = [];
        var tl = Hyprland.toplevels.values;
        for (var i = 0; i < tl.length; i++) {
            var t = tl[i];
            var o = t && t.lastIpcObject;
            if (!o || !o.address)
                continue;
            if (o.workspace && String(o.workspace.name).indexOf("special:") === 0)
                continue;
            var workspace = o.workspace && o.workspace.name
                ? String(o.workspace.name) : "";
            out.push({
                address: o.address,
                toplevel: t,
                title: o.title || o.class || I18n.tr("Window"),
                cls: o.class || "",
                workspace: workspace,
                keywords: [o.class || ""]
            });
        }
        return out;
    }

    function windowSignature() {
        var list = windows.entries();
        var parts = [];
        for (var index = 0; index < list.length; index++) {
            var entry = list[index];
            parts.push([entry.address, entry.title, entry.cls, entry.workspace]
                .join("\u001f"));
        }
        parts.sort();
        return parts.join("\u001e");
    }

    function rowFor(e) {
        return {
            id: "window:" + e.address,
            windowAddress: e.address,
            appId: e.cls,
            title: e.title,
            subtitle: e.cls,
            icon: e.cls ? Svc.Icons.path(e.cls, "application-x-executable") : "",
            type: "Window",
            score: 5,
            actions: [{
                id: "focus",
                name: I18n.tr("Focus"),
                icon: "",
                execute: function () {
                    windows.pendingFocus = e;
                    focusDelay.restart();
                }
            }]
        };
    }

    function query(text) {
        windows.requestInitialSnapshot();
        var list = windows.entries();
        var q = (text || "").trim().toLowerCase();
        var rows = [];
        for (var i = 0; i < list.length; i++)
            if (q.length === 0 || Fuzzy.score({ name: list[i].title, keywords: list[i].keywords }, q) < 99)
                rows.push(windows.rowFor(list[i]));
        return rows;
    }

    Component.onCompleted: {
        windows.publishedSignature = windows.windowSignature();
        windows.requestInitialSnapshot();
        Dispatcher.register(windows);
    }
}
