pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"
import "../../components"

// The selected element's own actions (docs/stage.md), shown in the inspector's
// element tab. A LAYER owns whether it is behind or in front of the widgets
// (never a widget: the same relationship is never shown twice), its near..far
// drift in Parallax, and Remove unless it is the subject. A WIDGET gets Lock,
// Settings and Remove -- no front/behind. The VISUALIZER picks its own placement
// and Remove. Layer edits go straight to the daemon through StageBackend; widget
// and visualizer actions are host-specific and reported as signals.
Item {
    id: el

    property string kind: ""        // layer | widget | viz | ""
    property int slot: -1           // layer index when kind == "layer"
    property bool isFront: false
    property real depth: 0.5
    property bool parallax: false
    property bool canRemove: true
    property bool locked: false

    signal widgetLock()
    signal widgetSettings()
    signal widgetRemove()
    signal vizFlip()
    signal vizRemove()

    // A pill action button: icon + label, optionally lit as a toggle.
    component ActBtn: Rectangle {
        id: ab
        property string icon: ""
        property string label: ""
        property bool on: false
        signal act()
        width: abRow.implicitWidth + 26
        height: 38
        radius: Theme.radiusWidget
        color: ab.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
            : abMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
        border.width: 1
        border.color: ab.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
            : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Row {
            id: abRow
            anchors.centerIn: parent
            spacing: 7
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: ab.icon
                font.pixelSize: 17
                visible: ab.icon.length > 0
                color: ab.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ab.label
                color: ab.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
                font.weight: Font.DemiBold
            }
        }
        MouseArea { id: abMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ab.act() }
    }

    // ── LAYER ────────────────────────────────────────────────────────────
    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: el.kind === "layer"
        spacing: 14

        StageSeg {
            width: 320
            anchors.verticalCenter: parent.verticalCenter
            options: [
                { id: "behind", label: "Behind widgets" },
                { id: "front", label: "In front of widgets" }
            ]
            current: el.isFront ? "front" : "behind"
            onChose: id => StageBackend.setLayerFront(el.slot, id === "front")
        }

        // near..far drift, Parallax only.
        Item {
            width: 210
            height: 38
            anchors.verticalCenter: parent.verticalCenter
            visible: el.parallax
            Text {
                id: nearLbl
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "near"
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 2
            }
            Text {
                id: farLbl
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "far"
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 2
            }
            Rectangle {
                id: track
                anchors.left: nearLbl.right
                anchors.right: farLbl.left
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 6
                radius: 3
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.18)
                Rectangle {
                    width: 15; height: 15; radius: 7.5
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(track.width - 15, (track.width - 15) * el.depth))
                    color: Theme.surface
                    border.width: 2
                    border.color: Theme.primary
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    cursorShape: Qt.SizeHorCursor
                    function set(mx) {
                        const frac = Math.max(0, Math.min(1, (mx - 7.5) / Math.max(1, track.width - 15)));
                        StageBackend.setLayerDepth(el.slot, frac);
                    }
                    onPressed: mouse => set(mouse.x)
                    onPositionChanged: mouse => { if (mouse.buttons & Qt.LeftButton) set(mouse.x); }
                }
            }
        }

        ActBtn {
            anchors.verticalCenter: parent.verticalCenter
            visible: el.canRemove
            icon: "close"
            label: "Remove"
            onAct: { StageBackend.removeLayer(el.slot); StageSession.deselect(); }
        }
    }

    // ── WIDGET ───────────────────────────────────────────────────────────
    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: el.kind === "widget"
        spacing: 12
        ActBtn { anchors.verticalCenter: parent.verticalCenter; icon: el.locked ? "lock" : "lock_open"; label: "Lock"; on: el.locked; onAct: el.widgetLock() }
        ActBtn { anchors.verticalCenter: parent.verticalCenter; icon: "tune"; label: "Settings"; onAct: el.widgetSettings() }
        ActBtn { anchors.verticalCenter: parent.verticalCenter; icon: "close"; label: "Remove"; onAct: el.widgetRemove() }
    }

    // ── VISUALIZER ───────────────────────────────────────────────────────
    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: el.kind === "viz"
        spacing: 14
        StageSeg {
            width: 300
            anchors.verticalCenter: parent.verticalCenter
            options: [
                { id: "desktop", label: "On desktop" },
                { id: "above", label: "Above windows" }
            ]
            current: el.isFront ? "above" : "desktop"
            onChose: id => { if ((id === "above") !== el.isFront) el.vizFlip(); }
        }
        ActBtn { anchors.verticalCenter: parent.verticalCenter; icon: "close"; label: "Remove"; onAct: el.vizRemove() }
    }
}
