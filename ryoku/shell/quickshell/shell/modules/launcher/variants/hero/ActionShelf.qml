import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons as Ui
import "../../shared/Singletons"
import "../../shared/lib/results.js" as Results

Flickable {
    id: root

    property real s: 1
    property bool open: false
    property bool animationsEnabled: true
    property bool snapping: false
    property var actions: []
    property var packedLayout: []
    property string focusedActionId: ""

    signal focusRequested(string actionId)
    signal executeRequested(string actionId)

    readonly property var geometry: Results.shelfGeometry(actions.length, s)
    readonly property real targetHeight: open ? geometry.viewportHeight : 0
    readonly property int firstVisibleRow: packedLayout.length === 0 ? 0
        : Math.max(0, Math.floor((contentY + 0.5) / (38 * s)))
    readonly property int lastVisibleRow: packedLayout.length === 0 ? -1
        : Math.min(packedLayout.length - 1,
            Math.max(firstVisibleRow, Math.ceil((contentY + height) / (38 * s)) - 1))
    readonly property int visibleStart: actionOffset(firstVisibleRow) + 1
    readonly property int visibleEnd: lastVisibleRow < firstVisibleRow ? 0
        : actionOffset(lastVisibleRow) + packedLayout[lastVisibleRow].actions.length
    readonly property string visibleRange: actions.length > 6
        ? visibleStart + "-" + visibleEnd + " / " + actions.length : ""

    implicitHeight: targetHeight
    height: targetHeight
    opacity: open ? 1 : 0
    clip: true
    contentWidth: width
    contentHeight: actionColumn.height
    boundsBehavior: Flickable.StopAtBounds
    interactive: open && shelfHover.hovered && contentHeight > height
    flickDeceleration: 2600

    Behavior on height {
        enabled: root.animationsEnabled && !root.snapping
        NumberAnimation {
            id: heightMotion
            duration: Motion.shelf
            easing.type: Easing.OutCubic
        }
    }
    Behavior on opacity {
        enabled: root.animationsEnabled && !root.snapping
        NumberAnimation {
            id: opacityMotion
            duration: Motion.shelf
            easing.type: Easing.OutCubic
        }
    }

    function snapAnimations() {
        snapping = true;
        height = Qt.binding(function () { return root.targetHeight; });
        opacity = Qt.binding(function () { return root.open ? 1 : 0; });
        snapping = false;
    }

    onAnimationsEnabledChanged: {
        if (!animationsEnabled)
            snapAnimations();
    }

    function actionOffset(rowIndex) {
        var offset = 0;
        for (var index = 0; index < rowIndex && index < packedLayout.length; index++)
            offset += packedLayout[index].actions.length;
        return offset;
    }

    function actionFor(actionId) {
        for (var index = 0; index < actions.length; index++) {
            if (String(actions[index].id) === String(actionId))
                return actions[index];
        }
        return null;
    }

    function rowForAction(actionId) {
        for (var row = 0; row < packedLayout.length; row++) {
            for (var column = 0; column < packedLayout[row].actions.length; column++) {
                if (String(packedLayout[row].actions[column].id) === String(actionId))
                    return row;
            }
        }
        return -1;
    }

    function ensureFocusedVisible() {
        var row = rowForAction(focusedActionId);
        if (row < 0 || height <= 0)
            return;
        var top = row * 38 * s;
        var bottom = top + 38 * s;
        if (top < contentY)
            contentY = top;
        else if (bottom > contentY + height)
            contentY = Math.min(Math.max(0, contentHeight - height), bottom - height);
    }

    onFocusedActionIdChanged: Qt.callLater(ensureFocusedVisible)
    onHeightChanged: Qt.callLater(ensureFocusedVisible)
    onOpenChanged: if (!open) contentY = 0

    Column {
        id: actionColumn
        width: root.width
        height: childrenRect.height

        Repeater {
            model: root.packedLayout.length

            delegate: Item {
                id: actionRow

                required property int index
                readonly property var packedRow: root.packedLayout[index]

                width: actionColumn.width
                height: 38 * root.s

                Repeater {
                    model: actionRow.packedRow.actions.length

                    delegate: Rectangle {
                        id: actionCell

                        required property int index
                        readonly property var packedAction: actionRow.packedRow.actions[index]
                        readonly property var currentAction: root.actionFor(packedAction.id)
                        readonly property bool focused: String(packedAction.id)
                            === root.focusedActionId
                        readonly property int actionCount: actionRow.packedRow.actions.length
                        readonly property real gap: Math.max(1, root.s)
                        readonly property bool atRightEdge: actionRow.packedRow.fullWidth
                            || index === actionCount - 1
                        readonly property real rangeReserve: root.actions.length > 6
                            && atRightEdge ? 52 * root.s : 0

                        objectName: "action-" + String(packedAction.id)
                        x: index * (width + gap)
                        width: actionRow.packedRow.fullWidth
                            ? actionRow.width
                            : (actionRow.width - gap * (actionCount - 1)) / actionCount
                        height: actionRow.height
                        color: focused ? Theme.drawerRaised
                            : (actionPointer.containsMouse ? Theme.sheen : "transparent")
                        border.width: 1
                        border.color: focused ? Theme.frame : Theme.hair

                        Accessible.role: Accessible.Button
                        Accessible.name: currentAction
                            ? String(currentAction.name || "") : ""
                        Accessible.description: Ui.I18n.tr("Secondary result action")
                        Accessible.ignored: !root.open || currentAction === null
                        Accessible.focusable: false
                        Accessible.selectable: true
                        Accessible.selected: focused
                        Accessible.onPressAction: {
                            if (!root.open || !actionCell.currentAction)
                                return;
                            root.focusRequested(String(actionCell.packedAction.id));
                            root.executeRequested(String(actionCell.packedAction.id));
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.selection
                                easing.type: Easing.OutCubic
                            }
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 9 * root.s
                            anchors.rightMargin: 9 * root.s + actionCell.rangeReserve
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7 * root.s

                            Image {
                                id: actionIcon
                                visible: actionCell.currentAction
                                    && String(actionCell.currentAction.icon || "").length > 0
                                width: visible ? 15 * root.s : 0
                                height: 15 * root.s
                                sourceSize.width: Math.round(30 * root.s)
                                sourceSize.height: Math.round(30 * root.s)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                source: visible ? actionCell.currentAction.icon : ""
                            }

                            Text {
                                width: Math.max(0, parent.width
                                    - (actionIcon.visible ? actionIcon.width + parent.spacing : 0))
                                text: actionCell.currentAction
                                    ? String(actionCell.currentAction.name || "").toUpperCase()
                                    : ""
                                color: actionCell.focused ? Theme.bright : Theme.subtle
                                font.family: Theme.mono
                                font.pixelSize: 9 * root.s
                                font.weight: actionCell.focused ? Font.DemiBold : Font.Medium
                                font.letterSpacing: 0.7 * root.s
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: actionPointer
                            objectName: "action-pointer-" + String(actionCell.packedAction.id)
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.open && actionCell.currentAction !== null
                            onClicked: {
                                root.focusRequested(String(actionCell.packedAction.id));
                                root.executeRequested(String(actionCell.packedAction.id));
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 52 * root.s
        height: 16 * root.s
        z: 10
        visible: root.visibleRange.length > 0
        color: Theme.drawer
        border.width: 1
        border.color: Theme.hair

        Text {
            anchors.centerIn: parent
            text: root.visibleRange
            color: Theme.bright
            font.family: Theme.mono
            font.pixelSize: 7.5 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }

    HoverHandler {
        id: shelfHover
        enabled: root.open
    }
}
