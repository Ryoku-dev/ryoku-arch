pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import ".."
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// Battery popout: a frame-edge card (shared PopoutCard, so it opens and melts
// like the music card) leading with a boxy battery gauge, the level, and the
// charge state + time; a power-profile switcher rides below, and a "!" opens the
// detail (rate, capacity, health, plus any connected Bluetooth device's own
// battery). All live off the Battery + PowerProfiles services. Never grabs the
// keyboard; dismisses on an outside click.
Item {
    id: root

    property real s: 1
    property bool open: false

    readonly property real pad: 11 * root.s
    readonly property color ink: Theme.ink(Theme.effectiveSurface)
    readonly property color inkDim: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
    readonly property color line: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.14)

    property bool detailOpen: false
    onOpenChanged: if (!root.open) root.detailOpen = false

    function profileLabel(name) {
        return name === "power-saver" ? I18n.tr("Eco")
            : name === "balanced" ? I18n.tr("Balanced")
            : name === "performance" ? I18n.tr("Performance")
            : name;
    }
    // connected Bluetooth devices that report a battery, for the detail block.
    readonly property var btBatteries: {
        if (typeof Bluetooth === "undefined" || !Bluetooth || !Bluetooth.devices)
            return [];
        const out = [];
        const vals = Bluetooth.devices.values;
        for (let i = 0; i < vals.length; i++) {
            const d = vals[i];
            if (d && d.connected && BtLink.batteryLevel(d) >= 0)
                out.push({ name: BtLink.label(d), pct: BtLink.batteryLevel(d) });
        }
        return out;
    }

    implicitWidth: 244 * root.s
    implicitHeight: content.implicitHeight + root.pad * 2

    PopoutCard { anchors.fill: parent }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        spacing: 9 * root.s

        // head: label + detail toggle.
        Item {
            width: parent.width
            height: 20 * root.s
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("BATTERY")
                color: root.inkDim
                font.family: Theme.mono
                font.pixelSize: 9 * root.s
                font.letterSpacing: 1.6
                font.weight: Font.Medium
            }
            PopoutHeadButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                s: root.s
                glyph: "info"
                active: root.detailOpen
                onClicked: root.detailOpen = !root.detailOpen
            }
        }

        // absent battery (desktop) - the widget self-hides, but stay honest.
        Column {
            width: parent.width
            spacing: 6 * root.s
            visible: !Battery.present
            topPadding: 6 * root.s
            bottomPadding: 4 * root.s
            GlyphIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 27 * root.s
                height: width
                name: "battery"
                stroke: 1.6
                color: root.inkDim
                opacity: 0.55
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("No battery")
                color: root.ink
                font.family: Theme.fontPrimary
                font.pixelSize: 12 * root.s
                font.weight: Font.DemiBold
            }
        }

        // hero: gauge, level, state + time.
        Column {
            width: parent.width
            spacing: 4 * root.s
            visible: Battery.present

            Row {
                spacing: 8 * root.s
                GlyphIcon {
                    visible: Battery.charging
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15 * root.s
                    height: width
                    name: "bolt"
                    color: root.ink
                    stroke: 0
                }
                PopoutBatteryGauge {
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    gw: 58 * root.s
                    gh: 25 * root.s
                    frac: Battery.frac
                    warn: Battery.low
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Battery.pct + "%"
                    color: Battery.low ? Theme.error : root.ink
                    font.family: Theme.mono
                    font.pixelSize: 22 * root.s
                    font.weight: Font.Medium
                    font.features: ({ "tnum": 1 })
                }
            }
            Text {
                width: parent.width
                text: !Battery.hasTime ? Battery.stateLabel
                    : Battery.charging ? I18n.tr("%1 · %2 to full").arg(Battery.stateLabel).arg(Battery.timeStr)
                    : I18n.tr("%1 · %2 left").arg(Battery.stateLabel).arg(Battery.timeStr)
                color: root.inkDim
                font.family: Theme.mono
                font.pixelSize: 9.5 * root.s
                elide: Text.ElideRight
            }
        }

        // power-profile switcher.
        Column {
            width: parent.width
            spacing: 5 * root.s
            visible: PowerProfiles.available
            Text {
                width: parent.width
                text: I18n.tr("POWER MODE")
                color: root.inkDim
                font.family: Theme.mono
                font.pixelSize: 8.5 * root.s
                font.letterSpacing: 1.5
            }
            Flow {
                width: parent.width
                spacing: 5 * root.s
                Repeater {
                    model: PowerProfiles.profiles
                    delegate: PopoutChip {
                        required property var modelData
                        s: root.s
                        label: root.profileLabel(modelData)
                        act: true
                        on: PowerProfiles.profile === modelData
                        onClicked: PowerProfiles.setProfile(modelData)
                    }
                }
            }
        }

        // detail block.
        Item {
            width: parent.width
            clip: true
            visible: Battery.present
            height: root.detailOpen ? detailCol.implicitHeight : 0
            Behavior on height { NumberAnimation { duration: Motion.rowReveal; easing.type: Motion.rowRevealCurve } }
            opacity: root.detailOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.rowFade } }

            Column {
                id: detailCol
                width: parent.width
                spacing: 0
                topPadding: 3 * root.s

                Rectangle { width: parent.width; height: Theme.borderWidth; color: root.line }
                Item { width: 1; height: 4 * root.s }

                PopoutDetailRow {
                    width: parent.width
                    s: root.s
                    label: Battery.charging ? I18n.tr("Charging at") : I18n.tr("Rate")
                    value: Math.abs(Battery.rateW).toFixed(1) + " W"
                }
                PopoutDetailRow {
                    width: parent.width
                    s: root.s
                    label: I18n.tr("Capacity")
                    value: Battery.capacityWh.toFixed(1) + " Wh"
                }
                PopoutDetailRow {
                    width: parent.width
                    visible: Battery.healthSupported
                    s: root.s
                    label: I18n.tr("Health")
                    value: Battery.health + "%"
                }
                PopoutDetailRow {
                    width: parent.width
                    s: root.s
                    label: I18n.tr("State")
                    value: Battery.stateLabel
                }

                Item { width: 1; height: 4 * root.s; visible: root.btBatteries.length > 0 }
                Text {
                    width: parent.width
                    visible: root.btBatteries.length > 0
                    text: I18n.tr("BLUETOOTH")
                    color: root.inkDim
                    font.family: Theme.mono
                    font.pixelSize: 8.5 * root.s
                    font.letterSpacing: 1.5
                }
                Repeater {
                    model: root.btBatteries
                    delegate: PopoutDetailRow {
                        required property var modelData
                        width: parent.width
                        s: root.s
                        label: modelData.name
                        value: modelData.pct + "%"
                    }
                }
            }
        }
    }
}
