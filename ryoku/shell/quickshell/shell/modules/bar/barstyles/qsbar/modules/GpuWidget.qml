import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root
    readonly property color contentColor: root.widgetContentColor("G17", root.widgetIconColor)

    readonly property int percent: root.gpuPercent
    readonly property string tooltipText: {
        var label = root.gpuBackend === "nvidia" ? "NVIDIA GPU" : "GPU"
        var text = label + " · " + percent + "%"
        if (root.gpuTemperatureC > 0) text += " · " + root.gpuTemperatureC + "°C"
        if (root.gpuMemoryTotalMiB > 0)
            text += I18n.tr(" · %1/%2 MiB").arg(root.gpuMemoryUsedMiB).arg(root.gpuMemoryTotalMiB)
        return text
    }

    visible: implicitWidth > 0.5
    implicitWidth: root.modGpu && root.gpuAvailable ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    opacity: root.modGpu && root.gpuAvailable ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 13

            Image {
                anchors.fill: parent
                source: Qt.resolvedUrl("../assets/gpu-card.svg")
                sourceSize: Qt.size(54, 39)
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                layer.enabled: true
                layer.smooth: true
                layer.textureSize: Qt.size(54, 39)
                layer.effect: ShaderEffect {
                    property color tintColor: rootMod.contentColor
                    fragmentShader: Qt.resolvedUrl("../shaders/logo-tint.frag.qsb")
                }
            }
        }

        UiText {
            visible: !root.iconOnly("G17")
            anchors.verticalCenter: parent.verticalCenter
            text: String(Math.min(100, rootMod.percent)).padStart(2, "0") + "%"
            color: rootMod.contentColor
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited: tip.hide()
        onClicked: { tip.hide(); root.gpuVisible = !root.gpuVisible }
    }
}
