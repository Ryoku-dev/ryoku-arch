pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// The first-run walkthrough: a five-step guided tour over the threshold art.
// Left half is the constant chrome (brand lockup, progress) laid over the art;
// the right half carries the current step (header + body) and the tour navigation.
// Paper and ink throughout: the scrims are the paper flooding over the art,
// and the only accent is the 力 mark and the art's own sun.
// Shown once on first login (autostart guards a state flag), and dismissible any
// time (Escape / Skip / close) -- the daemon marks it seen after this window exits.
Rectangle {
    id: root

    color: Tokens.paper
    focus: true
    implicitWidth: 1180
    implicitHeight: 760
    // the paper flooding back over the art, at a given depth.
    function scrim(a) { return Qt.rgba(Tokens.paper.r, Tokens.paper.g, Tokens.paper.b, a); }

    readonly property var steps: [
        { "eyebrow": I18n.tr("Welcome"),          "title": I18n.tr("Welcome to %1").arg(Theme.brandName),     "subtitle": I18n.tr("%1 \u00b7 a hand-built paper-and-ink desktop on Arch and Hyprland.").arg(Theme.mark), "next": I18n.tr("Take the tour") },
        { "eyebrow": I18n.tr("Getting around"),   "title": I18n.tr("The keys that matter"), "subtitle": I18n.tr("A handful of shortcuts open almost everything."),                    "next": I18n.tr("Next") },
        { "eyebrow": I18n.tr("Where things live"),"title": I18n.tr("Know your desktop"),    "subtitle": I18n.tr("Four surfaces, and how to summon each one."),                          "next": I18n.tr("Next") },
        { "eyebrow": I18n.tr("Make it yours"),    "title": I18n.tr("A few quick choices"),  "subtitle": I18n.tr("Set the essentials now; the rest waits in Settings."),                 "next": I18n.tr("Next") },
        { "eyebrow": I18n.tr("Ready"),            "title": I18n.tr("You're all set"),       "subtitle": I18n.tr("Everything from here is yours to change."),                            "next": I18n.tr("Enter %1").arg(Theme.brandName) }
    ]
    readonly property int lastStep: steps.length - 1
    property int step: 0

    function advance() { if (step < lastStep) step += 1; else finish(); }
    function back() { if (step > 0) step -= 1; }
    function goTo(i) { if (i >= 0 && i <= lastStep) step = i; }
    function finish() { Qt.quit(); }

    // Open Ryoku Settings, then close the tour. setsid forks the Hub into its own
    // session so it survives this process exiting; flock mirrors the Super+, launch
    // guard so a second instance no-ops instead of stacking.
    function openHubAndFinish() { hubProc.running = true; quitFallback.restart(); }

    Process {
        id: hubProc
        command: ["setsid", "-f", "flock", "-n", "-o", "/tmp/ryoku-hub.lock", "qs", "-c", "hub"]
        environment: Spawn.env
        onExited: Qt.quit()
    }
    Timer { id: quitFallback; interval: 1500; onTriggered: Qt.quit() }

    Keys.onEscapePressed: root.finish()
    Keys.onReturnPressed: root.advance()
    Keys.onEnterPressed: root.advance()
    Keys.onRightPressed: root.advance()
    Keys.onLeftPressed: root.back()

    Backdrop { anchors.fill: parent }

    // content scrim: darken the right half where the step content sits, leaving the
    // left (statue + red sun) clear. Horizontal so the art dissolves into legibility.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: root.scrim(0) }
            GradientStop { position: 0.42; color: root.scrim(0) }
            GradientStop { position: 0.62; color: root.scrim(0.74) }
            GradientStop { position: 1.0;  color: root.scrim(0.92) }
        }
    }

    // bottom + top scrims (full width) for the chrome laid over the art.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: root.scrim(0.34) }
            GradientStop { position: 0.16; color: root.scrim(0) }
            GradientStop { position: 0.74; color: root.scrim(0) }
            GradientStop { position: 1.0;  color: root.scrim(0.72) }
        }
    }

    // --- left chrome: brand lockup ----------------------------------------
    Row {
        id: brand
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 40
        anchors.topMargin: 34
        spacing: 13

        // the seal: a hairline plate, the mark in the brand sun. The accent may
        // name the brand (frame, 力, art); it never floods a surface, so the
        // plate itself stays paper.
        Rectangle {
            width: 42
            height: 42
            anchors.verticalCenter: parent.verticalCenter
            radius: Tokens.radius
            color: "transparent"
            border.width: Tokens.border
            border.color: Tokens.line

            BrandMark {
                anchors.centerIn: parent
                size: 24
                color: Tokens.sun
                weight: Font.Bold
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
                text: Theme.brandName.toUpperCase()
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: 16
                font.weight: Font.DemiBold
                font.letterSpacing: Tokens.trackMark
            }
            Text {
                text: I18n.tr("FIRST LIGHT")
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fTiny
                font.letterSpacing: Tokens.trackMark
            }
        }
    }

    // --- left chrome: progress -------------------------------------------
    Column {
        id: progress
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 42
        anchors.bottomMargin: 40
        spacing: 14

        // square registration ticks, one per step: the current one is the long
        // ink bar, visited ones keep faint ink, unvisited stay hairline ghosts.
        Row {
            spacing: 8
            Repeater {
                model: root.steps.length
                delegate: Rectangle {
                    id: tick
                    required property int index
                    readonly property bool active: root.step === index
                    readonly property bool done: index < root.step
                    width: active ? 26 : 10
                    height: 3
                    color: active ? Tokens.ink : (done ? Tokens.inkFaint : Tokens.lineSoft)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on width { NumberAnimation { duration: Motion.move; easing.type: Motion.ease } }
                    Behavior on color { ColorAnimation { duration: Motion.flap } }

                    // a taller hit area than a 3px bar: pad the handlers out.
                    HoverHandler { cursorShape: Qt.PointingHandCursor; margin: 6 }
                    TapHandler { margin: 6; onTapped: root.goTo(tick.index) }
                }
            }
        }

        Text {
            text: ("0" + (root.step + 1)).slice(-2) + "  /  0" + root.steps.length
            color: Tokens.inkFaint
            font.family: Tokens.mono
            font.pixelSize: Tokens.fMicro
            font.letterSpacing: Tokens.trackLabel
        }
    }

    // --- right column: the step ------------------------------------------
    Item {
        id: rightCol
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 52
        anchors.topMargin: 104
        anchors.bottomMargin: 40
        width: Math.min(520, root.width * 0.46)

        // header + body, revealed together on each step change.
        Item {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: nav.top
            anchors.bottomMargin: 24
            opacity: 0
            transform: Translate { id: slide; y: 12 }

            Column {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 14

                Eyebrow { text: root.steps[root.step].eyebrow }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: root.steps[root.step].title
                    color: Tokens.ink
                    font.family: Tokens.display
                    font.pixelSize: root.step === 0 ? Tokens.fTitle : Tokens.fHero
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    lineHeight: 0.98
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: root.steps[root.step].subtitle
                    color: Tokens.inkDim
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fRow
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                }
            }

            Loader {
                id: bodyLoader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: header.bottom
                anchors.topMargin: 30
                anchors.bottom: parent.bottom
                clip: true
                sourceComponent: root.bodyFor(root.step)
            }

            Connections {
                target: bodyLoader.item
                ignoreUnknownSignals: true
                function onOpenSettings() { root.openHubAndFinish(); }
            }
        }

        // navigation: stable across steps for easy orientation.
        Item {
            id: nav
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 40

            WelcomeButton {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                kind: "ghost"
                label: I18n.tr("Skip the tour")
                visible: root.step < root.lastStep
                onClicked: root.finish()
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                WelcomeButton {
                    kind: "ghost"
                    label: I18n.tr("Back")
                    visible: root.step > 0
                    onClicked: root.back()
                }
                WelcomeButton {
                    kind: "solid"
                    label: root.steps[root.step].next
                    onClicked: root.advance()
                }
            }
        }
    }

    function bodyFor(i) {
        switch (i) {
        case 0: return cWelcome;
        case 1: return cBasics;
        case 2: return cDesktop;
        case 3: return cCustomize;
        default: return cReady;
        }
    }

    Component { id: cWelcome;   StepWelcome {} }
    Component { id: cBasics;    StepBasics {} }
    Component { id: cDesktop;   StepDesktop {} }
    Component { id: cCustomize; StepCustomize {} }
    Component { id: cReady;     StepReady {} }

    // reveal the step content on every change. Mechanical: a short settle, no
    // drift; reduced motion collapses it to a cut via the Motion gate.
    SequentialAnimation {
        id: reveal
        PropertyAction { target: content; property: "opacity"; value: 0 }
        PropertyAction { target: slide; property: "y"; value: 12 }
        ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: Motion.swap; easing.type: Motion.ease }
            NumberAnimation { target: slide; property: "y"; to: 0; duration: Motion.swap; easing.type: Motion.ease }
        }
    }
    onStepChanged: reveal.restart()
    Component.onCompleted: reveal.restart()
}
