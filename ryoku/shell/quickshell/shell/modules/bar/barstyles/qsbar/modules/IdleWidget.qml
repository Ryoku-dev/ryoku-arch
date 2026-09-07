import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root
    readonly property color contentColor: root.widgetContentColor("G8", root.seal)

    // "Stay awake" mode active; Theme maps this to the active Ryoku idle backend.
    readonly property bool awake: root.stayAwake

    visible: awake
    implicitWidth: awake ? 20 : 0
    implicitHeight: 28


    readonly property string tooltipText: I18n.tr("Idle lock disabled")

    Text {
        anchors.centerIn: parent
        text: "\uDB86\uDED6"   // coffee (Nerd Font / JetBrainsMono)
        color: rootMod.contentColor
        font.family: root.mono
        font.pixelSize: 13
    }

    Process {
        id: toggleProc
        command: ["bash", "-c", "if command -v ryoku-cmd-caffeine >/dev/null 2>&1; then exec ryoku-cmd-caffeine; fi; exec omarchy toggle idle"]
        onExited: root.refreshStatusIndicators()
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited:  { tip.hide() }
        onClicked: {
            tip.hide()
            toggleProc.running = false; toggleProc.running = true
        }
    }
}
