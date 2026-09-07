pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Ryoku.PluginKit.Singletons

// desktop placement frame for one plugin widget on the wallpaper layer.
// measures the plugin's natural size, pads it, draws an optional card/glass
// backing with a soft lift, and carries the same desktop interaction the
// shipped WidgetSlot (the clock) uses: left-drag to move (grid-snapped,
// clamped to the host), right-click for the menu, and a bottom-right resize
// bracket that scrubs scale 0.5..2.5 with a live percent readout. free
// position, scale, and lock state persist to plugins.json through the host.
// the grip lives UNDER the content so chips/thumbs/search inside the plugin
// still get their own clicks while empty card chrome reads as a drag/menu
// surface.
Item {
    id: slot

    property string pluginId: ""
    property real freeX: 80
    property real freeY: 80
    property bool locked: false
    property real pad: 18
    property string bg: "card"            // none | card | glass
    property real radius: Theme.radius
    property real gridSize: 32
    property real scaleCfg: 1             // persisted scale, bound from the host
    // Keep the resize bracket present while an Edit widgets session is on: the
    // frame overlay above intercepts hover, so a hover-only bracket would never
    // reveal (see WidgetSlot).
    property bool composing: false

    signal moved(real x, real y)
    signal resized(real scale)
    signal menuRequested(real x, real y, string id)

    // build the plugin widget directly as a child of `holder` (via
    // createComponent, which renders Image correctly where Loader doesn't),
    // so the slot measures the widget's own implicit size exactly like
    // WidgetSlot hosts Clock directly. no wrapper Item between slot and widget.
    property string contentUrl: ""
    property var configure: null
    property var item: null
    property int _buildGeneration: 0
    onContentUrlChanged: _build()
    function _build() {
        const generation = ++slot._buildGeneration;
        if (!contentUrl || contentUrl.length === 0) {
            const previous = item;
            item = null;
            if (previous)
                previous.destroy();
            return;
        }
        const requestedUrl = contentUrl;
        const previous = item;
        const component = Qt.createComponent(requestedUrl);
        function publish() {
            if (generation !== slot._buildGeneration || requestedUrl !== slot.contentUrl)
                return;
            if (component.status === Component.Ready) {
                const next = component.createObject(holder);
                if (!next) {
                    console.warn("PluginDesktopSlot: could not create", requestedUrl);
                    return;
                }
                if (configure)
                    configure(next);
                item = next;
                if (previous && previous !== next)
                    previous.destroy();
            } else if (component.status === Component.Error) {
                console.warn("PluginDesktopSlot:", component.errorString());
            }
        }
        if (component.status === Component.Loading)
            component.statusChanged.connect(publish);
        else
            publish();
    }

    readonly property real cw: item ? item.implicitWidth : 100
    readonly property real ch: item ? item.implicitHeight : 100

    // drag/resize state. while holding (dragging/resizing, or briefly after
    // release until the persisted value lands) the rendered position/scale
    // stick to the live values so they never flash back to the old config
    // for a frame.
    property bool dragging: false
    property real dragX: 0
    property real dragY: 0
    property bool resizing: false
    property real resizeOX: 0
    property real resizeOY: 0
    property real resizeStartScale: 1
    property real resizeStartDiag: 1
    readonly property bool holding: slot.dragging || slot.resizing || guard.running

    // live scale during a resize scrub. mirrors scaleCfg when idle; mutates
    // while resizing so the readout and content track the cursor without
    // writing to the host every frame (plugins have no setLive fast path).
    property real liveScale: 1
    onScaleCfgChanged: if (!slot.resizing) slot.liveScale = slot.scaleCfg
    Component.onCompleted: { slot.liveScale = slot.scaleCfg; _build(); }
    readonly property real effectiveScale: (slot.resizing || guard.running) ? slot.liveScale : slot.scaleCfg

    width: Math.max(1, slot.cw * slot.effectiveScale + slot.pad * 2)
    height: Math.max(1, slot.ch * slot.effectiveScale + slot.pad * 2)

    function clampX(v) { return Math.max(0, Math.min(v, (slot.parent ? slot.parent.width : v + slot.width) - slot.width)); }
    function clampY(v) { return Math.max(0, Math.min(v, (slot.parent ? slot.parent.height : v + slot.height) - slot.height)); }
    function snap(v) { return Math.round(v / slot.gridSize) * slot.gridSize; }

    x: slot.holding ? slot.dragX : slot.clampX(slot.freeX)
    y: slot.holding ? slot.dragY : slot.clampY(slot.freeY)
    Behavior on x { enabled: !slot.holding; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !slot.holding; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    // press bump: small lift while dragging, so it feels picked up.
    scale: slot.dragging ? 1.03 : 1.0
    transformOrigin: Item.Center
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutExpo } }

    Timer { id: guard; interval: 90 }

    // soft lift off the wallpaper for the backed styles.
    MultiEffect {
        source: backing
        anchors.fill: backing
        visible: slot.bg !== "none"
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.5)
        shadowBlur: 1.0
        shadowVerticalOffset: 6
        blurMax: 32
        autoPaddingEnabled: true
    }

    Rectangle {
        id: backing
        anchors.fill: parent
        visible: slot.bg !== "none"
        radius: slot.radius
        // match the shipped desktop widgets (WidgetSlot): translucent dark
        // card with a faint white hairline, so plugin tiles read identical
        // to the clock on the wallpaper.
        color: slot.bg === "card" ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(16 / 255, 16 / 255, 24 / 255, 0.26)
        border.width: 1
        border.color: slot.bg === "card" ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.16)

        // glass sheen, matching WidgetSlot.
        Rectangle {
            visible: slot.bg === "glass"
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.06) }
            }
        }
    }

    // drag/menu grip UNDER the content: left-drag on empty card chrome (the
    // header eyebrow, padding, gaps) moves the tile and right-click opens
    // the menu, while plugin chrome (chips, thumbs, search) keeps its own
    // clicks on top. a grip above the content swallows every click (that
    // was the reported "unresponsive to clicks").
    MouseArea {
        id: grip
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: slot.locked ? Qt.ArrowCursor : (slot.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

        property bool leftDown: false
        property real grabOX: 0
        property real grabOY: 0

        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                const pr = slot.mapToItem(slot.parent, mouse.x, mouse.y);
                slot.menuRequested(pr.x, pr.y, slot.pluginId);
                return;
            }
            if (slot.locked)
                return;
            grip.leftDown = true;
            const p = slot.mapToItem(slot.parent, mouse.x, mouse.y);
            grip.grabOX = p.x - slot.x;
            grip.grabOY = p.y - slot.y;
        }
        onPositionChanged: (mouse) => {
            if (!grip.leftDown || slot.locked)
                return;
            const p = slot.mapToItem(slot.parent, mouse.x, mouse.y);
            const nx = p.x - grip.grabOX;
            const ny = p.y - grip.grabOY;
            if (!slot.dragging) {
                if (Math.abs(nx - slot.x) < 6 && Math.abs(ny - slot.y) < 6)
                    return;
                slot.dragging = true;
            }
            slot.dragX = slot.clampX(slot.snap(nx));
            slot.dragY = slot.clampY(slot.snap(ny));
        }
        onReleased: (mouse) => {
            if (slot.dragging) {
                slot.moved(Math.round(slot.dragX), Math.round(slot.dragY));
                slot.dragging = false;
                guard.restart();
            }
            grip.leftDown = false;
        }
    }

    // content holder: a Scale transform applies the live scale, so the
    // plugin grows visibly from its top-left as the resize bracket scrubs.
    // slot width/height grow in lockstep so the backing tracks the content.
    Item {
        id: holder
        x: slot.pad
        y: slot.pad
        width: slot.cw
        height: slot.ch
        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: slot.effectiveScale
            yScale: slot.effectiveScale
        }
    }

    // hover state for the slot and its children, so the resize handle stays
    // lit while you reach across to it.
    HoverHandler { id: slotHover }

    // quick resize: drag the bottom-right bracket to scrub the widget's
    // scale. top-left is pinned during the resize so it grows toward the
    // cursor; on release the new scale persists through the host.
    Item {
        id: handle
        width: 22
        height: 22
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        opacity: (((slotHover.hovered || slot.composing) && !slot.locked && !slot.dragging) || slot.resizing) ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 13
            height: 2
            radius: Theme.radius
            color: (hgrip.containsMouse || slot.resizing) ? Theme.accent : Theme.faint
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 2
            height: 13
            radius: Theme.radius
            color: (hgrip.containsMouse || slot.resizing) ? Theme.accent : Theme.faint
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        MouseArea {
            id: hgrip
            anchors.fill: parent
            enabled: !slot.locked
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor

            onPressed: (mouse) => {
                const ox = slot.x;
                const oy = slot.y;
                slot.dragX = ox;
                slot.dragY = oy;
                slot.resizeOX = ox;
                slot.resizeOY = oy;
                slot.resizeStartScale = slot.effectiveScale;
                const p = hgrip.mapToItem(slot.parent, mouse.x, mouse.y);
                slot.resizeStartDiag = Math.max(1, Math.hypot(p.x - ox, p.y - oy));
                slot.resizing = true;
            }
            onPositionChanged: (mouse) => {
                if (!slot.resizing)
                    return;
                const p = hgrip.mapToItem(slot.parent, mouse.x, mouse.y);
                const diag = Math.hypot(p.x - slot.resizeOX, p.y - slot.resizeOY);
                const ns = Math.max(0.5, Math.min(2.5, slot.resizeStartScale * diag / slot.resizeStartDiag));
                slot.liveScale = ns;
            }
            onReleased: (mouse) => {
                if (slot.resizing) {
                    slot.resized(slot.liveScale);
                    slot.resizing = false;
                    guard.restart();
                }
            }
        }
    }

    // live size readout while resizing.
    Rectangle {
        visible: slot.resizing
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 26
        anchors.bottomMargin: 26
        width: roText.implicitWidth + 16
        height: 20
        radius: Theme.radius
        color: Qt.rgba(0, 0, 0, 0.62)
        Text {
            id: roText
            anchors.centerIn: parent
            text: Math.round(slot.effectiveScale * 100) + "%"
            color: Theme.cream
            font.family: Theme.mono
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }
}
