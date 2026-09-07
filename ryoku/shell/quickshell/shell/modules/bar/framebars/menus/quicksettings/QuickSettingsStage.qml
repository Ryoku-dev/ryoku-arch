pragma ComponentBehavior: Bound

import QtQuick
import shell.services
import "../../../../stage"
import "../../../../stage/Singletons" as St

// Stage entry card for the Super+Esc quick-settings panel (docs/stage.md).
// Stage is a spatial feature, edited on the desktop, so the sidebar holds only
// this: a live preview of the current cut, the two switches (Depth, and Parallax
// inside it), and Edit desktop. Every other knob lives on the desktop island.
Item {
    id: root

    property real s: 1
    property bool open: false
    property var navigate: null
    property var closePanel: null

    readonly property var sb: St.StageBackend
    readonly property string effect: root.sb.effect
    readonly property string wall: root.sb.current

    function editStage() {
        const st = ShellState.forActive();
        if (st)
            st.stageComposing = true;
        if (root.closePanel)
            root.closePanel();
    }

    Rectangle { anchors.fill: parent; color: Theme.surface }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12

        Text {
            text: "Stage"
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontLg
            font.weight: Font.DemiBold
        }

        StagePreviewCard {
            wallpaperUrl: root.wall !== "" ? "file://" + root.wall : ""
            subjectUrl: root.sb.layerUrlFor(root.wall, 0)
            busy: root.sb.busy
        }

        StageSwitch {
            label: "Depth"
            checked: root.effect !== "off"
            onToggled: root.sb.setEffect(root.effect === "off" ? "depth" : "off")
        }
        StageSwitch {
            label: "Parallax"
            checked: root.effect === "parallax"
            switchEnabled: root.effect !== "off"
            onToggled: root.sb.setEffect(root.effect === "parallax" ? "depth" : "parallax")
        }

        StageBtn {
            kind: "filled"
            icon: "open_with"
            label: "Edit desktop"
            onAct: root.editStage()
        }
    }
}
