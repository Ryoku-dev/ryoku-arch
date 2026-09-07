import QtQuick
import Ryoku.Ui.Singletons
import "Singletons"

// The machine's ticket: a boarding-pass hero on a flat, hairline-framed stage
// (the brutalist shadow and ember frame die: the frame just brightens to
// lineStrong while running). Left is the tear-off stub: the OS mark, the hanko
// when the machine is sealed (ryovm's one rationed splash of red), the split-flap
// power word. A punched perforation column separates it from the manifest: the
// machine's name in the window's serif, an IATA-style field grid of the real
// hardware, and the annunciator matrix reporting each subsystem.
Item {
    id: stage

    property string name: ""
    property string guest: "linux"
    property string os: ""
    property bool running: false
    property string mode: "gtk"
    property string ssh: ""
    property string spice: ""
    property string cores: "auto"
    property string ram: "auto"
    property real diskUsed: 0
    property string diskCap: ""
    property bool installed: false
    property bool disposable: false
    property bool sshReady: false
    property bool sealed: false
    property bool tpmOn: false
    property bool uefiOn: true

    onSealedChanged: if (stage.sealed) hanko.thud()

    // one manifest field: an 8px caps label over a mono value.
    component Field: Column {
        id: fld
        property string k: ""
        property string v: ""
        property color vc: Tokens.ink
        spacing: 3
        Text {
            text: fld.k
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: 8
            font.weight: Font.Medium
            font.letterSpacing: 1.6
            font.capitalization: Font.AllUppercase
        }
        Text {
            text: fld.v
            color: fld.vc
            font.family: Tokens.mono
            font.pixelSize: 14
            font.weight: Font.Medium
        }
    }

    // the stage plate: flat, hairline, brightening while it runs.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: Tokens.radius
        border.width: Tokens.border
        border.color: stage.running ? Tokens.lineStrong : Tokens.line
        antialiasing: false
        Behavior on border.color { ColorAnimation { duration: Tokens.move } }
    }

    RegMark {
        x: parent.width - width - 16
        y: 15
        size: 12
        tint: Tokens.inkFaint
    }

    // ---- the stub: OS mark, seal, power flap ------------------------------
    Item {
        id: stub
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 148

        Column {
            anchors.centerIn: parent
            spacing: 18

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96
                height: 92

                OsIcon {
                    x: 2; y: 2
                    width: 64; height: 64; size: 64
                    slug: stage.os
                    label: stage.os.length > 0 ? stage.os : stage.guest
                    opacity: stage.running ? 1 : 0.8
                    Behavior on opacity { NumberAnimation { duration: Tokens.move } }
                }
                // the seal is stamped over the mark only when it certifies a
                // sealed machine (amendment 3): absence, not greyness.
                HankoSeal {
                    id: hanko
                    x: 46; y: 42
                    size: 48
                    visible: stage.sealed
                    title: stage.os.length > 0 ? stage.os : stage.guest
                    glyph: (stage.os.length > 0 ? stage.os : stage.guest).charAt(0).toUpperCase()
                }
            }

            FlapWord {
                anchors.horizontalCenter: parent.horizontalCenter
                text: stage.running ? (stage.disposable ? I18n.tr("BURNING") : I18n.tr("RUNNING")) : I18n.tr("STOPPED")
                pad: 7
                cellW: 13; cellH: 20; fontPx: 11
                ink: stage.running ? Tokens.ink : Tokens.inkDim
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("RYOPORT · PASS")
            color: Tokens.inkFaint
            font.family: Tokens.mono
            font.pixelSize: 9
            font.letterSpacing: 2
        }
    }

    // ---- perforation: punched holes, printed absence ----------------------
    Column {
        id: perf
        anchors.left: stub.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        width: 8
        spacing: 9
        Repeater {
            model: Math.max(0, Math.floor((perf.height + 9) / 15))
            delegate: Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 6; height: 6
                radius: 3            // a punched hole is round; it is absence
                color: "transparent"
                border.width: 1
                border.color: Tokens.lineSoft
            }
        }
    }

    // ---- the manifest ------------------------------------------------------
    Column {
        anchors.left: perf.right
        anchors.leftMargin: 24
        anchors.right: parent.right
        anchors.rightMargin: 26
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        Column {
            width: parent.width
            spacing: 2
            Text {
                // long quickget names (artixlinux-20260402-base-openrc) drop a
                // step past 22 chars, then elide whatever still overflows.
                width: parent.width
                elide: Text.ElideRight
                maximumLineCount: 1
                text: stage.name.length > 0 ? stage.name : I18n.tr("machine")
                color: Tokens.ink
                font.family: Tokens.display
                font.pixelSize: stage.name.length > 22 ? 21 : 28
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: (stage.guest || "linux").toUpperCase() + I18n.tr(" GUEST · QEMU/KVM CARRIER")
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: 9
                font.letterSpacing: 1.8
            }
        }

        Grid {
            columns: 3
            columnSpacing: 34
            rowSpacing: 12
            Field { k: I18n.tr("Cores"); v: stage.cores === "auto" ? I18n.tr("AUTO") : stage.cores }
            Field { k: I18n.tr("Memory"); v: stage.ram === "auto" ? I18n.tr("AUTO") : stage.ram }
            Field {
                k: I18n.tr("Disk")
                v: stage.diskUsed > 0
                    ? Vm.human(stage.diskUsed) + (stage.diskCap.length > 0 ? " / " + stage.diskCap : "")
                    : (stage.diskCap.length > 0 ? I18n.tr("%1 · EMPTY").arg(stage.diskCap) : I18n.tr("NONE"))
            }
            Field { k: I18n.tr("Mode"); v: ({ "gtk": I18n.tr("WINDOW"), "spice": I18n.tr("SPICE"), "none": I18n.tr("HEADLESS") })[stage.mode] || stage.mode }
            Field {
                k: I18n.tr("SSH")
                v: stage.running && stage.ssh.length > 0
                    ? ":" + stage.ssh + (stage.sshReady ? "" : " · " + I18n.tr("no answer"))
                    : "-"
                vc: stage.running && stage.sshReady ? Tokens.ink : Tokens.inkFaint
            }
            Field {
                k: I18n.tr("Console")
                v: stage.running && stage.spice.length > 0 ? I18n.tr("SPICE") : "-"
                vc: stage.running && stage.spice.length > 0 ? Tokens.ink : Tokens.inkFaint
            }
        }

        // the annunciator matrix: a rigid instrument grid, uniform 54px tiles,
        // dark = honestly off. SEALED simply lights; BURN inverts and blinks.
        Grid {
            id: annGrid
            columns: Math.max(3, Math.floor((parent.width + 5) / 59))
            columnSpacing: 5
            rowSpacing: 5
            Annunciator { label: I18n.tr("KVM"); lit: Vm.caps.kvm === true }
            Annunciator { label: I18n.tr("UEFI"); lit: stage.uefiOn }
            Annunciator { label: I18n.tr("TPM"); lit: stage.tpmOn }
            Annunciator { label: I18n.tr("DISK"); lit: stage.installed }
            Annunciator { label: I18n.tr("NET"); lit: stage.running }
            Annunciator { label: I18n.tr("SSH"); lit: stage.running && stage.sshReady }
            Annunciator { label: I18n.tr("SPICE"); lit: stage.running && stage.spice.length > 0 }
            Annunciator { label: I18n.tr("SEALED"); lit: stage.sealed }
            Annunciator { label: I18n.tr("BURN"); lit: stage.running && stage.disposable; warn: true }
        }
    }
}
