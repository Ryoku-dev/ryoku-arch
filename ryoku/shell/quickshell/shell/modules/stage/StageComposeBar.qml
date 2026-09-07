import QtQuick
import shell.services
import Ryoku.Ui.Singletons

// The Stage compose toolbar (docs/stage.md). Compose mode frees the widgets for
// dragging; the knobs live in the sidebar, so this bar only names the gesture
// and carries Done. Esc or Enter also leaves.
Item {
    id: bar
    signal done()
    anchors.fill: parent

    onVisibleChanged: if (bar.visible) bar.forceActiveFocus()
    Keys.onEscapePressed: e => { bar.done(); e.accepted = true; }
    Keys.onReturnPressed: e => { bar.done(); e.accepted = true; }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        width: content.implicitWidth + 40
        height: content.implicitHeight + 24
        radius: Theme.radiusWidget
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.96)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 16
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Drag widgets in front of or behind the subject. Right-click a widget for more.")
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
            }
            StageBtn {
                anchors.verticalCenter: parent.verticalCenter
                width: 96
                height: 34
                kind: "filled"
                icon: "check"
                label: I18n.tr("Done")
                onAct: bar.done()
            }
        }
    }
}
