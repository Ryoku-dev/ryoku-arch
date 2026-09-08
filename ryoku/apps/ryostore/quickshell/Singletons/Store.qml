pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var catalog: ({})
    property var categories: []
    property var items: []
    property bool loading: false
    property bool offline: false
    property string generatedAt: ""
    readonly property bool refreshing: loading && items.length > 0
    property string error: ""
    property string busyKey: ""
    property string installStage: ""
    property string installError: ""
    property string installErrorKey: ""
    property string _catalogOutput: ""
    property string _catalogError: ""
    property string _installError: ""
    property bool _clearBusyAfterRefresh: false
    property var _queue: []
    property bool updateAvailable: false
    property string revision: ""
    property bool _forced: false
    property string _checkOutput: ""

    function itemKey(item) {
        return item ? String(item.category || "") + ":" + String(item.id || "") : "";
    }

    function category(id) {
        for (let i = 0; i < categories.length; i++)
            if (categories[i].id === id)
                return categories[i];
        return null;
    }

    function refresh(force) {
        if (catalogProc.running)
            return;
        root._forced = force === true;
        loading = true;
        error = "";
        _catalogOutput = "";
        _catalogError = "";
        catalogProc.command = force ? ["ryostore", "catalog", "--refresh"] : ["ryostore", "catalog"];
        catalogProc.running = true;
    }

    // A lightweight upstream probe (registries only, no downloads): it lights the
    // refresh dot when ryostore has advanced past what the user last pulled,
    // without touching the shown catalogue.
    function check() {
        if (checkProc.running)
            return;
        root._checkOutput = "";
        checkProc.running = true;
    }

    // Stop every child process before the window tears down, so no fetch is in
    // flight when the QML engine is destroyed -- a shutdown-crash guard.
    function shutdown() {
        catalogProc.running = false;
        installProc.running = false;
        checkProc.running = false;
    }

    function install(item, dither, components) {
        if (!item || busyKey !== "")
            return;
        busyKey = itemKey(item);
        installStage = "FETCHING";
        installError = "";
        installErrorKey = "";
        _installError = "";
        var cmd = ["ryostore", "install", String(item.category), String(item.id)];
        // what you see is what you install: the catalogue leads with the colour
        // original, so an install with no explicit choice takes that one
        var wantDither = (dither === undefined) ? false : dither;
        if (wantDither && String(item.artRaw || "") !== "")
            cmd.push("--dither");
        if (Array.isArray(components) && components.length > 0)
            cmd.push("--only", components.join(","));
        installProc.command = cmd;
        installProc.running = true;
    }

    function clearInstallError(item) {
        if (installErrorKey !== itemKey(item))
            return;
        installError = "";
        installErrorKey = "";
        installStage = "";
    }

    function retryInstall(item, dither, components) {
        clearInstallError(item);
        install(item, dither, components);
    }

    // installAll queues every not-yet-installed item and installs them one at a
    // time (install is single-flight): each completion pumps the next. The batch
    // stops on the first failure so the error stays visible.
    function installAll(list) {
        var q = [];
        var src = Array.isArray(list) ? list : [];
        for (var i = 0; i < src.length; i++)
            if (src[i] && src[i].installed !== true)
                q.push(src[i]);
        _queue = q;
        _pumpQueue();
    }
    function _pumpQueue() {
        if (busyKey !== "" || _queue.length === 0)
            return;
        var next = _queue[0];
        _queue = _queue.slice(1);
        install(next);
    }

    function openSettings(item) {
        if (!item)
            return;
        Quickshell.execDetached(["ryostore", "settings", String(item.category), String(item.id)]);
    }

    Component.onCompleted: {
        refresh(false);
        check();
    }

    Process {
        id: catalogProc
        stdout: StdioCollector { onStreamFinished: root._catalogOutput = text }
        stderr: StdioCollector { onStreamFinished: root._catalogError = text }
        onExited: code => {
            root.loading = false;
            if (code !== 0) {
                root.error = root._catalogError.trim() || "Catalogue failed";
                if (root._clearBusyAfterRefresh) {
                    root._clearBusyAfterRefresh = false;
                    root.busyKey = "";
                }
                return;
            }
            try {
                const next = JSON.parse(root._catalogOutput);
                if (!Array.isArray(next.categories) || !Array.isArray(next.items))
                    throw new Error("catalogue arrays are missing");
                root.catalog = next;
                root.categories = next.categories.slice();
                root.items = next.items.slice();
                root.offline = next.offline === true;
                root.generatedAt = String(next.generatedAt || "");
                root.error = "";
                root.revision = String(next.revision || "");
                if (root._forced)
                    root.updateAvailable = false;
                // Fill the on-disk asset cache out of band so the next open (and
                // this session's later scrolling) renders previews from disk.
                Quickshell.execDetached(["ryostore", "warm"]);
                if (root._clearBusyAfterRefresh) {
                    root._clearBusyAfterRefresh = false;
                    root.installStage = "COMPLETE";
                    root.busyKey = "";
                }
            } catch (e) {
                root.error = "Invalid catalogue: " + e;
                if (root._clearBusyAfterRefresh) {
                    root._clearBusyAfterRefresh = false;
                    root.busyKey = "";
                }
            }
            root._pumpQueue();
        }
    }

    Process {
        id: installProc
        stderr: StdioCollector { onStreamFinished: root._installError = text }
        onRunningChanged: if (running) root.installStage = "INSTALLING"
        onExited: code => {
            if (code !== 0) {
                root.installStage = "FAILED";
                root.installError = root._installError.trim() || "Installation failed";
                root.installErrorKey = root.busyKey;
                root.busyKey = "";
                root._queue = [];
                return;
            }
            root.installStage = "VERIFYING";
            root._clearBusyAfterRefresh = true;
            root.refresh(true);
        }
    }

    Process {
        id: checkProc
        command: ["ryostore", "check"]
        stdout: StdioCollector { onStreamFinished: root._checkOutput = text }
        onExited: code => {
            if (code !== 0)
                return;
            try {
                const res = JSON.parse(root._checkOutput);
                root.updateAvailable = res.updateAvailable === true;
            } catch (e) {
                // A malformed probe never asserts an update.
            }
        }
    }
}
