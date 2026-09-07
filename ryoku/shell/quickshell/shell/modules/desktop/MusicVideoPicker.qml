pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import "Singletons"
import "music"
import Ryoku.Ui.Singletons

// The desktop's own video/GIF chooser, in the shell's ink rather than the
// system's file dialog: a paper card over a dim scrim, a folder list on the
// left and a live 9:16 preview of the highlighted clip on the right (the same
// backdrop the widget plays), then Use to set it. Opened from a widget's
// right-click menu; emits the chosen file URL.
Item {
    id: picker

    anchors.fill: parent
    visible: picker.open || fade.running

    property bool open: false
    signal chose(string url)

    readonly property string home: Quickshell.env("HOME") || ""
    property url folder: "file://" + picker.home
    property string sel: ""          // absolute path of the highlighted file

    onOpenChanged: if (picker.open) { picker.folder = "file://" + picker.home; picker.sel = ""; }

    function goUp() {
        const f = "" + picker.folder;
        if (f === "file:///")
            return;
        picker.folder = f.replace(/\/[^/]+\/?$/, "") || "file:///";
    }
    function baseName(p) {
        const s = ("" + p).replace(/\/+$/, "");
        return s.slice(s.lastIndexOf("/") + 1);
    }

    opacity: picker.open ? 1 : 0
    Behavior on opacity { NumberAnimation { id: fade; duration: Theme.medium; easing.type: Theme.ease } }

    // scrim: dismiss on click-away.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: picker.open = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 660
        height: 420
        radius: Theme.radiusWidget
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        // eat clicks so the scrim doesn't close it.
        MouseArea { anchors.fill: parent }

        scale: picker.open ? 1 : 0.96
        Behavior on scale { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }

        // ── header ──
        Text {
            id: title
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 16
            text: I18n.tr("Choose video or GIF")
            color: Theme.ink
            font.family: Theme.display
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: title.verticalCenter
            anchors.rightMargin: 16
            text: "\u2715"
            color: closeHov.hovered ? Theme.ink : Theme.inkDim
            font.pixelSize: 15
            HoverHandler { id: closeHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: picker.open = false }
        }

        // ── path bar ──
        Rectangle {
            id: pathBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: title.bottom
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 12
            height: 26
            radius: Theme.radiusWidget
            color: Theme.tile

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 9
                text: "\u2191"
                color: upHov.hovered ? Theme.ink : Theme.inkDim
                font.pixelSize: 13
                HoverHandler { id: upHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: picker.goUp() }
            }
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 30
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: ("" + picker.folder).replace("file://" + picker.home, "~").replace("file://", "")
                elide: Text.ElideLeft
                color: Theme.inkDim
                font.family: Theme.mono
                font.pixelSize: 10
            }
        }

        // ── file list ──
        ListView {
            id: list
            anchors.left: parent.left
            anchors.top: pathBar.bottom
            anchors.bottom: useBtn.top
            width: 320
            anchors.leftMargin: 16
            anchors.topMargin: 10
            anchors.bottomMargin: 12
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            model: FolderListModel {
                folder: picker.folder
                showDirs: true
                showDirsFirst: true
                showHidden: false
                caseSensitive: false
                sortField: FolderListModel.Name
                nameFilters: ["*.mp4", "*.webm", "*.mkv", "*.mov", "*.m4v", "*.avi", "*.gif"]
            }

            delegate: Rectangle {
                id: row
                required property string fileName
                required property string filePath
                required property bool fileIsDir
                width: list.width
                height: 30
                radius: Theme.radiusWidget
                readonly property bool active: !row.fileIsDir && picker.sel === row.filePath
                color: row.active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                    : rowHov.hovered ? Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.07)
                    : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.quick } }

                HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: row.fileIsDir ? (picker.folder = "file://" + row.filePath) : (picker.sel = row.filePath)
                    onDoubleTapped: if (!row.fileIsDir) { picker.chose("file://" + row.filePath); picker.open = false; }
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    text: (row.fileIsDir ? "\u203A  " : "") + row.fileName
                    elide: Text.ElideMiddle
                    color: row.fileIsDir ? Theme.ink : (row.active ? Theme.ink : Theme.inkDim)
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
        }

        // ── preview (the real backdrop) ──
        Rectangle {
            id: previewFrame
            anchors.left: list.right
            anchors.right: parent.right
            anchors.top: pathBar.bottom
            anchors.bottom: useBtn.top
            anchors.leftMargin: 14
            anchors.rightMargin: 16
            anchors.topMargin: 10
            anchors.bottomMargin: 12
            radius: Theme.radiusWidget
            color: Theme.tile
            clip: true

            MusicBackdrop {
                anchors.fill: parent
                radius: Theme.radiusWidget
                source: picker.sel
                active: picker.visible && picker.sel.length > 0
            }
            Text {
                anchors.centerIn: parent
                visible: picker.sel.length === 0
                text: I18n.tr("Pick a file to preview")
                color: Theme.inkDim
                font.family: Theme.font
                font.pixelSize: 11
            }
        }

        // ── use ──
        Rectangle {
            id: useBtn
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            width: 120
            height: 32
            radius: Theme.radiusWidget
            readonly property bool ready: picker.sel.length > 0
            color: useBtn.ready ? Theme.accent : Theme.tile
            opacity: useBtn.ready ? 1 : 0.5

            Text {
                anchors.centerIn: parent
                text: I18n.tr("Use this")
                color: useBtn.ready ? Theme.surface : Theme.inkDim
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            HoverHandler { enabled: useBtn.ready; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                enabled: useBtn.ready
                onTapped: { picker.chose("file://" + picker.sel); picker.open = false; }
            }
        }
    }
}
