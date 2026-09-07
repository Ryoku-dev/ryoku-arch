pragma ComponentBehavior: Bound
import QtQuick
import shell.services

// Shadow direction dial (0 = right, 90 = down): drag the dot (docs/stage.md).
// `dim` sizes the whole control so it fits the compact inspector row.
Item {
    id: dial
    property real angle: 90
    property real dim: 88
    signal changed(real deg)
    width: dial.dim
    height: dial.dim
    readonly property real rad: dial.angle * Math.PI / 180
    readonly property real cx: dial.dim / 2
    readonly property real cy: dial.dim / 2
    readonly property real ring: dial.dim - 8
    readonly property real tickR: dial.dim * 0.41
    readonly property real dotR: dial.dim * 0.30
    readonly property real dotSize: dial.dim * 0.23

    Rectangle {
        anchors.centerIn: parent
        width: dial.ring
        height: dial.ring
        radius: dial.ring / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) }
            GradientStop { position: 1.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) }
        }
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
    }
    Repeater {
        model: [0, 90, 180, 270]
        delegate: Rectangle {
            required property int modelData
            readonly property real t: modelData * Math.PI / 180
            width: 2
            height: 5
            radius: 1
            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.5)
            x: dial.cx - 1 + Math.cos(t) * dial.tickR
            y: dial.cy - 2.5 + Math.sin(t) * dial.tickR
        }
    }
    Rectangle {
        id: needle
        width: 2
        height: dial.dotR - 3
        radius: 1
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
        x: dial.cx - 1
        y: dial.cy - (dial.dotR - 3)
        transformOrigin: Item.Bottom
        rotation: dial.angle + 90
        Behavior on rotation { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.centerIn: parent
        width: dial.dim * 0.09
        height: dial.dim * 0.09
        radius: width / 2
        color: Theme.onSurface
    }
    Rectangle {
        id: dot
        width: dial.dotSize
        height: dial.dotSize
        radius: dial.dotSize / 2
        color: Theme.primary
        border.width: 3
        border.color: Theme.surface
        x: dial.cx - dial.dotSize / 2 + Math.cos(dial.rad) * dial.dotR
        y: dial.cy - dial.dotSize / 2 + Math.sin(dial.rad) * dial.dotR
        Behavior on x { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function update(mx, my) {
            const dx = mx - dial.cx;
            const dy = my - dial.cy;
            if (Math.abs(dx) < 2 && Math.abs(dy) < 2)
                return;
            let deg = Math.atan2(dy, dx) * 180 / Math.PI;
            if (deg < 0)
                deg += 360;
            dial.changed(Math.round(deg));
        }
        onPositionChanged: mouse => {
            if (mouse.buttons & Qt.LeftButton)
                update(mouse.x, mouse.y);
        }
        onPressed: mouse => update(mouse.x, mouse.y)
    }
}
