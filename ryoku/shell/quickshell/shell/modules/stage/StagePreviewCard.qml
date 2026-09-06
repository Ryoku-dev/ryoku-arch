import QtQuick
import QtQuick.Effects
import shell.services

// The Stage entry-card preview (docs/stage.md): the wallpaper with the cut
// subject lifted. Progress and editing live on the desktop, not here, so this
// card only shows the current cut: dimmed while the engine is working.
Rectangle {
    id: card
    property string wallpaperUrl: ""
    property string subjectUrl: ""
    property string fit: "Cover"
    property bool busy: false

    width: parent ? parent.width : 0
    height: 150
    radius: Theme.radiusWidget
    clip: true
    color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.04)
    border.width: 1
    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)

    function _fill(im) {
        switch (card.fit) {
        case "Contain": return Image.PreserveAspectFit;
        case "Fill": return Image.Stretch;
        default: return Image.PreserveAspectCrop;
        }
    }

    Image {
        id: wall
        anchors.fill: parent
        source: card.wallpaperUrl
        cache: false
        asynchronous: true
        fillMode: card._fill(wall)
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.crossfade } }
    }
    // The lifted subject: same frame, a soft shadow to sit it proud of the wall.
    Image {
        id: subj
        anchors.fill: parent
        source: card.subjectUrl
        cache: false
        asynchronous: true
        fillMode: card._fill(subj)
        visible: card.subjectUrl !== ""
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.crossfade } }
        layer.enabled: subj.visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.5)
            shadowBlur: 0.7
            shadowVerticalOffset: 5
        }
    }

    // Working: a gentle dim, no ring: progress is drawn on the desktop subject.
    Rectangle {
        anchors.fill: parent
        visible: card.busy
        color: Qt.rgba(0, 0, 0, 0.35)
    }
}
