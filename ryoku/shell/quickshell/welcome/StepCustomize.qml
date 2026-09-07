pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import "Singletons"

// Step 4 body: the essentials a new user most wants right away, wired through the
// same stores the shell reads live -- interface scale (the #1 "everything looks
// huge" fix), the bar style, which desktop widgets show, and a wallpaper reroll.
// Every control previews on the desktop behind the tour the moment it changes.
// Deeper knobs (colours, rounding) stay in Ryoku Settings.
Flickable {
    id: step

    contentHeight: col.implicitHeight
    contentWidth: width
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    readonly property string cfgDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku"

    property real uiScale: 100          // fontScale * 100, shown as a percent
    property string barStyle: "qsbar"
    property var widgets: ({})          // live mirror of widgets.json

    // read live state so the controls open on what the desktop is actually using.
    function syncShell() {
        try {
            var o = JSON.parse(shellFile.text() || "{}");
            if (typeof o.fontScale === "number") step.uiScale = Math.round(o.fontScale * 100);
            if (typeof o.barStyle === "string") step.barStyle = o.barStyle;
        } catch (e) {}
    }
    function syncWidgets() {
        try { step.widgets = JSON.parse(widgetsFile.text() || "{}") || ({}); } catch (e) { step.widgets = ({}); }
    }

    // merge one key into a store without dropping the rest: a JsonAdapter would
    // serialise only its own keys and clobber the others, so round-trip the whole
    // parsed object with setText (atomic by default).
    function mergeKey(file, k, v) {
        var o = {};
        try { o = JSON.parse(file.text() || "{}") || {}; } catch (e) { o = {}; }
        o[k] = v;
        file.setText(JSON.stringify(o, null, 2) + "\n");
    }
    function setShellKey(k, v) { step.mergeKey(shellFile, k, v); }
    function setWidget(k, v) {
        step.mergeKey(widgetsFile, k, v);
        var w = step.widgets || ({}); w[k] = v; step.widgets = w;   // reassign so bindings refresh
    }

    FileView {
        id: shellFile
        path: step.cfgDir + "/shell.json"
        blockLoading: true; watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: step.syncShell()
    }
    FileView {
        id: widgetsFile
        path: step.cfgDir + "/widgets.json"
        blockLoading: true; watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: step.syncWidgets()
    }

    Process { id: wallProc; command: ["ryogami", "wallpaper", "next"] }
    Process { id: barStudioProc; command: ["sh", "-c", "ryoku-hub config set section bar-studio; flock -n -o /tmp/ryoku-hub.lock qs -c hub"]; environment: Spawn.env }

    Component.onCompleted: { step.syncShell(); step.syncWidgets(); }

    Column {
        id: col
        width: step.width
        spacing: 24

        // --- Interface scale ---------------------------------------------
        Column {
            width: parent.width
            spacing: 10

            GroupMark { width: parent.width; text: I18n.tr("Interface scale") }

            SliderRow {
                width: parent.width
                label: I18n.tr("Scale")
                unit: "%"
                from: 80; to: 150; step: 5
                value: step.uiScale
                onMoved: (v) => step.uiScale = v
                onReleased: (v) => { step.uiScale = v; step.setShellKey("fontScale", Math.round(v) / 100); }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: I18n.tr("If everything looks oversized, ease this down - the whole shell resizes as you let go.")
                color: Tokens.inkFaint
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                lineHeight: 1.25
            }
        }

        // --- Bar ---------------------------------------------------------
        Column {
            width: parent.width
            spacing: 12

            GroupMark { width: parent.width; text: I18n.tr("Bar") }

            ChipRow {
                width: parent.width
                model: [
                    { "key": "qsbar", "label": I18n.tr("QS Bar") },
                    { "key": "sumi",  "label": I18n.tr("Sumi rail") }
                ]
                current: step.barStyle
                onSelected: (key) => { step.barStyle = key; step.setShellKey("barStyle", key); }
            }

            Row {
                width: parent.width
                spacing: 16
                WelcomeButton {
                    kind: "outline"
                    label: I18n.tr("Open Bar Studio")
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: barStudioProc.running = true
                }
                Text {
                    width: parent.width - 190
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.WordWrap
                    text: I18n.tr("QS Bar is the full top bar; Sumi is a minimal left rail. Arrange rails and widgets in Bar Studio.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    lineHeight: 1.25
                }
            }
        }

        // --- Desktop widgets ---------------------------------------------
        Column {
            width: parent.width
            spacing: 8

            GroupMark { width: parent.width; text: I18n.tr("Desktop widgets") }

            Repeater {
                model: [
                    { "key": "clockEnabled",    "label": I18n.tr("Clock") },
                    { "key": "calendarEnabled", "label": I18n.tr("Calendar") },
                    { "key": "musicEnabled",    "label": I18n.tr("Music player") }
                ]

                delegate: Row {
                    id: wr
                    required property var modelData
                    width: col.width
                    height: 30
                    readonly property bool on: step.widgets[wr.modelData.key] === true

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - toggle.width
                        text: wr.modelData.label
                        color: Tokens.inkDim
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fBody
                    }

                    // pill toggle: a bone plate when on, a hairline when off, with a
                    // square handle that slides -- the house toggle, no accent fill.
                    Rectangle {
                        id: toggle
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 22; radius: 11
                        color: wr.on ? Tokens.bone : "transparent"
                        border.width: Tokens.border
                        border.color: wr.on ? Tokens.bone : Tokens.line
                        Behavior on color { ColorAnimation { duration: Motion.snap } }
                        Behavior on border.color { ColorAnimation { duration: Motion.snap } }

                        Rectangle {
                            width: 14; height: 14; radius: 7
                            anchors.verticalCenter: parent.verticalCenter
                            x: wr.on ? parent.width - width - 4 : 4
                            color: wr.on ? Tokens.inkOnBone : Tokens.inkFaint
                            Behavior on x { NumberAnimation { duration: Motion.snap; easing.type: Motion.ease } }
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: step.setWidget(wr.modelData.key, !wr.on) }
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: I18n.tr("Turn one on and it lands on the desktop straight away; drag to place it later.")
                color: Tokens.inkFaint
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                lineHeight: 1.25
            }
        }

        // --- Wallpaper ---------------------------------------------------
        Column {
            width: parent.width
            spacing: 12

            GroupMark { width: parent.width; text: I18n.tr("Wallpaper") }

            Row {
                width: parent.width
                spacing: 16
                WelcomeButton {
                    kind: "solid"
                    label: I18n.tr("Shuffle")
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: wallProc.running = true
                }
                Text {
                    width: parent.width - 130
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.WordWrap
                    text: I18n.tr("Roll a new wallpaper - the whole desktop rethemes, and your palette follows it.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    lineHeight: 1.25
                }
            }
        }

        // --- footer hint -------------------------------------------------
        Row {
            width: parent.width
            spacing: 10
            Rectangle { width: 14; height: 1; color: Tokens.lineStrong; anchors.verticalCenter: hint.verticalCenter }
            Text {
                id: hint
                width: col.width - 24
                wrapMode: Text.WordWrap
                text: I18n.tr("Colours, window rounding and the deeper shell knobs wait for you in Ryoku Settings.")
                color: Tokens.inkFaint
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
            }
        }
    }
}
