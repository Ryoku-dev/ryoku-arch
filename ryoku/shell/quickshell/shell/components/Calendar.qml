pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import shell.services
import "../services/lib/events.js" as EventsModel
import "../services/lib/calendar.js" as CalendarModel
import Ryoku.Ui.Singletons

// calendar surface content. header (month/year + prev/next), weekday strip,
// day grid sized to exactly the rows the month needs. today gets a warm
// frame, weekend columns are dimmed, leading/trailing cells ghost the
// neighbour months' day numbers. view date snaps back to the real today (via
// SystemClock) every open. implicitHeight tracks the live row count so the
// pill shrinks with it; todayX/Y/Visible expose today's cell centre for the
// flame lap.
PillSurface {
    id: root

    mTop: 16
    mLeft: 18
    mRight: 18
    mBottom: 16

    readonly property var loc: Qt.locale("en_US")

    readonly property date today: sysClock.date
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    property string selectedKey: ""

    readonly property int offset: firstWeekdayOffset(viewYear, viewMonth)
    readonly property int monthLen: daysInMonth(viewYear, viewMonth)
    readonly property int rows: Math.ceil((offset + monthLen) / 7)

    readonly property real cellH: 24 * s
    readonly property real rowGap: 2 * s

    implicitHeight: grid.y + rows * cellH + (rows - 1) * rowGap + (Weather.available ? 34 * s : 0) + (selectedKey.length > 0 ? 12 * s + editorCol.implicitHeight : 0)

    readonly property bool todayVisible: viewMonth === today.getMonth()
        && viewYear === today.getFullYear()
    readonly property int todayIndex: offset + today.getDate() - 1
    readonly property real cellW: grid.width / 7
    readonly property real todayX: grid.x + (todayIndex % 7 + 0.5) * cellW
    readonly property real todayY: grid.y + (Math.floor(todayIndex / 7) + 0.5) * (cellH + rowGap) - rowGap / 2

    ameForm: todayVisible ? "ring" : "dock"
    amePoint: todayVisible ? Qt.point(todayX, todayY) : Qt.point(width / 2, height / 2)

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
        enabled: root.active
    }

    function firstWeekdayOffset(year, month) {
        var d = new Date(year, month, 1).getDay();
        return (d + 6) % 7;
    }

    function daysInMonth(year, month) {
        return CalendarModel.daysInMonth(year, month);
    }

    function isToday(day) {
        return day === today.getDate()
            && viewMonth === today.getMonth()
            && viewYear === today.getFullYear();
    }

    function shiftMonth(delta) {
        var next = CalendarModel.shiftMonth(viewYear, viewMonth, delta);
        viewYear = next.year;
        viewMonth = next.month;
    }

    function resetToday() {
        viewYear = today.getFullYear();
        viewMonth = today.getMonth();
    }

    function prettyDate(key) {
        var p = key.split("-");
        if (p.length !== 3)
            return "";
        return root.loc.toString(new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])), "ddd d MMM");
    }

    onActiveChanged: if (active) { resetToday(); selectedKey = EventsModel.dateKey(today.getFullYear(), today.getMonth(), today.getDate()); }

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 46 * root.s

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5 * root.s

            Eyebrow {
                label: I18n.tr("Calendar")
                s: root.s
            }

            Text {
                id: monthTitle
                text: root.loc.standaloneMonthName(root.viewMonth, Locale.LongFormat)
                    + " " + root.viewYear
                color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                font.family: Theme.display
                font.pixelSize: 21 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: -0.4 * root.s
            }
        }

        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2 * root.s
            spacing: 4 * root.s

            Repeater {
                model: [-1, 1]

                Rectangle {
                    id: nav
                    required property int modelData
                    width: 24 * root.s
                    height: 24 * root.s
                    radius: Theme.radiusWidget
                    color: navArea.containsMouse ? Theme.frameBg : "transparent"
                    border.width: navArea.containsMouse ? 1 : 0
                    border.color: Theme.frameBorder

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 16 * root.s
                        height: 16 * root.s
                        name: nav.modelData < 0 ? "chevron-left" : "chevron-right"
                        color: Theme.inkOn(Theme.effectiveSurface, navArea.containsMouse ? Theme.onSurface : Theme.onSurfaceVariant, 3.0)
                        stroke: 1.8
                    }

                    MouseArea {
                        id: navArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.shiftMonth(nav.modelData)
                    }
                }
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.outlineVariant
    }

    Row {
        id: weekdays
        anchors.top: divider.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right

        Repeater {
            model: 7

            Item {
                id: wd
                required property int index
                readonly property bool weekend: index >= 5
                width: weekdays.width / 7
                height: 16 * root.s

                Text {
                    anchors.centerIn: parent
                    text: root.loc.standaloneDayName((wd.index + 1) % 7, Locale.NarrowFormat)
                    color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                    font.family: Theme.fontPrimary
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Medium
                    font.letterSpacing: 0.5 * root.s
                }
            }
        }
    }

    Grid {
        id: grid
        y: weekdays.y + weekdays.height + 4 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        columns: 7
        rowSpacing: root.rowGap
        columnSpacing: 0

        Repeater {
            model: root.rows * 7

            Item {
                id: cell
                required property int index
                readonly property int weekday: index % 7
                readonly property bool weekend: weekday >= 5
                width: grid.width / 7
                height: root.cellH

                readonly property int dayNum: index - root.offset + 1
                readonly property bool inMonth: dayNum >= 1 && dayNum <= root.monthLen
                readonly property bool current: inMonth && root.isToday(dayNum)
                readonly property string key: cell.inMonth
                    ? EventsModel.dateKey(root.viewYear, root.viewMonth, cell.dayNum) : ""
                readonly property bool selected: cell.inMonth && cell.key === root.selectedKey
                readonly property bool hasEv: cell.inMonth && Events.hasEvents(cell.key)
                readonly property int ghostNum: dayNum < 1
                    ? root.daysInMonth(root.viewYear, root.viewMonth - 1) + dayNum
                    : dayNum - root.monthLen

                Rectangle {
                    anchors.centerIn: parent
                    width: 22 * root.s
                    height: 22 * root.s
                    radius: Theme.radiusWidget
                    color: cellArea.containsMouse && cell.inMonth && !cell.current
                        ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.04) : "transparent"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 24 * root.s
                    height: 24 * root.s
                    radius: Theme.radiusWidget
                    visible: cell.current
                    color: Qt.alpha(Theme.primary, 0.16)
                    border.width: 1
                    border.color: Qt.alpha(Theme.primary, 0.55)
                }
                // The 力 seal set faint behind today's number: the brand mark in
                // one quiet place. The primary-tinted ring above stays as it was.
                BrandMark {
                    anchors.centerIn: parent
                    visible: cell.current
                    size: 18 * root.s
                    color: Theme.primary
                    opacity: 0.24
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 24 * root.s
                    height: 24 * root.s
                    radius: Theme.radiusWidget
                    visible: cell.selected && !cell.current
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Theme.onSurface, 0.22)
                }

                Text {
                    anchors.centerIn: parent
                    text: cell.inMonth ? cell.dayNum : cell.ghostNum
                    color: cell.inMonth
                        ? (cell.current ? Theme.inkOn(Theme.effectiveSurface, Theme.primary, 3.0)
                            : (cell.weekend ? Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                                            : Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)))
                        : Theme.ghost
                    font.family: Theme.fontPrimary
                    font.pixelSize: 11 * root.s
                    font.weight: cell.current ? Font.DemiBold : Font.Normal
                    font.features: { "tnum": 1 }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.verticalCenter
                    anchors.topMargin: 7 * root.s
                    width: 3 * root.s
                    height: 3 * root.s
                    radius: 1.5 * root.s
                    visible: cell.hasEv
                    color: cell.current ? Theme.flameCore : Theme.primary
                }

                MouseArea {
                    id: cellArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: cell.inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (cell.inMonth) root.selectedKey = cell.key
                }
            }
        }
    }

    Item {
        id: weatherFooter
        visible: Weather.available
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: grid.bottom
        anchors.topMargin: 10 * root.s
        height: 24 * root.s

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.outlineVariant
        }

        Row {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            spacing: 8 * root.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.s
                height: 16 * root.s
                name: Weather.glyph
                color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                stroke: 1.7
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.temp
                color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                font.family: Theme.fontPrimary
                font.pixelSize: 13 * root.s
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Weather.daily.length > 0
                text: Weather.daily.length > 0
                    ? "\u2191" + Weather.daily[0].hi + "\u00b0  \u2193" + Weather.daily[0].lo + "\u00b0" : ""
                color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                font.family: Theme.fontPrimary
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }
        }

        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1 * root.s
            text: Weather.condition
            color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
            font.family: Theme.fontPrimary
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
        }
    }

    Item {
        id: editor
        visible: root.selectedKey.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: weatherFooter.visible ? weatherFooter.bottom : grid.bottom
        anchors.topMargin: 12 * root.s
        height: editorCol.implicitHeight

        Column {
            id: editorCol
            width: parent.width
            spacing: 6 * root.s

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outlineVariant
            }

            Text {
                text: root.prettyDate(root.selectedKey)
                color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                font.family: Theme.fontPrimary
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.8 * root.s
            }

            Repeater {
                model: Events.forDate(root.selectedKey)

                Row {
                    id: evRow
                    required property var modelData
                    readonly property bool hasRange: !!(evRow.modelData.endTime && evRow.modelData.endTime.length > 0)
                    width: editorCol.width
                    height: 20 * root.s
                    spacing: 8 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: evRow.hasRange ? 72 * root.s : 36 * root.s
                        text: evRow.modelData.time && evRow.modelData.time.length > 0
                            ? (evRow.hasRange ? evRow.modelData.time + "-" + evRow.modelData.endTime : evRow.modelData.time)
                            : I18n.tr("all")
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                        font.family: Theme.fontPrimary
                        font.pixelSize: 10 * root.s
                        font.features: { "tnum": 1 }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (evRow.hasRange ? 72 : 36) * root.s - delBtn.width - 16 * root.s
                        text: evRow.modelData.text
                        elide: Text.ElideRight
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                        font.family: Theme.fontPrimary
                        font.pixelSize: 11 * root.s
                    }

                    Rectangle {
                        id: delBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18 * root.s
                        height: 18 * root.s
                        radius: Theme.radiusWidget
                        color: delArea.containsMouse ? Theme.frameBg : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\u00d7"
                            color: Theme.inkOn(Theme.effectiveSurface, delArea.containsMouse ? Theme.primary : Theme.onSurfaceVariant, 3.0)
                            font.family: Theme.fontPrimary
                            font.pixelSize: 14 * root.s
                        }

                        MouseArea {
                            id: delArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Events.remove(evRow.modelData.id)
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 26 * root.s + Theme.shadowOffset * root.s

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: Theme.shadowOffset * root.s
                    anchors.topMargin: Theme.shadowOffset * root.s
                    width: parent.width
                    height: 26 * root.s
                    radius: Theme.radiusWidget
                    visible: addField.activeFocus
                    color: Theme.primary
                }

                Rectangle {
                    id: addFieldBox
                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: parent.width
                    height: 26 * root.s
                    radius: Theme.radiusWidget
                    color: addField.activeFocus ? Theme.frameBg : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.03)
                    border.width: 1
                    border.color: addField.activeFocus ? Theme.frameBorder : Theme.outlineVariant

                    TextField {
                        id: addField
                        anchors.fill: parent
                        anchors.leftMargin: 9 * root.s
                        anchors.rightMargin: 9 * root.s
                        verticalAlignment: TextInput.AlignVCenter
                        background: null
                        padding: 0
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                        font.family: Theme.fontPrimary
                        font.pixelSize: 11 * root.s
                        placeholderText: I18n.tr("Add for this day (e.g. 09:30 standup)")
                        placeholderTextColor: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                        selectByMouse: true
                        selectionColor: Theme.primary
                        onAccepted: {
                            if (Events.addEntry(root.selectedKey, text))
                                text = "";
                        }
                        Keys.onPressed: (e) => {
                            if (e.key === Qt.Key_Escape) {
                                addField.text = "";
                                addField.focus = false;
                                e.accepted = true;
                            }
                        }
                    }
                }
            }
        }
    }
}
