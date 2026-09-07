import QtQuick
import QtQuick.Controls
import ".."
import "../services"
import Ryoku.Ui.Singletons

Item {
    id: folderFilter

    property var colors
    property var service

    readonly property int _skew: 10 * Config.uiScale
    readonly property var _folders: service ? (service.availableFolders || []) : []

    visible: _folders.length > 0
    width: visible ? (_content.width + 24 + _skew) : 0
    height: 24 * Config.uiScale

    readonly property string _currentLabel: {
        if (!service) return I18n.tr("Main")
        var f = service.selectedFolder
        if (f === "*") return I18n.tr("All folders")
        if (f === "") return I18n.tr("Main")
        return f
    }
    readonly property bool _engaged: service && service.selectedFolder !== ""

    Canvas {
        anchors.fill: parent
        property color fillColor: folderFilter._engaged
            ? (folderFilter.colors ? Qt.rgba(folderFilter.colors.primary.r, folderFilter.colors.primary.g, folderFilter.colors.primary.b, 0.22) : Qt.rgba(0.4, 0.5, 0.8, 0.22))
            : (folderFilter.colors ? Qt.rgba(folderFilter.colors.surfaceContainer.r, folderFilter.colors.surfaceContainer.g, folderFilter.colors.surfaceContainer.b, 0.85) : Qt.rgba(0.1, 0.12, 0.18, 0.85))
        property color strokeColor: folderFilter._engaged
            ? (folderFilter.colors ? Qt.rgba(folderFilter.colors.primary.r, folderFilter.colors.primary.g, folderFilter.colors.primary.b, 0.55) : Qt.rgba(0.5, 0.7, 1.0, 0.55))
            : (folderFilter.colors ? Qt.rgba(folderFilter.colors.primary.r, folderFilter.colors.primary.g, folderFilter.colors.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.08))
        onFillColorChanged: requestPaint()
        onStrokeColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var sk = folderFilter._skew
            ctx.fillStyle = fillColor
            ctx.strokeStyle = strokeColor
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(sk, 0)
            ctx.lineTo(width, 0)
            ctx.lineTo(width - sk, height)
            ctx.lineTo(0, height)
            ctx.closePath()
            ctx.fill()
            ctx.stroke()
        }
    }

    Row {
        id: _content
        anchors.centerIn: parent
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f024b}"
            font.family: Style.fontFamilyNerdIcons
            font.pixelSize: 12 * Config.uiScale
            color: folderFilter._engaged
                ? (folderFilter.colors ? folderFilter.colors.primary : Style.fallbackAccent)
                : (folderFilter.colors ? Qt.rgba(folderFilter.colors.surfaceText.r, folderFilter.colors.surfaceText.g, folderFilter.colors.surfaceText.b, 0.6) : Qt.rgba(1, 1, 1, 0.5))
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: folderFilter._currentLabel
            font.family: Style.fontFamily
            font.pixelSize: 10 * Config.uiScale
            font.weight: Font.Bold
            font.letterSpacing: 0.5
            color: folderFilter._engaged
                ? (folderFilter.colors ? folderFilter.colors.primary : Style.fallbackAccent)
                : (folderFilter.colors ? Qt.rgba(folderFilter.colors.surfaceText.r, folderFilter.colors.surfaceText.g, folderFilter.colors.surfaceText.b, 0.6) : Qt.rgba(1, 1, 1, 0.5))
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "▾"
            font.pixelSize: 9 * Config.uiScale
            color: folderFilter.colors ? Qt.rgba(folderFilter.colors.surfaceText.r, folderFilter.colors.surfaceText.g, folderFilter.colors.surfaceText.b, 0.45) : Qt.rgba(1, 1, 1, 0.35)
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: _menu.open()
    }

    function _menuModel() {
        var out = [{ label: I18n.tr("Main"), value: "" }, { label: I18n.tr("All folders"), value: "*" }]
        for (var i = 0; i < _folders.length; i++) out.push({ label: _folders[i], value: _folders[i] })
        return out
    }

    Popup {
        id: _menu
        y: folderFilter.height + 6
        x: 0
        padding: 4
        modal: false
        focus: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

        background: Rectangle {
            color: folderFilter.colors
                ? Qt.rgba(folderFilter.colors.surface.r, folderFilter.colors.surface.g, folderFilter.colors.surface.b, 0.97)
                : Qt.rgba(0.08, 0.08, 0.12, 0.97)
            radius: 8
            border.width: 1
            border.color: folderFilter.colors
                ? Qt.rgba(folderFilter.colors.primary.r, folderFilter.colors.primary.g, folderFilter.colors.primary.b, 0.4)
                : Qt.rgba(1, 1, 1, 0.2)
        }

        contentItem: Column {
            spacing: 1

            Repeater {
                model: folderFilter._menuModel()

                delegate: Item {
                    id: _menuRow
                    required property var modelData
                    width: 150 * Config.uiScale
                    height: 26 * Config.uiScale
                    readonly property bool _sel: folderFilter.service && folderFilter.service.selectedFolder === modelData.value

                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: _menuRow._sel
                            ? (folderFilter.colors ? Qt.rgba(folderFilter.colors.primary.r, folderFilter.colors.primary.g, folderFilter.colors.primary.b, 0.16) : Qt.rgba(1, 1, 1, 0.10))
                            : (_rowMouse.containsMouse ? (folderFilter.colors ? Qt.rgba(folderFilter.colors.primary.r, folderFilter.colors.primary.g, folderFilter.colors.primary.b, 0.08) : Qt.rgba(1, 1, 1, 0.05)) : "transparent")
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10 * Config.uiScale
                        anchors.right: parent.right
                        anchors.rightMargin: 8 * Config.uiScale
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr(_menuRow.modelData.label)
                        elide: Text.ElideRight
                        font.family: Style.fontFamily
                        font.pixelSize: 11 * Config.uiScale
                        font.weight: _menuRow._sel ? Font.Bold : Font.Normal
                        color: _menuRow._sel
                            ? (folderFilter.colors ? folderFilter.colors.primary : "#7986cb")
                            : (folderFilter.colors ? folderFilter.colors.surfaceText : "#ffffff")
                    }

                    MouseArea {
                        id: _rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (folderFilter.service) folderFilter.service.selectedFolder = _menuRow.modelData.value
                            _menu.close()
                        }
                    }
                }
            }
        }
    }
}
