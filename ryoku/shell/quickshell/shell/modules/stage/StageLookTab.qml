import QtQuick
import shell.services
import "Singletons"

// Look tab (docs/stage.md): Quality, Edge, Shadow and -- only while Shadow > 0
// -- the shadow angle dial. Everything the layers inherit, in one row that
// shrinks the sliders on narrow screens instead of wrapping (tested at 1366).
Item {
    id: t
    readonly property real gap: 16
    readonly property bool shadowOn: Config.shadow > 0
    readonly property real dialW: t.shadowOn ? 52 : 0
    readonly property real qualW: Math.max(300, Math.min(440, t.width * 0.36))
    readonly property real slidersW: t.width - t.qualW - t.dialW - t.gap * (t.shadowOn ? 3 : 2)
    readonly property real sliderW: Math.max(88, t.slidersW / 2)

    function setQuality(id) {
        Config.setQuality(id);
        if (StageBackend.qualityInstalled(id) && StageBackend.effect !== "off")
            StageBackend.refresh();
    }

    StageQuality {
        id: ql
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        width: t.qualW
        current: Config.quality
        onChose: id => t.setQuality(id)
    }
    StageDragSlider {
        id: edge
        x: t.qualW + t.gap
        anchors.verticalCenter: parent.verticalCenter
        width: t.sliderW
        title: "Edge"
        value: Config.edge
        min: 0; max: 1; decimals: 2
        onChanged: v => Config.setEdge(v)
    }
    StageDragSlider {
        id: shadow
        x: edge.x + t.sliderW + t.gap
        anchors.verticalCenter: parent.verticalCenter
        width: t.sliderW
        title: "Shadow"
        value: Config.shadow
        min: 0; max: 1; decimals: 2
        onChanged: v => Config.setShadow(v)
    }
    StageAngleDial {
        x: shadow.x + t.sliderW + t.gap
        anchors.verticalCenter: parent.verticalCenter
        visible: t.shadowOn
        dim: 52
        angle: Config.shadowAngle
        onChanged: deg => Config.setShadowAngle(deg)
    }
}
