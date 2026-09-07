pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import shell.services
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Capture companion for the selected monitor. The window itself spans the
// output so global placement is stable; only the visible stack accepts pointer
// input, and even that mask vanishes while a recording is live.
PanelWindow {
    id: win

    required property var modelData

    // Per-monitor UI scale (shell.json displays.ui_scale): scales the key badges
    // and drag chrome without touching the fullscreen bounds. 1.0 is a no-op.
    readonly property real us: Tokens.uiScaleFor(modelData ? modelData.name : "")

    readonly property var mon: {
        const monitors = Hyprland.monitors.values;
        for (var i = 0; i < monitors.length; i++) {
            if (monitors[i].name === (modelData ? modelData.name : ""))
                return monitors[i];
        }
        return null;
    }
    readonly property real monX: mon ? mon.x : 0
    readonly property real monY: mon ? mon.y : 0
    readonly property real monScale: mon && mon.scale > 0 ? mon.scale : 1
    readonly property real screenW: mon ? mon.width / monScale : (modelData ? modelData.width : 0)
    readonly property real screenH: mon ? mon.height / monScale : (modelData ? modelData.height : 0)
    readonly property string targetMonitor: Keypresses.sessionMonitor !== ""
        ? Keypresses.sessionMonitor
        : (ShellState.screens.length > 0 ? ShellState.screens[0].name : "")
    readonly property bool onScreen: modelData && modelData.name === targetMonitor
    readonly property bool pointerEnabled: !Recorder.anyActive
        && (drag.dragging || display.width > 0)

    readonly property real defCX: monX + screenW / 2
    readonly property real defCY: monY + screenH - display.implicitHeight / 2 - 72
    readonly property real savedCX: isNaN(Keypresses.px) ? defCX : Keypresses.px
    readonly property real savedCY: isNaN(Keypresses.py) ? defCY : Keypresses.py
    readonly property real globalCX: drag.dragging ? drag.cx : savedCX
    readonly property real globalCY: drag.dragging ? drag.cy : savedCY
    readonly property var clamped: KeypressMath.clampTopLeft(
        globalCX - monX - display.implicitWidth / 2,
        globalCY - monY - display.implicitHeight / 2,
        display.implicitWidth, display.implicitHeight,
        screenW, screenH, 24)

    screen: modelData
    visible: Keypresses.active && onScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "ryoku-keypresses"
    anchors { top: true; bottom: true; left: true; right: true }

    mask: Region {
        x: drag.dragging ? 0 : display.x - 14 * win.us
        y: drag.dragging ? 0 : display.y - 14 * win.us
        width: win.pointerEnabled ? (drag.dragging ? win.width : display.width + 28 * win.us) : 0
        height: win.pointerEnabled ? (drag.dragging ? win.height : display.height + 28 * win.us) : 0
    }

    KeypressStack {
        id: display
        us: win.us
        x: win.clamped.x
        y: win.clamped.y
        width: display.implicitWidth
        height: display.implicitHeight
        theme: Keypresses.theme
        preview: Keypresses.placementPreview && !Recorder.anyActive
        motionEnabled: !Motion.reduce
    }

    Rectangle {
        anchors.fill: display
        anchors.margins: -10 * win.us
        visible: opacity > 0.01
        opacity: (stackHover.hovered || drag.dragging) && !Recorder.anyActive ? 1 : 0
        color: "transparent"
        radius: (Tokens.radius + 6) * win.us
        border.width: Tokens.border * win.us
        border.color: Keypresses.theme === "dark" ? Tokens.keycapOnDark : Tokens.keycapOnLight

        Behavior on opacity {
            NumberAnimation { duration: Motion.dur(150); easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: Tokens.s1 * win.us
            width: dragLabel.implicitWidth + 18 * win.us
            height: 24 * win.us
            radius: height / 2
            color: Keypresses.theme === "dark" ? Tokens.keycapLight : Tokens.keycapDark

            Text {
                id: dragLabel
                anchors.centerIn: parent
                text: I18n.tr("DRAG TO PLACE")
                color: Keypresses.theme === "dark" ? Tokens.keycapOnLight : Tokens.keycapOnDark
                font.family: Tokens.ui
                font.pixelSize: 9 * win.us
                font.weight: Font.DemiBold
                font.letterSpacing: Tokens.trackLabel * win.us
            }
        }
    }

    Item {
        id: dragSurface
        x: drag.dragging ? drag.originCX - win.monX - width / 2 : win.clamped.x
        y: drag.dragging ? drag.originCY - win.monY - height / 2 : win.clamped.y
        width: display.implicitWidth
        height: display.implicitHeight
    }

    HoverHandler {
        id: stackHover
        parent: dragSurface
        enabled: !Recorder.anyActive
        cursorShape: Qt.SizeAllCursor
    }

    DragHandler {
        id: drag
        parent: dragSurface
        target: null
        enabled: !Recorder.anyActive
        dragThreshold: 4

        property bool dragging: false
        property real originCX: 0
        property real originCY: 0
        property real cx: 0
        property real cy: 0

        onActiveChanged: {
            if (active) {
                originCX = win.monX + display.x + display.implicitWidth / 2;
                originCY = win.monY + display.y + display.implicitHeight / 2;
                cx = originCX;
                cy = originCY;
                dragging = true;
            } else if (dragging) {
                Keypresses.savePlacement(cx, cy, win.modelData ? win.modelData.name : "");
                dragging = false;
            }
        }

        onActiveTranslationChanged: {
            if (!active)
                return;
            const next = KeypressMath.clampTopLeft(
                originCX - win.monX - display.implicitWidth / 2 + activeTranslation.x,
                originCY - win.monY - display.implicitHeight / 2 + activeTranslation.y,
                display.implicitWidth, display.implicitHeight,
                win.screenW, win.screenH, 24);
            cx = win.monX + next.x + display.implicitWidth / 2;
            cy = win.monY + next.y + display.implicitHeight / 2;
        }
    }

    Connections {
        target: Keypresses
        function onChord(keys, repeat, state, timestamp) {
            display.push(keys, repeat, state, timestamp);
        }
        function onActiveChanged() {
            if (!Keypresses.active)
                display.clear();
        }
    }

    Connections {
        target: Recorder
        function onAnyActiveChanged() {
            if (Recorder.anyActive)
                display.clear();
        }
    }
}
