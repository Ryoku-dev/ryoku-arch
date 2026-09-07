pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

// The passthrough lane: GPU-passthrough VMs shown only through Looking Glass, a
// world apart from the quickemu yard. One dGPU is bound to the guest, so the
// engine first tells us whether the host is even capable (`ready`) and, if not,
// why (`blocker`). Every verb speaks to `ryovm lg`, which answers in JSON. The
// list is the facts; a sticky fault surfaces the engine's stderr, in the same
// grammar Vm.qml uses, so a failed bind never evaporates before it's read.
Singleton {
    id: root

    // a shown page flips this; the ~5s poll gates on it (mirrors Remotes.active).
    property bool poll: false

    property bool ready: false           // the host can bind a dGPU right now
    property string blocker: ""          // one sentence: why it can't, when it can't
    property var machines: []
    property bool loading: false
    property bool busy: false            // a mutating verb is in flight

    // the receipt / fault surface, exactly Vm's grammar: a receipt lands on
    // status, a fault stays sticky until dismissed or the next verb succeeds.
    property string status: ""
    property string fault: ""            // first line, for the fault row
    property string faultDetail: ""      // full engine stderr, un-truncated

    function raiseFault(text) {
        var t = ("" + text).trim();
        if (t.length === 0)
            return;
        fault = t.split("\n")[0];
        faultDetail = t;
        status = "";
    }
    function clearFault() { fault = ""; faultDetail = ""; }
    function info(msg) { status = msg; }

    Component.onCompleted: root.refresh()

    function refresh() { listProc.running = true; }

    function create(name, iso, os, diskGb, ramMb) {
        var cmd = ["ryovm", "lg", "create", "--name", name, "--iso", iso, "--os", os];
        if (diskGb > 0) cmd = cmd.concat(["--disk-gb", String(diskGb)]);
        if (ramMb > 0) cmd = cmd.concat(["--ram-mb", String(ramMb)]);
        run(cmd);
    }
    // start binds the dGPU and opens looking-glass-client in one go; a
    // lookingGlass:false receipt means the viewer binary is missing.
    function launch(name) { run(["ryovm", "lg", "start", "--name", name]); }
    function stop(name) { run(["ryovm", "lg", "stop", "--name", name]); }
    function remove(name, deleteDisk) {
        var cmd = ["ryovm", "lg", "remove", "--name", name];
        if (deleteDisk === true)
            cmd = cmd.concat(["--delete-disk", "true"]);
        run(cmd);
    }

    // one lifecycle runner for every mutating verb: hold on stderr, and on a
    // clean exit fold the JSON receipt to a human line before reloading the list.
    function run(cmd) {
        if (busy)
            return;
        busy = true;
        runProc.errText = "";
        runProc.outText = "";
        runProc.command = cmd;
        runProc.running = true;
    }

    function _receipt(o) {
        if (!o)
            return "";
        if (o.started === true)
            return o.lookingGlass === false
                ? I18n.tr("Started %1, but looking-glass-client is not installed. Install it to see the guest.").arg(o.name || "")
                : I18n.tr("Opening %1 in Looking Glass").arg(o.name || "");
        if (o.defined === true)
            return (o.virtio === true ? I18n.tr("Defined %1 with the VirtIO driver CD attached") : I18n.tr("Defined %1")).arg(o.name || "");
        if (o.removed === true)
            return o.diskDeleted === true
                ? I18n.tr("Removed %1 and deleted its disk").arg(o.name || "")
                : I18n.tr("Removed %1").arg(o.name || "");
        if (o.stopped === true)
            return I18n.tr("Stopped");
        return "";
    }

    Process {
        id: listProc
        command: ["ryovm", "lg", "list"]
        onStarted: root.loading = true
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    var o = JSON.parse(this.text);
                    root.ready = o.ready === true;
                    root.blocker = o.blocker || "";
                    root.machines = Array.isArray(o.machines) ? o.machines : [];
                } catch (e) {
                    root.ready = false;
                    root.blocker = "";
                    root.machines = [];
                }
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.loading = false;
                root.ready = false;
                root.machines = [];
            }
        }
    }

    Process {
        id: runProc
        property string errText: ""
        property string outText: ""
        stderr: StdioCollector { onStreamFinished: runProc.errText = this.text }
        stdout: StdioCollector { onStreamFinished: runProc.outText = this.text }
        onExited: (code) => {
            root.busy = false;
            if (code !== 0) {
                root.raiseFault(runProc.errText.trim().length > 0
                    ? runProc.errText.trim()
                    : I18n.tr("Command failed (exit %1)").arg(code));
            } else {
                root.clearFault();
                var line = "";
                try { line = root._receipt(JSON.parse(runProc.outText)); } catch (e) {}
                if (line.length > 0)
                    root.info(line);
                root.refresh();
            }
        }
    }

    // while a passthrough page is on screen, keep the list fresh on a ~5s cadence
    // so a VM settles to its new state (running after a launch, gone after a
    // remove) on its own; a hidden page costs nothing.
    Timer {
        interval: 5000
        repeat: true
        running: root.poll
        onTriggered: root.refresh()
    }
}
