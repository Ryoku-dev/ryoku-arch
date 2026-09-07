pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// In-shell multi-file picker for the Compress / Install tools. A compact
// paper-and-ink file browser that lives inside the sidebar: navigate folders,
// tap files to select several, then confirm. Nothing steals focus or closes
// the sidebar the way an external file dialog would.
Item {
    id: root

    property real s: 1
    property string mode: "compress"            // compress | install
    signal cancelled()
    signal confirmed(var paths)

    readonly property string home: Quickshell.env("HOME") || ""
    property url folder: "file://" + root.home
    property var selected: ({})                 // absolute path -> true
    readonly property int selCount: Object.keys(root.selected).length
    readonly property color ink: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
    readonly property color dim: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)

    readonly property var videoImage: ["*.mp4", "*.mkv", "*.webm", "*.mov", "*.avi", "*.m4v", "*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp", "*.gif", "*.tiff"]
    readonly property var appFiles: ["*.AppImage", "*.pkg.tar.zst", "*.pkg.tar.xz", "*.deb", "*.rpm", "*.flatpak", "*.tar.gz", "*.tgz", "*.tar.xz", "*.tar.bz2", "*.tar.zst", "*.tar"]

    implicitHeight: 520 * root.s

    onVisibleChanged: if (root.visible) { root.selected = ({}); root.folder = "file://" + root.home; }

    function toggle(path) {
        const n = Object.assign({}, root.selected);
        if (n[path]) delete n[path]; else n[path] = true;
        root.selected = n;
    }
    function goUp() {
        const f = "" + root.folder;
        if (f === "file:///" || f === "file://" + "/") return;
        root.folder = f.replace(/\/[^/]+\/?$/, "") || "file:///";
    }
    function chosenPaths() {
        return Object.keys(root.selected);
    }
    function fileGlyph(name) {
        const e = ("" + name).toLowerCase().split(".").pop();
        if (/^(png|jpe?g|webp|gif|bmp|tiff?|avif)$/.test(e)) return "image";
        if (/^(mp4|mkv|webm|mov|avi|m4v)$/.test(e)) return "movie";
        return "deployed_code";
    }

    FolderListModel {
        id: fm
        folder: root.folder
        showDirs: true
        showHidden: false
        caseSensitive: false
        nameFilters: root.mode === "install" ? root.appFiles : root.videoImage
        sortField: FolderListModel.Name
    }

    // ── header: back + title ──
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14 * root.s
        height: 20 * root.s

        MaterialIcon {
            id: backBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 16 * root.s
            text: "arrow_back"
            color: backHov.containsMouse ? root.ink : root.dim
            MouseArea {
                id: backHov
                anchors.fill: parent
                anchors.margins: -8 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cancelled()
            }
        }
        Text {
            anchors.left: backBtn.right
            anchors.leftMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "install" ? I18n.tr("SELECT APPS TO INSTALL") : I18n.tr("SELECT VIDEOS OR IMAGES")
            color: root.dim
            font.family: Theme.fontPrimary
            font.pixelSize: 8 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 1.5
        }
    }

    // ── path bar: up + current folder ──
    Rectangle {
        id: pathBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: 14 * root.s
        anchors.rightMargin: 14 * root.s
        anchors.topMargin: 10 * root.s
        height: 26 * root.s
        radius: Theme.radiusWidget
        color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05)

        MaterialIcon {
            id: upBtn
            anchors.left: parent.left
            anchors.leftMargin: 9 * root.s
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 14 * root.s
            text: "arrow_upward"
            color: upHov.containsMouse ? root.ink : root.dim
            MouseArea {
                id: upHov
                anchors.fill: parent
                anchors.margins: -6 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goUp()
            }
        }
        Text {
            anchors.left: upBtn.right
            anchors.right: parent.right
            anchors.leftMargin: 9 * root.s
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: ("" + root.folder).replace("file://" + root.home, "~").replace("file://", "")
            elide: Text.ElideLeft
            color: root.ink
            font.family: Theme.mono
            font.pixelSize: 9 * root.s
        }
    }

    // ── file list ──
    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: pathBar.bottom
        anchors.bottom: footer.top
        anchors.leftMargin: 14 * root.s
        anchors.rightMargin: 14 * root.s
        anchors.topMargin: 8 * root.s
        anchors.bottomMargin: 8 * root.s
        clip: true
        model: fm
        spacing: 2 * root.s
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: fileRow
            required property string fileName
            required property string filePath
            required property bool fileIsDir
            readonly property bool sel: !fileRow.fileIsDir && root.selected[fileRow.filePath] === true
            width: ListView.view.width
            height: 28 * root.s
            radius: Theme.radiusWidget
            color: fileRow.sel ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)
                : rowHov.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
                : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            MouseArea {
                id: rowHov
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: fileRow.fileIsDir ? (root.folder = "file://" + fileRow.filePath) : root.toggle(fileRow.filePath)
            }

            Row {
                anchors.left: parent.left
                anchors.right: check.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10 * root.s
                spacing: 9 * root.s

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 14 * root.s
                    text: fileRow.fileIsDir ? "folder" : root.fileGlyph(fileRow.fileName)
                    color: fileRow.fileIsDir ? root.ink : root.dim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 23 * root.s - parent.spacing
                    text: fileRow.fileName
                    elide: Text.ElideMiddle
                    color: root.ink
                    font.family: Theme.fontPrimary
                    font.pixelSize: 10 * root.s
                }
            }

            MaterialIcon {
                id: check
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 10 * root.s
                font.pixelSize: 14 * root.s
                visible: fileRow.sel
                text: "check_circle"
                fill: 1
                color: Theme.primary
            }

            MaterialIcon {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 10 * root.s
                font.pixelSize: 14 * root.s
                visible: fileRow.fileIsDir
                text: "chevron_right"
                color: root.dim
            }
        }
    }

    // ── footer: confirm ──
    Rectangle {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14 * root.s
        anchors.rightMargin: 14 * root.s
        anchors.bottomMargin: 14 * root.s
        height: 30 * root.s
        radius: Theme.radiusWidget
        readonly property bool ready: root.selCount > 0
        color: footer.ready ? Theme.primary : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.04)
        border.width: footer.ready ? 0 : Theme.borderWidth
        border.color: Theme.outline
        opacity: footer.ready ? 1 : 0.5
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        SumiEdge { visible: footer.ready }

        Row {
            anchors.centerIn: parent
            spacing: 8 * root.s
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 14 * root.s
                text: root.mode === "install" ? "install_desktop" : "compress"
                color: footer.ready ? Theme.inkOn(Theme.primary, Theme.onPrimary) : root.ink
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.selCount > 0
                    ? (root.mode === "install" ? I18n.tr("Install %1").arg(root.selCount) : I18n.tr("Compress %1").arg(root.selCount))
                    : (root.mode === "install" ? I18n.tr("Select apps to install") : I18n.tr("Select files to compress"))
                color: footer.ready ? Theme.inkOn(Theme.primary, Theme.onPrimary) : root.dim
                font.family: Theme.fontPrimary
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
            }
        }

        scale: confirmHov.pressed && footer.ready ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Motion.fast } }
        MouseArea {
            id: confirmHov
            anchors.fill: parent
            enabled: footer.ready
            cursorShape: Qt.PointingHandCursor
            onClicked: root.confirmed(root.chosenPaths())
        }
    }
}
