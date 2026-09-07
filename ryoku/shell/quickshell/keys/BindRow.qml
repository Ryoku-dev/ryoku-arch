pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons

// One shortcut line: description on the left, its key caps ("+"-joined) on the
// right. No rules or fills -- the rows are spaced, not packed, so the eye rests.
Item {
    id: row

    property var keys: []
    property string desc: ""

    implicitHeight: 38

    Text {
        anchors.left: parent.left
        anchors.right: caps.left
        anchors.rightMargin: Tokens.s4
        anchors.verticalCenter: parent.verticalCenter
        text: I18n.tr(row.desc)
        color: Tokens.inkDim
        font.family: Tokens.ui
        font.pixelSize: Tokens.fBody
        elide: Text.ElideRight
    }

    Row {
        id: caps
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.s1

        Repeater {
            model: row.keys
            delegate: Row {
                id: capWrap
                required property string modelData
                required property int index
                spacing: Tokens.s1
                Text {
                    visible: capWrap.index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+"
                    color: Tokens.inkFaint
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fMicro
                }
                KeyCap {
                    anchors.verticalCenter: parent.verticalCenter
                    text: capWrap.modelData
                }
            }
        }
    }
}
