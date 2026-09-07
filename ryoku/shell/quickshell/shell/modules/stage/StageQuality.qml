import QtQuick
import shell.services
import "Singletons"
import "../../components"

// The Look "Quality" control (docs/stage.md), compact enough for one inspector
// row: the Draft | Standard | Fine tiers from the ryostage catalogue, with the
// selected tier's model status inline: its size + Download when missing (a bar
// while installing), and a small Remove for the optional Fine model when it is
// installed but not the tier in use. Width is driven by the parent.
Item {
    id: q
    property string current: "draft"
    signal chose(string id)
    width: parent ? parent.width : 320
    implicitHeight: 38

    readonly property var sb: StageBackend
    readonly property var model: q.sb.modelForQuality(q.current)
    readonly property bool installed: !!(q.model && q.model.installed === true)
    readonly property var fine: q.sb.modelByTier("fine")
    readonly property bool fineInstalled: !!(q.fine && q.fine.installed === true)
    // Free the big Fine model only when it is installed and not the tier in use.
    readonly property bool showRemove: q.fineInstalled && q.current !== "fine" && !q.sb.installing && !q.sb.removing

    readonly property real segW: Math.max(180, Math.min(240, q.width * 0.55))

    StageSeg {
        id: seg
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: q.segW
        options: [
            { id: "draft", label: "Draft" },
            { id: "standard", label: "Standard" },
            { id: "fine", label: "Fine" }
        ]
        current: q.current
        onChose: id => q.chose(id)
    }

    // Inline status area, to the right of the tiers.
    Item {
        id: status
        anchors.left: seg.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 34

        // Missing model: size + Download in place.
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusWidget
            visible: q.model !== null && !q.installed && !q.sb.installing
            color: dlMa.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
            Behavior on color { ColorAnimation { duration: Motion.crossfade } }
            Row {
                anchors.centerIn: parent
                spacing: 6
                MaterialIcon { anchors.verticalCenter: parent.verticalCenter; text: "download"; font.pixelSize: 16; color: Theme.onSurface }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (q.model ? q.model.size : "") + " \u00B7 Download"
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                    font.weight: Font.DemiBold
                }
            }
            MouseArea {
                id: dlMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (q.model) q.sb.install(q.model.id)
            }
        }

        // Installing: an indeterminate sweep plus the latest engine line.
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 3
            visible: q.sb.installing
            Rectangle {
                width: parent.width
                height: 5
                radius: 2.5
                clip: true
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
                Rectangle {
                    id: sweep
                    width: parent.width * 0.34
                    height: parent.height
                    radius: 2.5
                    color: Theme.primary
                    x: -width
                    SequentialAnimation on x {
                        running: q.sb.installing
                        loops: Animation.Infinite
                        NumberAnimation { from: -sweep.width; to: sweep.parent.width; duration: 1100; easing.type: Easing.InOutSine }
                    }
                }
            }
            Text {
                width: parent.width
                text: q.sb.progress.length > 0 ? q.sb.progress : "Downloading\u2026"
                elide: Text.ElideRight
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 3
            }
        }

        // Installed Fine model, not in use: a small secondary Remove.
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: rmRow.implicitWidth + 18
            height: 30
            radius: Theme.radiusWidget
            visible: q.showRemove
            color: rmMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
            border.width: 1
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
            Behavior on color { ColorAnimation { duration: Motion.crossfade } }
            Row {
                id: rmRow
                anchors.centerIn: parent
                spacing: 6
                MaterialIcon { anchors.verticalCenter: parent.verticalCenter; text: "delete"; font.pixelSize: 15; color: Theme.onSurfaceVariant }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Remove Fine (" + (q.fine ? q.fine.size : "") + ")"
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 2
                }
            }
            MouseArea {
                id: rmMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (q.fine) q.sb.remove(q.fine.id)
            }
        }

        // Removing: a brief note in place.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: q.sb.removing
            text: "Removing\u2026"
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
        }
    }
}
