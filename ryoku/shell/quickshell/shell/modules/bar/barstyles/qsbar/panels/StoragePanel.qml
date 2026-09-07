import QtQuick
import "../modules"
import Quickshell
import Quickshell.Wayland
import Ryoku.Ui.Singletons

PanelWindow {
    id: storagePanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-storage"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6

    readonly property int pct: root.storagePercent
    readonly property real usedGiB: root.storageUsedGiB
    readonly property real totalGiB: root.storageTotalGiB
    readonly property real freeGiB: Math.max(0, totalGiB - usedGiB)

    function formatCapacity(bytes) {
        var value = Number(bytes) || 0
        if (value >= 1000000000000)
            return (value / 1000000000000).toFixed(value >= 10000000000000 ? 0 : 1) + " TB"
        if (value >= 1000000000)
            return (value / 1000000000).toFixed(value >= 100000000000 ? 0 : 1) + " GB"
        return (value / 1000000).toFixed(0) + " MB"
    }

    function formatFree(bytes) {
        var value = Number(bytes) || 0
        if (value >= 1099511627776) return I18n.tr("%1 TiB free").arg((value / 1099511627776).toFixed(1))
        return I18n.tr("%1 GiB free").arg((value / 1073741824).toFixed(1))
    }

    function formatGiB(bytes) {
        return (Math.max(0, Number(bytes) || 0) / 1073741824).toFixed(1) + " GiB"
    }

    function driveTypeIcon(driveType) {
        if (driveType === "nvme") return "󰢮"
        if (driveType === "ssd") return "󰭳"
        return "󰋊"
    }

    property real reveal: root.storageVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.storageVisible ? 160 : 120
            easing.type: root.storageVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.storageVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    component DriveRow: Item {
        id: driveRow
        required property var drive
        required property bool lastRow

        width: parent ? parent.width : 0

        readonly property bool showUsageDetails: drive.totalBytes > 0
            && drive.state !== "/boot"
        readonly property real contentBottom: showUsageDetails
            ? driveMetrics.y + driveMetrics.height
            : driveInfo.y + driveInfo.height
        height: Math.ceil(contentBottom) + (lastRow ? 0 : 17)

        UiText {
            id: driveIcon
            anchors.left: parent.left
            anchors.top: parent.top
            width: 18
            text: storagePanel.driveTypeIcon(drive.driveType)
            color: storagePanel.root.seal
            font.family: storagePanel.root.mono
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
        }

        UiText {
            id: driveModel
            anchors.left: driveIcon.right
            anchors.leftMargin: 7
            anchors.right: driveCapacity.left
            anchors.rightMargin: 10
            anchors.top: parent.top
            text: drive.model
            color: storagePanel.root.ink
            font.family: storagePanel.root.mono
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        UiText {
            id: driveCapacity
            anchors.right: parent.right
            anchors.top: parent.top
            text: storagePanel.formatCapacity(drive.size)
            color: storagePanel.root.ink
            font.family: storagePanel.root.mono
            font.pixelSize: 11
            font.weight: Font.Medium
        }

        UiText {
            id: driveInfo
            anchors.left: parent.left
            anchors.right: driveFree.visible ? driveFree.left : parent.right
            anchors.rightMargin: driveFree.visible ? 10 : 0
            anchors.top: driveModel.bottom
            anchors.topMargin: 3
            text: drive.media
                + (drive.fileSystems !== "" ? " · " + drive.fileSystems : "")
                + " · " + drive.state
                + (!showUsageDetails && drive.percent >= 0 ? " · " + drive.percent + "%" : "")
            color: storagePanel.root.sumiHi
            font.family: storagePanel.root.mono
            font.pixelSize: 9
            elide: Text.ElideMiddle
        }

        UiText {
            id: driveFree
            anchors.right: parent.right
            anchors.top: driveModel.bottom
            anchors.topMargin: 3
            visible: drive.freeBytes >= 0 && !showUsageDetails
            text: storagePanel.formatFree(drive.freeBytes)
            color: storagePanel.root.ink
            font.family: storagePanel.root.mono
            font.pixelSize: 9
            font.weight: Font.Medium
        }

        Item {
            id: driveUsage
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: driveInfo.bottom
            anchors.topMargin: 7
            height: 16
            visible: showUsageDetails

            UiText {
                id: usageLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("USAGE")
                color: storagePanel.root.sumiHi
                font.family: storagePanel.root.mono
                font.pixelSize: 10
                font.letterSpacing: 1
            }
            UiText {
                id: usageValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: drive.percent + "%"
                color: storagePanel.root.seal
                font.family: storagePanel.root.mono
                font.pixelSize: 10
                font.weight: Font.Medium
            }
            Rectangle {
                anchors.left: usageLabel.right
                anchors.leftMargin: 8
                anchors.right: usageValue.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 8
                radius: 4
                color: storagePanel.root.fillActive

                Rectangle {
                    width: parent.width * Math.max(0, drive.percent) / 100
                    height: parent.height
                    radius: 4
                    color: storagePanel.root.seal
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
            }
        }

        Row {
            id: driveMetrics
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: driveUsage.bottom
            anchors.topMargin: 5
            height: 28
            visible: showUsageDetails

            Repeater {
                model: [
                    { label: I18n.tr("USED"), value: storagePanel.formatGiB(drive.usedBytes) },
                    { label: I18n.tr("FREE"), value: storagePanel.formatGiB(drive.freeBytes) },
                    { label: I18n.tr("TOTAL"), value: storagePanel.formatGiB(drive.totalBytes) }
                ]
                delegate: Item {
                    required property var modelData
                    width: driveUsage.width / 3
                    height: 28
                    UiText {
                        anchors.top: parent.top
                        text: I18n.tr(modelData.label)
                        color: storagePanel.root.sumi
                        font.family: storagePanel.root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                    UiText {
                        anchors.bottom: parent.bottom
                        text: modelData.value
                        color: storagePanel.root.ink
                        font.family: storagePanel.root.mono
                        font.pixelSize: 10
                    }
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            y: Math.ceil(driveRow.contentBottom) + 8
            height: 1
            color: storagePanel.root.sep
            visible: !driveRow.lastRow
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.storageVisible = false
    }

    Rectangle {
        id: card
        width: 340
        height: col.implicitHeight + 24
        radius: reveal > 0.001 ? root.panelRadius : 0
        color: "transparent"
        border.color: root.panelBorder
        border.width: 0
        PillShadow { theme: root }
        ConnectedPanelSurface {
            root: storagePanel.root
            ownerActive: storagePanel.root.storageVisible
            targetX: storagePanel.root.storageBarX
            reveal: storagePanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.storageBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - storagePanel.reveal)
            : (barBottom + gap) - 2 * (1 - storagePanel.reveal)
        opacity: storagePanel.reveal
        focus: root.storageVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.storageVisible = false
                event.accepted = true
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Item {
                width: parent.width
                height: 24
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("STORAGE")
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                UiText {
                    anchors.right: closeText.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("DRIVES: %1").arg(root.storageDrives.length)
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 0.5
                }
                UiText {
                    id: closeText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: closeMa.containsMouse ? root.seal : root.sumi
                    font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.storageVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Item {
                width: parent.width
                height: 16
                UiText {
                    id: fsLbl
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("ROOT")
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }
                UiText {
                    id: fsVal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: storagePanel.pct + "%"
                    color: root.seal
                    font.family: root.mono
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                Rectangle {
                    anchors.left: fsLbl.right
                    anchors.leftMargin: 8
                    anchors.right: fsVal.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 8
                    radius: 4
                    color: root.fillActive
                    Rectangle {
                        width: parent.width * storagePanel.pct / 100
                        height: parent.height
                        radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            Row {
                width: parent.width
                height: 30

                Repeater {
                    model: [
                        { label: I18n.tr("USED"), value: storagePanel.usedGiB.toFixed(1) + " GiB" },
                        { label: I18n.tr("FREE"), value: storagePanel.freeGiB.toFixed(1) + " GiB" },
                        { label: I18n.tr("TOTAL"), value: storagePanel.totalGiB.toFixed(1) + " GiB" }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: col.width / 3
                        height: 30
                        UiText {
                            anchors.top: parent.top
                            text: I18n.tr(modelData.label)
                            color: root.sumi
                            font.family: root.mono
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                        UiText {
                            anchors.bottom: parent.bottom
                            text: modelData.value
                            color: root.ink
                            font.family: root.mono
                            font.pixelSize: 11
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Column {
                width: parent.width
                spacing: 0
                visible: root.storageDrives.length > 0

                Repeater {
                    model: root.storageDrives
                    delegate: DriveRow {
                        required property var modelData
                        required property int index
                        drive: modelData
                        lastRow: index === root.storageDrives.length - 1
                    }
                }
            }

            UiText {
                width: parent.width
                visible: root.storageDrives.length === 0
                text: root.storageInventoryAvailable ? I18n.tr("No physical drives found") : I18n.tr("Reading drive information…")
                color: root.sumiHi
                font.family: root.mono
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
