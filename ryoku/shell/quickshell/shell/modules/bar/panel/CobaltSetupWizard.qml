pragma ComponentBehavior: Bound

import QtQuick
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// First-run setup for the stash Cobalt engine, as a modal over the Tools panel.
//
// The switch used to dead-end on a sentence naming two chores ("start
// docker.service or add yourself to the docker group") and doing neither. This
// does them: ryoku-docker starts the service and grants container access, then
// the cobalt image is pulled and the container started. Each step reports for
// itself so a failure names the step that failed rather than the whole feature.
//
// There is no reboot step. The helper escalates through polkit and never reads
// this session's groups, so the engine works in the session the user is already
// in; the group is still added, which is why the access step says plain `docker`
// on the command line arrives at the next login.
//
// All state lives in Stash (setupSteps / setupState / setupStep). This file only
// renders it, which is what lets the flow be tested without a window.
Item {
    id: root

    property real s: 1
    property bool open: false
    signal closed()

    visible: opacity > 0.01
    opacity: root.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    readonly property bool busy: Stash.setupState === "running"

    // Scrim: swallows clicks so the panel behind cannot be driven mid-setup.
    // Dismissing while a privileged step is in flight would leave the host
    // half-provisioned with nothing watching it, so the scrim only closes when
    // the run is not busy.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea {
            anchors.fill: parent
            onClicked: if (!root.busy) root.closed()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 24 * root.s, 300 * root.s)
        implicitHeight: body.implicitHeight + 22 * root.s
        height: implicitHeight
        radius: Theme.radiusWidget
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)

        // Clicks on the card must not reach the scrim underneath.
        MouseArea { anchors.fill: parent }

        Column {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 11 * root.s
            anchors.topMargin: 11 * root.s
            spacing: 7 * root.s

            Text {
                text: I18n.tr("Set up the cobalt engine")
                color: Theme.inkOn(Theme.surfaceContainer, Theme.onSurface)
                font.family: Theme.fontPrimary
                font.pixelSize: 11 * root.s
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: {
                    switch (Stash.setupState) {
                    case "done":
                        return I18n.tr("Ready. Downloads now run through your local cobalt.");
                    case "failed":
                        return I18n.tr("Setup stopped. Nothing was left running.");
                    default:
                        return I18n.tr("cobalt ships only as a container, so this starts the runtime and pulls the image once. No reboot needed.");
                    }
                }
                color: Theme.inkOn(Theme.surfaceContainer, Theme.onSurfaceVariant, 3.0)
                font.family: Theme.fontPrimary
                font.pixelSize: 8 * root.s
            }

            Column {
                width: parent.width
                spacing: 5 * root.s

                Repeater {
                    model: Stash.setupSteps

                    delegate: Item {
                        id: stepRow

                        required property string label
                        required property string stepState
                        required property string msg

                        width: body.width
                        implicitHeight: Math.max(stepText.implicitHeight, 13 * root.s)

                        readonly property color tone: {
                            switch (stepRow.stepState) {
                            case "done":    return Theme.primary;
                            case "failed":  return Theme.vermLit;
                            case "running": return Theme.inkOn(Theme.surfaceContainer, Theme.onSurface);
                            default:        return Theme.inkOn(Theme.surfaceContainer, Theme.onSurfaceVariant, 3.0);
                            }
                        }

                        MaterialIcon {
                            id: stepIcon
                            anchors.left: parent.left
                            anchors.top: parent.top
                            font.pixelSize: 12 * root.s
                            color: stepRow.tone
                            text: {
                                switch (stepRow.stepState) {
                                case "done":    return "check_circle";
                                case "failed":  return "error";
                                case "running": return "progress_activity";
                                default:        return "radio_button_unchecked";
                                }
                            }
                            RotationAnimation on rotation {
                                running: stepRow.stepState === "running"
                                loops: Animation.Infinite
                                from: 0; to: 360; duration: 900
                            }
                        }

                        Column {
                            id: stepText
                            anchors.left: stepIcon.right
                            anchors.leftMargin: 7 * root.s
                            anchors.right: parent.right
                            spacing: 1 * root.s

                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: I18n.tr(stepRow.label)
                                color: stepRow.tone
                                font.family: Theme.fontPrimary
                                font.pixelSize: 9 * root.s
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                visible: stepRow.msg.length > 0
                                text: stepRow.msg
                                color: stepRow.stepState === "failed"
                                    ? Theme.vermLit
                                    : Theme.inkOn(Theme.surfaceContainer, Theme.onSurfaceVariant, 3.0)
                                font.family: Theme.fontPrimary
                                font.pixelSize: 8 * root.s
                            }
                        }
                    }
                }
            }

            // Buttons. Retry re-runs the whole flow rather than resuming, which
            // is safe because every step converges: the service is already up,
            // the group already holds the user, the image is already pulled.
            Row {
                anchors.right: parent.right
                spacing: 6 * root.s

                WizButton {
                    s: root.s
                    label: Stash.setupState === "done" ? I18n.tr("Done") : I18n.tr("Close")
                    enabled: !root.busy
                    onTapped: root.closed()
                }

                WizButton {
                    s: root.s
                    label: I18n.tr("Retry")
                    accent: true
                    visible: Stash.setupState === "failed"
                    onTapped: Stash.startSetup()
                }

                WizButton {
                    s: root.s
                    label: I18n.tr("Start setup")
                    accent: true
                    visible: Stash.setupState === "idle"
                    onTapped: Stash.startSetup()
                }
            }
        }
    }

    // The panel's ActionButton is an inline component of PanelTools, so it
    // cannot cross files; this is the same visual language at wizard scale.
    component WizButton: Item {
        id: btn
        property real s: 1
        property string label: ""
        property bool accent: false
        signal tapped()

        implicitWidth: btnText.implicitWidth + 20 * btn.s
        implicitHeight: 21 * btn.s
        opacity: btn.enabled ? 1 : 0.4

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusWidget
            color: btn.accent ? Theme.primary
                : ba.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05)
            border.width: btn.accent ? 0 : 1
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)

            Text {
                id: btnText
                anchors.centerIn: parent
                text: I18n.tr(btn.label)
                color: btn.accent ? Theme.inkOn(Theme.primary, Theme.onPrimary)
                    : Theme.inkOn(Theme.surfaceContainer, Theme.onSurface)
                font.family: Theme.fontPrimary
                font.pixelSize: 9 * btn.s
                font.weight: btn.accent ? Font.DemiBold : Font.Normal
            }

            MouseArea {
                id: ba
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: btn.enabled
                onClicked: btn.tapped()
            }
        }
    }
}
