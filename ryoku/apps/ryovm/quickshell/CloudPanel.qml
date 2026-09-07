pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// The INSTANT lane's right pane: pick a prebuilt cloud OS, choose burn vs keeper,
// pick the toolset baked in on first boot, and press one key to get an ssh-able
// machine with the ryoku burn account, no installer. Reuses the create download
// bar (instant streams the same phases). The sheet is the taxonomy: a disposable
// sw cell, the toolset as a true multi, an extra-packages field.
Item {
    id: pane

    property var os: null              // a cloudList entry
    property bool disposableRun: true  // instant machines default to burn

    // clip (OSC 52 host clipboard) is always baked; spice adds the console
    // clipboard. heavy tools reinstall on every disposable boot, the steer
    // points those users at templates.
    property var toolDefs: [
        { id: "git", label: "git" }, { id: "build", label: I18n.tr("build tools") },
        { id: "python", label: "python" }, { id: "node", label: "node/npm" },
        { id: "go", label: "go" }, { id: "rust", label: "rust" },
        { id: "docker", label: "docker", heavy: true }, { id: "podman", label: "podman", heavy: true },
        { id: "jq", label: "jq" }, { id: "net", label: "curl/wget" },
        { id: "cli", label: "htop·tmux·vim·rg" }, { id: "spice", label: I18n.tr("SPICE clipboard") }
    ]
    readonly property var toolLabels: pane.toolDefs.map(t => t.label)
    property var pickedIds: (Vm.settings.tools || "").split(",").filter(s => s.length > 0)
    readonly property var pickedLabels: pane.toolDefs.filter(t => pane.pickedIds.indexOf(t.id) >= 0).map(t => t.label)
    function toggleLabel(label) {
        var def = pane.toolDefs.find(t => t.label === label);
        if (!def) return;
        var i = pane.pickedIds.indexOf(def.id);
        if (i < 0) pane.pickedIds.push(def.id); else pane.pickedIds.splice(i, 1);
        pane.pickedIds = pane.pickedIds.slice();
        Vm.settings.tools = pane.pickedIds.join(",");
        Vm.saveSettings();
    }
    readonly property bool heavyDisposable: pane.disposableRun
        && pane.toolDefs.some(t => t.heavy && pane.pickedIds.indexOf(t.id) >= 0)

    // empty state.
    Column {
        anchors.centerIn: parent
        spacing: Tokens.s3
        visible: pane.os === null
        Mark { anchors.horizontalCenter: parent.horizontalCenter; size: 96 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            width: 320
            wrapMode: Text.WordWrap
            text: I18n.tr("Pick a system for an instant machine: prebuilt, no installer, logs in as ryoku.")
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: 12
        }
    }

    // active downloads: the shared stack, so several instant builds run at once.
    DownloadStack {
        id: dlStack
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
    }

    // chosen OS: the create sheet.
    Item {
        anchors.top: dlStack.visible ? dlStack.bottom : parent.top
        anchors.topMargin: dlStack.visible ? Tokens.s4 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: pane.os !== null

        // hero: brand mark, name, the burn-account line (mono, file truth).
        Rectangle {
            id: hero
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(150, parent.height * 0.26)
            color: "transparent"
            radius: Tokens.radius
            border.width: Tokens.border
            border.color: Tokens.line
            antialiasing: false

            RegMark { x: parent.width - width - 16; y: 15; size: 12; tint: Tokens.inkFaint }

            Column {
                anchors.centerIn: parent
                spacing: Tokens.s3
                OsIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64; height: 64; size: 64
                    slug: pane.os ? pane.os.os : ""
                    label: pane.os ? pane.os.name : ""
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pane.os ? pane.os.name : ""
                    color: Tokens.ink
                    font.family: Tokens.display
                    font.pixelSize: 22
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (pane.os ? "~" + pane.os.size + " · " : "") + I18n.tr("logs in as ryoku / ryoku")
                    color: Tokens.inkFaint
                    font.family: Tokens.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }
            }
        }

        Flickable {
            anchors.top: hero.bottom
            anchors.topMargin: Tokens.s4
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: createRow.top
            anchors.bottomMargin: Tokens.s4
            contentWidth: width
            contentHeight: lower.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollRail {}

            Column {
                id: lower
                width: parent.width - 8
                spacing: Tokens.s4

                Section {
                    id: sect
                    width: parent.width
                    title: I18n.tr("Provision")

                    Cell {
                        width: sect.span(Spans.of("sw"))
                        block: false
                        controlWidth: Spans.inlineWidth("sw", 0, width)
                        label: I18n.tr("Disposable")
                        value: pane.disposableRun ? I18n.tr("BURN") : I18n.tr("KEEP")
                        desc: pane.disposableRun
                            ? I18n.tr("Every boot re-provisions the ryoku account, factory-fresh.")
                            : I18n.tr("A normal machine you can seal and reuse.")
                        Sw {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: pane.disposableRun
                            onToggled: (v) => pane.disposableRun = v
                        }
                    }

                    Cell {
                        width: sect.span(Spans.of("multi"))
                        height: Spans.rows("multi") * Tokens.cellH + (Spans.rows("multi") - 1) * Tokens.s2
                        block: true
                        label: I18n.tr("Toolset")
                        value: String(pane.pickedIds.length)
                        unit: I18n.tr("baked")
                        desc: I18n.tr("Tools baked in on first boot, clip is always on.")
                        Multi {
                            anchors.fill: parent
                            options: pane.toolLabels
                            chosen: pane.pickedLabels
                            onToggled: (k) => pane.toggleLabel(k)
                        }
                    }
                }

                // extra packages: file truth, so mono.
                Column {
                    width: parent.width
                    spacing: Tokens.s2
                    Text {
                        text: I18n.tr("EXTRA PACKAGES")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui; font.pixelSize: 10; font.weight: Font.Medium
                        font.letterSpacing: Tokens.trackLabel; font.capitalization: Font.AllUppercase
                    }
                    Field {
                        width: parent.width
                        tabular: true
                        text: Vm.settings.extraPkgs || ""
                        placeholder: I18n.tr("…and any other packages, comma-separated (e.g. postgresql, redis)")
                        onEdited: (v) => { Vm.settings.extraPkgs = v; Vm.saveSettings(); }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: pane.heavyDisposable
                    text: I18n.tr("Heavy tools reinstall on every disposable boot (~a minute). For a fast throwaway with these baked in, make this a keeper, then \u201cSave as template\u201d in its detail pane and spawn clones: tools baked, boot in seconds.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: 11
                }

                Item { width: 1; height: Tokens.s1 }
            }
        }

        Row {
            id: createRow
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 32
            spacing: Tokens.s3
            Btn {
                primary: true
                text: pane.disposableRun ? I18n.tr("CREATE · BURN") : I18n.tr("CREATE MACHINE")
                armed: pane.os !== null && Vm.caps.quickemu === true
                onAct: { Vm.instant(pane.os.os, "", pane.disposableRun, pane.pickedIds.join(","), Vm.settings.extraPkgs || ""); pane.os = null; }
            }
        }
    }
}
