pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import shell.services
import "../../components"
import Ryoku.Ui.Singletons
import Ryoku.Ui

// polkit authentication island, grown from the pill centre. Renders the PAM
// conversation the ryoku-shell daemon runs as the PolicyKit1 agent, in place of
// the stock agent's centred grey dialog: same island, fields, and buttons as the
// keyring prompt, so an administrator password looks like the rest of the shell.
//
// State lives in Polkit; this only renders and collects input. The typed answer
// goes to the daemon over the control socket, never as a process argument.
PillSurface {
    id: root

    mTop: 16
    mLeft: 22
    mRight: 22
    mBottom: 16

    ameForm: "off"

    // PAM's prompt doubles as the field label. Its trailing ": " reads as a form
    // label in a dialog that already has a heading, so trim it.
    readonly property string fieldLabel: {
        const p = Polkit.prompt.trim();
        if (p === "")
            return I18n.tr("Password");
        return p.replace(/:\s*$/, "");
    }
    readonly property string bodyText: Polkit.message !== "" ? Polkit.message
        : I18n.tr("An application is asking for administrator access.")

    implicitHeight: col.implicitHeight

    function reset() {
        field.text = "";
        field.forceActiveFocus();
    }

    function trySubmit() {
        if (Polkit.busy)
            return;
        Polkit.submit(field.text);
    }

    onOpenChanged: if (open) reset()

    Connections {
        target: Polkit
        // A retry re-prompts without the island closing, so clear the stale
        // answer and take focus again rather than leaving the old one in place.
        function onRefreshed() { root.reset(); }
    }

    Keys.onEscapePressed: root.requestClose()

    Column {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 11 * root.s

        Row {
            spacing: 10 * root.s
            width: parent.width

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 30 * root.s
                height: 30 * root.s
                radius: width / 2
                color: Qt.alpha(Theme.primary, 0.14)
                border.width: 1
                border.color: Qt.alpha(Theme.primary, 0.40)

                GlyphIcon {
                    anchors.centerIn: parent
                    width: 16 * root.s
                    height: 16 * root.s
                    name: "lock-round"
                    color: Theme.primary
                    stroke: 1.8
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 40 * root.s
                text: I18n.tr("Administrator access")
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: 14 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        Text {
            width: parent.width
            text: root.bodyText
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: 11.5 * root.s
            wrapMode: Text.WordWrap
            lineHeight: 1.15
        }

        // The reader appears the moment pam_fprintd starts narrating a scan
        // (Polkit.fingerprint), so an admin prompt answers to a touch OR the
        // typed password, like macOS. Same component as the lock and the Hub.
        Item {
            width: parent.width
            height: visible ? 78 * root.s : 0
            visible: Polkit.fingerprint !== ""
            FingerprintScan {
                anchors.centerIn: parent
                sizePx: 68 * root.s
                accent: Theme.primary
                ink: Theme.onSurface
                phase: Polkit.fingerprint === "fail" ? "fail" : "scanning"
            }
        }

        Text {
            width: parent.width
            visible: Polkit.info !== ""
            text: Polkit.info
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: 10.5 * root.s
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            height: 36 * root.s
            radius: Theme.radiusWidget
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: field.activeFocus ? Theme.frameBorder
                : (Polkit.error !== "" ? Qt.alpha(Theme.primary, 0.6) : Theme.outline)
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

            TextField {
                id: field
                anchors.fill: parent
                anchors.leftMargin: 12 * root.s
                anchors.rightMargin: 12 * root.s
                background: null
                padding: 0
                verticalAlignment: TextInput.AlignVCenter
                // PAM says whether the answer is a secret; a one-time code prompt
                // asks with echo on and must not be masked.
                echoMode: Polkit.echo ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: 13 * root.s
                placeholderText: root.fieldLabel
                placeholderTextColor: Theme.onSurfaceVariant
                selectByMouse: true
                selectionColor: Theme.primary
                enabled: !Polkit.busy
                onAccepted: root.trySubmit()
            }
        }

        // a rejected attempt: PAM re-prompts in place, so this sits above the
        // same field the retry is typed into.
        Text {
            width: parent.width
            visible: Polkit.error !== ""
            text: Polkit.error
            color: Theme.vermLit
            font.family: Theme.fontPrimary
            font.pixelSize: 10.5 * root.s
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            spacing: 9 * root.s
            layoutDirection: Qt.RightToLeft

            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: 34 * root.s
                radius: Theme.radiusWidget
                color: okArea.containsMouse ? Theme.vermLit : Theme.primary
                opacity: Polkit.busy ? 0.6 : 1
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    anchors.centerIn: parent
                    text: Polkit.busy ? I18n.tr("Checking…") : I18n.tr("Authenticate")
                    color: "#fdeee6"
                    font.family: Theme.fontPrimary
                    font.pixelSize: 12 * root.s
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: okArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !Polkit.busy
                    onClicked: root.trySubmit()
                }
            }

            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: 34 * root.s
                radius: Theme.radiusWidget
                color: cancelArea.containsMouse ? Theme.frameBg : Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.outline
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    anchors.centerIn: parent
                    text: I18n.tr("Cancel")
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: 12 * root.s
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: cancelArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestClose()
                }
            }
        }
    }
}
