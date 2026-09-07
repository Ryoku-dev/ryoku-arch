pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Ryoku.Ui.Singletons

PanelWindow {
    id: cover

    required property var targetScreen
    required property string phase
    required property bool startClose
    required property var reloadCover
    signal mapped()

    screen: targetScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "ryoku-reload-cover"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region {}

    property real diagonal: Math.sqrt(width * width + height * height)
    property real iris: diagonal
    property bool mappedReported: false
    readonly property real mediaOpacity: {
        if (cover.phase === "closing") return Math.max(0, 1 - cover.iris / (cover.diagonal * 0.38));
        if (cover.phase === "hold" || cover.phase === "failed") return 1;
        if (cover.phase === "opening") return Math.max(0, 1 - cover.iris / (cover.diagonal * 0.38));
        return 0;
    }


    function reportMapped(): void {
        if (!mappedReported && backingWindowVisible && width > 0 && height > 0) {
            mappedReported = true;
            mapped();
        }
    }

    function closeIris(): void {
        iris = diagonal;
        closeAnim.restart();
    }
    function openIris(): void {
        iris = 0;
        openAnim.restart();
    }

    Component.onCompleted: reportMapped()
    onBackingWindowVisibleChanged: reportMapped()
    onWidthChanged: reportMapped()
    onHeightChanged: reportMapped()
    onStartCloseChanged: if (startClose) closeIris()
    onPhaseChanged: if (phase === "opening") openIris()

    NumberAnimation {
        id: closeAnim
        target: cover
        property: "iris"
        from: cover.diagonal
        to: 0
        duration: 520
        easing.type: Easing.InOutCubic
    }
    NumberAnimation {
        id: openAnim
        target: cover
        property: "iris"
        from: 0
        to: cover.diagonal
        duration: 520
        easing.type: Easing.InOutCubic
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        visible: cover.phase === "hold" || cover.phase === "failed"
    }
    Item {
        anchors.fill: parent
        visible: cover.phase === "closing" || cover.phase === "opening"

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "black"
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                PathRectangle { x: 0; y: 0; width: cover.width; height: cover.height }
                PathSvg {
                    path: {
                        const r = Math.max(0.001, cover.iris);
                        const x = cover.width / 2 - r;
                        const y = cover.height / 2;
                        return "M " + x + " " + y
                            + " A " + r + " " + r + " 0 1 0 " + (x + r * 2) + " " + y
                            + " A " + r + " " + r + " 0 1 0 " + x + " " + y + " Z";
                    }
                }
            }
        }
    }

    ReloadMedia {
        id: media
        anchors.fill: parent
        descriptor: cover.reloadCover
        active: cover.backingWindowVisible
        forceDefault: cover.phase === "failed"
        opacity: cover.mediaOpacity
        scale: opacity < 1 ? 0.94 + opacity * 0.06 : 1
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.verticalCenter
        anchors.topMargin: media.defaultLogoHeight / 2 + 18
        visible: cover.phase !== "failed" && media.showingDefault && cover.mediaOpacity > 0
        text: I18n.tr("SHELL RELOADING")
        color: "#d8e8f5"
        opacity: cover.mediaOpacity * 0.72
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
        font.letterSpacing: 4
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.verticalCenter
        anchors.topMargin: media.defaultLogoHeight / 2 + 28
        visible: cover.phase === "failed"
        text: I18n.tr("RELOAD FAILED")
        color: "#ff735d"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 14
        font.letterSpacing: 3
    }
}
