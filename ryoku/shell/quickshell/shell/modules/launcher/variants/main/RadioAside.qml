import QtQuick
import "../../shared/Singletons"
import "metrics.js" as MainMetrics
import Ryoku.Ui.Singletons

// The radio's between-states chip, two coats:
//  - tuning: the engine says on air but the player hasn't sounded yet (yt-dlp
//    can take a long moment) - without this strip, Enter looks like it did
//    nothing and a confused second Enter would stop the still-resolving radio.
//  - parked: other music started, the watcher set the radio aside - one tap
//    (or RESUME) tunes it back in; the small × lets it go.
Rectangle {
    id: chip

    property real s: 1
    readonly property bool tuningMode: Radio.tuning
    readonly property string label: tuningMode ? (Radio.label || I18n.tr("radio"))
        : (Radio.aside && Radio.aside.label ? I18n.tr(Radio.aside.label) : I18n.tr("radio"))

    implicitHeight: 34 * s
    radius: MainMetrics.radiusRow * s
    color: hover.containsMouse ? Theme.threadBg : Qt.rgba(0.94, 0.88, 0.84, 0.03)
    border.width: 1
    border.color: hover.containsMouse ? Theme.lineStrong : Qt.alpha(Theme.vermLit, 0.25)

    // the tally lamp: dim when parked, pulsing while the tuner works.
    Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.leftMargin: 12 * chip.s
        anchors.verticalCenter: parent.verticalCenter
        width: 6 * chip.s
        height: width
        radius: width / 2
        color: chip.tuningMode ? Theme.vermLit : Qt.alpha(Theme.vermLit, 0.55)
        SequentialAnimation on opacity {
            running: chip.tuningMode && chip.visible
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.25; to: 1; duration: 700; easing.type: Easing.InOutSine }
            onStopped: dot.opacity = 1
        }
    }

    Text {
        anchors.left: dot.right
        anchors.right: resume.left
        anchors.leftMargin: 10 * chip.s
        anchors.rightMargin: 8 * chip.s
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.StyledText
        text: chip.tuningMode
            ? I18n.tr("%1  <font color=\"%2\">·  tuning in - a few quiet seconds is normal</font>").arg(chip.label).arg(Theme.faint)
            : I18n.tr("%1  <font color=\"%2\">·  set aside for your music</font>").arg(chip.label).arg(Theme.faint)
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: Metrics.fontSubtitle * chip.s
        elide: Text.ElideRight
    }

    Rectangle {
        id: resume
        visible: !chip.tuningMode
        anchors.right: dismiss.left
        anchors.rightMargin: 6 * chip.s
        anchors.verticalCenter: parent.verticalCenter
        width: chip.tuningMode ? 0 : resumeLabel.implicitWidth + 18 * chip.s
        height: 22 * chip.s
        radius: height / 2
        color: resumeHover.containsMouse ? Qt.alpha(Theme.vermLit, 0.22) : Qt.alpha(Theme.vermLit, 0.12)
        border.width: 1
        border.color: Theme.vermLit
        Text {
            id: resumeLabel
            anchors.centerIn: parent
            text: I18n.tr("RESUME")
            color: Theme.vermLit
            font.family: Theme.mono
            font.pixelSize: 9 * chip.s
            font.letterSpacing: 1.5
        }
        MouseArea {
            id: resumeHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Radio.resume()
        }
    }

    Text {
        id: dismiss
        anchors.right: parent.right
        anchors.rightMargin: 10 * chip.s
        anchors.verticalCenter: parent.verticalCenter
        text: "×"
        color: dismissHover.containsMouse ? Theme.cream : Theme.faint
        font.family: Theme.font
        font.pixelSize: 14 * chip.s
        MouseArea {
            id: dismissHover
            anchors.fill: parent
            anchors.margins: -6 * chip.s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Radio.stop()   // clears the parked station for good
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // behind the buttons: a tap anywhere else resumes a parked station;
        // while tuning there is nothing to resume, so the strip is inert.
        z: -1
        enabled: !chip.tuningMode
        onClicked: Radio.resume()
    }
}
