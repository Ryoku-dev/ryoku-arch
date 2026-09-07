import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import "../../Singletons"
import "../requeststate.js" as RequestState
import ".."

// Scoped file finder, reached only by an explicit command so a plain search is
// never flooded with deep system paths:
//   /file <q>    files by name (home, junk excluded)
//   /folder <q>  directories
//   /image <q>   images in Pictures + Downloads (by extension)
//   /video <q>   videos in Videos + Downloads (by extension)
// Backed by fd, async + cached per (mode, query). Opens with xdg-open; a
// secondary action reveals the containing folder. Not a default provider.
Provider {
    id: find

    providerId: "find"
    defaultProvider: false
    prefixes: ["/file", "/folder", "/image", "/video"]

    property bool available: false
    onAvailableChanged: {
        find.cachedKey = "";
        find.cachedRows = [];
        find.clearRequest();
        Dispatcher.notifyAsync();
    }
    property string cachedKey: ""
    property var cachedRows: []
    property string pendingMode: ""
    property string pendingQuery: ""
    property string pendingKey: ""
    property int pendingGeneration: 0
    property bool debounceReady: false
    property var requestState: RequestState.initial()

    readonly property string home: Quickshell.env("HOME") || "."

    function setRequestState(next) {
        if (next === find.requestState)
            return false;
        var wasBusy = RequestState.isBusy(find.requestState);
        var nowBusy = RequestState.isBusy(next);
        find.requestState = next;
        if (wasBusy !== nowBusy)
            Dispatcher.setBusy("find", nowBusy);
        return true;
    }

    function cancelProcess() {
        if (findProc.inFlight)
            findProc.running = false;
    }

    function clearRequest() {
        var next = RequestState.clear(find.requestState);
        if (next === find.requestState)
            return;
        find.setRequestState(next);
        debounce.stop();
        find.debounceReady = false;
        find.cancelProcess();
    }

    function adoptCached(key) {
        var next = RequestState.adoptSettled(find.requestState, key);
        if (next === find.requestState)
            return;
        find.setRequestState(next);
        debounce.stop();
        find.debounceReady = false;
        find.cancelProcess();
    }

    function schedule(mode, text, key) {
        var next = RequestState.begin(find.requestState, key);
        if (next === find.requestState)
            return;
        find.setRequestState(next);
        find.pendingMode = mode;
        find.pendingQuery = text;
        find.pendingKey = key;
        find.pendingGeneration = next.generation;
        find.debounceReady = false;
        debounce.restart();
        find.cancelProcess();
    }

    function startPending() {
        if (!find.debounceReady || findProc.inFlight)
            return;
        var next = RequestState.markRunning(
            find.requestState, find.pendingKey, find.pendingGeneration);
        if (next === find.requestState)
            return;
        find.debounceReady = false;
        find.setRequestState(next);
        findProc.cacheKey = find.pendingKey;
        findProc.requestGeneration = find.pendingGeneration;
        findProc.command = find.fdArgs(
            find.pendingMode, find.pendingQuery);
        findProc.hits = [];
        findProc.inFlight = true;
        findProc.didStart = false;
        findProc.running = true;
    }

    function modeFor(prefix) {
        if (prefix === "/folder") return "folder";
        if (prefix === "/image") return "image";
        if (prefix === "/video") return "video";
        return "file";
    }

    // fd argv for a mode: type, extension filters, and the roots to search. No
    // --hidden, so dot-dirs (.cache, .claude, .config) are skipped; explicit
    // excludes drop the heavy non-dot dirs too.
    function fdArgs(mode, query) {
        var common = ["--max-results", "25", "--exclude", "node_modules",
            "--exclude", ".git", "--exclude", "Trash"];
        var imgExt = ["--extension", "png", "--extension", "jpg", "--extension", "jpeg",
            "--extension", "gif", "--extension", "webp", "--extension", "svg",
            "--extension", "bmp", "--extension", "avif"];
        var vidExt = ["--extension", "mp4", "--extension", "mkv", "--extension", "webm",
            "--extension", "mov", "--extension", "avi", "--extension", "m4v"];
        if (mode === "folder")
            return ["fd", "--type", "d"].concat(common).concat([query, find.home]);
        if (mode === "image")
            return ["fd", "--type", "f"].concat(imgExt).concat(common).concat([query, find.home + "/Pictures", find.home + "/Downloads"]);
        if (mode === "video")
            return ["fd", "--type", "f"].concat(vidExt).concat(common).concat([query, find.home + "/Videos", find.home + "/Downloads"]);
        return ["fd", "--type", "f"].concat(common).concat([query, find.home]);
    }

    function baseName(path) {
        var p = String(path);
        var i = p.lastIndexOf("/");
        return i >= 0 ? p.slice(i + 1) : p;
    }

    function shortPath(path) {
        // prefix-anchored: an unanchored replace would also rewrite a home
        // path embedded mid-string.
        var p = String(path);
        return p.indexOf(find.home) === 0 ? "~" + p.slice(find.home.length) : p;
    }

    function fileUrl(path) {
        return "file://" + encodeURIComponent(String(path)).replace(/%2F/g, "/");
    }

    // Section label per mode, so folder results read FOLDER, not FILE.
    function kindFor(mode) {
        if (mode === "folder") return "Folder";
        if (mode === "image") return "Image";
        if (mode === "video") return "Video";
        return "File";
    }

    function rowFor(rawPath, kind) {
        // fd prints directories with a trailing slash; strip it or the
        // basename comes out empty and the row renders with no title.
        var path = String(rawPath).replace(/\/+$/, "");
        return {
            id: "find:" + path,
            title: baseName(path),
            subtitle: shortPath(path.replace(/\/[^/]*$/, "")),
            icon: "",
            preview: kind === "Image" ? fileUrl(path) : "",
            type: kind || "File",
            score: 0,
            actions: [
                { id: "open", name: I18n.tr("Open"), icon: "", execute: function () { Spawn.run(["xdg-open", path]); } },
                { id: "reveal", name: I18n.tr("Reveal"), icon: "", execute: function () { Spawn.run(["xdg-open", path.replace(/\/[^/]*$/, "")]); } }
            ]
        };
    }

    function query(text, prefix) {
        if (!find.available) {
            find.clearRequest();
            return [];
        }
        var mode = modeFor(prefix);
        var t = (text || "").trim();
        if (t.length < 1) {
            find.clearRequest();
            return [];
        }
        var key = mode + "\u0000" + t;
        if (key === find.cachedKey) {
            find.adoptCached(key);
            var kind = find.kindFor(mode);
            return find.cachedRows.map(function (p) { return find.rowFor(p, kind); });
        }
        find.schedule(mode, t, key);
        return [];
    }

    Timer {
        id: debounce
        interval: 130
        repeat: false
        onTriggered: {
            find.debounceReady = true;
            find.startPending();
        }
    }

    Process {
        id: availProc
        command: ["sh", "-c", "command -v fd >/dev/null 2>&1"]
        onExited: (code) => { find.available = (code === 0); }
    }

    Process {
        id: findProc
        property string cacheKey: ""
        property int requestGeneration: 0
        property bool inFlight: false
        property bool didStart: false
        property var hits: []
        stdout: SplitParser {
            onRead: line => { if (line.trim().length) findProc.hits.push(line.trim()); }
        }
        onStarted: findProc.didStart = true
        onRunningChanged: {
            if (!running && findProc.inFlight && !findProc.didStart) {
                var key = findProc.cacheKey;
                var generation = findProc.requestGeneration;
                findProc.inFlight = false;
                if (find.requestState.phase === "running"
                        && RequestState.isCurrent(
                            find.requestState, key, generation)) {
                    find.setRequestState(RequestState.settle(
                        find.requestState, key, generation));
                }
                find.startPending();
            }
        }
        onExited: (code, status) => {
            var key = findProc.cacheKey;
            var generation = findProc.requestGeneration;
            findProc.inFlight = false;
            var current = find.requestState.phase === "running"
                && RequestState.isCurrent(
                    find.requestState, key, generation);
            if (current) {
                var succeeded = status === 0 && code <= 1;
                if (succeeded) {
                    find.cachedKey = key;
                    find.cachedRows = findProc.hits.slice();
                }
                find.setRequestState(RequestState.settle(
                    find.requestState, key, generation));
                if (succeeded)
                    Dispatcher.notifyAsync();
            }
            find.startPending();
        }
    }

    Component.onCompleted: {
        availProc.running = true;
        Dispatcher.register(find);
    }
}
