import QtQuick
import shell.services
import "Singletons"

// Effect tab (docs/stage.md): the Off | Depth | Parallax segmented control and
// the one-line caption for the selected effect. Nothing else.
Item {
    id: t
    readonly property string effect: StageBackend.effect

    function caption(e) {
        if (e === "depth") return "Depth: the subject sits in front of your widgets.";
        if (e === "parallax") return "Parallax: the scene drifts with your cursor.";
        return "Off: plain wallpaper.";
    }

    StageSeg {
        id: seg
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(320, parent.width * 0.5)
        options: [
            { id: "off", label: "Off" },
            { id: "depth", label: "Depth" },
            { id: "parallax", label: "Parallax" }
        ]
        current: t.effect
        onChose: id => StageBackend.setEffect(id)
    }
    Text {
        anchors.left: seg.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: t.caption(t.effect)
        elide: Text.ElideRight
        color: Theme.onSurfaceVariant
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm
    }
}
