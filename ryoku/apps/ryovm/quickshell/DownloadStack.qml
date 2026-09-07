pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// The active builds, one compact row each: name, live percent or phase word, a
// hairline track, and its own cancel, so several machines download at once. Fed
// by Vm.dlJobs; a row clears itself when its build lands in the Library.
Column {
    id: stack
    spacing: Tokens.s2
    visible: Vm.dlCount > 0

    Repeater {
        model: Vm.dlJobs
        delegate: Rectangle {
            id: dlRow
            required property var model
            width: stack.width
            height: 48
            radius: Tokens.radius
            color: "transparent"
            border.width: Tokens.border
            border.color: Tokens.line
            antialiasing: false

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.s3
                anchors.rightMargin: Tokens.s3
                spacing: 5

                Row {
                    width: parent.width
                    spacing: Tokens.s2
                    Text {
                        width: parent.width - pctT.implicitWidth - xBtn.width - Tokens.s2 * 2
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: dlRow.model.name
                        color: Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                        id: pctT
                        anchors.verticalCenter: parent.verticalCenter
                        text: dlRow.model.indet
                            ? (({ "resolve": I18n.tr("FINDING MIRROR"), "download": I18n.tr("DOWNLOADING"), "config": I18n.tr("PREPARING") })[dlRow.model.phase] || I18n.tr("WORKING"))
                            : Math.round(dlRow.model.progress * 100) + "%" + (dlRow.model.bps > 0 ? "  ·  " + (dlRow.model.bps / 1048576).toFixed(1) + I18n.tr(" MB/s") : "")
                        color: Tokens.inkMuted
                        font.family: Tokens.mono; font.pixelSize: 10
                    }
                    Btn {
                        id: xBtn
                        anchors.verticalCenter: parent.verticalCenter
                        compact: true
                        text: I18n.tr("CANCEL")
                        onAct: Vm.cancelJob(dlRow.model.key)
                    }
                }

                Item {
                    width: parent.width
                    height: 3
                    visible: !dlRow.model.indet
                    Rectangle { anchors.fill: parent; color: "transparent"; border.width: Tokens.border; border.color: Tokens.line; antialiasing: false }
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, dlRow.model.progress))
                        height: parent.height
                        color: Tokens.ink
                        antialiasing: false
                        Behavior on width { NumberAnimation { duration: Tokens.move; easing.type: Tokens.ease } }
                    }
                }
                Text {
                    width: parent.width
                    visible: dlRow.model.indet
                    elide: Text.ElideRight
                    text: dlRow.model.log.length > 0 ? dlRow.model.log : I18n.tr("Working…")
                    color: Tokens.inkFaint
                    font.family: Tokens.mono; font.pixelSize: 10
                }
            }
        }
    }
}
