pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    property string style: "glass"
    property int weeks: 6
    property bool showWeekNumbers: true
    readonly property date today: new Date()
    readonly property int preferredWeeks: Math.max(4, Math.min(8, root.weeks))
    readonly property int leadingDays: (new Date(root.today.getFullYear(), root.today.getMonth(), 1).getDay() + 6) % 7
    readonly property int requiredWeeks: Math.ceil((root.leadingDays
        + new Date(root.today.getFullYear(), root.today.getMonth() + 1, 0).getDate()) / 7)
    readonly property int clampedWeeks: Math.max(root.preferredWeeks, root.requiredWeeks)
    readonly property real headerHeight: 44
    readonly property real weekColumn: root.showWeekNumbers ? 22 : 0
    readonly property real cellWidth: (width - 28 - root.weekColumn) / 7
    readonly property real cellHeight: (height - root.headerHeight - 28) / root.clampedWeeks
    readonly property var days: root.buildDays()

    function buildDays() {
        const first = new Date(root.today.getFullYear(), root.today.getMonth(), 1);
        const offset = (first.getDay() + 6) % 7;
        const start = new Date(first.getFullYear(), first.getMonth(), 1 - offset);
        const result = [];
        for (let i = 0; i < root.clampedWeeks * 7; i++) {
            const date = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            result.push({
                day: date.getDate(), month: date.getMonth(), row: Math.floor(i / 7), column: i % 7,
                today: date.getFullYear() === root.today.getFullYear() && date.getMonth() === root.today.getMonth() && date.getDate() === root.today.getDate(),
                holiday: i === 9 || i === 24, event: i === 15
            });
        }
        return result;
    }

    Rectangle {
        anchors.fill: parent
        radius: root.style === "glass" ? Tokens.radius * 3 : Tokens.radius
        color: root.style === "glass" ? Qt.rgba(Tokens.paperLift.r, Tokens.paperLift.g, Tokens.paperLift.b, 0.88) : Tokens.paper
        border.width: Tokens.border
        border.color: Tokens.lineStrong
    }

    Text {
        x: 14; y: 10
        text: Qt.locale().standaloneMonthName(root.today.getMonth(), Locale.LongFormat) + " " + root.today.getFullYear()
        color: Tokens.ink
        font.family: Tokens.display
        font.pixelSize: 17
        font.weight: Font.Medium
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 14; y: 14
        text: I18n.tr("WEEK %1").arg(root.weekNumber(root.today))
        color: Tokens.inkMuted
        font.family: Tokens.mono
        font.pixelSize: 8
        font.letterSpacing: Tokens.trackLabel
    }

    Row {
        x: 14 + root.weekColumn; y: 35
        Repeater {
            // weekday initials come from the locale, exactly as the real
            // calendars do (shell/components/Calendar.qml): a Polish week is
            // P W S C P S N, which no translation of the letter "M" could
            // produce. Monday first, matching buildDays() above.
            model: 7
            delegate: Text {
                required property int index
                width: root.cellWidth
                horizontalAlignment: Text.AlignHCenter
                text: Qt.locale().standaloneDayName((index + 1) % 7, Locale.NarrowFormat)
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: 8
            }
        }
    }

    Repeater {
        model: root.showWeekNumbers ? root.clampedWeeks : 0
        delegate: Text {
            required property int index
            x: 14; y: root.headerHeight + index * root.cellHeight + (root.cellHeight - height) / 2
            width: root.weekColumn
            horizontalAlignment: Text.AlignHCenter
            text: String(root.weekNumber(new Date(root.days[index * 7].month === 11 ? root.today.getFullYear() - 1 : root.today.getFullYear(), root.days[index * 7].month, root.days[index * 7].day)))
            color: Tokens.inkFaint
            font.family: Tokens.mono
            font.pixelSize: 7
        }
    }

    Repeater {
        model: root.days
        delegate: Item {
            required property var modelData
            x: 14 + root.weekColumn + modelData.column * root.cellWidth
            y: root.headerHeight + modelData.row * root.cellHeight
            width: root.cellWidth; height: root.cellHeight
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.72
                height: width
                radius: root.style === "glass" ? width / 2 : Tokens.radius
                color: modelData.today ? Tokens.ink : "transparent"
            }
            Text {
                anchors.centerIn: parent
                text: modelData.day
                color: modelData.today ? Tokens.paper : (modelData.month === root.today.getMonth() ? Tokens.ink : Tokens.inkFaint)
                font.family: Tokens.ui
                font.pixelSize: 9
                font.weight: modelData.today ? Font.DemiBold : Font.Normal
            }
            Rectangle {
                visible: modelData.holiday
                width: parent.width * 0.28; height: 1
                anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
                color: Tokens.inkMuted
            }
            Rectangle {
                visible: modelData.event
                width: 3; height: 3; radius: width / 2
                anchors.right: parent.right; anchors.top: parent.top
                color: Tokens.ink
            }
        }
    }

    function weekNumber(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        const day = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - day);
        const start = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return Math.ceil((((d - start) / 86400000) + 1) / 7);
    }
}
