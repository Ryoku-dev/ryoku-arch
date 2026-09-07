pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import ".."
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// The focused device as a compact instrument row: a boxed class glyph, the name
// and one mono status line, then a battery gauge and -- for the active audio
// sink -- the live codec, an A2DP<->headset flip and a volume bar. The primary
// action reads the device's own state. A "!" opens a detail block with the rest
// (address, state, trust, wake, connection age, capabilities, forget). Built on
// the shared popout kit so it matches the other cards.
Item {
    id: root

    property real s: 1
    property var device: null
    property bool busy: false

    signal primaryActed()
    signal forgetActed()

    readonly property bool present: root.device !== null
    readonly property bool connected: root.present && root.device.connected
    readonly property bool pairing: root.present && root.device.pairing
    readonly property bool connecting: root.present && (root.busy || root.pairing
        || root.device.state === BluetoothDeviceState.Connecting)
    readonly property bool disconnecting: root.present && root.device.state === BluetoothDeviceState.Disconnecting
    readonly property bool paired: root.present && (root.device.paired || root.device.bonded)
    readonly property int battery: BtLink.batteryLevel(root.device)
    readonly property bool lowBattery: root.battery >= 0 && root.battery <= 20

    readonly property var sinkDev: (Audio.sinkIsBluez && Audio.sink) ? Audio.btDeviceFor(Audio.sink) : null
    readonly property bool isCurrentSink: root.present && root.sinkDev
        && ((root.sinkDev.address || "") + "").toUpperCase() === ((root.device.address || "") + "").toUpperCase()
    readonly property bool audioCapable: {
        const ic = (root.present && root.device.icon ? String(root.device.icon) : "").toLowerCase();
        return ic.indexOf("audio") >= 0 || ic.indexOf("headset") >= 0
            || ic.indexOf("headphone") >= 0 || ic.indexOf("speaker") >= 0;
    }
    function sinkNodeFor(d) {
        if (!d)
            return null;
        const mac = ((d.address || "") + "").toUpperCase();
        const outs = Audio.outputs;
        for (let i = 0; i < outs.length; i++)
            if (Audio.isBluez(outs[i]) && Audio.btMac(outs[i]).toUpperCase() === mac)
                return outs[i];
        return null;
    }

    readonly property color ink: Theme.ink(Theme.effectiveSurface)
    readonly property color inkDim: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
    readonly property color line: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.14)

    property bool detailOpen: false
    onDeviceChanged: { root.detailOpen = false; root.caps = ""; }

    implicitWidth: parent ? parent.width : 240 * root.s
    implicitHeight: col.implicitHeight

    property string caps: ""
    Process {
        id: infoProc
        stdout: StdioCollector { onStreamFinished: root.caps = this.text }
    }
    onDetailOpenChanged: {
        if (root.detailOpen && root.present) {
            infoProc.command = ["bluetoothctl", "info", root.device.address];
            infoProc.running = false;
            infoProc.running = true;
        }
    }
    readonly property var capChips: {
        const t = root.caps;
        if (!t.length)
            return [];
        const out = [];
        if (t.indexOf("Audio Sink") >= 0 || t.indexOf("Advanced Audio") >= 0)
            out.push({ g: "speaker", l: I18n.tr("Audio") });
        if (t.indexOf("Handsfree") >= 0 || t.indexOf("Headset") >= 0)
            out.push({ g: "mic", l: I18n.tr("Mic") });
        if (t.indexOf("A/V Remote Control") >= 0)
            out.push({ g: "play-s", l: I18n.tr("Media") });
        if (t.indexOf("Human Interface Device") >= 0)
            out.push({ g: "keyboard", l: I18n.tr("Input") });
        return out;
    }

    Column {
        id: col
        width: parent.width
        spacing: 7 * root.s

        // identity: boxed glyph, name + status, detail toggle.
        Item {
            width: parent.width
            height: 30 * root.s

            Rectangle {
                id: iconTile
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 30 * root.s
                height: width
                radius: 4 * root.s
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                border.width: Theme.borderWidth
                border.color: root.line
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 16 * root.s
                    height: width
                    name: BtLink.glyphFor(root.device)
                    stroke: 1.7
                    color: root.connected ? root.ink : root.inkDim
                    opacity: root.connecting ? 0.55 : 1
                    SequentialAnimation on opacity {
                        running: root.connecting
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.35; to: 0.9; duration: 620; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.9; to: 0.35; duration: 620; easing.type: Easing.InOutQuad }
                    }
                }
            }

            Rectangle {
                id: infoBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 20 * root.s
                height: width
                radius: 4 * root.s
                color: root.detailOpen ? Theme.inverseSurface
                    : (infoTap.pressed ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)
                    : (infoHover.hovered ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent"))
                border.width: root.detailOpen ? 0 : Theme.borderWidth
                border.color: root.line
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 12 * root.s
                    height: width
                    name: "info"
                    stroke: 1.9
                    color: root.detailOpen ? Theme.inverseOnSurface : root.inkDim
                }
                HoverHandler { id: infoHover; cursorShape: Qt.PointingHandCursor }
                MouseArea { id: infoTap; anchors.fill: parent; onClicked: root.detailOpen = !root.detailOpen }
            }

            Column {
                anchors.left: iconTile.right
                anchors.leftMargin: 9 * root.s
                anchors.right: infoBtn.left
                anchors.rightMargin: 7 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s
                Text {
                    width: parent.width
                    text: BtLink.label(root.device)
                    color: root.ink
                    font.family: Theme.fontPrimary
                    font.pixelSize: 12.5 * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: {
                        if (root.disconnecting) return I18n.tr("Disconnecting…");
                        if (root.pairing) return I18n.tr("Pairing…");
                        if (root.connecting) return I18n.tr("Connecting…");
                        if (root.connected) {
                            const age = BtLink.durationText(BtLink.durationFor(root.device ? root.device.address : ""));
                            return age.length ? I18n.tr("Connected · %1").arg(age) : I18n.tr("Connected");
                        }
                        if (root.paired) return I18n.tr("Paired");
                        return I18n.tr("Not paired");
                    }
                    color: root.inkDim
                    font.family: Theme.mono
                    font.pixelSize: 9 * root.s
                    elide: Text.ElideRight
                }
            }
        }

        // stat line: battery gauge, codec, profile flip.
        Row {
            width: parent.width
            spacing: 6 * root.s
            visible: root.battery >= 0 || (root.connected && root.isCurrentSink)

            Row {
                visible: root.battery >= 0
                spacing: 4 * root.s
                PopoutBatteryGauge {
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    gw: 17 * root.s
                    gh: 9 * root.s
                    frac: root.battery / 100
                    warn: root.lowBattery
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.battery + "%"
                    color: root.lowBattery ? Theme.error : root.ink
                    font.family: Theme.mono
                    font.pixelSize: 9.5 * root.s
                    font.features: ({ "tnum": 1 })
                }
            }

            PopoutChip {
                visible: root.connected && root.isCurrentSink && Audio.btCodec.length > 0
                anchors.verticalCenter: parent.verticalCenter
                s: root.s
                label: Audio.btCodec
            }
            PopoutChip {
                visible: root.connected && root.isCurrentSink && Audio.profileLabel().length > 0
                anchors.verticalCenter: parent.verticalCenter
                s: root.s
                glyph: "flip"
                label: Audio.profileLabel()
                act: true
                onClicked: Audio.toggleProfile()
            }
        }

        // volume, bound to the bluez sink.
        Item {
            id: vol
            width: parent.width
            height: 14 * root.s
            visible: root.connected && root.isCurrentSink && Audio.sink && Audio.sink.audio
            readonly property real frac: (Audio.sink && Audio.sink.audio) ? Math.max(0, Math.min(1, Audio.sink.audio.volume)) : 0
            GlyphIcon {
                id: volIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 12 * root.s
                height: width
                name: "speaker"
                stroke: 1.6
                color: root.inkDim
            }
            Text {
                id: volPct
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(vol.frac * 100) + "%"
                color: root.inkDim
                font.family: Theme.mono
                font.pixelSize: 9 * root.s
                font.features: ({ "tnum": 1 })
            }
            Rectangle {
                id: volTrack
                anchors.left: volIcon.right
                anchors.right: volPct.left
                anchors.leftMargin: 8 * root.s
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                height: 2.5 * root.s
                radius: 1 * root.s
                color: root.line
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * vol.frac
                    height: parent.height
                    radius: 1 * root.s
                    color: root.ink
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -7 * root.s
                    cursorShape: Qt.PointingHandCursor
                    function setAt(mx) {
                        if (!Audio.sink || !Audio.sink.audio)
                            return;
                        Audio.sink.audio.volume = Math.max(0, Math.min(1, (mx - 7 * root.s) / volTrack.width));
                    }
                    onPressed: mouse => setAt(mouse.x)
                    onPositionChanged: mouse => { if (pressed) setAt(mouse.x); }
                }
            }
        }

        // primary action.
        PopoutAction {
            width: parent.width
            s: root.s
            enabled: !root.connecting && !root.disconnecting
            label: root.disconnecting ? I18n.tr("Disconnecting…")
                : root.pairing ? I18n.tr("Pairing…")
                : root.connecting ? I18n.tr("Connecting…")
                : root.connected ? I18n.tr("Disconnect")
                : root.paired ? I18n.tr("Connect")
                : I18n.tr("Pair")
            onClicked: root.primaryActed()
        }

        // make this connected audio device the default output.
        PopoutAction {
            width: parent.width
            visible: root.connected && root.audioCapable && !root.isCurrentSink && root.sinkNodeFor(root.device) !== null
            s: root.s
            destructive: true
            label: I18n.tr("Set as output")
            onClicked: Audio.setOutput(root.sinkNodeFor(root.device))
        }

        // detail: opens under the "!", carrying the rest.
        Item {
            width: parent.width
            clip: true
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

                PopoutDetailRow { width: parent.width; s: root.s; label: I18n.tr("Type"); value: BtLink.typeLabel(root.device) }
                PopoutDetailRow { width: parent.width; s: root.s; label: I18n.tr("Address"); value: root.present ? root.device.address : "" }
                PopoutDetailRow { width: parent.width; s: root.s; label: I18n.tr("State"); value: root.present ? BluetoothDeviceState.toString(root.device.state) : "" }
                PopoutDetailRow {
                    width: parent.width
                    visible: root.connected
                    s: root.s
                    label: I18n.tr("Connected")
                    value: BtLink.durationText(BtLink.durationFor(root.present ? root.device.address : ""))
                }
                PopoutDetailRow {
                    width: parent.width
                    s: root.s
                    label: I18n.tr("Trusted")
                    toggle: true
                    on: root.present && root.device.trusted
                    onToggled: if (root.present) root.device.trusted = !root.device.trusted
                }
                PopoutDetailRow {
                    width: parent.width
                    s: root.s
                    label: I18n.tr("Wake host")
                    toggle: true
                    on: root.present && root.device.wakeAllowed
                    onToggled: if (root.present) root.device.wakeAllowed = !root.device.wakeAllowed
                }
                PopoutDetailRow {
                    width: parent.width
                    visible: root.present && root.device.blocked
                    s: root.s
                    label: I18n.tr("Blocked")
                    toggle: true
                    on: root.present && root.device.blocked
                    onToggled: if (root.present) root.device.blocked = !root.device.blocked
                }

                Item { width: 1; height: 4 * root.s; visible: root.capChips.length > 0 }
                Flow {
                    width: parent.width
                    spacing: 4 * root.s
                    visible: root.capChips.length > 0
                    Repeater {
                        model: root.capChips
                        delegate: PopoutChip {
                            required property var modelData
                            s: root.s
                            glyph: modelData.g
                            label: modelData.l
                        }
                    }
                }

                Item { width: 1; height: 6 * root.s }
                PopoutAction {
                    width: parent.width
                    visible: root.paired
                    s: root.s
                    destructive: true
                    label: I18n.tr("Forget this device")
                    onClicked: root.forgetActed()
                }
            }
        }
    }
}
