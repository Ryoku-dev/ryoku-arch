pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import shell.services
import Ryoku.Ui.Singletons

// The desktop's 10-band equalizer, as the now-playing card sees it. `ryoku-eq`
// owns the audio graph (a WirePlumber smart filter in front of the default sink,
// see the script's header); this owns the state the UI binds to.
//
// Every mutation is applied here first and shipped to the script second. A band
// gain reaches the biquads in one param write, so the slider must not wait for a
// round trip to look like it moved -- and the reload below is deferred past the
// write so the script's answer can never snap a slider back under the finger.
Singleton {
    id: root

    readonly property string bin: (Quickshell.env("RYOKU_SHELL_DIR") || "").length > 0
        ? Quickshell.env("RYOKU_SHELL_DIR") + "/scripts/ryoku-eq"
        : "ryoku-eq"

    readonly property int bandCount: 10
    // ISO octave centres, the labels the card prints under each slider.
    readonly property var bandLabels: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property int range: 12          // ±dB a band can travel
    readonly property var presets: ["Flat", "Bass", "Treble", "Vocal", "Pop", "Rock", "Jazz", "Classic"]

    property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string preset: "Flat"
    property bool on: false
    // The filter is in the graph. Distinct from `on`: the script starts the node
    // asynchronously, so the UI reads `on` for intent and this for the truth.
    property bool running: false

    function gainAt(i) {
        var g = root.gains;
        return (i >= 0 && i < g.length && g[i] !== undefined) ? g[i] : 0;
    }

    // The preset name the script stores is an identifier, so every label is spelt
    // out here as a literal: the i18n extractor reads source, and a tr() around a
    // variable would leave all eight strings out of every catalogue.
    function presetLabel(name) {
        switch (name) {
        case "Flat":    return I18n.tr("Flat");
        case "Bass":    return I18n.tr("Bass");
        case "Treble":  return I18n.tr("Treble");
        case "Vocal":   return I18n.tr("Vocal");
        case "Pop":     return I18n.tr("Pop");
        case "Rock":    return I18n.tr("Rock");
        case "Jazz":    return I18n.tr("Jazz");
        case "Classic": return I18n.tr("Classic");
        case "Custom":  return I18n.tr("Custom");
        }
        return name;
    }

    function run(args) {
        eqProc.running = false;
        eqProc.command = [root.bin].concat(args);
        eqProc.running = true;
        reload.restart();
    }

    function setBand(i, db) {
        var v = Math.max(-root.range, Math.min(root.range, Math.round(db)));
        var next = root.gains.slice();
        next[i] = v;
        root.gains = next;
        root.preset = "Custom";
        root.on = true;
        root.run(["set-band", "" + (i + 1), "" + v]);
    }

    function applyPreset(name) {
        root.preset = name;
        root.run(["preset", name]);
    }

    function setOn(enabled) {
        root.on = enabled;
        root.run([enabled ? "on" : "off"]);
    }

    // --- reading the script's state ------------------------------------------

    function ingest(text) {
        var s = ("" + text).trim();
        if (!s.length)
            return;
        var d;
        try {
            d = JSON.parse(s);
        } catch (e) {
            return;
        }
        var g = [];
        for (var i = 1; i <= root.bandCount; i++)
            g.push(Number(d["b" + i]) || 0);
        root.gains = g;
        root.preset = ("" + (d.preset || "Flat"));
        root.on = d.on === true;
        // `running` is the graph's answer, which only `ryoku-eq get` reports; the
        // state file has no opinion on it and must not clear it.
        if (d.running !== undefined)
            root.running = d.running === true;
    }

    Process {
        id: eqProc
        stdout: StdioCollector { onStreamFinished: root.ingest(this.text) }
        stderr: StdioCollector {}
    }

    Process {
        id: getProc
        command: [root.bin, "get"]
        stdout: StdioCollector { onStreamFinished: root.ingest(this.text) }
        stderr: StdioCollector {}
    }

    function refresh() {
        getProc.running = false;
        getProc.running = true;
    }

    Timer {
        id: reload
        interval: 400
        onTriggered: root.refresh()
    }

    // The script is the state's owner, and it is drivable from a shell, a keybind
    // or a second monitor's card. Watching the file it writes is what keeps every
    // reader honest: without it the card only ever showed the curve it had set
    // itself, and a `ryoku-eq preset ...` from anywhere else left it displaying a
    // curve the speakers had stopped playing.
    FileView {
        id: stateFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
            + "/ryoku/equalizer.json"
        watchChanges: true
        printErrors: false
        onFileChanged: stateFile.reload()
        onLoaded: root.ingest(stateFile.text())
    }

    // A smart filter names the sink it sits in front of, so a new default output
    // (headphones in, a Bluetooth speaker connecting) has to be handed to the
    // filter or the equalizer would quietly stop applying. The script no-ops
    // unless the equalizer is on.
    Connections {
        target: Audio
        function onSinkChanged() { retarget.restart() }
    }

    Timer {
        id: retarget
        interval: 700
        onTriggered: root.run(["retarget"])
    }

    // Re-arm the graph on shell start: the filter lives in a systemd user unit
    // that nothing else starts, so a login (or a shell restart after a crash)
    // relies on this to bring back the curve the user left on.
    Component.onCompleted: root.run(["apply"])
}
