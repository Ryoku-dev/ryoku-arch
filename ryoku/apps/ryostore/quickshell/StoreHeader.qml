import QtQuick
import Ryoku.Ui.Singletons

// The store's app bar, in two tiers. Tier 1 carries identity (the 力 seal and
// wordmark), a persistent search field with a magnifier, and the account
// actions (Library, Refresh). Tier 2 is the category navigation as bone-invert
// plates (the design system's Tabs idiom), so every section stays visible
// rather than clipping in one crammed row.
Item {
    id: header

    property string view: "discover"
    property string categoryID: ""
    property var categories: []
    property string query: ""
    property int libraryCount: 0
    property int updateCount: 0
    property bool offline: false
    property bool refreshing: false
    property bool searchActive: false
    property int resultCount: 0
    property bool updateAvailable: false

    signal routeRequested(string view, string categoryID)
    signal refreshRequested()
    signal queryEdited(string value)
    signal searchActivated()
    signal searchEscaped()

    readonly property int tier1Height: 60
    readonly property int tier2Height: 48
    implicitHeight: tier1Height + tier2Height

    readonly property string libraryLabel: updateCount > 0
            ? (updateCount === 1
                ? I18n.tr("LIBRARY %1 / %2 UPDATE").arg(libraryCount).arg(updateCount)
                : I18n.tr("LIBRARY %1 / %2 UPDATES").arg(libraryCount).arg(updateCount))
            : I18n.tr("LIBRARY %1").arg(libraryCount)

    function activateDiscover() { routeRequested("discover", ""); }
    function activateCategory(id) { routeRequested("discover", id); }
    function activateLibrary() { routeRequested("library", ""); }
    function focusSearch() { searchField.forceActiveFocus(); }

    // A right-aligned account action: mono label, hairline underline when current.
    component HeaderAction: Item {
        id: act
        required property string label
        property bool current: false
        property bool flagged: false
        signal triggered()
        implicitWidth: actLabel.implicitWidth + (act.flagged ? Tokens.s2 : 0)
        implicitHeight: actLabel.implicitHeight + Tokens.s3
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: act.label
        Accessible.onPressAction: act.triggered()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                act.triggered();
                event.accepted = true;
            }
        }
        Text {
            id: actLabel
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
            text: I18n.tr(act.label)
            color: act.current || act.activeFocus ? Tokens.ink : Tokens.inkDim
            font.family: Tokens.mono
            font.pixelSize: Tokens.fMicro
            font.weight: Font.Medium
            font.letterSpacing: Tokens.trackLabel
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: actLabel.bottom; topMargin: 3 }
            height: Tokens.border * 2
            color: Tokens.ink
            visible: act.current || act.activeFocus
        }
        // Attention dot: upstream (ryostore) has advanced past what the user
        // last pulled. Fixed alert red so it always reads as "something new".
        Rectangle {
            visible: act.flagged
            width: 5
            height: 5
            radius: 2.5
            color: Tokens.alert
            anchors { left: actLabel.right; leftMargin: Tokens.s1; top: actLabel.top }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: act.triggered() }
    }

    // A category plate: bone-invert when active with the // lead, matching Tabs.
    component NavPlate: Rectangle {
        id: plate
        property string label: ""
        property bool active: false
        signal chose()
        width: navContent.implicitWidth + Tokens.s4
        height: 30
        radius: Tokens.radius
        color: plate.active ? Tokens.bone : (ph.hovered ? Tokens.tint5 : "transparent")
        border.width: Tokens.border
        border.color: plate.active ? Tokens.bone : Tokens.line
        activeFocusOnTab: true
        Behavior on color { ColorAnimation { duration: Tokens.snap } }
        Accessible.role: Accessible.Button
        Accessible.name: plate.label
        Accessible.onPressAction: plate.chose()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                plate.chose();
                event.accepted = true;
            }
        }
        Row {
            id: navContent
            anchors.centerIn: parent
            spacing: Tokens.s2
            Text {
                visible: plate.active
                text: "//"
                color: Tokens.inkOnBoneDim
                font.family: Tokens.mono
                font.pixelSize: 10
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: I18n.tr(plate.label)
                color: plate.active ? Tokens.inkOnBone : (plate.activeFocus ? Tokens.ink : Tokens.inkDim)
                font.family: Tokens.ui
                font.pixelSize: 11
                font.weight: Font.Medium
                font.letterSpacing: Tokens.trackLabel
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: Tokens.snap } }
            }
        }
        HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: plate.chose() }
    }

    // ---- Tier 1: identity, search, account ----
    Item {
        id: tier1
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: header.tier1Height

        Row {
            anchors { left: parent.left; leftMargin: Tokens.s6; verticalCenter: parent.verticalCenter }
            spacing: Tokens.s3
            Text {
                text: "力"
                color: Tokens.ink
                font.family: Tokens.jp
                font.pixelSize: 22
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: I18n.tr("RYOSTORE")
                color: Tokens.ink
                font.family: Tokens.mono
                font.pixelSize: 15
                font.weight: Font.Medium
                font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle {
            id: searchBox
            objectName: "ryostore-header-search"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(460, header.width * 0.42)
            height: 34
            radius: Tokens.radius
            color: searchField.activeFocus ? Tokens.tint5 : "transparent"
            border.width: Tokens.border
            border.color: searchField.activeFocus ? Tokens.lineStrong : Tokens.line
            Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

            Item {
                id: mag
                width: 15; height: 15
                anchors { left: parent.left; leftMargin: Tokens.s3; verticalCenter: parent.verticalCenter }
                readonly property color glyph: searchField.activeFocus ? Tokens.ink : Tokens.inkDim
                Rectangle {
                    x: 0; y: 0; width: 10; height: 10; radius: 5
                    color: "transparent"; border.width: 1.5; border.color: mag.glyph
                }
                Rectangle {
                    x: 9; y: 10; width: 6; height: 1.5; radius: 1
                    color: mag.glyph; rotation: 45; transformOrigin: Item.TopLeft
                }
            }

            TextInput {
                id: searchField
                objectName: "ryostore-header-search-field"
                anchors {
                    left: mag.right; leftMargin: Tokens.s2
                    right: countLabel.left; rightMargin: Tokens.s2
                    verticalCenter: parent.verticalCenter
                }
                Component.onCompleted: text = header.query
                color: Tokens.ink
                selectionColor: Tokens.tint16
                selectedTextColor: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: Tokens.fRow
                clip: true
                activeFocusOnTab: true
                Accessible.role: Accessible.EditableText
                Accessible.name: header.offline ? I18n.tr("Search RyoStore (offline)") : I18n.tr("Search RyoStore")
                Accessible.description: I18n.tr("Type to filter the store")
                onTextEdited: header.queryEdited(text)
                onActiveFocusChanged: if (activeFocus) header.searchActivated()
                Keys.onEscapePressed: event => {
                    header.searchEscaped();
                    event.accepted = true;
                }
                Connections {
                    target: header
                    function onQueryChanged() {
                        if (searchField.text !== header.query)
                            searchField.text = header.query;
                    }
                }

                Text {
                    anchors.fill: parent
                    visible: searchField.text === ""
                    text: header.offline ? I18n.tr("Search the store (offline)") : I18n.tr("Search the store")
                    color: Tokens.inkMuted
                    font: searchField.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            Text {
                id: countLabel
                anchors { right: parent.right; rightMargin: Tokens.s3; verticalCenter: parent.verticalCenter }
                visible: header.searchActive && header.query !== ""
                text: header.resultCount === 1
                        ? I18n.tr("%1 RESULT").arg(header.resultCount)
                        : I18n.tr("%1 RESULTS").arg(header.resultCount)
                color: Tokens.inkDim
                font.family: Tokens.mono
                font.pixelSize: Tokens.fMicro
                font.letterSpacing: Tokens.trackLabel
            }

            HoverHandler { cursorShape: Qt.IBeamCursor }
            TapHandler { onTapped: searchField.forceActiveFocus() }
        }

        Row {
            anchors { right: parent.right; rightMargin: Tokens.s6; verticalCenter: parent.verticalCenter }
            spacing: Tokens.s5

            HeaderAction {
                objectName: "ryostore-header-library"
                label: header.libraryLabel
                current: header.view === "library"
                onTriggered: header.activateLibrary()
            }
            HeaderAction {
                objectName: "ryostore-header-refresh"
                label: header.refreshing ? I18n.tr("SYNCING") : I18n.tr("REFRESH")
                current: header.refreshing
                flagged: header.updateAvailable && !header.refreshing
                onTriggered: header.refreshRequested()
            }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: tier1.bottom }
        height: Tokens.border
        color: Tokens.line
    }

    // ---- Tier 2: category navigation ----
    Item {
        id: tier2
        anchors { left: parent.left; right: parent.right; top: tier1.bottom }
        height: header.tier2Height

        Flickable {
            id: navScroll
            objectName: "ryostore-header-categories"
            anchors { fill: parent; leftMargin: Tokens.s6; rightMargin: Tokens.s6 }
            contentWidth: navRow.width
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            function reveal(itemX, itemWidth) {
                const maximum = Math.max(0, contentWidth - width);
                if (itemX < contentX)
                    contentX = Math.max(0, itemX);
                else if (itemX + itemWidth > contentX + width)
                    contentX = Math.min(maximum, itemX + itemWidth - width);
            }

            Row {
                id: navRow
                height: parent.height
                spacing: Tokens.s2

                NavPlate {
                    objectName: "ryostore-header-discover"
                    label: I18n.tr("DISCOVER")
                    active: header.view === "discover" && header.categoryID === "" && !header.searchActive
                    anchors.verticalCenter: parent.verticalCenter
                    onChose: header.activateDiscover()
                }
                Repeater {
                    model: header.categories
                    delegate: NavPlate {
                        required property var modelData
                        required property int index
                        objectName: "ryostore-header-category-" + String(modelData.id || "")
                        label: String(modelData.name || modelData.id || "").toUpperCase()
                        active: header.view === "discover" && header.categoryID === String(modelData.id || "") && !header.searchActive
                        anchors.verticalCenter: parent.verticalCenter
                        onChose: header.activateCategory(String(modelData.id || ""))
                        onActiveFocusChanged: if (activeFocus) navScroll.reveal(x, width)
                    }
                }
            }
        }

        // A right-edge fade telling the eye there are more categories to scroll to.
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: Tokens.s7
            visible: navScroll.contentWidth > navScroll.width + 1
                    && navScroll.contentX < navScroll.contentWidth - navScroll.width - 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Tokens.paper }
            }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Tokens.border
        color: Tokens.line
    }
}
