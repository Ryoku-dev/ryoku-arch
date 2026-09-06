pragma ComponentBehavior: Bound

import QtQuick
import shell.services
import "../../../../stage"
import "../../../../stage/Singletons" as St

// Stage entry card for the Super+Esc quick-settings panel (docs/stage.md).
// Stage is a spatial feature, so it is edited on the desktop, not in a scrolling
// sidebar: this card only previews the current cut, switches the effect, and
// opens the desktop edit mode. Every knob lives in the on-desktop toolbar.
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
    function caption(e) {
        if (e === "depth") return "The subject sits in front of your widgets.";
        if (e === "parallax") return "The scene drifts with your cursor.";
        return "Plain wallpaper.";
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

        StageSeg {
            options: [
                { id: "off", label: "Off" },
                { id: "depth", label: "Depth" },
                { id: "parallax", label: "Parallax" }
            ]
            current: root.effect
            onChose: id => root.sb.setEffect(id)
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.caption(root.effect)
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
        }

        StageBtn {
            kind: "filled"
            icon: "open_with"
            label: "Edit stage"
            onAct: root.editStage()
        }
    }
}
