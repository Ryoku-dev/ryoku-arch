import QtQuick
import shell.services
import "../../components"
import Ryoku.Ui.Singletons

Item {
    id: root

    property real us: 1

    readonly property string layout: KeyboardLayout.variant || I18n.tr("Unknown")

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    Row {
        id: content

        anchors.centerIn: parent
        spacing: 8 * root.us

        Text {
            text: "⌨ "
            color: Theme.onSurface

            font.pixelSize: 20 * root.us
            font.family: Theme.mono

            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.layout
            color: Theme.onSurface

            font.family: Theme.mono
            font.pixelSize: Theme.fontMd * root.us

            verticalAlignment: Text.AlignVCenter

            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
