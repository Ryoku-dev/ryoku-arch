import QtQuick
import Quickshell
import Quickshell.Io
import "../kit"
import "../../modules"
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Community route (有志): every bar plugin installed from outside Ryoku, kept
// apart from the shipped set so a widget someone else wrote is never mixed in
// with the built-ins, under a plain warning that Ryoku does not review it. The
// same CcWidgetList sheet as Widgets, so a community widget is shown, tuned and
// coloured exactly like a built-in; each row also names its author and can
// EXPORT it (a Ryostore-shaped folder), SHARE it (the catalogue pull request)
// or REMOVE it. Those run the plugin CLI here, with the result printed in a
// console strip, so a bad URL or a missing preview is never silent. Below the
// sheet, the two ways in: a git URL or a local folder handed to `ryoku plugin
// add --bar`, and Ryostore's plugin shelf.
Item {
    id: page
    property var root: null
    property var cc: null
    readonly property var tk: page.cc ? page.cc.tokens : null
    readonly property real colW: page.width
    implicitHeight: contentCol.implicitHeight

    property alias selId: clist.selId
    property string colorGid: ""
    property string colorLabel: ""
    readonly property bool colorSupported: !!(page.root && page.root.widgetHasFill)

    readonly property var communityEntries: {
        var c = (page.root && page.root.barCatalog) ? page.root.barCatalog : []
        var out = []
        for (var i = 0; i < c.length; i++)
            if (c[i].kind === "plugin" && c[i].official !== true) out.push(c[i])
        return out
    }

    // ── the plugin CLI, run here so its result is visible ──
    // One job at a time; the console strip shows what is running, then the
    // command's last lines. `ryoku plugin add` clones/copies, validates and
    // installs without running anything from the plugin; --bar places it on the
    // bar, which re-derives on the plugins.json change.
    property string jobLabel: ""
    property string jobText: ""     // the last lines, for the strip
    property string jobFull: ""     // everything, for the path and the URL
    property bool jobFailed: false
    readonly property string jobPath: {
        var m = /-> (\/\S+)/.exec(page.jobFull)
        return m ? m[1] : ""
    }
    readonly property string jobUrl: {
        var m = /(https:\/\/github\.com\/\S+)/.exec(page.jobFull)
        return m ? m[1] : ""
    }
    Process {
        id: job
        property string out: ""
        stdout: StdioCollector { onStreamFinished: job.out += this.text }
        stderr: StdioCollector { onStreamFinished: job.out += this.text }
        onExited: (code) => {
            page.jobFull = job.out.replace(/\x1b\[[0-9;]*m/g, "")
            var lines = page.jobFull.trim().split("\n").filter(l => l.trim() !== "")
            page.jobText = lines.slice(-3).join("\n")
            page.jobFailed = code !== 0
            if (page.jobText === "") page.jobText = code === 0 ? I18n.tr("done") : I18n.tr("failed (exit %1)").arg(code)
        }
    }
    function run(label, cmd) {
        if (job.running) return
        page.jobLabel = label
        page.jobText = ""
        page.jobFull = ""
        page.jobFailed = false
        job.out = ""
        job.command = cmd
        job.running = true
    }
    function addFrom(source) {
        var u = String(source || "").trim()
        if (u === "") return
        // a folder typed the shell way: no shell runs here, so expand it
        if (u.indexOf("~/") === 0) u = Quickshell.env("HOME") + u.substring(1)
        page.run(I18n.tr("Adding %1").arg(u), ["ryoku", "plugin", "add", u, "--bar", "--yes"])
        gitField.text = ""
    }
    function exportPlugin(id) { page.run(I18n.tr("Exporting %1").arg(id), ["ryoku", "plugin", "export", id]) }
    function sharePlugin(id)  { page.run(I18n.tr("Sharing %1").arg(id), ["ryoku", "plugin", "share", id]) }
    function removePlugin(id) {
        page.run(I18n.tr("Removing %1").arg(id), ["ryoku", "plugin", "remove", id])
        if (page.selId === id) page.selId = ""
    }

    // what is still below the plate's edge; the stage reads it for the fade.
    readonly property real scrollRemaining: Math.max(0, flick.contentHeight - flick.height - flick.contentY)

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight + (contentCol.implicitHeight > height && page.tk ? page.tk.tailPad : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: contentCol
            width: page.colW
            spacing: page.tk ? page.tk.sectionGap : 24

            // ── the warning every community widget sits under ──
            Entrance {
                width: page.colW
                index: 0
                Rectangle {
                    width: page.colW
                    height: warnRow.implicitHeight + (page.tk ? page.tk.gap * 2 : 24)
                    radius: Tokens.radius
                    color: "transparent"
                    border.width: Tokens.border
                    border.color: Tokens.lineStrong
                    Row {
                        id: warnRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: page.tk ? page.tk.gap : 12
                        anchors.rightMargin: page.tk ? page.tk.gap : 12
                        spacing: page.tk ? page.tk.gap : 12
                        IconText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "warning"
                            color: Tokens.inkDim
                            font.pixelSize: Tokens.fRow
                        }
                        UiText {
                            id: warnText
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Tokens.fRow - parent.spacing
                            text: I18n.tr("Community plugin. Ryoku does not review or maintain it: it runs inside your shell with your permissions, so inspect its code before you trust it.")
                            color: Tokens.inkDim
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            Entrance {
                width: page.colW
                index: 1
                visible: page.communityEntries.length > 0
                CcWidgetList {
                    id: clist
                    width: page.colW
                    title: I18n.tr("INSTALLED")
                    kana: "\u5c0e\u5165"
                    root: page.root
                    tk: page.tk
                    entries: page.communityEntries
                    colorGid: page.colorGid
                    onColorRequested: (gid, label) => {
                        if (page.colorGid === gid) { page.colorGid = ""; page.colorLabel = "" }
                        else { page.colorGid = gid; page.colorLabel = label }
                    }
                    onExportRequested: (id) => page.exportPlugin(id)
                    onShareRequested: (id) => page.sharePlugin(id)
                    onRemoveRequested: (id) => page.removePlugin(id)
                }
            }

            // nothing installed yet: say so plainly, in the sheet's own frame.
            Entrance {
                width: page.colW
                index: 1
                visible: page.communityEntries.length === 0
                Rectangle {
                    width: page.colW
                    height: emptyCol.implicitHeight + (page.tk ? page.tk.pad * 2 : 48)
                    radius: Tokens.radius
                    color: "transparent"
                    border.width: Tokens.border
                    border.color: Tokens.line
                    Column {
                        id: emptyCol
                        anchors.centerIn: parent
                        width: parent.width - (page.tk ? page.tk.pad * 2 : 48)
                        spacing: 2
                        UiText {
                            text: I18n.tr("No community widgets yet")
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fRow
                            font.weight: Font.Medium
                        }
                        UiText {
                            width: parent.width
                            text: I18n.tr("A bar plugin from a git repo or Ryostore lands here.")
                            color: Tokens.inkMuted
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // ── the console strip: what the plugin CLI is doing, and its result ──
            Entrance {
                width: page.colW
                index: 2
                visible: page.jobLabel !== ""
                Rectangle {
                    width: page.colW
                    height: consoleCol.implicitHeight + (page.tk ? page.tk.gap * 2 : 24)
                    radius: Tokens.radius
                    color: Tokens.paperLift
                    border.width: Tokens.border
                    border.color: page.jobFailed ? Tokens.lineStrong : Tokens.line
                    Column {
                        id: consoleCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: page.tk ? page.tk.gap : 12
                        anchors.rightMargin: page.tk ? page.tk.gap : 12
                        spacing: page.tk ? page.tk.gap / 2 : 6
                        Row {
                            spacing: page.tk ? page.tk.gap / 2 : 6
                            UiText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: job.running ? I18n.tr("WORKING") : (page.jobFailed ? I18n.tr("FAILED") : I18n.tr("DONE"))
                                color: Tokens.inkFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fMicro
                                font.letterSpacing: Tokens.trackMark
                                font.weight: Font.DemiBold
                            }
                            UiText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.jobLabel
                                color: Tokens.inkDim
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                elide: Text.ElideRight
                            }
                        }
                        UiText {
                            visible: page.jobText !== ""
                            width: parent.width
                            text: page.jobText
                            color: page.jobFailed ? Tokens.ink : Tokens.inkMuted
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fTiny
                            wrapMode: Text.WrapAnywhere
                        }
                        Flow {
                            width: parent.width
                            spacing: page.tk ? page.tk.gap / 2 : 6
                            visible: !job.running && (page.jobPath !== "" || page.jobUrl !== "")
                            Btn {
                                visible: page.jobPath !== ""
                                text: I18n.tr("OPEN FOLDER")
                                onAct: Quickshell.execDetached(["xdg-open", page.jobPath])
                            }
                            Btn {
                                visible: page.jobUrl !== ""
                                text: I18n.tr("OPEN PULL REQUEST")
                                onAct: Quickshell.execDetached(["xdg-open", page.jobUrl])
                            }
                        }
                    }
                }
            }

            Entrance {
                width: page.colW
                index: 3
                SettingCard {
                    width: page.colW
                    title: I18n.tr("ADD")
                    kana: "\u8ffd\u52a0"
                    collapsible: false

                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        block: true
                        label: I18n.tr("From a git repo or a folder")
                        desc: I18n.tr("Checked, installed, then placed on the bar")
                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: page.tk ? page.tk.gap : 12
                            Field {
                                id: gitField
                                width: parent.width - addBtn.width - parent.spacing
                                tabular: true
                                placeholder: I18n.tr("https://github.com/someone/ryoku-widget  or  ~/my-widget")
                                onCommitted: (v) => page.addFrom(v)
                            }
                            Btn {
                                id: addBtn
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("ADD")
                                primary: true
                                onAct: page.addFrom(gitField.text)
                            }
                        }
                    }
                    SettingRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        divider: true
                        controlWidth: 150
                        label: I18n.tr("From Ryostore")
                        desc: I18n.tr("The curated shelf")
                        Btn {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("OPEN RYOSTORE")
                            onAct: {
                                Quickshell.execDetached(["ryostore", "open", "plugins"])
                                if (page.cc) page.cc.close()
                            }
                        }
                    }
                }
            }
        }
    }

    CcScrollRail { root: page.root; tk: page.tk; flick: flick; z: 5 }

    Component {
        id: colorPopComp
        CcWidgetColorPopover {
            root: page.root
            tk: page.tk
            gid: page.colorGid
            label: page.colorLabel
            onDismissed: { page.colorGid = ""; page.colorLabel = "" }
        }
    }
    Loader {
        anchors.fill: parent
        z: 60
        active: page.colorSupported && page.colorGid !== ""
        sourceComponent: colorPopComp
    }
}
