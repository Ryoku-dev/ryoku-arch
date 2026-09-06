import QtQuick
import shell.services

// A small caps section label for the Stage tab (docs/stage.md).
Text {
    id: sec
    property string title: ""
    text: sec.title.toUpperCase()
    color: Theme.primary
    font.family: Theme.fontPrimary
    font.pixelSize: Theme.fontSm - 3
    font.weight: Font.DemiBold
    width: parent ? parent.width : 0
}
