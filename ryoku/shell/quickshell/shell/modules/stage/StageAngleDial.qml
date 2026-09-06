import QtQuick
import shell.services

// Shadow direction dial (0 = right, 90 = down) — drag the dot (docs/stage.md).
Item {
    id: dial
    property real angle: 90
    signal changed(real deg)
    width: 88
    height: 88
    readonly property real rad: dial.angle * Math.PI / 180
    readonly property real cx: 44
    readonly property real cy: 44
    readonly property real dotR: 26

    Rectangle {
        anchors.centerIn: parent
        width: 80
        height: 80
        radius: 40
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
            x: dial.cx - 1 + Math.cos(t) * 36
            y: dial.cy - 2.5 + Math.sin(t) * 36
        }
    }
    Rectangle {
        id: needle
        width: 2
        height: dial.dotR - 4
        radius: 1
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
        x: dial.cx - 1
        y: dial.cy - (dial.dotR - 4)
        transformOrigin: Item.Bottom
        rotation: dial.angle + 90
        Behavior on rotation { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.centerIn: parent
        width: 8
        height: 8
        radius: 4
        color: Theme.onSurface
    }
    Rectangle {
        id: dot
        width: 20
        height: 20
        radius: 10
        color: Theme.primary
        border.width: 3
        border.color: Theme.surface
        x: dial.cx - 10 + Math.cos(dial.rad) * dial.dotR
        y: dial.cy - 10 + Math.sin(dial.rad) * dial.dotR
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
            if (Math.abs(dx) < 2 && Math.abs(dy) < 2) return;
            let deg = Math.atan2(dy, dx) * 180 / Math.PI;
            if (deg < 0) deg += 360;
            dial.changed(Math.round(deg));
        }
        onPositionChanged: mouse => {
            if (mouse.buttons & Qt.LeftButton)
                update(mouse.x, mouse.y);
        }
        onPressed: mouse => update(mouse.x, mouse.y)
    }
}
