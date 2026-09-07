import QtQuick
import "../modules"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Ryoku.Ui.Singletons

PanelWindow {
    id: cpuPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-cpu"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6
    readonly property int cpuPct: root.systemCpuPercent

    readonly property string topologySummary: root.cpuCoreCount > 0 && root.cpuThreadCount > 0
        ? root.cpuCoreCount + "C / " + root.cpuThreadCount + "T" : ""
    readonly property string clockSummary: root.cpuClockMHz > 0
        ? (root.cpuClockMHz / 1000).toFixed(1) + " / "
            + (root.cpuMaxClockMHz / 1000).toFixed(1) + " GHz"
        : ""
    readonly property string loadSummary: root.systemLoad1.toFixed(2) + " · "
        + root.systemLoad5.toFixed(2) + " · " + root.systemLoad15.toFixed(2)
    readonly property string powerMode: {
        var mode = root.cpuEnergyPreference !== ""
            ? root.cpuEnergyPreference : root.cpuScalingGovernor
        return mode.replace(/_/g, " ")
    }

    property real reveal: root.cpuVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.cpuVisible ? 160 : 120
            easing.type: root.cpuVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.cpuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    component InfoRow: Item {
        property string label: ""
        property string value: ""
        property color valueColor: cpuPanel.root.ink

        width: parent ? parent.width : 0
        height: 16
        visible: value !== ""

        UiText {
            id: infoLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: label
            color: cpuPanel.root.sumiHi
            font.family: cpuPanel.root.mono
            font.pixelSize: 10
        }
        UiText {
            anchors.left: infoLabel.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: value
            color: valueColor
            font.family: cpuPanel.root.mono
            font.pixelSize: 10
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.cpuVisible = false
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
            root: cpuPanel.root
            ownerActive: cpuPanel.root.cpuVisible
            targetX: cpuPanel.root.cpuBarX
            reveal: cpuPanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.cpuBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - cpuPanel.reveal)
            : (barBottom + gap) - 2 * (1 - cpuPanel.reveal)
        opacity: cpuPanel.reveal
        focus: root.cpuVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.cpuVisible = false
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
                    text: "CPU"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                UiText {
                    anchors.right: closeText.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("KERNEL %1").arg(root.kernelRelease)
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 9
                }
                UiText {
                    id: closeText
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
                        onClicked: root.cpuVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Item {
                width: parent.width
                height: 16
                UiText {
                    anchors.left: parent.left
                    anchors.right: topologyValue.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.cpuModelName
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                UiText {
                    id: topologyValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: cpuPanel.topologySummary
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 10
                }
            }

            Item {
                width: parent.width
                height: 16
                UiText {
                    id: cpuLbl
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("USAGE")
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }
                UiText {
                    id: cpuVal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: cpuPanel.cpuPct + "%"
                    color: root.seal
                    font.family: root.mono
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                Rectangle {
                    anchors.left: cpuLbl.right
                    anchors.leftMargin: 8
                    anchors.right: cpuVal.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 8
                    radius: 4
                    color: root.fillActive
                    Rectangle {
                        width: parent.width * cpuPanel.cpuPct / 100
                        height: parent.height
                        radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            Sparkline {
                width: parent.width
                root: cpuPanel.root
                value: cpuPanel.cpuPct
                active: cpuPanel.visible && root.cpuVisible
            }

            InfoRow { label: I18n.tr("Clock"); value: cpuPanel.clockSummary }
            InfoRow { label: I18n.tr("Load 1 · 5 · 15"); value: cpuPanel.loadSummary }
            InfoRow {
                label: I18n.tr("Breakdown")
                value: "User " + root.systemCpuUserPercent + "% · System "
                    + root.systemCpuSystemPercent + "% · I/O " + root.systemCpuIoWaitPercent + "%"
            }
            InfoRow { label: I18n.tr("Power mode"); value: cpuPanel.powerMode }
            InfoRow {
                label: I18n.tr("Throttling")
                value: root.cpuThrottleCount > 0 ? I18n.tr("%1 events").arg(root.cpuThrottleCount) : ""
                valueColor: root.sealRaw
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Item {
                width: parent.width
                height: 14
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("TOP PROCESSES")
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
                UiText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CPU"
                    color: root.sumi
                    font.family: root.mono
                    font.pixelSize: 9
                }
            }

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: 3
                    delegate: Item {
                        required property int index
                        readonly property var process: index < root.cpuTopProcesses.length
                            ? root.cpuTopProcesses[index] : null
                        width: col.width
                        height: 16

                        UiText {
                            id: processRank
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(index + 1).padStart(2, "0")
                            color: root.sumi
                            font.family: root.mono
                            font.pixelSize: 9
                        }
                        UiText {
                            anchors.left: processRank.right
                            anchors.leftMargin: 10
                            anchors.right: processValue.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: process ? process.name : (index === 0 ? I18n.tr("Collecting…") : "-")
                            color: process ? root.ink : root.sumi
                            font.family: root.mono
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                        UiText {
                            id: processValue
                            width: 52
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: process ? Number(process.percent).toFixed(1) + "%" : "-"
                            color: process ? root.ink : root.sumi
                            font.family: root.mono
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
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
                        root.cpuVisible = false
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
