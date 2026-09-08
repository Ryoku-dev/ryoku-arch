import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "lib/store.js" as StoreLogic

Item {
    id: stage

    property var item: null
    property var previewItem: null
    property string busyKey: ""
    property string installStage: ""
    property string installErrorKey: ""
    property string installError: ""
    property string positionText: ""
    property bool offline: false
    property bool reducedMotion: false
    property real artworkReveal: 1

    signal installRequested(var item)
    signal detailsRequested(var item)
    signal settingsRequested(var item)

    readonly property var displayItem: previewItem || item || ({})
    readonly property var actionItem: item || ({})
    readonly property int motionDuration: reducedMotion ? 0 : Tokens.swap
    readonly property string actionKey: StoreLogic.itemKey(actionItem)
    readonly property string primaryLabel: busyKey === actionKey && installStage !== ""
            ? installStage
            : StoreLogic.primaryAction(actionItem)
    readonly property string secondaryLabel: StoreLogic.secondaryAction(actionItem)
    readonly property bool hasActionItem: item !== null && item !== undefined
    readonly property color stageSurface: displayItem.surface || Tokens.paper
    readonly property var coverItem: ({
        id: displayItem.id,
        name: displayItem.name || displayItem.id,
        art: displayItem.art || "",
        category: displayItem.category,
        categoryName: displayItem.categoryName,
        accent: displayItem.accent,
        surface: displayItem.surface,
        installed: displayItem.installed,
        active: displayItem.active,
        enabled: displayItem.enabled,
        installedCount: displayItem.installedCount,
        totalCount: displayItem.totalCount,
        updateAvailable: displayItem.updateAvailable
    })

    clip: true

    function triggerInstall() {
        if (hasActionItem && StoreLogic.primaryAction(actionItem) !== "INSTALLED" && busyKey === "")
            installRequested(actionItem);
    }

    function triggerDetails() {
        if (hasActionItem)
            detailsRequested(actionItem);
    }

    function triggerSettings() {
        if (hasActionItem && secondaryLabel !== "")
            settingsRequested(actionItem);
    }

    function revealArtwork() {
        if (reducedMotion) {
            artworkReveal = 1;
            return;
        }
        artworkReveal = 0;
        Qt.callLater(function() { stage.artworkReveal = 1; });
    }

    // Play the entrance reveal only when the committed selection changes (or the
    // stage first gets an item), not on every hover preview: a preview swaps the
    // hero art via ProductMedia's own crossfade, so re-dimming the whole stage on
    // each hover is what made scanning the grid feel janky.
    onItemChanged: revealArtwork()
    onReducedMotionChanged: {
        if (reducedMotion)
            artworkReveal = 1;
    }

    ProductCover {
        id: artwork
        objectName: "ryostore-stage-artwork"
        anchors.fill: parent
        item: stage.coverItem
        mode: "hero"
        opacity: 0.45 + stage.artworkReveal * 0.55
        scale: 0.985 + stage.artworkReveal * 0.015

        Behavior on opacity {
            enabled: !stage.reducedMotion
            NumberAnimation { duration: stage.motionDuration; easing.type: Tokens.ease }
        }
        Behavior on scale {
            enabled: !stage.reducedMotion
            NumberAnimation { duration: stage.motionDuration; easing.type: Tokens.ease }
        }
    }

    Rectangle {
        objectName: "ryostore-stage-scrim"
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: Qt.rgba(stage.stageSurface.r, stage.stageSurface.g,
                               stage.stageSurface.b, 0.94)
            }
            GradientStop {
                position: 0.34
                color: Qt.rgba(stage.stageSurface.r, stage.stageSurface.g,
                               stage.stageSurface.b, 0.6)
            }
            GradientStop {
                position: 0.64
                color: Qt.rgba(stage.stageSurface.r, stage.stageSurface.g,
                               stage.stageSurface.b, 0.1)
            }
            GradientStop { position: 1; color: "#00000000" }
        }
    }

    // seat the stage in the surface at the bottom so the filmstrip reads as one
    // continuous shelf, not a seam
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#00000000" }
            GradientStop { position: 0.7; color: "#00000000" }
            GradientStop {
                position: 1
                color: Qt.rgba(stage.stageSurface.r, stage.stageSurface.g,
                               stage.stageSurface.b, 0.85)
            }
        }
    }

    // a low wash of the product's own accent under the story text, so each
    // hero carries a hint of the product's colour
    Rectangle {
        anchors.fill: parent
        visible: stage.hasActionItem
        opacity: 0.5 * stage.artworkReveal
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: Qt.rgba((stage.displayItem.accent ? Qt.color(stage.displayItem.accent) : Tokens.sun).r,
                               (stage.displayItem.accent ? Qt.color(stage.displayItem.accent) : Tokens.sun).g,
                               (stage.displayItem.accent ? Qt.color(stage.displayItem.accent) : Tokens.sun).b, 0.16)
            }
            GradientStop { position: 0.5; color: "#00000000" }
            GradientStop { position: 1; color: "#00000000" }
        }
        Behavior on opacity {
            enabled: !stage.reducedMotion
            NumberAnimation { duration: stage.motionDuration; easing.type: Tokens.ease }
        }
    }

    Text {
        objectName: "ryostore-stage-position"
        anchors { top: parent.top; right: parent.right; margins: Tokens.s5 }
        text: stage.positionText
        visible: text !== ""
        color: Tokens.ink
        font.family: Tokens.mono
        font.pixelSize: Tokens.fMicro
        font.letterSpacing: Tokens.trackLabel
    }

    Column {
        id: story
        anchors { left: parent.left; bottom: parent.bottom; margins: Tokens.s6 }
        width: Math.min(stage.width * 0.48, 520)
        spacing: Tokens.s3
        visible: stage.hasActionItem

        Text {
            width: parent.width
            text: String(stage.displayItem && (stage.displayItem.categoryName || stage.displayItem.category) || "").toUpperCase()
            color: Tokens.inkDim
            font.family: Tokens.mono
            font.pixelSize: Tokens.fMicro
            font.letterSpacing: Tokens.trackMark
            elide: Text.ElideRight
        }

        Text {
            objectName: "ryostore-stage-title"
            width: parent.width
            text: String(stage.displayItem && (stage.displayItem.name || stage.displayItem.id) || "")
            color: Tokens.ink
            font.family: Tokens.display
            font.pixelSize: Tokens.fHero
            font.weight: Font.Medium
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: String(stage.displayItem && (stage.displayItem.summary || stage.displayItem.description) || "")
            visible: text !== ""
            color: Tokens.inkDim
            font.family: Tokens.ui
            font.pixelSize: Tokens.fBody
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }

        StatusReadout {
            objectName: "ryostore-stage-status"
            item: stage.displayItem
            busyKey: stage.busyKey
            installStage: stage.installStage
            installErrorKey: stage.installErrorKey
            installError: stage.installError
            offline: stage.offline
        }

        Row {
            spacing: Tokens.s2

            Btn {
                objectName: "ryostore-stage-primary"
                text: stage.primaryLabel
                primary: true
                armed: stage.hasActionItem
                        && StoreLogic.primaryAction(stage.actionItem) !== "INSTALLED"
                        && stage.busyKey === ""
                Accessible.role: Accessible.Button
                Accessible.name: text
                onAct: stage.triggerInstall()
                Accessible.onPressAction: stage.triggerInstall()
            }

            Btn {
                objectName: "ryostore-stage-details"
                text: I18n.tr("VIEW DETAILS")
                armed: stage.hasActionItem
                Accessible.role: Accessible.Button
                Accessible.name: text
                onAct: stage.triggerDetails()
                Accessible.onPressAction: stage.triggerDetails()
            }

            Btn {
                objectName: "ryostore-stage-settings"
                text: stage.secondaryLabel
                visible: text !== ""
                armed: visible && stage.hasActionItem
                Accessible.role: Accessible.Button
                Accessible.name: text
                onAct: stage.triggerSettings()
                Accessible.onPressAction: stage.triggerSettings()
            }
        }
    }
}
