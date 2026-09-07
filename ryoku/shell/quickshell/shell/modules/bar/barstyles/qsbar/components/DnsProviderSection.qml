import QtQuick
import shell.services
import "../modules"
import Ryoku.Ui.Singletons

Column {
    id: section

    required property var theme
    required property real buttonRadius

    spacing: 4

    property string pendingProvider: ""
    property int pendingCallId: 0
    property bool customOpen: false
    property string customText: ""
    property string errorText: ""

    readonly property bool busy: pendingCallId !== 0
    readonly property string shownProvider: pendingProvider !== ""
        ? pendingProvider : Network.dnsProvider

    function customServers() {
        var text = customText.trim()
        return text === "" ? [] : text.split(/[\s,]+/).filter(function(value) {
            return value !== ""
        })
    }

    function submitProvider(provider, servers) {
        if (busy)
            return
        errorText = ""
        pendingProvider = provider
        pendingCallId = Network.setDnsProvider(provider, servers)
        requestTimeout.restart()
    }

    function chooseProvider(provider) {
        if (provider === "custom") {
            customOpen = !customOpen
            if (customOpen && customText === "" && Network.dnsProvider === "custom")
                customText = Network.dnsServers.join(", ")
            if (customOpen)
                Qt.callLater(customInput.forceActiveFocus)
            return
        }
        customOpen = false
        submitProvider(provider, [])
    }

    Connections {
        target: Network

        function onReplied(id, ok, error) {
            if (id !== section.pendingCallId)
                return
            requestTimeout.stop()
            section.pendingCallId = 0
            section.pendingProvider = ""
            if (ok) {
                section.customOpen = false
                section.errorText = ""
            } else {
                section.errorText = error || I18n.tr("Could not change DNS provider")
            }
        }
    }

    Timer {
        id: requestTimeout
        interval: 60000
        onTriggered: {
            if (!section.busy)
                return
            section.pendingCallId = 0
            section.pendingProvider = ""
            section.errorText = I18n.tr("DNS change timed out; check authorization and try again")
        }
    }

    Item {
        width: parent.width
        height: 20

        UiText {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("DNS PROVIDER")
            color: section.theme.sumiHi
            font.family: section.theme.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        UiText {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: section.busy ? I18n.tr("applying…") : ""
            color: section.theme.seal
            font.family: section.theme.mono
            font.pixelSize: 9
        }
    }

    Row {
        id: providerRow
        width: parent.width
        height: 28
        spacing: 4

        Repeater {
            model: [
                { label: I18n.tr("DHCP"), value: "dhcp" },
                { label: I18n.tr("Cloudflare"), value: "cloudflare" },
                { label: I18n.tr("Google"), value: "google" },
                { label: I18n.tr("Custom"), value: "custom" }
            ]

            delegate: Rectangle {
                id: providerButton

                required property var modelData

                width: (providerRow.width - providerRow.spacing * 3) / 4
                height: providerRow.height
                radius: section.buttonRadius
                enabled: !section.busy
                readonly property bool active: section.shownProvider === modelData.value
                color: active ? section.theme.fillActive
                              : providerMouse.containsMouse ? section.theme.fillHover
                              : section.theme.fillIdle
                border.color: active || providerMouse.containsMouse
                    ? section.theme.seal : section.theme.sep
                border.width: 1
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label

                UiText {
                    anchors.centerIn: parent
                    text: I18n.tr(providerButton.modelData.label)
                    color: providerButton.active ? section.theme.seal : section.theme.ink
                    font.family: section.theme.mono
                    font.pixelSize: 9
                }

                MouseArea {
                    id: providerMouse
                    anchors.fill: parent
                    enabled: providerButton.enabled
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: section.chooseProvider(providerButton.modelData.value)
                }

                Keys.onReturnPressed: section.chooseProvider(modelData.value)
                Keys.onEnterPressed: section.chooseProvider(modelData.value)
                Keys.onSpacePressed: section.chooseProvider(modelData.value)
            }
        }
    }

    Item {
        width: parent.width
        height: section.customOpen ? 30 : 0
        visible: height > 0
        clip: true

        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: applyButton.left
            anchors.rightMargin: 4
            height: 28
            radius: section.buttonRadius
            color: section.theme.fillIdle
            border.color: customInput.activeFocus ? section.theme.seal : section.theme.sep
            border.width: 1

            UiText {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: customInput.text === "" && !customInput.activeFocus
                text: I18n.tr("DNS server addresses")
                color: section.theme.sumiHi
                font.family: section.theme.mono
                font.pixelSize: 9
            }

            TextInput {
                id: customInput
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                text: section.customText
                color: section.theme.ink
                selectionColor: section.theme.seal
                selectedTextColor: section.theme.paper
                font.family: section.theme.mono
                font.pixelSize: 10
                clip: true
                inputMethodHints: Qt.ImhNoPredictiveText
                Accessible.name: I18n.tr("Custom DNS server addresses")
                onTextEdited: section.customText = text
                onAccepted: section.submitProvider("custom", section.customServers())
            }
        }

        Rectangle {
            id: applyButton
            anchors.right: parent.right
            width: 48
            height: 28
            radius: section.buttonRadius
            color: applyMouse.containsMouse ? section.theme.fillPrimaryHover : section.theme.seal
            activeFocusOnTab: true
            enabled: !section.busy && section.customServers().length > 0
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("Apply custom DNS servers")

            UiText {
                anchors.centerIn: parent
                text: I18n.tr("apply")
                color: section.theme.paper
                font.family: section.theme.mono
                font.pixelSize: 9
            }

            MouseArea {
                id: applyMouse
                anchors.fill: parent
                enabled: applyButton.enabled
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: section.submitProvider("custom", section.customServers())
            }

            Keys.onReturnPressed: section.submitProvider("custom", section.customServers())
            Keys.onEnterPressed: section.submitProvider("custom", section.customServers())
            Keys.onSpacePressed: section.submitProvider("custom", section.customServers())
        }
    }

    UiText {
        width: parent.width
        visible: section.errorText !== ""
        text: section.errorText
        color: section.theme.seal
        wrapMode: Text.Wrap
        font.family: section.theme.mono
        font.pixelSize: 9
    }
}
