import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import "../../Singletons"
import ".."
import "recent.js" as RecentData

Provider {
    id: recent

    providerId: "recent"
    defaultProvider: false

    property var cachedRows: []
    property int generation: 0
    property var queuedRequest: null
    property bool providerBusy: false
    property int availabilityState: 0

    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME")
        || ((Quickshell.env("HOME") || ".") + "/.local/share")

    function setProviderBusy(busy) {
        if (recent.providerBusy === busy)
            return;
        recent.providerBusy = busy;
        Dispatcher.setBusy("recent", busy);
    }

    function publish(request, rows) {
        if (request.generation !== recent.generation)
            return;
        recent.cachedRows = RecentData.sortRecent(rows, 40);
        Dispatcher.notifyAsync();
        request.published = true;
    }

    function acceptText(text) {
        var request = {
            generation: ++recent.generation,
            candidates: RecentData.parseXbel(text),
            published: false
        };

        if (request.candidates.length === 0)
            recent.publish(request, []);

        if (validation.running) {
            recent.queuedRequest = request;
            return;
        }
        recent.startRequest(request);
    }

    function settleQueue() {
        var next = recent.queuedRequest;
        recent.queuedRequest = null;
        if (next)
            recent.startRequest(next);
        else
            recent.setProviderBusy(false);
    }

    function finishAvailability(available) {
        recent.availabilityState = available ? 1 : -1;
        recent.settleQueue();
    }

    function startRequest(request) {
        recent.queuedRequest = null;
        if (request.candidates.length === 0) {
            if (!request.published)
                recent.publish(request, []);
            recent.setProviderBusy(false);
            return;
        }
        if (recent.availabilityState === 0) {
            recent.queuedRequest = request;
            recent.setProviderBusy(true);
            return;
        }
        if (recent.availabilityState < 0) {
            recent.publish(request, []);
            recent.settleQueue();
            return;
        }

        validation.requestGeneration = request.generation;
        validation.candidates = request.candidates.slice();
        validation.hits = [];
        validation.command = ["find"].concat(
            validation.candidates.map(function (row) { return row.path; })
        ).concat(["-maxdepth", "0", "-print0"]);
        recent.setProviderBusy(true);
        validation.awaitingCompletion = true;
        validation.running = true;
    }

    function completeRequest(exitCode, exitStatus) {
        var validRun = exitStatus === 0 && (exitCode === 0 || exitCode === 1);
        if (validation.requestGeneration === recent.generation) {
            if (!validRun) {
                recent.publish({
                    generation: validation.requestGeneration,
                    published: false
                }, []);
            } else {
                recent.publish({
                    generation: validation.requestGeneration,
                    published: false
                }, RecentData.filterExisting(validation.candidates, validation.hits));
            }
        }

        recent.settleQueue();
    }

    function failedValidation(requestGeneration) {
        recent.availabilityState = -1;
        if (requestGeneration === recent.generation) {
            recent.publish({
                generation: requestGeneration,
                published: false
            }, []);
        }
        validation.candidates = [];
        validation.hits = [];
        recent.settleQueue();
    }

    function rowFor(candidate, rank) {
        var uri = candidate.uri;
        var path = candidate.path;
        var folder = RecentData.parentUri(path);
        return {
            id: "recent:" + uri,
            title: candidate.title,
            subtitle: path,
            icon: "",
            type: "Recent",
            score: rank,
            actions: [
                {
                    id: "open",
                    name: I18n.tr("Open"),
                    icon: "",
                    execute: function () { Qt.openUrlExternally(uri); }
                },
                {
                    id: "reveal",
                    name: I18n.tr("Reveal"),
                    icon: "",
                    execute: function () { Qt.openUrlExternally(folder); }
                }
            ]
        };
    }

    function allRows(filter) {
        var needle = String(filter || "").trim().toLowerCase();
        var source = needle.length === 0 ? recent.cachedRows
            : recent.cachedRows.filter(function (row) {
                return row.title.toLowerCase().indexOf(needle) !== -1
                    || row.path.toLowerCase().indexOf(needle) !== -1;
            });
        return source.map(function (row, index) {
            return recent.rowFor(row, index);
        });
    }

    function query(text) {
        return recent.allRows(text);
    }

    FileView {
        id: store
        path: recent.dataHome + "/recently-used.xbel"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: recent.acceptText(store.text())
        onLoadFailed: recent.acceptText("")
    }

    Process {
        id: availability

        property bool awaitingCompletion: false

        command: ["find", "--version"]
        stdout: SplitParser {}
        stderr: SplitParser {}

        onExited: (exitCode, exitStatus) => {
            availability.awaitingCompletion = false;
            recent.finishAvailability(exitStatus === 0 && exitCode === 0);
        }
        onRunningChanged: {
            if (!running && availability.awaitingCompletion) {
                availability.awaitingCompletion = false;
                recent.finishAvailability(false);
            }
        }
    }

    Process {
        id: validation

        property int requestGeneration: 0
        property var candidates: []
        property var hits: []
        property bool awaitingCompletion: false

        stdout: SplitParser {
            splitMarker: "\u0000"
            onRead: data => {
                if (data.length)
                    validation.hits.push(data);
            }
        }
        stderr: SplitParser {}

        onExited: (exitCode, exitStatus) => {
            validation.awaitingCompletion = false;
            recent.completeRequest(exitCode, exitStatus);
        }
        onRunningChanged: {
            if (!running && validation.awaitingCompletion) {
                validation.awaitingCompletion = false;
                recent.failedValidation(validation.requestGeneration);
            }
        }
    }

    Component.onCompleted: {
        Dispatcher.register(recent);
        availability.awaitingCompletion = true;
        availability.running = true;
    }
}
