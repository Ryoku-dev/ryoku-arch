pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as C
import QtQuick.Effects
import Qt.labs.folderlistmodel
import "Singletons"
import Ryoku.Ui.Singletons

// A decorative filler poster in the reference's noir style: a real, noir-baked
// image or gif (a statue, the moon, a Muybridge/phenakistoscope motion loop), a
// big Japanese title, a vertical tategaki phrase, a fine-print caption, a
// scannable barcode and a kanji seal. Pure decoration -- it holds no control and
// means nothing -- so it fills a dead grid slot and gives a section its face.
//
// Right-click the art to open the editor. The image is framed the way the App
// Launcher frames its hero: sized to cover the panel, then placed by a 0..1
// focal point (drag to move it) with a zoom (scroll / pinch / buttons; below 100%
// reveals more of the image, above crops in). Because the focal point is a
// fraction, the small editor preview crops identically to the real box (WYSIWYG).
// Pick from the gallery underneath -- the baked set or a custom file of your own,
// desaturated to noir -- and press Enter to save (Esc cancels). Choice and framing
// persist per `boxId` through `DecorStore`. With no image it falls back to the
// in-engine `DitherField`.
Item {
    id: dec
    visible: Tokens.showPosters

    property string title: ""        // big JP title, e.g. 入力
    property string sub: ""          // small JP subtitle
    property string tate: ""         // vertical tategaki phrase
    property string caption: ""      // fine-print english
    property string code: "RYOKU"    // barcode text
    property string seal: "\u529b"   // seal glyph (力 by default)
    property var readout: []         // instrument readout, "LABEL|value" per cell

    property string boxId: ""        // stable key for persisted state
    property real seed: 1.0          // default image index + dither field
    property real ditherFreq: 1.0

    // the baked art set (bare filenames under ~/Pictures/ryodecors, resolved via
    // Ryodecors.dir); an empty list falls back to the procedural DitherField.
    property var images: dec.defaultArt
    readonly property var defaultArt: [
        "laocoon.png", "david.png", "aurelius.png", "moon.png", "lighthouse.png",
        "horse.gif", "disc.gif", "earth.gif", "cradle.gif", "wave.gif",
        "render.gif", "torus.gif", "sphere.gif", "cube.gif", "spring.gif", "bounce.gif", "compass.gif"
    ]

    // Store-installed decors share the shipped set's folder but are not part of
    // it; surface them in the editor gallery so a store install is pickable in
    // any box, without joining the per-context default images above.
    property var installedArt: []
    readonly property var galleryArt: dec.images.concat(dec.installedArt.filter(function (n) { return dec.images.indexOf(n) < 0; }))
    FolderListModel {
        id: decorFolder
        folder: Ryodecors.dir
        showDirs: false
        showHidden: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp"]
        sortField: FolderListModel.Name
        onCountChanged: {
            var names = [];
            for (var i = 0; i < decorFolder.count; i++) {
                var nm = "" + decorFolder.get(i, "fileName");
                if (dec.defaultArt.indexOf(nm) < 0)
                    names.push(nm);
            }
            dec.installedArt = names;
        }
    }

    // persisted, live state (never a binding, so an edit sticks and never reverts)
    property int shot: 0
    property real zoom: 1            // 1 = cover the panel; <1 reveals more, >1 crops in
    property real posX: 0.5          // focal point, 0..1, like the launcher's hero
    property real posY: 0.5
    property string src: ""          // a custom file, overrides the baked set
    property bool editing: false

    readonly property int idx: dec.galleryArt.length > 0
        ? ((dec.shot % dec.galleryArt.length) + dec.galleryArt.length) % dec.galleryArt.length : 0
    readonly property bool isCustom: dec.src !== ""
    // a noir desaturation layer freezes an animated gif to one captured frame, so
    // it is applied only to a custom still; gifs (custom or baked) animate as-is.
    readonly property bool srcIsGif: dec.art.toLowerCase().endsWith(".gif")
    readonly property string art: dec.isCustom ? dec.src : (dec.galleryArt.length > 0 ? dec.galleryArt[dec.idx] : "")
    readonly property bool hasArt: dec.art !== ""
    readonly property url artSource: dec.isCustom ? dec.src : (dec.hasArt ? Ryodecors.dir + dec.art : "")

    readonly property bool wide: width >= 430
    readonly property bool roomy: width >= 560   // room for the barcode beside the title
    readonly property bool dense: height < 130
    // the box's art-panel shape, so the editor preview can match it (WYSIWYG)
    readonly property real artAspect: art.height > 0 ? art.width / art.height : 2

    // ── persistence ─────────────────────────────────────────────────────────
    function syncFromStore() {
        if (dec.editing || dec.justEdited)
            return;                            // never clobber a live edit
        var b = dec.boxId !== "" ? DecorStore.box(dec.boxId) : ({});
        dec.shot = (b.shot !== undefined) ? b.shot : Math.floor(dec.seed);
        dec.zoom = (b.zoom !== undefined) ? b.zoom : 1;
        dec.posX = (b.posX !== undefined) ? b.posX : 0.5;
        dec.posY = (b.posY !== undefined) ? b.posY : 0.5;
        dec.src = (b.src !== undefined) ? b.src : "";
    }
    // A local edit (framing, pick, next/shuffle) persists at once; DecorStore's own
    // file-watch then re-broadcasts, and a stale re-read would revert the very change
    // we just made. Hold a short guard after a local write so syncFromStore skips it;
    // external changes still land once the window passes.
    property bool justEdited: false
    Timer { id: editGuard; interval: 700; onTriggered: dec.justEdited = false }
    function persistNow() {
        if (dec.boxId === "")
            return;
        dec.justEdited = true;
        editGuard.restart();
        DecorStore.put(dec.boxId, { shot: dec.shot, zoom: dec.zoom, posX: dec.posX, posY: dec.posY, src: dec.src });
    }
    Component.onCompleted: dec.syncFromStore()
    Connections { target: DecorStore; function onDataChanged() { dec.syncFromStore(); } }
    onEditingChanged: if (dec.editing) editor.open()

    // the image, sized to cover the panel and placed by the 0..1 focal point,
    // exactly like the launcher's hero. A custom (colour) source goes noir.
    component ArtView: Item {
        id: av
        clip: true
        DitherField {
            anchors.fill: parent; anchors.margins: 1
            visible: !dec.hasArt
            freq: dec.ditherFreq; seed: dec.seed
        }
        AnimatedImage {
            id: im
            visible: dec.hasArt
            source: dec.artSource
            asynchronous: true
            playing: true
            onStatusChanged: if (status === Image.Ready) playing = true
            // re-apply the current art after an edit: the box was occluded by the
            // modal, so the source change never painted. A fresh toggle forces the
            // load; it runs deferred (see below) once the box is rendering again.
            function reapplyArt() {
                source = "";
                source = Qt.binding(function () { return dec.artSource; });
            }
            cache: true
            fillMode: Image.Stretch
            readonly property real fw: av.width - 2
            readonly property real fh: av.height - 2
            readonly property real fa: fh > 0 ? fw / fh : 1
            readonly property real ia: implicitHeight > 0 ? implicitWidth / implicitHeight : fa
            // cover the frame at the image's own aspect, then apply zoom
            width: (ia > fa ? fh * ia : fw) * dec.zoom
            height: (ia > fa ? fh : fw / ia) * dec.zoom
            x: 1 + (fw - width) * dec.posX
            y: 1 + (fh - height) * dec.posY
            layer.enabled: dec.isCustom && !dec.srcIsGif
            layer.effect: MultiEffect { saturation: -1.0 }
        }
        // While the editor is open the box is occluded by the modal, so a source
        // change made in there never paints. When editing ends, re-apply the art
        // deferred (Qt.callLater), after the popup is torn down and the box renders
        // again, so the new pick shows at once instead of only after a restart.
        Connections {
            target: dec
            function onEditingChanged() {
                if (!dec.editing && dec.hasArt)
                    Qt.callLater(im.reapplyArt);
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius
        color: "transparent"
        border.width: Tokens.border
        border.color: dec.editing ? Tokens.lineStrong : Tokens.line
        clip: true

        // ── the art panel ──
        Item {
            id: art
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: Tokens.s3 }
            width: Math.round((parent.width - Tokens.s3 * 2) * 0.42)

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: Tokens.border
                border.color: dec.editing ? Tokens.bone : Tokens.line
                clip: true
                ArtView { anchors.fill: parent }
            }
            Ticks { color: Tokens.lineStrong; arm: 8 }

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: ctxMenu.popup()
            }
            component MItem: C.MenuItem {
                id: mi
                implicitHeight: 28
                contentItem: Text {
                    text: mi.text
                    color: mi.enabled ? (mi.highlighted ? Tokens.ink : Tokens.inkDim) : Tokens.inkFaint
                    font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                    verticalAlignment: Text.AlignVCenter; leftPadding: Tokens.s2
                }
                background: Rectangle {
                    color: mi.down ? Tokens.tint16 : (mi.highlighted ? Tokens.tint10 : "transparent"); radius: Tokens.radius
                }
            }
            C.Menu {
                id: ctxMenu
                implicitWidth: 178
                padding: Tokens.s1
                background: Rectangle {
                    color: Tokens.paperLift
                    border.width: Tokens.border; border.color: Tokens.lineStrong
                    radius: Tokens.radius
                }
                MItem { text: I18n.tr("Adjust (drag, zoom, pick)"); onTriggered: dec.editing = true }
                MItem {
                    text: I18n.tr("Next image"); enabled: dec.galleryArt.length > 1
                    onTriggered: { dec.src = ""; dec.shot = (dec.shot + 1) % dec.galleryArt.length; dec.posX = 0.5; dec.posY = 0.5; dec.zoom = 1; dec.persistNow(); }
                }
                MItem {
                    text: I18n.tr("Shuffle"); enabled: dec.galleryArt.length > 1
                    onTriggered: { dec.src = ""; dec.shot = Math.floor(Math.random() * dec.galleryArt.length); dec.posX = 0.5; dec.posY = 0.5; dec.zoom = 1; dec.persistNow(); }
                }
                C.MenuSeparator { }
                MItem {
                    text: I18n.tr("Reset framing")
                    enabled: dec.zoom !== 1 || dec.posX !== 0.5 || dec.posY !== 0.5
                    onTriggered: { dec.zoom = 1; dec.posX = 0.5; dec.posY = 0.5; dec.persistNow(); }
                }
            }
        }

        // ── the typography column, on black ──
        Item {
            id: txt
            anchors { left: art.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: Tokens.s4 }

            Column {
                id: tateCol
                visible: dec.tate !== "" && dec.wide
                anchors { right: parent.right; top: parent.top }
                spacing: 1
                Repeater {
                    model: dec.tate.length
                    Text {
                        required property int index
                        text: dec.tate.charAt(index)
                        color: Tokens.inkFaint
                        font.family: Tokens.jp; font.pixelSize: 11
                    }
                }
            }

            Text {
                id: reg
                anchors { left: parent.left; top: parent.top }
                text: "\u002f\u002f " + dec.code
                color: Tokens.inkFaint
                font.family: Tokens.mono; font.pixelSize: 9; font.letterSpacing: 1.2
            }

            Text {
                anchors {
                    left: parent.left; top: reg.bottom; topMargin: Tokens.s2
                    bottom: readoutRow.visible ? readoutRow.top : titleBlock.top; bottomMargin: Tokens.s2
                    right: tateCol.visible ? tateCol.left : parent.right
                    rightMargin: tateCol.visible ? Tokens.s3 : 0
                }
                text: dec.caption
                color: Tokens.inkMuted
                verticalAlignment: Text.AlignTop
                font.family: Tokens.ui; font.pixelSize: 10; wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }

            // a horizontal instrument readout, filling the band beside the art
            Row {
                id: readoutRow
                visible: dec.readout.length > 0 && dec.wide
                anchors {
                    left: parent.left; verticalCenter: parent.verticalCenter
                    right: tateCol.visible ? tateCol.left : parent.right
                    rightMargin: tateCol.visible ? Tokens.s3 : 0
                }
                spacing: Tokens.s6
                Repeater {
                    model: dec.readout
                    Column {
                        id: cell
                        required property string modelData
                        readonly property var kv: cell.modelData.split("|")
                        spacing: 3
                        Text {
                            text: cell.kv[0]
                            color: Tokens.inkDim
                            font.family: Tokens.mono; font.pixelSize: 9; font.letterSpacing: 1.4
                        }
                        Text {
                            text: cell.kv.length > 1 ? cell.kv[1] : ""
                            color: Tokens.ink
                            font.family: Tokens.ui; font.pixelSize: 14; font.weight: Font.Medium
                        }
                    }
                }
            }

            Column {
                id: titleBlock
                anchors { left: parent.left; bottom: parent.bottom }
                spacing: 0
                Text {
                    text: dec.title
                    color: Tokens.ink
                    font.family: Tokens.jp; font.pixelSize: dec.dense ? 24 : 30; font.weight: Font.Medium
                }
                Text {
                    visible: dec.sub !== ""
                    text: dec.sub
                    color: Tokens.inkMuted
                    font.family: Tokens.jp; font.pixelSize: 12; font.letterSpacing: 2
                }
            }

            Row {
                anchors { right: parent.right; bottom: parent.bottom }
                spacing: Tokens.s3
                Barcode {
                    visible: dec.roomy
                    anchors.verticalCenter: parent.verticalCenter
                    text: dec.code; unit: 0.9; barHeight: 16
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26; height: 26
                    color: "transparent"
                    border.width: Tokens.border; border.color: Tokens.line
                    Text {
                        anchors.centerIn: parent
                        text: dec.seal
                        color: Tokens.inkDim
                        font.family: Tokens.jp; font.pixelSize: 14
                    }
                }
            }
        }
    }

    // ── the editor: cover + focal-point framing, gallery underneath ──────────
    C.Popup {
        id: editor
        parent: C.Overlay.overlay
        anchors.centerIn: parent
        width: 580; height: 470
        modal: true
        focus: true
        closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutside
        padding: Tokens.s4

        property var snap: ({})
        property bool saved: false

        background: Rectangle {
            color: Tokens.paperLift
            border.width: Tokens.border; border.color: Tokens.lineStrong
            radius: Tokens.radius
        }

        onAboutToShow: {
            editor.snap = { shot: dec.shot, zoom: dec.zoom, posX: dec.posX, posY: dec.posY, src: dec.src };
            editor.saved = false;
        }
        onOpened: keyScope.forceActiveFocus()
        onClosed: {
            if (!editor.saved) {
                dec.shot = editor.snap.shot; dec.zoom = editor.snap.zoom;
                dec.posX = editor.snap.posX; dec.posY = editor.snap.posY; dec.src = editor.snap.src;
            }
            dec.editing = false;
        }
        function commit() { editor.saved = true; dec.persistNow(); editor.close(); }

        contentItem: FocusScope {
            id: keyScope
            focus: true
            Keys.onReturnPressed: editor.commit()
            Keys.onEnterPressed: editor.commit()
            Keys.onEscapePressed: editor.close()

            Column {
                anchors.fill: parent
                spacing: Tokens.s3

                Row {
                    width: parent.width
                    spacing: Tokens.s2
                    Text {
                        text: "//"; color: Tokens.inkFaint
                        font.family: Tokens.mono; font.pixelSize: Tokens.fMicro
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: I18n.tr("ADJUST DECORATION"); color: Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                        font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 1; height: 1 }
                }

                // the framing preview -- same shape as the real box (WYSIWYG)
                Rectangle {
                    id: previewFrame
                    width: Math.min(parent.width, 232 * dec.artAspect)
                    height: Math.min(232, parent.width / dec.artAspect)
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Tokens.paper
                    border.width: Tokens.border; border.color: Tokens.line
                    clip: true

                    ArtView { anchors.fill: parent }
                    Ticks { color: Tokens.lineStrong; arm: 9 }

                    DragHandler {
                        id: panDrag
                        target: null
                        property real sx: 0.5
                        property real sy: 0.5
                        onActiveChanged: if (panDrag.active) { panDrag.sx = dec.posX; panDrag.sy = dec.posY; }
                        onActiveTranslationChanged: {
                            dec.posX = Math.max(0, Math.min(1, panDrag.sx - panDrag.activeTranslation.x / previewFrame.width));
                            dec.posY = Math.max(0, Math.min(1, panDrag.sy - panDrag.activeTranslation.y / previewFrame.height));
                        }
                    }
                    // trackpad pinch-to-zoom (when the compositor forwards it)
                    PinchHandler {
                        id: pinch
                        target: null
                        property real z0: 1
                        onActiveChanged: if (pinch.active) pinch.z0 = dec.zoom
                        onActiveScaleChanged: dec.zoom = Math.max(0.2, Math.min(5, pinch.z0 * pinch.activeScale))
                    }
                    // mouse wheel and trackpad two-finger scroll both zoom: a mouse
                    // sends angleDelta, a trackpad sends pixelDelta -- read whichever.
                    WheelHandler {
                        onWheel: (ev) => {
                            var d = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.pixelDelta.y;
                            if (d !== 0)
                                dec.zoom = Math.max(0.2, Math.min(5, dec.zoom * Math.exp(d * 0.0012)));
                        }
                    }
                    HoverHandler { cursorShape: Qt.OpenHandCursor }

                    Rectangle {
                        anchors { left: parent.left; top: parent.top; margins: Tokens.s2 }
                        width: h.implicitWidth + Tokens.s2 * 2; height: h.implicitHeight + Tokens.s1 * 2
                        color: Qt.rgba(0, 0, 0, 0.66); radius: Tokens.radius
                        Text {
                            id: h
                            anchors.centerIn: parent
                            text: I18n.tr("drag to move \u00b7 scroll / pinch to zoom")
                            color: Tokens.inkDim; font.family: Tokens.mono; font.pixelSize: 9; font.letterSpacing: 1
                        }
                    }
                }

                // the gallery: the baked set, then a custom-file tile
                Text {
                    text: I18n.tr("GALLERY"); color: Tokens.inkMuted
                    font.family: Tokens.ui; font.pixelSize: 9
                    font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
                }
                Flickable {
                    width: parent.width; height: 58
                    contentWidth: gRow.width; contentHeight: height
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    C.ScrollBar.horizontal: C.ScrollBar { policy: C.ScrollBar.AsNeeded }
                    Row {
                        id: gRow
                        spacing: Tokens.s2
                        Repeater {
                            model: dec.galleryArt
                            Rectangle {
                                required property int index
                                required property var modelData
                                width: 54; height: 54
                                color: "transparent"
                                border.width: (!dec.isCustom && index === dec.idx) ? 2 : 1
                                border.color: (!dec.isCustom && index === dec.idx) ? Tokens.bone : Tokens.line
                                radius: Tokens.radius
                                Image {
                                    anchors.fill: parent; anchors.margins: 2
                                    source: Ryodecors.dir + modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { dec.src = ""; dec.shot = index; dec.posX = 0.5; dec.posY = 0.5; dec.zoom = 1; } }
                            }
                        }
                        // the current custom image, if any -- tap to replace it
                        Rectangle {
                            visible: dec.isCustom
                            width: 54; height: 54; radius: Tokens.radius
                            color: "transparent"
                            border.width: 2; border.color: Tokens.bone
                            Image {
                                anchors.fill: parent; anchors.margins: 2
                                source: dec.src
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                layer.enabled: !dec.srcIsGif
                                layer.effect: MultiEffect { saturation: -1.0 }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: fileDlg.open() }
                        }
                        // always-present tile to add or choose a custom file
                        Rectangle {
                            width: 54; height: 54; radius: Tokens.radius
                            color: addTap.pressed ? Tokens.tint16 : (addHov.hovered ? Tokens.tint10 : "transparent")
                            border.width: Tokens.border; border.color: Tokens.line
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                            Text {
                                anchors.centerIn: parent
                                text: "\uff0b"; color: Tokens.inkDim
                                font.family: Tokens.ui; font.pixelSize: 22
                            }
                            HoverHandler { id: addHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: addTap; onTapped: fileDlg.open() }
                        }
                    }
                }

                // footer: the save/cancel contract, zoom control, reset
                Item {
                    width: parent.width; height: 28
                    // zoom control + reset, left
                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        spacing: Tokens.s2
                        IconBtn { glyph: "\u2212"; armed: dec.zoom > 0.2; onAct: dec.zoom = Math.max(0.2, dec.zoom / 1.15) }
                        Text {
                            text: Math.round(dec.zoom * 100) + "%"
                            color: Tokens.inkDim; font.family: Tokens.mono; font.pixelSize: 10
                            width: 40; height: 26
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        IconBtn { glyph: "+"; armed: dec.zoom < 5; onAct: dec.zoom = Math.min(5, dec.zoom * 1.15) }
                        IconBtn {
                            glyph: "\u21bb"; armed: dec.zoom !== 1 || dec.posX !== 0.5 || dec.posY !== 0.5
                            onAct: { dec.zoom = 1; dec.posX = 0.5; dec.posY = 0.5; }
                        }
                    }
                    // cancel / save, right -- click always works (no keyboard focus needed)
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: Tokens.s2
                        Rectangle {
                            width: cxl.implicitWidth + Tokens.s4; height: 26; radius: Tokens.radius
                            color: cxlTap.pressed ? Tokens.tint16 : (cxlHov.hovered ? Tokens.tint10 : "transparent")
                            border.width: Tokens.border; border.color: Tokens.line
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                            Text { id: cxl; anchors.centerIn: parent; text: I18n.tr("CANCEL"); color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: 10; font.letterSpacing: 1 }
                            HoverHandler { id: cxlHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: cxlTap; onTapped: editor.close() }
                        }
                        Rectangle {
                            width: svl.implicitWidth + Tokens.s4; height: 26; radius: Tokens.radius
                            color: svlHov.hovered ? Qt.lighter(Tokens.bone, 1.05) : Tokens.bone
                            Text { id: svl; anchors.centerIn: parent; text: I18n.tr("SAVE"); color: Tokens.inkOnBone; font.family: Tokens.ui; font.pixelSize: 10; font.weight: Font.Medium; font.letterSpacing: 1 }
                            HoverHandler { id: svlHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: editor.commit() }
                        }
                    }
                }
            }

            // custom image/gif picker: the shared paper-and-ink overlay, inside
            // the editor modal so it covers it (the editor sits on the Overlay).
            PickFile {
                id: fileDlg
                title: I18n.tr("Choose an image or gif")
                onPicked: (p) => { dec.src = "" + p; dec.posX = 0.5; dec.posY = 0.5; dec.zoom = 1; keyScope.forceActiveFocus(); fileDlg.active = false; }
                onCanceled: fileDlg.active = false
            }
        }
    }
}
