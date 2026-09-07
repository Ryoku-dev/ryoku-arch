import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import "../../Singletons"
import "../../lib/providerids.js" as ProviderIds
import "../../lib/rofiscript.js" as RofiScript
import "../requeststate.js" as RequestState
import ".."
import shell.services as Svc

// Script provider: runs user scripts that speak the rofi-script protocol, so the
// existing ecosystem (rofimoji, rofi-rbw, custom menus) works in Ryoku unchanged.
// Scripts are declared in ~/.config/ryoku/launcher-scripts.json as
// [{ keyword, name, exec }]. Typing "<keyword> <query>" runs the script (pass 1,
// ROFI_RETV=0), parses its rows, and activating a row re-runs it (ROFI_RETV=1,
// ROFI_INFO=<row info>). Async + cached per keyword+query.
Provider {
    id: script

    providerId: "script"

    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/launcher-scripts.json"
    property var scripts: []
    onScriptsChanged: {
        script.cachedKey = "";
        script.cachedRows = [];
        script.clearRequest();
        Dispatcher.notifyAsync();
    }
    property string cachedKey: ""
    property var cachedRows: []
    property string pendingExec: ""
    property string pendingQuery: ""
    property string pendingKey: ""
    property int pendingGeneration: 0
    property bool debounceReady: false
    property var requestState: RequestState.initial()

    function setRequestState(next) {
        if (next === script.requestState)
            return false;
        var wasBusy = RequestState.isBusy(script.requestState);
        var nowBusy = RequestState.isBusy(next);
        script.requestState = next;
        if (wasBusy !== nowBusy)
            Dispatcher.setBusy("script", nowBusy);
        return true;
    }

    function cancelProcess() {
        if (listProc.inFlight)
            listProc.running = false;
    }

    function clearRequest() {
        var next = RequestState.clear(script.requestState);
        if (next === script.requestState)
            return;
        script.setRequestState(next);
        debounce.stop();
        script.debounceReady = false;
        script.cancelProcess();
    }

    function adoptCached(key) {
        var next = RequestState.adoptSettled(script.requestState, key);
        if (next === script.requestState)
            return;
        script.setRequestState(next);
        debounce.stop();
        script.debounceReady = false;
        script.cancelProcess();
    }

    function schedule(def, text, key) {
        var next = RequestState.begin(script.requestState, key);
        if (next === script.requestState)
            return;
        script.setRequestState(next);
        script.pendingExec = JSON.stringify(def.exec);
        script.pendingQuery = text;
        script.pendingKey = key;
        script.pendingGeneration = next.generation;
        script.debounceReady = false;
        debounce.restart();
        script.cancelProcess();
    }

    function startPending() {
        if (!script.debounceReady || listProc.inFlight)
            return;
        var command;
        try {
            command = JSON.parse(script.pendingExec);
        } catch (e) {
            command = [];
        }
        if (!Array.isArray(command) || command.length === 0) {
            script.debounceReady = false;
            script.setRequestState(RequestState.settle(
                script.requestState, script.pendingKey,
                script.pendingGeneration));
            return;
        }
        var next = RequestState.markRunning(
            script.requestState, script.pendingKey,
            script.pendingGeneration);
        if (next === script.requestState)
            return;
        script.debounceReady = false;
        script.setRequestState(next);
        listProc.command = command;
        // Strip the crash handle (Spawn.env) alongside the ROFI_* vars, so a rofi
        // script that launches a Quickshell app starts fresh instead of the desktop.
        listProc.environment = Object.assign({}, Spawn.env, {
            ROFI_RETV: "0",
            ROFI_INFO: script.pendingQuery
        });
        listProc.cacheKey = script.pendingKey;
        listProc.requestGeneration = script.pendingGeneration;
        listProc.out = "";
        listProc.inFlight = true;
        listProc.didStart = false;
        listProc.running = true;
    }

    FileView {
        id: configFile
        path: script.configPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var v = JSON.parse(configFile.text());
                script.scripts = Array.isArray(v) ? v : [];
            } catch (e) {
                script.scripts = [];
            }
        }
        onLoadFailed: script.scripts = []
    }

    function matchScript(text) {
        for (var i = 0; i < script.scripts.length; i++) {
            var s = script.scripts[i];
            if (!s.keyword)
                continue;
            if (text === s.keyword || text.indexOf(s.keyword + " ") === 0)
                return { def: s, query: text.slice(s.keyword.length).replace(/^\s+/, "") };
        }
        return null;
    }

    function rowFor(def, row) {
        if (row.nonselectable)
            return null;
        return {
            id: ProviderIds.scriptRowId(def.keyword, row),
            title: row.text,
            subtitle: def.name || def.keyword,
            icon: row.icon ? Svc.Icons.path(row.icon, "") : "",
            type: def.name || "Script",
            score: 0,
            actions: [{
                id: "run",
                name: I18n.tr("Select"),
                icon: "",
                execute: function () {
                    activateProc.command = def.exec.concat([row.text]);
                    activateProc.environment = Object.assign({}, Spawn.env, { ROFI_RETV: "1", ROFI_INFO: row.info });
                    activateProc.running = false;
                    activateProc.running = true;
                }
            }]
        };
    }

    function query(text) {
        var m = matchScript((text || "").trim());
        if (!m) {
            script.clearRequest();
            return [];
        }
        var key = m.def.keyword + "\u0000" + m.query;
        if (key === script.cachedKey) {
            script.adoptCached(key);
            var out = [];
            for (var i = 0; i < script.cachedRows.length; i++) {
                var r = script.rowFor(m.def, script.cachedRows[i]);
                if (r) out.push(r);
            }
            return ProviderIds.dedupeRows(out);
        }
        script.schedule(m.def, m.query, key);
        return [];
    }

    Timer {
        id: debounce
        interval: 120
        repeat: false
        onTriggered: {
            script.debounceReady = true;
            script.startPending();
        }
    }

    Process {
        id: listProc
        property string out: ""
        property string cacheKey: ""
        property int requestGeneration: 0
        property bool inFlight: false
        property bool didStart: false
        stdout: SplitParser {
            onRead: line => listProc.out += line + "\n"
        }
        onStarted: listProc.didStart = true
        onRunningChanged: {
            if (!running && listProc.inFlight && !listProc.didStart) {
                var key = listProc.cacheKey;
                var generation = listProc.requestGeneration;
                listProc.inFlight = false;
                if (script.requestState.phase === "running"
                        && RequestState.isCurrent(
                            script.requestState, key, generation)) {
                    script.setRequestState(RequestState.settle(
                        script.requestState, key, generation));
                }
                script.startPending();
            }
        }
        onExited: (code, status) => {
            var key = listProc.cacheKey;
            var generation = listProc.requestGeneration;
            listProc.inFlight = false;
            var current = script.requestState.phase === "running"
                && RequestState.isCurrent(
                    script.requestState, key, generation);
            if (current) {
                if (status === 0) {
                    script.cachedKey = key;
                    script.cachedRows = RofiScript.parse(
                        listProc.out).rows;
                }
                script.setRequestState(RequestState.settle(
                    script.requestState, key, generation));
                if (status === 0)
                    Dispatcher.notifyAsync();
            }
            script.startPending();
        }
    }

    Process {
        id: activateProc
    }

    Component.onCompleted: Dispatcher.register(script);
}
