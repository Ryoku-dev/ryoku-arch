import QtQuick
import "../modules"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Ryoku.Ui.Singletons

PanelWindow {
    id: gpuPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-gpu"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6
    readonly property int gpuUtil: root.gpuPercent
    readonly property int gpuTemp: root.gpuTemperatureC
    readonly property int gpuMemUsed: root.gpuMemoryUsedMiB
    readonly property int gpuMemTotal: root.gpuMemoryTotalMiB

    function gib(mib) {
        return (Math.max(0, mib) / 1024).toFixed(1) + " GiB"
    }

    property real reveal: root.gpuVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.gpuVisible ? 160 : 120
            easing.type: root.gpuVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.gpuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    component InfoRow: Item {
        property string label: ""
        property string value: ""

        width: parent ? parent.width : 0
        height: 16
        visible: value !== ""

        UiText {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: label
            color: gpuPanel.root.sumiHi
            font.family: gpuPanel.root.mono
            font.pixelSize: 10
        }
        UiText {
            anchors.left: parent.left
            anchors.leftMargin: 112
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: value
            color: gpuPanel.root.ink
            font.family: gpuPanel.root.mono
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.gpuVisible = false
    }

    Rectangle {
        id: card
        width: 340
        height: col.implicitHeight + 24
        radius: reveal > 0.001 ? root.panelRadius : 0
        color: "transparent"
        border.color: root.panelBorder
        border.width: 0
        PillShadow { theme: root }
        ConnectedPanelSurface {
            root: gpuPanel.root
            ownerActive: gpuPanel.root.gpuVisible
            targetX: gpuPanel.root.gpuBarX
            reveal: gpuPanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.gpuBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - gpuPanel.reveal)
            : (barBottom + gap) - 2 * (1 - gpuPanel.reveal)
        opacity: gpuPanel.reveal
        focus: root.gpuVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.gpuVisible = false
                event.accepted = true
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Item {
                width: parent.width
                height: 24
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "GPU"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                UiText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: closeMa.containsMouse ? root.seal : root.sumi
                    font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.gpuVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            InfoRow {
                label: I18n.tr("Model")
                value: root.gpuAvailable
                    ? (root.gpuName !== "" ? root.gpuName
                        : (root.gpuBackend === "nvidia" ? "NVIDIA GPU" : "GPU"))
                    : ""
            }

            Item {
                width: parent.width
                height: 16
                visible: root.gpuAvailable
                UiText {
                    id: gpuLbl
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("USAGE")
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }
                UiText {
                    id: gpuVal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: gpuPanel.gpuUtil + "%"
                    color: root.seal
                    font.family: root.mono
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                Rectangle {
                    anchors.left: gpuLbl.right
                    anchors.leftMargin: 8
                    anchors.right: gpuVal.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 8
                    radius: 4
                    color: root.fillActive
                    Rectangle {
                        width: parent.width * gpuPanel.gpuUtil / 100
                        height: parent.height
                        radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            Sparkline {
                width: parent.width
                root: gpuPanel.root
                value: gpuPanel.gpuUtil
                active: gpuPanel.visible && root.gpuVisible
                visible: root.gpuAvailable
            }

            InfoRow {
                label: I18n.tr("Temperature")
                value: gpuPanel.gpuTemp > 0 ? gpuPanel.gpuTemp + "°C" : ""
            }
            InfoRow {
                label: I18n.tr("VRAM")
                value: gpuPanel.gpuMemTotal > 0
                    ? gpuPanel.gib(gpuPanel.gpuMemUsed) + " / " + gpuPanel.gib(gpuPanel.gpuMemTotal)
                    : ""
            }
            InfoRow {
                label: I18n.tr("Graphics clock")
                value: root.gpuClockMHz > 0 ? root.gpuClockMHz + " MHz" : ""
            }
            InfoRow {
                label: I18n.tr("Power")
                value: root.gpuPowerW > 0
                    ? root.gpuPowerW.toFixed(0) + " W"
                        + (root.gpuPowerLimitW > 0 ? " / " + root.gpuPowerLimitW.toFixed(0) + " W" : "")
                    : ""
            }
            InfoRow {
                label: I18n.tr("Fan · state")
                value: root.gpuFanPercent > 0 || root.gpuPerformanceState !== ""
                    ? (root.gpuFanPercent > 0 ? root.gpuFanPercent + "%" : "-")
                        + (root.gpuPerformanceState !== "" ? " · " + root.gpuPerformanceState : "")
                    : ""
            }
            InfoRow { label: I18n.tr("Driver"); value: root.gpuDriverVersion }

            UiText {
                width: parent.width
                visible: !root.gpuAvailable
                text: I18n.tr("GPU telemetry unavailable")
                color: root.sumiHi
                font.family: root.mono
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Rectangle {
                width: parent.width
                height: 28
                radius: root.panelButtonRadius
                color: btopMa.containsMouse ? root.fillPrimaryHover : root.seal
                Behavior on color { ColorAnimation { duration: 120 } }
                UiText {
                    anchors.centerIn: parent
                    text: I18n.tr("Open btop")
                    color: root.paper
                    font.family: root.mono
                    font.pixelSize: 11
                }
                MouseArea {
                    id: btopMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.gpuVisible = false
                        btopRunner.running = false
                        btopRunner.running = true
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
