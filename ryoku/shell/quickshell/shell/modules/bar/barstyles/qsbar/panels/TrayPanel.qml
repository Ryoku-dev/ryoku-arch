import Quickshell
import "../modules"
import shell.services
import Quickshell.Wayland
import QtQuick
import Ryoku.Ui.Singletons

PanelWindow {
    id: trayPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-tray"
    // no mask → whole overlay is interactive (modal): click-outside + ESC work

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6
    readonly property int popupW: 328
    readonly property int maxListH: 320

    property real reveal: root.trayVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.trayVisible ? 160 : 120
            easing.type: root.trayVisible ? Easing.OutCubic : Easing.InCubic
        }
    }

    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.trayVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // auto-close when there are no hidden (unpinned) items left to show
    readonly property int hiddenCount: {
        var n = 0, its = Tray.items
        for (var i = 0; i < its.length; i++)
            if (root.trayPinned.indexOf(its[i].service) < 0) n++
        return n
    }
    readonly property int attentionCount: {
        var n = 0, its = Tray.items
        for (var i = 0; i < its.length; i++)
            if (root.trayPinned.indexOf(its[i].service) < 0 && its[i].status === "NeedsAttention") n++
        return n
    }
    onHiddenCountChanged: if (root.trayVisible && hiddenCount === 0) root.trayVisible = false

    // click-outside-to-close: full-overlay dismiss area behind the card
    MouseArea { anchors.fill: parent; onClicked: root.trayVisible = false }

    Rectangle {
        id: card
        width: popupW
        height: col.implicitHeight + 24
        radius: reveal > 0.001 ? root.panelRadius : 0
        color: "transparent"
        border.color: root.panelBorder
        border.width: 0
        PillShadow { theme: root }
        ConnectedPanelSurface {
            root: trayPanel.root
            ownerActive: trayPanel.root.trayVisible
            targetX: trayPanel.root.trayCaretBarX
            reveal: trayPanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.trayBarX, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - trayPanel.reveal)
            : (barBottom + gap) - 2 * (1 - trayPanel.reveal)
        opacity: trayPanel.reveal
        focus: root.trayVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.trayVisible = false
                event.accepted = true
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Match the updater's restrained title/count/close hierarchy.
            Item {
                width: parent.width
                height: 24

                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Tray Apps")
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }

                UiText {
                    anchors.right: closeX.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: (trayPanel.hiddenCount === 1 ? I18n.tr("%1 APP").arg(trayPanel.hiddenCount) : I18n.tr("%1 APPS").arg(trayPanel.hiddenCount))
                        + (trayPanel.attentionCount > 0 ? "  ·  " + I18n.tr("%1 ATTENTION").arg(trayPanel.attentionCount) : "")
                    color: trayPanel.attentionCount > 0 ? root.seal : root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 10
                }

                UiText {
                    id: closeX
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2715"
                    color: closeMa.containsMouse ? root.seal : root.sumi
                    font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.trayVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Item {
                width: parent.width
                height: Math.min(trayRows.implicitHeight, trayPanel.maxListH)

                Flickable {
                    id: appsFlick
                    anchors.fill: parent
                    contentHeight: trayRows.implicitHeight
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: trayRows
                        width: appsFlick.width
                        spacing: 6

                        Repeater {
                            model: Tray.items

                            delegate: Item {
                                id: appRow
                                required property var modelData
                                required property int index

                                readonly property string appName: root.trayDisplayName(modelData)
                                readonly property string appDescription: root.trayDescription(modelData, appName)
                                readonly property bool needsAttention: modelData.status === "NeedsAttention"
                                readonly property string statusDescription: needsAttention
                                    ? "\u26a0 " + (appDescription !== "" ? appDescription : I18n.tr("Needs attention"))
                                    : appDescription
                                readonly property int cellWidth: 96
                                readonly property string iconSource: modelData.iconPath ? "file://" + modelData.iconPath : (modelData.iconName ? Icons.path(modelData.iconName, true) : "")
                                readonly property bool hasMenu: modelData.menu != null

                                width: trayRows.width
                                height: visible ? 28 : 0
                                visible: root.trayPinned.indexOf(modelData.service) < 0

                                function openAppMenu() {
                                    if (!appRow.hasMenu) return
                                    var gp = menuButton.mapToItem(null, 0, 0)
                                    root.openTrayMenu(modelData.service,
                                                      gp.x + menuButton.width / 2 - 110,
                                                      appName, appRow.iconSource)
                                }

                                function activateApp() {
                                    var svc = modelData.service
                                    root.trayVisible = false
                                    // Release the layer-shell keyboard focus before asking
                                    // the application to surface/focus its primary window.
                                    Qt.callLater(function() {
                                        if (svc) Tray.activate(svc)
                                    })
                                }

                                Rectangle {
                                    id: appButton
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: appRow.cellWidth
                                    height: 28
                                    radius: root.panelButtonRadius
                                    color: activateMa.containsMouse ? root.fillHover : root.fillIdle
                                    border.color: activateMa.containsMouse ? root.seal : root.sep
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Image {
                                        id: appIcon
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: appRow.iconSource
                                        sourceSize.width: 16
                                        sourceSize.height: 16
                                        width: 16
                                        height: 16
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                    }

                                    UiText {
                                        anchors.left: appIcon.right
                                        anchors.leftMargin: 6
                                        anchors.right: parent.right
                                        anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (appRow.needsAttention ? "\u26a0 " : "") + appRow.appName
                                        color: appRow.needsAttention ? root.seal
                                            : (activateMa.containsMouse ? root.seal : root.ink)
                                        font.family: root.mono
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }

                                    TooltipMixin {
                                        id: appTip
                                        root: trayPanel.root
                                        owner: appButton
                                        text: appRow.statusDescription !== ""
                                            ? appRow.appName + "\n" + appRow.statusDescription
                                            : appRow.appName
                                    }

                                    MouseArea {
                                        id: activateMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: appTip.show()
                                        onExited: appTip.hide()
                                        onClicked: {
                                            appTip.hide()
                                            if (appRow.modelData.itemIsMenu && appRow.hasMenu)
                                                appRow.openAppMenu()
                                            else
                                                appRow.activateApp()
                                        }
                                    }
                                }

                                Rectangle {
                                    id: pinButton
                                    anchors.left: appButton.right
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: appRow.cellWidth
                                    height: 28
                                    radius: root.panelButtonRadius
                                    color: pinMa.containsMouse ? root.fillHover : root.fillIdle
                                    border.color: pinMa.containsMouse ? root.seal : root.sep
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    UiText {
                                        anchors.centerIn: parent
                                        text: I18n.tr("Pin")
                                        color: pinMa.containsMouse ? root.seal : root.ink
                                        font.family: root.mono
                                        font.pixelSize: 11
                                    }

                                    MouseArea {
                                        id: pinMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.trayToggleHide(appRow.modelData)
                                    }
                                }

                                Rectangle {
                                    id: menuButton
                                    anchors.left: pinButton.right
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: appRow.cellWidth
                                    height: 28
                                    radius: root.panelButtonRadius
                                    color: appRow.hasMenu
                                        ? (menuMa.containsMouse ? root.fillHover : root.fillIdle)
                                        : "transparent"
                                    border.color: appRow.hasMenu
                                        ? (menuMa.containsMouse ? root.seal : root.sep)
                                        : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
                                    border.width: 1
                                    opacity: appRow.hasMenu ? 1.0 : 0.42
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    UiText {
                                        anchors.centerIn: parent
                                        text: appRow.hasMenu ? I18n.tr("AppMenu") : I18n.tr("No Menu")
                                        color: menuMa.containsMouse && appRow.hasMenu ? root.seal : root.ink
                                        font.family: root.mono
                                        font.pixelSize: 11
                                    }

                                    MouseArea {
                                        id: menuMa
                                        anchors.fill: parent
                                        enabled: appRow.hasMenu
                                        hoverEnabled: enabled
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: appRow.openAppMenu()
                                    }
                                }

                            }
                        }
                    }
                }
            }
        }
    }
}
