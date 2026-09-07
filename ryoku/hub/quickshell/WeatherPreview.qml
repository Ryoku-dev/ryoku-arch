pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons

/**
 * A plain-QML preview of the weather desktop widget for the Desktop Widgets
 * section, so the chosen layout reads at a glance without leaning over to the
 * wallpaper. It mirrors the live weather/WeatherWidget.qml in its two looks --
 * `compact` (glyph, temperature, city) and `full` (plus the condition, a
 * humidity/wind/feels row and a three-day strip) -- with fixed sample values and
 * no Weather singleton. Ink follows the hub theme through Tokens; the background
 * is transparent so the card surface shows through.
 */
Item {
    id: root

    property string design: "compact"   // compact | full
    readonly property bool full: root.design === "full"

    readonly property string sym: "Material Symbols Rounded"
    readonly property var days: [
        { "day": "Mon", "icon": "sunny", "hi": "27\u00b0", "lo": "15\u00b0" },
        { "day": "Tue", "icon": "partly_cloudy_day", "hi": "25\u00b0", "lo": "14\u00b0" },
        { "day": "Wed", "icon": "rainy", "hi": "22\u00b0", "lo": "13\u00b0" }
    ]

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    component Metric: Column {
        property string label: ""
        property string value: ""
        spacing: 1
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr(parent.label)
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: 1
            font.capitalization: Font.AllUppercase
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.value
            color: Tokens.ink
            font.family: Tokens.ui
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
    }

    Column {
        id: col
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "partly_cloudy_day"
            color: Tokens.sun
            font.family: root.sym
            font.pixelSize: 76
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "72\u00b0"
            color: Tokens.ink
            font.family: Tokens.display
            font.pixelSize: 66
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("Portland")
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: 20
            font.weight: Font.Medium
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.full
            spacing: 14

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Partly Cloudy")
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: 24
                font.weight: Font.Medium
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 22
                Metric { label: I18n.tr("Humidity"); value: "54%" }
                Metric { label: I18n.tr("Wind"); value: "12" }
                Metric { label: I18n.tr("Feels"); value: "70\u00b0" }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20
                Repeater {
                    model: root.days
                    delegate: Column {
                        id: day
                        required property var modelData
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: day.modelData.day
                            color: Tokens.inkMuted
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: day.modelData.icon
                            color: Tokens.ink
                            font.family: root.sym
                            font.pixelSize: 26
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 5
                            Text {
                                text: day.modelData.hi
                                color: Tokens.ink
                                font.family: Tokens.ui
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: day.modelData.lo
                                color: Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }
}
