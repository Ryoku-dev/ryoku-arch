pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

// One source for the shipped Ryoku edition strings every surface shows. The CLI
// already knows how to resolve the version from a checkout and from an installed
// package, so QML asks it once and parses the prerelease tag.
Singleton {
    id: root

    property string rawVersion: ""

    readonly property string editionIndex: {
        const parsed = root.parseVersion(root.rawVersion);
        return parsed.index;
    }

    readonly property string editionNumber: {
        const parsed = root.parseVersion(root.rawVersion);
        return parsed.number;
    }

    readonly property string editionSummary: {
        return root.editionNumber.length > 0
            ? root.editionIndex + " · " + root.editionNumber
            : root.editionIndex;
    }

    function parseVersion(text) {
        const clean = (text || "").trim();
        const dash = clean.indexOf("-");
        if (dash < 0)
            return { index: I18n.tr("STABLE"), number: "" };

        const prerelease = clean.slice(dash + 1).trim();
        const parts = prerelease.split(".");
        const tail = parts.length > 0 ? parts[parts.length - 1] : "";
        const head = parts.slice(0, -1).join(" ").trim();
        if (!/^\d+$/.test(tail) || head.length === 0)
            return { index: I18n.tr("STABLE"), number: "" };
        return { index: head.toUpperCase(), number: tail };
    }

    function refresh() {
        versionProc.running = true;
    }

    Process {
        id: versionProc
        command: ["sh", "-c", "ryoku version 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.rawVersion = this.text.trim() }
    }

    Component.onCompleted: refresh()
}
