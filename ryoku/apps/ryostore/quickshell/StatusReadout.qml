import QtQuick
import Ryoku.Ui.Singletons
import "lib/store.js" as StoreLogic

Flow {
    id: readout

    required property var item
    property string busyKey: ""
    property string installStage: ""
    property string installErrorKey: ""
    property string installError: ""
    property bool offline: false

    readonly property var labels: {
        var result = StoreLogic.statusLabels(item).slice();
        var key = StoreLogic.itemKey(item);
        if (key === busyKey && installStage !== "")
            result.push(installStage);
        if (offline)
            result.push(I18n.tr("OFFLINE"));
        if (key === installErrorKey && installError !== "")
            result.push(installError);
        return result;
    }

    spacing: Tokens.s2

    Repeater {
        model: readout.labels

        delegate: Row {
            id: labelRow
            required property string modelData
            spacing: Tokens.s1

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 4
                height: 4
                color: Tokens.inkDim
            }

            Text {
                objectName: "ryostore-status-" + labelRow.modelData
                text: I18n.tr(labelRow.modelData)
                textFormat: Text.PlainText
                color: Tokens.inkDim
                font.family: Tokens.mono
                font.pixelSize: Tokens.fMicro
                font.weight: Font.Medium
                font.letterSpacing: Tokens.trackLabel
            }
        }
    }
}
