import QtQuick
import shell.services

// A titled + hinted segmented field (docs/stage.md).
Column {
    id: field
    property string title: ""
    property string hint: ""
    property var choices: []
    property string current: ""
    signal chose(string id)
    width: parent ? parent.width : 0
    spacing: 5
    Text {
        text: field.title
        color: Theme.onSurface
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm
        font.weight: Font.DemiBold
    }
    Text {
        width: field.width
        visible: field.hint.length > 0
        text: field.hint
        wrapMode: Text.WordWrap
        color: Qt.rgba(Theme.onSurfaceVariant.r, Theme.onSurfaceVariant.g, Theme.onSurfaceVariant.b, 0.9)
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm - 3
    }
    StageSeg {
        width: field.width
        options: field.choices
        current: field.current
        onChose: id => field.chose(id)
    }
}
