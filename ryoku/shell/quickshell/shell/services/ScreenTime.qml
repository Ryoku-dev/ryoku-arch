pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import shell.services

/**
 * Local screen-time tracking. Every few seconds it asks Hyprland for the
 * focused window's app class and banks the elapsed time against today's bucket
 * (per app, per hour, and a running total). "Active" means a real app is
 * focused; nothing syncs and nothing leaves the box. History persists to
 * ~/.local/state/ryoku/screentime.json (last 30 days) so a shell restart
 * resumes the same day.
 */
Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"
    readonly property int sampleSec: 10

    // { "YYYY-MM-DD": { total: int, apps: { class: sec }, hours: [24 ints] } }
    property var days: ({})
    property string today: ""
    property bool dirty: false

    readonly property var todayEntry: root.days[root.today] || null
    readonly property int activeToday: root.todayEntry ? (root.todayEntry.total || 0) : 0

    // Top apps today, resolved to a display name + icon, most used first.
    readonly property var topApps: {
        const e = root.todayEntry;
        if (!e || !e.apps)
            return [];
        const arr = [];
        for (const cls in e.apps)
            arr.push({ cls: cls, seconds: e.apps[cls] });
        arr.sort((a, b) => b.seconds - a.seconds);
        return arr.slice(0, 6).map(function (a) {
            const entry = (typeof DesktopEntries !== "undefined" && DesktopEntries.heuristicLookup)
                ? DesktopEntries.heuristicLookup(a.cls) : null;
            return {
                cls: a.cls,
                seconds: a.seconds,
                name: (entry && entry.name) ? entry.name : root.prettyClass(a.cls),
                icon: (entry && entry.icon) ? Icons.path(entry.icon, true) : ""
            };
        });
    }
    readonly property int topSeconds: root.topApps.length > 0 ? root.topApps[0].seconds : 1

    // Last seven days including today, oldest first, for the trend bars.
    readonly property var weekly: {
        const out = [];
        const now = new Date();
        const dow = ["S", "M", "T", "W", "T", "F", "S"];
        for (let i = 6; i >= 0; i--) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
            const key = root.dateKey(d);
            const e = root.days[key];
            out.push({ key: key, label: dow[d.getDay()], total: e ? (e.total || 0) : 0, isToday: i === 0 });
        }
        return out;
    }
    readonly property int weeklyMax: {
        let m = 1;
        for (let i = 0; i < root.weekly.length; i++)
            m = Math.max(m, root.weekly[i].total);
        return m;
    }

    function dateKey(d) {
        const m = ("0" + (d.getMonth() + 1)).slice(-2);
        const day = ("0" + d.getDate()).slice(-2);
        return d.getFullYear() + "-" + m + "-" + day;
    }
    function prettyClass(c) {
        const s = ("" + c).split(".").pop();
        return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : c;
    }
    function fmtDuration(sec) {
        sec = Math.max(0, Math.floor(sec));
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        if (h > 0)
            return I18n.tr("%1h %2m").arg(h).arg(m);
        if (m > 0)
            return I18n.tr("%1m").arg(m);
        return I18n.tr("%1s").arg(sec);
    }
    function isRealApp(c) {
        return !!c && !/^(ryoku|quickshell|org\.quickshell)/i.test(c);
    }
    function zeros24() {
        const a = [];
        for (let i = 0; i < 24; i++)
            a.push(0);
        return a;
    }

    // Bank one sample against the focused app. Rebuilds the day map with fresh
    // references so the derived bindings (total, top apps, week) re-evaluate.
    function accrue(c) {
        if (!root.isRealApp(c))
            return;
        const key = root.dateKey(new Date());
        const prev = root.days[key] || { total: 0, apps: ({}), hours: root.zeros24() };
        const e = {
            total: (prev.total || 0) + root.sampleSec,
            apps: Object.assign({}, prev.apps),
            hours: (prev.hours && prev.hours.length === 24) ? prev.hours.slice() : root.zeros24()
        };
        e.apps[c] = (e.apps[c] || 0) + root.sampleSec;
        const hr = new Date().getHours();
        e.hours[hr] = (e.hours[hr] || 0) + root.sampleSec;
        const d = Object.assign({}, root.days);
        d[key] = e;
        root.days = d;
        root.today = key;
        root.dirty = true;
    }

    function prune() {
        const keys = Object.keys(root.days).sort();
        if (keys.length <= 30)
            return;
        const d = Object.assign({}, root.days);
        for (let i = 0; i < keys.length - 30; i++)
            delete d[keys[i]];
        root.days = d;
    }
    function persist() {
        root.prune();
        file.setText(JSON.stringify({ days: root.days }));
        root.dirty = false;
    }
    function load(text) {
        try {
            const j = JSON.parse(text || "{}");
            root.days = (j && j.days) ? j.days : ({});
        } catch (e) {
            root.days = ({});
        }
        const key = root.dateKey(new Date());
        root.today = key;
        if (!root.days[key]) {
            const d = Object.assign({}, root.days);
            d[key] = { total: 0, apps: ({}), hours: root.zeros24() };
            root.days = d;
        }
    }

    Timer {
        interval: root.sampleSec * 1000
        running: true
        repeat: true
        onTriggered: probe.running = true
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: if (root.dirty) root.persist()
    }

    // Direct query beats Quickshell's event-driven activeToplevel, which stays
    // empty here until a focus change and is not bound by every bar style.
    Process {
        id: probe
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector { id: probeOut }
        onExited: {
            var c = "";
            try {
                var o = JSON.parse(probeOut.text || "{}");
                c = (o && (o.class || o.initialClass)) || "";
            } catch (e) {}
            root.accrue(c);
        }
    }

    Process {
        command: ["mkdir", "-p", root.stateDir]
        running: true
    }
    FileView {
        id: file
        path: root.stateDir + "/screentime.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.load(file.text())
        onLoadFailed: root.load("{}")
    }

    Component.onDestruction: if (root.dirty) root.persist()
}
