import QtQuick
import "../modules"
import Quickshell
import Quickshell.Wayland
import Ryoku.Ui.Singletons

PanelWindow {
    id: thermalPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-thermals"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6

    function status(value, maximum, critical) {
        if (critical > 0 && value >= critical * 0.9) return I18n.tr("HOT")
        if (maximum > 0 && value >= maximum * 0.8) return I18n.tr("WARM")
        return maximum > 0 || critical > 0 ? I18n.tr("NORMAL") : I18n.tr("LIVE")
    }

    function statusColor(value, maximum, critical) {
        var state = status(value, maximum, critical)
        if (state === "HOT") return root.sealRaw
        if (state === "WARM") return root.color03
        return root.seal
    }

    property real reveal: root.thermalVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.thermalVisible ? 160 : 120
            easing.type: root.thermalVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.thermalVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    component ThermalRow: Item {
        required property string label
        required property int value
        property int maximum: 0
        property int critical: 0

        width: parent ? parent.width : 0
        height: 34
        visible: value > 0

        readonly property int scaleMax: critical > 0 ? critical : (maximum > 0 ? maximum : 100)
        readonly property color meterColor: thermalPanel.statusColor(value, maximum, critical)

        UiText {
            id: sensorLabel
            anchors.left: parent.left
            anchors.right: sensorValue.left
            anchors.rightMargin: 8
            anchors.top: parent.top
            text: label
            color: thermalPanel.root.sumiHi
            font.family: thermalPanel.root.mono
            font.pixelSize: 10
            elide: Text.ElideRight
        }

        UiText {
            id: sensorValue
            anchors.right: parent.right
            anchors.top: parent.top
            text: value + "°C · " + thermalPanel.status(value, maximum, critical)
            color: meterColor
            font.family: thermalPanel.root.mono
            font.pixelSize: 10
            font.weight: Font.Medium
        }

        Rectangle {
            id: meterTrack
            anchors.left: parent.left
            anchors.right: limitLabel.left
            anchors.rightMargin: 8
            anchors.bottom: parent.bottom
            height: 6
            radius: 3
            color: thermalPanel.root.fillActive

            Item {
                width: parent.width * Math.max(0, Math.min(1, value / scaleMax))
                height: parent.height
                clip: true
                Behavior on width { NumberAnimation { duration: 300 } }

                Rectangle {
                    width: meterTrack.width
                    height: meterTrack.height
                    radius: meterTrack.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: thermalPanel.root.accentHint }
                        GradientStop { position: 0.42; color: thermalPanel.root.color02 }
                        GradientStop { position: 0.72; color: thermalPanel.root.color03 }
                        GradientStop { position: 1.00; color: thermalPanel.root.sealRaw }
                    }
                }
            }
        }

        UiText {
            id: limitLabel
            width: 48
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: I18n.tr("%1° limit").arg(scaleMax)
            color: thermalPanel.root.sumi
            font.family: thermalPanel.root.mono
            font.pixelSize: 8
            horizontalAlignment: Text.AlignRight
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.thermalVisible = false
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
            root: thermalPanel.root
            ownerActive: thermalPanel.root.thermalVisible
            targetX: thermalPanel.root.thermalBarX
            reveal: thermalPanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.thermalBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - thermalPanel.reveal)
            : (barBottom + gap) - 2 * (1 - thermalPanel.reveal)
        opacity: thermalPanel.reveal
        focus: root.thermalVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.thermalVisible = false
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
                    text: I18n.tr("THERMALS")
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
                        onClicked: root.thermalVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Item {
                width: parent.width
                height: 14
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("BAR SENSOR")
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
                UiText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.barTemperatureSourceLabel(root.barTemperatureSource)
                    color: root.seal
                    font.family: root.mono
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }
            }

            Row {
                id: sourceRow
                width: parent.width
                height: 28
                spacing: 4

                Repeater {
                    model: [
                        { id: "cpu", label: "CPU" },
                        { id: "core", label: I18n.tr("CORE") },
                        { id: "gpu", label: "GPU" },
                        { id: "nvme", label: "NVME" },
                        { id: "memory", label: "RAM" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool selected: root.barTemperatureSource === modelData.id
                        readonly property bool available: root.barTemperatureSourceAvailable(modelData.id)
                        readonly property bool hovered: sourceMa.containsMouse && available

                        width: root.evenW((sourceRow.width - sourceRow.spacing * 4) / 5)
                        height: sourceRow.height
                        radius: root.panelButtonRadius
                        opacity: available ? 1 : 0.35
                        color: selected ? root.fillActive
                            : hovered ? root.fillHover
                            : root.fillIdle
                        border.color: (selected || hovered) ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        UiText {
                            anchors.centerIn: parent
                            text: I18n.tr(modelData.label)
                            color: (selected || hovered) ? root.seal : root.ink
                            font.family: root.mono
                            font.pixelSize: 9
                            font.weight: selected ? Font.Medium : Font.Normal
                        }

                        MouseArea {
                            id: sourceMa
                            anchors.fill: parent
                            enabled: parent.available
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.barTemperatureSource = parent.modelData.id
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            ThermalRow {
                label: I18n.tr("CPU package")
                value: root.cpuTemperatureC
                maximum: root.cpuTemperatureMaxC
                critical: root.cpuTemperatureCriticalC
            }
            ThermalRow {
                label: I18n.tr("Hottest CPU core")
                value: root.cpuCoreMaxTemperatureC
                maximum: root.cpuTemperatureMaxC
                critical: root.cpuTemperatureCriticalC
            }
            ThermalRow {
                label: root.gpuName !== "" ? "GPU · " + root.gpuName : "GPU"
                value: root.gpuTemperatureC
            }
            ThermalRow {
                label: I18n.tr("NVMe composite")
                value: root.nvmeTemperatureC
                maximum: root.nvmeTemperatureMaxC
                critical: root.nvmeTemperatureCriticalC
            }
            ThermalRow {
                label: I18n.tr("Memory sensor")
                value: root.memoryTemperatureC
            }

            UiText {
                width: parent.width
                visible: !root.cpuTemperatureAvailable && root.gpuTemperatureC <= 0
                    && root.nvmeTemperatureC <= 0 && root.memoryTemperatureC <= 0
                text: I18n.tr("No temperature sensors available")
                color: root.sumiHi
                font.family: root.mono
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
