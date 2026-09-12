// The Kairos clock, shared by the bar island and the launcher so both surfaces
// read the same time in the same regional-formats locale. 24-hour: the style
// ships no settings yet.

import QtQuick
import Quickshell
import shell.services

// An Item, not a QtObject: QtObject has no default property, so the SystemClock
// below could not be declared inside it. It draws nothing and stays 0x0.
Item {
    id: clock

    readonly property date now: systemClock.date
    readonly property string time: clock.pad(now.getHours()) + ":" + clock.pad(now.getMinutes())
    readonly property string date: now.toLocaleDateString(Config.formatLoc, "ddd d MMM").toUpperCase()

    function pad(n) { return (n < 10 ? "0" : "") + n }

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }
}
