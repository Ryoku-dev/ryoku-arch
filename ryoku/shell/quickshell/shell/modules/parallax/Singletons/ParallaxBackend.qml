pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Availability and provisioning for the standalone parallax engine
// (docs/parallax.md); own state dir, no dependency on the depth install.
Singleton {
    id: root

    readonly property string bin: {
        const d = Quickshell.env("RYOKU_SHELL_DIR");
        return (d && d.length > 0) ? d + "/scripts/ryoku-parallax-engine" : "ryoku-parallax-engine";
    }

    property bool available: false
    property bool installing: false
    property bool removing: false
    property var models: []
    property string progress: ""

    function recheck() {
        checkProc.running = false;
        checkProc.running = true;
    }
    function install(model) {
        if (root.installing)
            return;
        root.installing = true;
        root.progress = "";
        installProc.command = (model && model.length > 0)
            ? [root.bin, "install", model] : [root.bin, "install"];
        installProc.running = false;
        installProc.running = true;
    }
    function remove(model) {
        if (root.removing || root.installing || !model || model.length === 0)
            return;
        root.removing = true;
        root.progress = "";
        removeProc.command = [root.bin, "remove", model];
        removeProc.running = false;
        removeProc.running = true;
    }
    function hasModel(m) {
        return (root.models || []).indexOf(m) >= 0;
    }
    function openFolder() {
        openProc.running = false;
        openProc.running = true;
    }
    function openManualFolderFor(wallPath) {
        if (!wallPath) return;
        const base = wallPath.split("/").pop();
        const stem = base.replace(/\.[^.]+$/, "");
        const folder = (Quickshell.env("HOME") || "") + "/Pictures/Parallax/" + stem;
        // Pass the folder as a positional argument ($1) so a path with shell
        // metacharacters cannot be interpreted as part of the command.
        openProc.command = ["sh", "-c",
            "mkdir -p \"$1\" && (nautilus \"$1\" 2>/dev/null || gio open \"$1\" 2>/dev/null || xdg-open \"$1\")",
            "sh", folder];
        openProc.running = false;
        openProc.running = true;
    }

    property bool checked: false

    Process {
        id: checkProc
        command: [root.bin, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.available = ("" + this.text).trim() === "available";
                if (root.available)
                    modelsProc.running = true;
                else
                    root.checked = true;
            }
        }
    }
    Process {
        id: modelsProc
        command: [root.bin, "models"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = ("" + this.text).split("\n");
                for (var i = 0; i < lines.length; i++) {
                    const t = lines[i].trim();
                    if (t.length > 0)
                        out.push(t);
                }
                root.models = out;
                root.checked = true;
            }
        }
    }
    Process {
        id: installProc
        stdout: SplitParser { onRead: line => root.progress = line }
        stderr: SplitParser { onRead: line => root.progress = line }
        onExited: {
            root.installing = false;
            root.recheck();
        }
    }
    Process {
        id: removeProc
        stdout: SplitParser { onRead: line => root.progress = line }
        stderr: SplitParser { onRead: line => root.progress = line }
        onExited: {
            root.removing = false;
            root.recheck();
        }
    }
    Process {
        id: openProc
        command: ["sh", "-c", "d=\"$HOME/Pictures/Parallax\"; mkdir -p \"$d\"; nautilus \"$d\" 2>/dev/null || gio open \"$d\" 2>/dev/null || xdg-open \"$d\""]
    }

    Component.onCompleted: root.recheck()
}
