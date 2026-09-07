import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import "../../Singletons"
import "calc.js" as Calc
import "../requeststate.js" as RequestState
import ".."

// Calculator provider: evaluates the query with qalc. Routed by the "=" prefix,
// and offered in the default fan-out when the query looks numeric. qalc runs
// async, so query() returns the cached row for the current text and starts a
// fresh evaluation (debounced) when the text changes; the cached row repaints via
// Dispatcher.notifyAsync once qalc resolves.
Provider {
    id: calc

    providerId: "calc"
    prefix: "="
    defaultProvider: false
    numericFallback: true

    property string cachedText: ""
    property string cachedResult: ""
    property string pendingText: ""
    property int pendingGeneration: 0
    property bool debounceReady: false
    property var requestState: RequestState.initial()

    function setRequestState(next) {
        if (next === calc.requestState)
            return false;
        var wasBusy = RequestState.isBusy(calc.requestState);
        var nowBusy = RequestState.isBusy(next);
        calc.requestState = next;
        if (wasBusy !== nowBusy)
            Dispatcher.setBusy("calc", nowBusy);
        return true;
    }

    function cancelProcess() {
        if (proc.inFlight)
            proc.running = false;
    }

    function clearRequest() {
        var next = RequestState.clear(calc.requestState);
        if (next === calc.requestState)
            return;
        calc.setRequestState(next);
        debounce.stop();
        calc.debounceReady = false;
        calc.cancelProcess();
    }

    function adoptCached(key) {
        var next = RequestState.adoptSettled(calc.requestState, key);
        if (next === calc.requestState)
            return;
        calc.setRequestState(next);
        debounce.stop();
        calc.debounceReady = false;
        calc.cancelProcess();
    }

    function schedule(text) {
        var next = RequestState.begin(calc.requestState, text);
        if (next === calc.requestState)
            return;
        calc.setRequestState(next);
        calc.pendingText = text;
        calc.pendingGeneration = next.generation;
        calc.debounceReady = false;
        debounce.restart();
        calc.cancelProcess();
    }

    function startPending() {
        if (!calc.debounceReady || proc.inFlight)
            return;
        var next = RequestState.markRunning(
            calc.requestState, calc.pendingText, calc.pendingGeneration);
        if (next === calc.requestState)
            return;
        calc.debounceReady = false;
        calc.setRequestState(next);
        proc.expr = calc.pendingText;
        proc.requestGeneration = calc.pendingGeneration;
        proc.out = "";
        proc.inFlight = true;
        proc.didStart = false;
        proc.running = true;
    }

    function rowFor(expr, result) {
        return {
            id: "calc:" + expr,
            title: result,
            subtitle: expr,
            icon: "",
            type: "Calc",
            score: -10,   // a valid calc result outranks app matches
            actions: [{
                id: "copy",
                name: I18n.tr("Copy"),
                icon: "",
                execute: function () { Quickshell.clipboardText = result; }
            }]
        };
    }

    function query(text) {
        var t = (text || "").trim();
        if (t.length === 0) {
            calc.clearRequest();
            return [];
        }
        if (t === calc.cachedText) {
            calc.adoptCached(t);
            return calc.cachedResult.length ? [rowFor(t, calc.cachedResult)] : [];
        }
        calc.schedule(t);
        return [];
    }

    Timer {
        id: debounce
        interval: 60
        repeat: false
        onTriggered: {
            calc.debounceReady = true;
            calc.startPending();
        }
    }

    Process {
        id: proc
        property string expr: ""
        property int requestGeneration: 0
        property bool inFlight: false
        property bool didStart: false
        property string out: ""
        command: [Config.scriptsDir + "ryoku-cmd-calc", expr]
        stdout: SplitParser {
            onRead: data => proc.out += data + "\n"
        }
        onStarted: proc.didStart = true
        onRunningChanged: {
            if (!running && proc.inFlight && !proc.didStart) {
                var expr = proc.expr;
                var generation = proc.requestGeneration;
                proc.inFlight = false;
                if (calc.requestState.phase === "running"
                        && RequestState.isCurrent(
                            calc.requestState, expr, generation)) {
                    calc.setRequestState(RequestState.settle(
                        calc.requestState, expr, generation));
                }
                calc.startPending();
            }
        }
        onExited: (code, status) => {
            var expr = proc.expr;
            var generation = proc.requestGeneration;
            proc.inFlight = false;
            var current = calc.requestState.phase === "running"
                && RequestState.isCurrent(
                    calc.requestState, expr, generation);
            if (current) {
                if (status === 0) {
                    var result = Calc.parseResult(proc.out);
                    calc.cachedText = expr;
                    calc.cachedResult = result ? result : "";
                }
                calc.setRequestState(RequestState.settle(
                    calc.requestState, expr, generation));
                if (status === 0)
                    Dispatcher.notifyAsync();
            }
            calc.startPending();
        }
    }

    Component.onCompleted: Dispatcher.register(calc);
}
