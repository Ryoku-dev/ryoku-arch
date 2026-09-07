import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import ".."
import Ryoku.Ui.Singletons

Rectangle {
    id: preview
    property var colors

    property string sourcePath: ""
    property string bgMode: "blurred"
    property color  bgColor: "#000000"
    property int    blur: 30
    property int    shrinkPct: 70
    property int    borderPx: 15
    property color  borderColor: "#1a1a1a"

    property int previewHeight: 200
    property int sidePad: 12

    width: parent ? parent.width : 0
    height: previewHeight + sidePad * 2
    radius: 0
    color: "transparent"
    border.width: 0
    clip: true

    property int _frameCh: 14

    Shape {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        z: -1
        ShapePath {
            fillColor: preview.colors ? Qt.rgba(preview.colors.surfaceContainer.r, preview.colors.surfaceContainer.g, preview.colors.surfaceContainer.b, 0.78) : Qt.rgba(0.1, 0.12, 0.18, 0.78)
            strokeColor: "transparent"
            strokeWidth: 0
            startX: preview._frameCh; startY: 0
            PathLine { x: preview.width - 8;                    y: 0 }
            PathLine { x: preview.width - 8;                    y: preview.height - preview._frameCh }
            PathLine { x: preview.width - 8 - preview._frameCh; y: preview.height }
            PathLine { x: 0;                                    y: preview.height }
            PathLine { x: 0;                                    y: preview._frameCh }
            PathLine { x: preview._frameCh;                     y: 0 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: preview.colors ? preview.colors.primary : Qt.rgba(0.5, 0.7, 1.0, 1.0)
            strokeWidth: 3
            startX: 0; startY: preview._frameCh
            PathLine { x: preview._frameCh; y: 0 }
        }
    }

    Item {
        id: canvas
        anchors.centerIn: parent

        readonly property real _aspect: bgImage.sourceSize.width > 0
            ? bgImage.sourceSize.width / bgImage.sourceSize.height
            : 16/9
        readonly property real _availW: preview.width - preview.sidePad * 2
        readonly property real _availH: preview.previewHeight
        readonly property real _byHeight: _availH * _aspect
        readonly property real _byWidth: _availW / _aspect
        width: _byHeight <= _availW ? _byHeight : _availW
        height: _byHeight <= _availW ? _availH : _byWidth

        readonly property real _scale: bgImage.sourceSize.width > 0
            ? width / bgImage.sourceSize.width
            : 1.0

        Image {
            id: bgImage
            anchors.fill: parent
            source: preview.sourcePath ? "file://" + preview.sourcePath : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: preview.bgMode === "blurred" && status === Image.Ready
            layer.enabled: preview.bgMode === "blurred" && status === Image.Ready
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 64
                blur: Math.min(1.0, preview.blur / 50.0)
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: preview.bgMode === "solid"
            color: preview.bgColor
        }

        Rectangle {
            id: borderRect
            anchors.centerIn: parent
            width: parent.width * (preview.shrinkPct / 100)
            height: parent.height * (preview.shrinkPct / 100)
            color: preview.borderColor
            visible: preview.sourcePath.length > 0 && bgImage.status === Image.Ready

            Image {
                anchors.fill: parent
                anchors.margins: Math.max(1, Math.round(preview.borderPx * canvas._scale))
                source: preview.sourcePath ? "file://" + preview.sourcePath : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
        }

        Text {
            anchors.centerIn: parent
            visible: preview.sourcePath.length === 0
            text: I18n.tr("no source\napply a wallpaper first")
            horizontalAlignment: Text.AlignHCenter
            font.family: Style.fontFamily
            font.pixelSize: 11
            color: preview.colors
                ? Qt.rgba(preview.colors.onSurface.r, preview.colors.onSurface.g, preview.colors.onSurface.b, 0.45)
                : Qt.rgba(1, 1, 1, 0.4)
        }
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 8
        anchors.bottomMargin: 4
        text: I18n.tr("preview")
        font.family: Style.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 1.2
        color: preview.colors
            ? Qt.rgba(preview.colors.surfaceText.r, preview.colors.surfaceText.g, preview.colors.surfaceText.b, 0.35)
            : Qt.rgba(1, 1, 1, 0.25)
    }

    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 8
        anchors.bottomMargin: 4
        text: I18n.tr("approx · %1% · blur %2").arg(preview.shrinkPct).arg(preview.blur)
        font.family: Style.fontFamilyCode
        font.pixelSize: 9
        font.letterSpacing: 0.8
        color: preview.colors
            ? Qt.rgba(preview.colors.surfaceText.r, preview.colors.surfaceText.g, preview.colors.surfaceText.b, 0.35)
            : Qt.rgba(1, 1, 1, 0.25)
    }
}
