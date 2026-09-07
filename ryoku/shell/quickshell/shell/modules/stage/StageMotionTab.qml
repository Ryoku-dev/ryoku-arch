import QtQuick
import shell.services
import "Singletons"

// Motion tab (docs/stage.md): Amount, Idle and React-to-music, the drift the
// whole stack shares. Only Parallax has motion, so off Parallax the row is
// greyed with a caption pointing at the Effect tab.
Item {
    id: t
    readonly property bool parallax: StageBackend.effect === "parallax"

    // Greyed caption when there is nothing to tune yet.
    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: !t.parallax
        text: "Motion turns on with Parallax \u2014 pick it in the Effect tab."
        color: Theme.onSurfaceVariant
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm
    }

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: t.parallax
        spacing: 14

        Column {
            spacing: 3
            Text {
                text: "AMOUNT"
                color: Theme.primary
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 4
                font.weight: Font.DemiBold
            }
            StageSeg {
                width: 220
                options: [
                    { id: "subtle", label: "Subtle" },
                    { id: "normal", label: "Normal" },
                    { id: "strong", label: "Strong" }
                ]
                current: Config.amount
                onChose: id => Config.setAmount(id)
            }
        }
        Column {
            spacing: 3
            Text {
                text: "IDLE"
                color: Theme.primary
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 4
                font.weight: Font.DemiBold
            }
            StageSeg {
                width: 230
                options: [
                    { id: "none", label: "None" },
                    { id: "float", label: "Float" },
                    { id: "breathe", label: "Breathe" }
                ]
                current: Config.idle
                onChose: id => Config.setIdle(id)
            }
        }
        Column {
            spacing: 3
            Text {
                text: "MUSIC"
                color: Theme.primary
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 4
                font.weight: Font.DemiBold
            }
            Rectangle {
                width: 150
                height: 38
                radius: Theme.radiusWidget
                color: Config.music ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                    : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Text {
                    anchors.centerIn: parent
                    text: Config.music ? "React: On" : "React: Off"
                    color: Config.music ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.setMusic(!Config.music)
                }
            }
        }
    }
}
