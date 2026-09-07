import QtQuick
import "../modules"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Ryoku.Ui.Singletons

PanelWindow {
    id: memPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-memory"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6

    readonly property int memTotal: root.systemMemTotalMiB
    readonly property int memAvail: root.systemMemAvailMiB
    readonly property int memFree: root.systemMemFreeMiB
    readonly property int memBuffers: root.systemMemBuffersMiB
    readonly property int memCached: root.systemMemCachedMiB
    readonly property int memUsed: root.systemMemUsedMiB
    readonly property int pct: root.systemMemPercent
    readonly property real usedGiB: memUsed / 1024
    readonly property real totalGiB: memTotal / 1024

    property real reveal: root.memVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.memVisible ? 160 : 120
            easing.type: root.memVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.memVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.memVisible = false
    }

    Rectangle {
        id: card
        width: 320
        height: col.implicitHeight + 24
        radius: reveal > 0.001 ? root.panelRadius : 0
        color: "transparent"
        border.color: root.panelBorder
        border.width: 0
        PillShadow { theme: root }
        ConnectedPanelSurface {
            root: memPanel.root
            ownerActive: memPanel.root.memVisible
            targetX: memPanel.root.memoryBarX
            reveal: memPanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.memoryBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - memPanel.reveal)
            : (barBottom + gap) - 2 * (1 - memPanel.reveal)
        opacity: memPanel.reveal
        focus: root.memVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.memVisible = false;
                event.accepted = true;
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ── header ──
            Item {
                width: parent.width
                height: 24
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Memory")
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                UiText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2715"
                    color: closeMa.containsMouse ? root.seal : root.sumi
                    font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.memVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── usage bar ──
            Item {
                width: parent.width
                height: 30
                UiText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    text: memPanel.pct + "%"
                    color: root.seal
                    font.family: root.mono; font.pixelSize: 11; font.weight: Font.Medium
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 8; radius: 4
                    color: root.fillActive
                    Rectangle {
                        width: parent.width * memPanel.pct / 100
                        height: parent.height; radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            Sparkline {
                width: parent.width
                root: memPanel.root
                value: memPanel.pct
                active: memPanel.visible && root.memVisible
            }

            // ── stats ──
            Column {
                width: parent.width
                spacing: 4
                Row {
                    width: parent.width
                    UiText { text: I18n.tr("Used"); color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText { text: memPanel.usedGiB.toFixed(1) + " GiB"; color: root.ink; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                    UiText { text: memPanel.memUsed + " MiB"; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6); font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                }
                Row {
                    width: parent.width
                    UiText { text: I18n.tr("Available"); color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText { text: (memPanel.memAvail / 1024).toFixed(1) + " GiB"; color: root.ink; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                    UiText { text: memPanel.memAvail + " MiB"; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6); font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                }
                Row {
                    width: parent.width
                    UiText { text: I18n.tr("Total"); color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText { text: memPanel.totalGiB.toFixed(1) + " GiB"; color: root.ink; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                    UiText { text: memPanel.memTotal + " MiB"; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6); font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                }
                Row {
                    width: parent.width
                    visible: root.memorySpeedMTs > 0
                    UiText { text: I18n.tr("Speed"); color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText { text: root.memorySpeedMTs + " MT/s"; color: root.ink; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                    UiText { text: root.memoryType; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6); font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── button ──
            Rectangle {
                width: parent.width
                height: 28; radius: root.panelButtonRadius
                color: btopMa.containsMouse ? root.fillPrimaryHover : root.seal
                Behavior on color { ColorAnimation { duration: 120 } }
                UiText {
                    anchors.centerIn: parent
                    text: I18n.tr("Open btop")
                    color: root.paper
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: btopMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.memVisible = false;
                        btopRunner.running = false;
                        btopRunner.running = true;
                    }
                }
            }
        }
    }

    Process {
        id: btopRunner
        command: ["bash", "-c", "kitty 'btop'"]
    }
}
