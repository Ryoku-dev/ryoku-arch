import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root
    readonly property color contentColor: root.widgetContentColor("G8", root.ink)

    readonly property string state: root.voxState   // idle | recording | transcribing
    readonly property string hint:  root.voxHint
    readonly property bool   hasVoxtype: root.voxAvailable

    readonly property string displayIcon: {
        if (state === "recording")    return "\uE029"   // mic
        if (state === "transcribing") return "\uE65F"   // auto_awesome
        return ""
    }

    visible: displayIcon !== ""
    implicitWidth: visible ? 20 : 0
    implicitHeight: 28


    readonly property string tooltipText: hint !== "" ? hint : (state === "recording" ? I18n.tr("Voxtype recording") : I18n.tr("Voxtype transcribing"))

    IconText {
        id: ico
        anchors.centerIn: parent
        text: rootMod.displayIcon
        color: root.widgetHasFill("G8")
            ? rootMod.contentColor
            : (rootMod.state === "recording" ? root.seal : root.ink)
        font.pixelSize: 14

        // pulse while recording
        SequentialAnimation on opacity {
            running: rootMod.state === "recording"
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 600; easing.type: Easing.InOutSine }
        }
        onTextChanged: if (rootMod.state !== "recording") opacity = 1.0
    }

    Process { id: modelProc;  command: ["bash", "-c", "true"] }
    Process { id: configProc; command: ["bash", "-c", "true"] }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tip.show()
        onExited:  { tip.hide() }
        onClicked: (e) => {
            tip.hide()
            if (e.button === Qt.RightButton) { configProc.running = false; configProc.running = true }
            else                             { modelProc.running = false;  modelProc.running = true }
        }
    }
}
