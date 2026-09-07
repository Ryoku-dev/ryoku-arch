pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons

// System > Dictation (DESIGN.md section 11, SYSTEM). Voxtype speech-to-text:
// switch voice typing on, pick a speech-to-text engine and model, download
// models in place, and add an API key for the cloud engine. This is not a
// settings sheet -- its backend is the `ryoku-hub voxtype` subcommand and the
// systemd user service, not the shared config store -- so it is full-bleed and
// draws its whole content region itself. The shell owns Super+` and the pill's
// mic-wave; this page just shapes ~/.config/voxtype/config.toml and the user
// service. Every colour, face, size, radius and duration reads from Tokens.
Item {
    id: pg

    property var hub
    // A full-bleed page draws the whole content region itself: the shell hides
    // the side panel and global action bar, and keeps the rail.
    readonly property bool fullBleed: true
    // The page's contract with the shell: it is never dirty, everything applies
    // instantly (the API key is the one thing behind an explicit Save).
    readonly property bool previewDirty: false

    // ── live snapshot from `ryoku-hub voxtype get` ────────────────────────
    property var presets: []
    property string selected: "whisper-fast"
    property bool voiceOn: false
    property bool installed: false
    property bool loaded: false
    property bool openaiKeySet: false
    property string downloading: ""    // preset key whose model is downloading, or ""
    property string busyError: ""
    property string notice: ""    // one-shot info banner, e.g. after a download
    // streamed download percent, -1 while indeterminate (voxtype emits progress
    // to stdout; a newline-terminated percent lights the determinate track, and
    // otherwise the heartbeat dot carries the wait).
    property real dlPercent: -1

    readonly property var sel: {
        for (var i = 0; i < pg.presets.length; i++)
            if (pg.presets[i].key === pg.selected)
                return pg.presets[i];
        return null;
    }
    readonly property string keyKind: pg.sel !== null ? pg.sel.keyKind : ""
    readonly property bool needsKey: pg.keyKind !== ""
    readonly property bool keyOnFile: pg.openaiKeySet
    // can voice typing be switched on yet? a local model has to be downloaded,
    // or a cloud engine needs its key. otherwise the toggle stays locked.
    readonly property bool usable: pg.sel !== null && (pg.sel.cloud ? pg.keyOnFile : pg.sel.present)

    function reload() { getProc.running = true; }

    // apply a full snapshot: the selected preset, the enable state, and any
    // freshly typed key (blank keys are kept by the backend, never wiped).
    function apply(extra) {
        var req = { "preset": pg.selected, "enabled": pg.voiceOn, "openaiKey": "" };
        if (extra)
            for (var k in extra)
                req[k] = extra[k];
        pg.busyError = "";
        setProc.command = ["ryoku-hub", "voxtype", "set", JSON.stringify(req)];
        setProc.running = true;
    }
    // clicking a card selects it; a local model that isn't downloaded is fetched
    // first (one click gets it), then selected when the download lands.
    function choose(key) {
        var p = null;
        for (var i = 0; i < pg.presets.length; i++)
            if (pg.presets[i].key === key)
                p = pg.presets[i];
        if (p !== null && !p.cloud && !p.present) {
            pg.download(key);
            return;
        }
        pg.selected = key;
        pg.apply(null);
    }
    function setEnabled(on) { pg.voiceOn = on; pg.apply(null); }
    function saveKey(value) {
        if (value.length === 0)
            return;
        pg.apply({ "openaiKey": value });
    }
    // download a model in-process, no terminal. the card shows a heartbeat (or a
    // filled track when voxtype streams a percent) until it lands; on success
    // the model is selected. one download at a time.
    function download(key) {
        if (pg.downloading !== "")
            return;
        pg.busyError = "";
        pg.notice = "";
        pg.dlPercent = -1;
        pg.downloading = key;
        dlProc.command = ["ryoku-hub", "voxtype", "download", key];
        dlProc.running = true;
    }
    function removeModel(key) {
        pg.busyError = "";
        rmProc.command = ["ryoku-hub", "voxtype", "rmmodel", key];
        rmProc.running = true;
    }

    // gpk (GlazePKG, the RyokuArch package manager) needs a tty for its AUR
    // build and sudo prompts; --hold keeps any error on screen after it exits.
    function installVoxtype() {
        Spawn.run(["kitty", "--hold", "-e", "gpk", "install", "voxtype-bin", "--manager", "aur"]);
    }

    // remove: gpk drops the package (tty for sudo), then we disable and delete
    // the user service so no dead unit lingers; config and models stay for a
    // reinstall.
    function removeVoxtype() {
        Spawn.run(["kitty", "--hold", "-e", "sh", "-c",
            "gpk remove voxtype-bin && { systemctl --user disable --now voxtype.service 2>/dev/null; rm -f ~/.config/systemd/user/voxtype.service; systemctl --user daemon-reload 2>/dev/null; }"]);
    }

    // when the gpk terminal closes and the Hub regains focus, re-probe so the
    // page flips from the install prompt to the live settings on its own.
    readonly property bool windowActive: Window.active
    onWindowActiveChanged: if (pg.windowActive) pg.reload()

    Component.onCompleted: pg.reload()

    Process {
        id: getProc
        command: ["ryoku-hub", "voxtype", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    pg.presets = d.presets || [];
                    pg.selected = d.selected || "whisper-fast";
                    pg.voiceOn = d.enabled === true;
                    pg.installed = d.installed === true;
                    pg.openaiKeySet = d.openaiKeySet === true;
                    pg.loaded = true;
                } catch (e) {
                    console.log("voxtype: get parse failed: " + e);
                }
            }
        }
    }
    Process {
        id: setProc
        stdout: StdioCollector { onStreamFinished: pg.reload() }
        stderr: StdioCollector {
            onStreamFinished: {
                var e = this.text.trim();
                if (e.length > 0)
                    pg.busyError = e;
            }
        }
    }
    // model download: a heartbeat/track shows while it runs; on success select
    // the model (which re-probes via setProc), otherwise surface the failure.
    Process {
        id: dlProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                var m = String(line).match(/(\d+(?:\.\d+)?)\s*%/);
                if (m)
                    pg.dlPercent = Math.max(0, Math.min(100, parseFloat(m[1])));
            }
        }
        onExited: (code) => {
            var k = pg.downloading;
            pg.downloading = "";
            pg.dlPercent = -1;
            if (code === 0) {
                pg.selected = k;
                pg.notice = I18n.tr("Model downloaded. If dictation doesn't respond, a reboot may be needed to apply it.");
                pg.apply(null);
            } else {
                pg.busyError = I18n.tr("Download failed (voxtype exited %1).").arg(code);
                pg.reload();
            }
        }
    }
    Process {
        id: rmProc
        stdout: StdioCollector { onStreamFinished: pg.reload() }
        stderr: StdioCollector {
            onStreamFinished: {
                var e = this.text.trim();
                if (e.length > 0)
                    pg.busyError = e;
            }
        }
    }

    // ── head: eyebrow, Fraunces title, blurb (matches every settings page) ──
    Column {
        id: head
        anchors {
            left: parent.left; right: micDecor.visible ? micDecor.left : parent.right; top: parent.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6; topMargin: Tokens.s6
        }
        spacing: Tokens.s2

        Row {
            spacing: Tokens.s2
            Rectangle {
                width: 16; height: 1; color: Tokens.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "力"; color: Tokens.ink; font.family: Tokens.jp
                font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: I18n.tr("TOOLS"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            text: I18n.tr("Dictation"); color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("Switch voice typing on, pick a speech-to-text engine and model, download models in place, and add an API key for the cloud engine.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // ── content region below the head ─────────────────────────────────────
    Item {
        id: below
        anchors {
            left: parent.left; right: micDecor.visible ? micDecor.left : parent.right; top: head.bottom; bottom: parent.bottom
            leftMargin: Tokens.s6; rightMargin: Tokens.s6; topMargin: Tokens.s5; bottomMargin: Tokens.s6
        }

        // voxtype missing: a clear message, not an inert page. voxtype-bin ships
        // with the desktop, so this is the rare hand-removed case.
        Column {
            id: emptyState
            visible: pg.loaded && !pg.installed
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.6, 460)
            spacing: Tokens.s4

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("Voxtype isn't installed")
                color: Tokens.ink
                font.family: Tokens.ui; font.pixelSize: Tokens.fRow; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("Voice dictation needs the voxtype-bin package. GlazePKG opens a terminal to confirm the install, and this page fills in once it finishes.")
                color: Tokens.inkMuted
                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("About 600 MB for the engine and runtimes, before any model.")
                color: Tokens.inkFaint
                font.family: Tokens.mono; font.pixelSize: Tokens.fMicro
            }
            Item {
                width: parent.width
                height: installBtn.implicitHeight
                Btn {
                    id: installBtn
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Install Voxtype")
                    primary: true
                    onAct: pg.installVoxtype()
                }
            }
        }

        Flickable {
            id: flick
            visible: !pg.loaded || pg.installed
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.height + Tokens.s5
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

            Column {
                id: content
                width: Math.min(flick.width - Tokens.s3, 720)   // reserve a scroll lane
                spacing: Tokens.s5

                // a one-shot info note (tap to dismiss), e.g. after a download.
                Rectangle {
                    visible: pg.notice !== ""
                    width: parent.width
                    height: noticeText.implicitHeight + Tokens.s3 * 2
                    radius: Tokens.radius
                    color: Tokens.tint5
                    border.width: Tokens.border
                    border.color: Tokens.line
                    Text {
                        id: noticeText
                        anchors {
                            left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                            leftMargin: Tokens.s4; rightMargin: Tokens.s4
                        }
                        text: pg.notice
                        color: Tokens.inkDim
                        wrapMode: Text.WordWrap
                        font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pg.notice = "" }
                }

                // ── DICTATION: the voice-typing switch and its guidance ──
                SettingCard {
                    width: content.width
                    title: I18n.tr("DICTATION")

                    Text {
                        width: parent.width
                        leftPadding: Tokens.s4; rightPadding: Tokens.s4
                        topPadding: Tokens.s3; bottomPadding: Tokens.s1
                        wrapMode: Text.WordWrap
                        text: (pg.voiceOn || pg.usable)
                            ? I18n.tr("Tap Super+` to dictate into whatever app has focus; tap again to stop. The pill grows a live mic wave while you speak.")
                            : (pg.sel && pg.sel.cloud
                                ? I18n.tr("Add an API key below before you can switch this on.")
                                : I18n.tr("Download a model below before you can switch this on."))
                        // calm guidance recedes to inkMuted; a call-to-action (you
                        // must download/add a key first) brightens to ink, since
                        // there is no colour to raise the alarm with.
                        color: (pg.voiceOn || pg.usable) ? Tokens.inkMuted : Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                    }

                    SettingRow {
                        anchors.left: parent.left; anchors.right: parent.right
                        label: I18n.tr("Voice typing")
                        controlWidth: 54
                        Sw {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            on: pg.voiceOn
                            // switch off any time; switch on only once there's a model to use.
                            enabled: pg.voiceOn || pg.usable
                            opacity: enabled ? 1 : 0.3
                            onToggled: (v) => pg.setEnabled(v)
                        }
                    }
                }

                // ── ENGINE & MODEL: the click-to-select card list ──
                SettingCard {
                    width: content.width
                    title: I18n.tr("ENGINE & MODEL")

                    Item {
                        width: parent.width
                        height: enginesCol.height + Tokens.s3 * 2
                        Column {
                            id: enginesCol
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.leftMargin: Tokens.s4; anchors.rightMargin: Tokens.s4; anchors.topMargin: Tokens.s3
                            spacing: Tokens.s2

                        Repeater {
                            model: pg.presets

                            // one engine/model row: name, provider, size, a wrapped
                            // detail, and a trailing action (download / heartbeat /
                            // remove). click the row to use it; a missing local
                            // model downloads first.
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                readonly property bool active: pg.selected === card.modelData.key
                                readonly property bool busy: pg.downloading === card.modelData.key
                                width: parent ? parent.width : 0
                                height: cardCol.implicitHeight + Tokens.s3 * 2
                                radius: Tokens.radius
                                // selection is the ON member of an exclusive set:
                                // tint10 + ink border + a corner dot, the same tell
                                // Gallery uses for a content-rich tile (a full-card
                                // invert would break the two-ink-levels bone rule).
                                color: card.active ? Tokens.tint10 : (cardHov.hovered ? Tokens.tint5 : "transparent")
                                border.width: Tokens.border
                                border.color: card.active ? Tokens.ink : (cardHov.hovered ? Tokens.lineStrong : Tokens.line)
                                Behavior on color { ColorAnimation { duration: Tokens.snap } }
                                Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

                                Column {
                                    id: cardCol
                                    anchors.left: parent.left
                                    anchors.right: action.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Tokens.s4
                                    anchors.rightMargin: Tokens.s3
                                    spacing: Tokens.s1

                                    Row {
                                        width: parent.width
                                        spacing: Tokens.s2
                                        Text {
                                            text: I18n.tr(card.modelData.label)
                                            color: card.active ? Tokens.ink : Tokens.inkDim
                                            font.family: Tokens.ui
                                            font.pixelSize: Tokens.fBody
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            // provider . size . status is file-truth chrome, so mono.
                                            text: card.modelData.provider + "  \u00b7  " + card.modelData.size
                                                + (card.busy ? I18n.tr("  \u00b7  downloading\u2026")
                                                    : (card.modelData.cloud ? ""
                                                        : (card.modelData.present ? I18n.tr("  \u00b7  downloaded") : I18n.tr("  \u00b7  not downloaded"))))
                                            color: (card.busy || (!card.modelData.cloud && !card.modelData.present)) ? Tokens.ink : Tokens.inkFaint
                                            font.family: Tokens.mono
                                            font.pixelSize: Tokens.fTiny
                                        }
                                    }
                                    Text {
                                        width: cardCol.width
                                        wrapMode: Text.WordWrap
                                        text: I18n.tr(card.modelData.detail)
                                        color: Tokens.inkMuted
                                        font.family: Tokens.ui
                                        font.pixelSize: Tokens.fSmall
                                    }
                                    // determinate progress: shown only while a streamed
                                    // percent is known -- hairline track + square ink
                                    // fill + percent (the shared progress spec).
                                    Item {
                                        width: cardCol.width
                                        height: (card.busy && pg.dlPercent >= 0) ? 12 : 0
                                        visible: card.busy && pg.dlPercent >= 0
                                        Rectangle {
                                            id: pgTrack
                                            anchors.left: parent.left
                                            anchors.right: pgPct.left
                                            anchors.rightMargin: Tokens.s2
                                            anchors.verticalCenter: parent.verticalCenter
                                            height: 4
                                            color: Tokens.lineSoft
                                            antialiasing: false
                                            Rectangle {
                                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                                width: parent.width * Math.max(0, Math.min(1, pg.dlPercent / 100))
                                                color: Tokens.ink
                                                antialiasing: false
                                                Behavior on width { NumberAnimation { duration: Tokens.flap } }
                                            }
                                        }
                                        Text {
                                            id: pgPct
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            text: Math.round(pg.dlPercent) + "%"
                                            color: Tokens.ink
                                            font.family: Tokens.ui
                                            font.pixelSize: Tokens.fTiny
                                        }
                                    }
                                }

                                // selected marker, out of the flow so it never nudges
                                // the name (Gallery's corner dot idiom).
                                Text {
                                    visible: card.active
                                    anchors.right: parent.right; anchors.bottom: parent.bottom
                                    anchors.rightMargin: Tokens.s3; anchors.bottomMargin: Tokens.s2
                                    text: "\u25cf"
                                    color: Tokens.ink
                                    font.pixelSize: 7
                                }

                                // trailing action: heartbeat while downloading, else
                                // a download or remove glyph for local models (cloud:
                                // none). the MouseArea consumes its own clicks so the
                                // card's tap-to-select does not double-fire here.
                                Item {
                                    id: action
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.rightMargin: Tokens.s3
                                    width: 26
                                    height: 26

                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: card.busy
                                        width: 6; height: 6; radius: 3
                                        color: Tokens.ink
                                        // a heartbeat, not an alarm: 600ms each way (DESIGN.md section 5).
                                        SequentialAnimation on opacity {
                                            running: card.busy
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 0.3; duration: 600 }
                                            NumberAnimation { to: 1.0; duration: 600 }
                                        }
                                    }
                                    Rectangle {
                                        id: actBtn
                                        anchors.fill: parent
                                        visible: !card.busy && !card.modelData.cloud
                                        radius: Tokens.radius
                                        color: actMa.containsMouse ? Tokens.tint10 : "transparent"
                                        border.width: Tokens.border
                                        border.color: actMa.containsMouse ? Tokens.lineStrong : Tokens.line
                                        Behavior on color { ColorAnimation { duration: Tokens.snap } }
                                        Behavior on border.color { ColorAnimation { duration: Tokens.snap } }
                                        Text {
                                            anchors.centerIn: parent
                                            // a paired minus for remove (not danger, and
                                            // there is no red here to carry one); a down
                                            // arrow for a fetch.
                                            text: card.modelData.present ? "\u2212" : "\u2193"
                                            color: Tokens.inkDim
                                            font.family: Tokens.ui
                                            font.pixelSize: 12
                                        }
                                    }
                                    MouseArea {
                                        id: actMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: !card.modelData.cloud && !card.busy
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (card.modelData.present)
                                                pg.removeModel(card.modelData.key);
                                            else
                                                pg.download(card.modelData.key);
                                        }
                                    }
                                }

                                HoverHandler { id: cardHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: pg.choose(card.modelData.key) }
                            }
                        }
                        }
                    }
                }

                // ── API KEY: only for a cloud engine that needs one ──
                SettingCard {
                    width: content.width
                    visible: pg.needsKey
                    title: I18n.tr("API KEY")

                    Text {
                        width: parent.width
                        leftPadding: Tokens.s4; rightPadding: Tokens.s4
                        topPadding: Tokens.s3; bottomPadding: Tokens.s1
                        wrapMode: Text.WordWrap
                        text: pg.keyOnFile
                            ? I18n.tr("A key is saved. Enter a new one to replace it.")
                            : I18n.tr("This cloud engine needs an API key. It is stored locally in your Voxtype config.")
                        // a saved key is a settled state (recedes); a missing key is
                        // the call to action (brightens).
                        color: pg.keyOnFile ? Tokens.inkMuted : Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                    }

                    // the key entry, kept as its bespoke masked field + Save button,
                    // inset from the card border.
                    Item {
                        width: parent.width
                        height: 36 + Tokens.s3 * 2

                        Item {
                            id: keyEntry
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            anchors.leftMargin: Tokens.s4; anchors.rightMargin: Tokens.s4
                            height: 36

                            Btn {
                                id: saveKeyBtn
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Save key")
                                primary: true
                                onAct: { pg.saveKey(keyInput.text); keyInput.text = ""; }
                            }

                            // the key is write-only: masked, never read back into the UI
                            // (only the openaiKeySet bool). mono, since it is a literal
                            // the machine will be told.
                            Rectangle {
                                id: keyField
                                anchors.left: parent.left
                                anchors.right: saveKeyBtn.left
                                anchors.rightMargin: Tokens.s2
                                anchors.verticalCenter: parent.verticalCenter
                                height: 36
                                radius: Tokens.radius
                                color: "transparent"
                                border.width: keyInput.activeFocus ? 2 : Tokens.border
                                border.color: keyInput.activeFocus ? Tokens.ink : (keyMa.containsMouse ? Tokens.lineStrong : Tokens.line)
                                Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

                                TextInput {
                                    id: keyInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 9
                                    anchors.rightMargin: 9
                                    verticalAlignment: Text.AlignVCenter
                                    echoMode: TextInput.Password
                                    color: Tokens.ink
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fMicro
                                    clip: true
                                    onAccepted: { pg.saveKey(text); text = ""; }

                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: keyInput.text.length === 0
                                        text: I18n.tr("OpenAI API key")
                                        color: Tokens.inkMuted
                                        font: keyInput.font
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    id: keyMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: keyInput.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                // ── PACKAGE: uninstall handoff ──
                SettingCard {
                    width: content.width
                    title: I18n.tr("PACKAGE")

                    Text {
                        width: parent.width
                        leftPadding: Tokens.s4; rightPadding: Tokens.s4
                        topPadding: Tokens.s3; bottomPadding: Tokens.s1
                        wrapMode: Text.WordWrap
                        text: I18n.tr("Voxtype is installed (voxtype-bin). Removing it uninstalls the package; your engine choice and downloaded models stay on disk.")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                    }

                    Item {
                        width: parent.width
                        height: pkgBtn.implicitHeight + Tokens.s3 * 2
                        Btn {
                            id: pkgBtn
                            anchors.left: parent.left; anchors.leftMargin: Tokens.s4
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Remove Voxtype")
                            onAct: pg.removeVoxtype()
                        }
                    }
                }

                // error banner, pinned at the bottom: an error is inverted text and
                // the word (DESIGN.md section 1), so the tag flips to bone; the raw
                // ryoku-hub message reads in ink. cleared by the next action.
                Rectangle {
                    visible: pg.busyError !== ""
                    width: parent.width
                    height: errText.implicitHeight + Tokens.s3 * 2
                    radius: Tokens.radius
                    color: "transparent"
                    border.width: Tokens.border
                    border.color: Tokens.lineStrong

                    Rectangle {
                        id: errTag
                        anchors.left: parent.left; anchors.top: parent.top
                        anchors.leftMargin: Tokens.s3; anchors.topMargin: Tokens.s3
                        width: errTagLab.width + Tokens.s2 * 2
                        height: 18
                        radius: Tokens.radius
                        color: Tokens.bone
                        Text {
                            id: errTagLab
                            anchors.centerIn: parent
                            text: I18n.tr("ERROR")
                            color: Tokens.inkOnBone
                            font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
                            font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
                        }
                    }
                    Text {
                        id: errText
                        anchors {
                            left: errTag.right; right: parent.right; top: parent.top
                            leftMargin: Tokens.s3; rightMargin: Tokens.s3; topMargin: Tokens.s3
                        }
                        text: pg.busyError
                        color: Tokens.ink
                        wrapMode: Text.WordWrap
                        font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                    }
                }

                // a live audio-wave specimen dressing the page foot: voice made
                // visible, in the reference's dither (reuses the Input decor idiom).
                Decor {
                    width: parent.width
                    height: Tokens.cellH + Tokens.s5
                    title: "\u97f3\u58f0"
                    sub: "\u30dc\u30a4\u30b9"
                    tate: "\u58f0\u3092\u6587\u5b57\u306b"
                    caption: I18n.tr("Speak, and the words land in whatever app has focus.")
                    code: "VOICE-02"
                    seal: "\u58f0"
                    seed: 8
                    ditherFreq: 1.0
                    boxId: "dictation.voice"
                }
            }
        }
    }

    // fill the head's dead right the way Connections and Recording do: a mic
    // specimen (the 1938 RCA ribbon-mic patent) baked smooth so its line-art
    // reads, right-aligned from the head to the page foot. Head and content are
    // held to its left; it hides on a window too narrow to spare the rail.
    Placard {
        id: micDecor
        anchors {
            right: parent.right; rightMargin: Tokens.s6
            top: head.top; bottom: parent.bottom
            bottomMargin: Tokens.s6
        }
        width: Math.round(pg.width * 0.28)
        visible: Tokens.showPosters && (pg.width - width - Tokens.s7 >= 460)
        code: "MIC-02"
        title: "\u30de\u30a4\u30af"
        sub: I18n.tr("RIBBON \u00b7 1938")
        chapter: "05"
        label: I18n.tr("TOOLS")
        quote: I18n.tr("SPEAK, AND IT LISTENS.")
        seal: "\u97f3"
        art: "mic.png"
    }
}
