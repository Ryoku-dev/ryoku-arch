import QtQuick
import shell.services
import "Singletons"
import "../../components"

// The Look "Quality" control (docs/stage.md): the Draft | Standard | Fine tiers
// rendered from the ryostage catalogue, with the selected tier's model status in
// place: its size + Download when missing (a bar while installing), Remove for
// the optional Fine model afterwards: and a one-line licence footnote so the
// provenance is always visible.
Column {
    id: q
    property string current: "draft"
    signal chose(string id)
    width: parent ? parent.width : 0
    spacing: 8

    readonly property var sb: StageBackend
    readonly property var model: q.sb.modelForQuality(q.current)
    readonly property bool installed: !!(q.model && q.model.installed === true)
    // Only the large optional Fine model is removable; Draft/Standard share the
    // base u2netp weights the engine always needs.
    readonly property bool removable: !!(q.model && q.model.tier === "fine")

    StageSeg {
        options: [
            { id: "draft", label: "Draft" },
            { id: "standard", label: "Standard" },
            { id: "fine", label: "Fine" }
        ]
        current: q.current
        onChose: id => q.chose(id)
    }

    // Missing model: size + Download in place.
    Rectangle {
        width: parent.width
        height: 40
        radius: Theme.radiusWidget
        visible: q.model !== null && !q.installed && !q.sb.installing
        color: dlMa.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
            : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
        Behavior on color { ColorAnimation { duration: Motion.crossfade } }
        Row {
            anchors.centerIn: parent
            spacing: 8
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "download"
                font.pixelSize: 17
                color: Theme.onSurface
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (q.model ? q.model.size : "") + " \u00B7 Download"
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
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

    // Installing: an indeterminate bar plus the latest engine line.
    Column {
        width: parent.width
        spacing: 4
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

    // Installed + removable: free the model again.
    Rectangle {
        width: parent.width
        height: 36
        radius: Theme.radiusWidget
        visible: q.installed && q.removable && !q.sb.installing
        color: rmMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.crossfade } }
        Row {
            anchors.centerIn: parent
            spacing: 8
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "delete"
                font.pixelSize: 16
                color: Theme.onSurfaceVariant
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: q.sb.removing ? "Removing\u2026" : ("Remove (" + (q.model ? q.model.size : "") + ")")
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
            }
        }
        MouseArea {
            id: rmMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (q.model && !q.sb.removing) q.sb.remove(q.model.id)
        }
    }

    // Licence footnote: provenance always visible.
    Text {
        width: parent.width
        visible: q.model !== null
        text: q.model ? (q.model.licence + " \u00B7 " + q.model.upstream) : ""
        wrapMode: Text.WrapAnywhere
        color: Qt.rgba(Theme.onSurfaceVariant.r, Theme.onSurfaceVariant.g, Theme.onSurfaceVariant.b, 0.8)
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm - 4
    }
}
