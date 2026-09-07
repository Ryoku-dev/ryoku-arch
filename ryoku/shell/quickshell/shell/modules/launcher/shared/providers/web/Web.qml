import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import "../../Singletons"
import "engines.js" as Engines
import "ddg.js" as Ddg
import ".."

// Web-search provider: the "?" prefix opens a search in the browser, with
// "!bang" shorthands (?!yt cats) picking a site. Also offered as a low-ranked
// fallback on a plain query so an unmatched search can still go to the web.
//
// Under a plain "?" query (no bang) we also fetch a DuckDuckGo instant answer
// in the background and expose it via the `answer` property so the launcher
// can render an AnswerPanel above the fallback row. A "!bang" skips the fetch
// because the user has already picked the target site; hitting the network
// would only add latency to what is meant to be a snap redirect.
Provider {
    id: web

    providerId: "web"
    prefix: "?"

    // Async DDG state. cachedQuery/cachedAnswer are the last resolved fetch;
    // pendingQuery is the debounce baton so revision-driven re-queries do not
    // restart an already-scheduled request; liveQuery is what the user is
    // actually looking at right now, so a stale cached answer for the previous
    // keystroke reads as unavailable while the next fetch is in flight.
    property string cachedQuery: ""
    property var cachedAnswer: ({ available: false, heading: "", text: "", source: "", url: "" })
    property string pendingQuery: ""
    property string liveQuery: ""

    readonly property var answer: (liveQuery.length > 0 && liveQuery === cachedQuery)
        ? cachedAnswer
        : ({ available: false, heading: "", text: "", source: "", url: "" })

    // A query becomes a single "search the web" row. Scored low so it ranks
    // below real app matches in the default fan-out, and stands alone under
    // the "?" prefix as the always-there fallback so Enter runs a search even
    // before (or without) an instant answer.
    function rowFor(text) {
        return {
            id: "web:" + text,
            title: text,
            subtitle: I18n.tr("Search %1").arg(Engines.engineName(text, "g")),
            icon: "",
            type: "Web",
            score: 90,
            actions: [{
                id: "search",
                name: I18n.tr("Search"),
                icon: "",
                execute: function () { Qt.openUrlExternally(Engines.buildUrl(text, "g")); }
            }]
        };
    }

    function query(text, prefix) {
        if (!text || text.length === 0)
            return [];
        if (prefix === "?") {
            web.liveQuery = text;
            var parsed = Engines.parseBang(text);
            var knownBang = parsed.bang && Engines.ENGINES[parsed.bang];
            // Only schedule a fetch when the query is new for us; a same-query
            // re-run (revision bump from another async provider) must not
            // restart the timer or the network.
            if (!knownBang && text !== web.cachedQuery && text !== web.pendingQuery) {
                web.pendingQuery = text;
                ddgDebounce.restart();
            }
        }
        return [rowFor(text)];
    }

    Timer {
        id: ddgDebounce
        interval: 200
        repeat: false
        onTriggered: {
            ddgProc.q = web.pendingQuery;
            ddgProc.running = false;
            ddgProc.running = true;
        }
    }

    Process {
        id: ddgProc
        onRunningChanged: Dispatcher.setBusy("web", running)
        property string q: ""
        command: ["curl", "-s", "--max-time", "8", Ddg.apiUrl(q)]
        stdout: StdioCollector {
            id: ddgOut
        }
        onExited: (code, status) => {
            // killed = superseded by a newer keystroke; non-zero = network
            // failure. Cache neither, so the same query can retry instead of
            // pinning an empty answer for the session.
            if (status !== 0 || code !== 0)
                return;
            web.cachedAnswer = Ddg.parseAnswer(ddgOut.text);
            web.cachedQuery = ddgProc.q;
            Dispatcher.notifyAsync();
        }
    }

    Component.onCompleted: Dispatcher.register(web);
}
