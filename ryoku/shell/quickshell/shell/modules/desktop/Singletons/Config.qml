pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live config for the wallpaper clock. Ryoku Settings, desktop dragging and the
// right-click menu share widgets.json; FileView watches it so every surface
// follows the next write. Placement is a compass anchor or free monitor pixels.
Singleton {
    id: root
    property bool ready: false

    // -- clock ---------------------------------------------------------------
    property alias clockEnabled: adapter.clockEnabled
    property alias clockDesign:  adapter.clockDesign   // digital | minimal | analog | flip | rings
    property alias clock24h:     adapter.clock24h
    property alias clockSeconds: adapter.clockSeconds
    property alias clockAccent:  adapter.clockAccent   // palette | brand | mono
    property alias clockScale:   adapter.clockScale
    property alias clockAnchor:  adapter.clockAnchor   // top-left .. center .. bottom-right | free
    property alias clockX:       adapter.clockX        // free placement, monitor pixels
    property alias clockY:       adapter.clockY
    property alias clockLocked:  adapter.clockLocked   // prevent drag/resize
    property alias clockOpacity: adapter.clockOpacity
    property alias clockBg:      adapter.clockBg        // none | card | glass
    property alias clockRadius:  adapter.clockRadius
    // per-widget ink colour: "" follows the wallpaper (adaptive), a hex pins a
    // solid fill, and Gradient blends <widget>Color -> <widget>Color2 across the
    // rendered glyphs. Only the bare (bg:none) widgets read these.
    property alias clockColor:    adapter.clockColor
    property alias clockColor2:   adapter.clockColor2
    property alias clockGradient: adapter.clockGradient
    property alias dateShow:     adapter.dateShow
    property alias dateDesign:   adapter.dateDesign     // inline | badge | stacked

    // widget typography: the sans family every clock face and Theme.font widget
    // renders with. Empty = the built-in default (Space Grotesk); a bundled or
    // installed family name overrides it. Picked in Hub -> Widgets.
    property alias widgetFont: adapter.widgetFont

    property alias calendarEnabled:       adapter.calendarEnabled
    property alias calendarStyle:         adapter.calendarStyle
    property alias calendarWeeks:         adapter.calendarWeeks
    property alias calendarWeekNumbers:   adapter.calendarWeekNumbers
    property alias calendarHolidayRegion: adapter.calendarHolidayRegion
    property alias calendarScale:         adapter.calendarScale
    property alias calendarAnchor:        adapter.calendarAnchor
    property alias calendarX:             adapter.calendarX
    property alias calendarY:             adapter.calendarY
    property alias calendarLocked:        adapter.calendarLocked
    property alias calendarOpacity:       adapter.calendarOpacity
    property alias calendarColor:    adapter.calendarColor
    property alias calendarColor2:   adapter.calendarColor2
    property alias calendarGradient: adapter.calendarGradient

    property alias musicEnabled: adapter.musicEnabled
    property alias musicStyle:   adapter.musicStyle    // cover | glass
    property alias musicLyrics:  adapter.musicLyrics   // show the synced lyric sheet
    property alias musicViz:     adapter.musicViz     // bars | wave (no-lyrics visualiser look)
    property alias musicScale:   adapter.musicScale
    property alias musicAnchor:  adapter.musicAnchor
    property alias musicX:       adapter.musicX
    property alias musicY:       adapter.musicY
    property alias musicLocked:  adapter.musicLocked
    property alias musicOpacity: adapter.musicOpacity
    property alias musicApp:     adapter.musicApp     // launch command for the corner button
    property alias musicShape:     adapter.musicShape      // wide | tall (9:16)
    property alias musicVideo:     adapter.musicVideo      // off | canvas | custom
    property alias musicVideoFile: adapter.musicVideoFile  // custom backdrop file
    property alias musicColor:    adapter.musicColor
    property alias musicColor2:   adapter.musicColor2
    property alias musicGradient: adapter.musicGradient

    property alias aioEnabled: adapter.aioEnabled
    property alias aioStyle:   adapter.aioStyle     // wide | tall
    property alias aioScale:   adapter.aioScale
    property alias aioAnchor:  adapter.aioAnchor
    property alias aioX:       adapter.aioX
    property alias aioY:       adapter.aioY
    property alias aioLocked:  adapter.aioLocked
    property alias aioOpacity: adapter.aioOpacity
    property alias aioColor:    adapter.aioColor
    property alias aioColor2:   adapter.aioColor2
    property alias aioGradient: adapter.aioGradient

    property alias statsEnabled: adapter.statsEnabled
    property alias statsScale:   adapter.statsScale
    property alias statsAnchor:  adapter.statsAnchor
    property alias statsX:       adapter.statsX
    property alias statsY:       adapter.statsY
    property alias statsLocked:  adapter.statsLocked
    property alias statsOpacity: adapter.statsOpacity
    property alias statsColor:    adapter.statsColor
    property alias statsColor2:   adapter.statsColor2
    property alias statsGradient: adapter.statsGradient

    property alias weatherEnabled: adapter.weatherEnabled
    property alias weatherDesign:  adapter.weatherDesign   // compact | full
    property alias weatherScale:   adapter.weatherScale
    property alias weatherAnchor:  adapter.weatherAnchor
    property alias weatherX:       adapter.weatherX
    property alias weatherY:       adapter.weatherY
    property alias weatherLocked:  adapter.weatherLocked
    property alias weatherOpacity: adapter.weatherOpacity
    property alias weatherColor:    adapter.weatherColor
    property alias weatherColor2:   adapter.weatherColor2
    property alias weatherGradient: adapter.weatherGradient

    property alias notesEnabled: adapter.notesEnabled
    property alias notesScale:   adapter.notesScale
    property alias notesAnchor:  adapter.notesAnchor
    property alias notesX:       adapter.notesX
    property alias notesY:       adapter.notesY
    property alias notesLocked:  adapter.notesLocked
    property alias notesOpacity: adapter.notesOpacity
    property alias notesWidth:   adapter.notesWidth   // pad size in logical px, before scale
    property alias notesHeight:  adapter.notesHeight
    property alias notesColor:    adapter.notesColor
    property alias notesColor2:   adapter.notesColor2
    property alias notesGradient: adapter.notesGradient

    // brand: the desktop's mark + name, user-overridable from Ryoku Settings ->
    // Shell -> Global. a small cross-cutting identity master (like theme.json).
    // markText is the glyph/short-text seal (default 力); markImage an optional
    // image path that wins over the text; markTint recolours a single-colour
    // image to the accent; name is the wordmark ("Ryoku") shown in chrome copy.
    // Ryoku's own apps (the Hub, ryo* apps) never read this and keep the 力 brand.
    property alias markText:  brandAdapter.markText
    property alias markImage: brandAdapter.markImage
    property alias markTint:  brandAdapter.markTint
    property alias brandName: brandAdapter.name

    // write helpers used by desktop drag + right-click menu. write the same file
    // Settings does; the watch reloads it (no-op for the value just written) so
    // running widgets and the next Settings open agree.
    function set(key, value) {
        adapter[key] = value;
        file.writeAdapter();
    }
    // Many keys, one write. A burst of set() calls interleaves file writes with
    // the watcher's reloads of older versions, and a stale reload followed by
    // the next write can put an old value back (a Reset restoring thirty keys
    // lost some this way); assigning everything first and writing once cannot.
    function setMany(values) {
        for (const key in values)
            if (adapter[key] !== values[key])
                adapter[key] = values[key];
        file.writeAdapter();
    }
    // memory-only, no file write. for a live drag like resize: aliases update
    // at once so the widget re-renders; setFree/set on release does the single
    // persisting write.
    function setLive(key, value) {
        adapter[key] = value;
    }
    function toggle(key) {
        adapter[key] = !adapter[key];
        file.writeAdapter();
    }
    function setAnchor(prefix, zone) {
        adapter[prefix + "Anchor"] = zone;
        file.writeAdapter();
    }
    function setFree(prefix, x, y) {
        adapter[prefix + "Anchor"] = "free";
        adapter[prefix + "X"] = x;
        adapter[prefix + "Y"] = y;
        file.writeAdapter();
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/widgets.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: root.ready = true
        onLoadFailed: root.ready = true

        JsonAdapter {
            id: adapter
            property bool clockEnabled: true
            property string clockDesign: "digital"
            property bool clock24h: true
            property bool clockSeconds: false
            property string clockAccent: "palette"
            property real clockScale: 1.0
            property string clockAnchor: "top-left"
            property int clockX: 72
            property int clockY: 64
            property bool clockLocked: false
            property real clockOpacity: 1.0
            property string clockBg: "none"
            property int clockRadius: 26
            property string clockColor: ""
            property string clockColor2: ""
            property bool clockGradient: false
            property bool dateShow: true
            property string dateDesign: "inline"
            property string widgetFont: ""
            property bool calendarEnabled: true
            property string calendarStyle: "glass"
            property int calendarWeeks: 6
            property bool calendarWeekNumbers: true
            property string calendarHolidayRegion: ""
            property real calendarScale: 1.0
            property string calendarAnchor: "bottom-right"
            property int calendarX: 80
            property int calendarY: 80
            property bool calendarLocked: false
            property real calendarOpacity: 1.0
            property string calendarColor: ""
            property string calendarColor2: ""
            property bool calendarGradient: false
            property bool musicEnabled: false
            property string musicStyle: "cover"
            property bool musicLyrics: true
            property string musicViz: "bars"
            property real musicScale: 1.0
            property string musicAnchor: "bottom-left"
            property int musicX: 80
            property int musicY: 80
            property bool musicLocked: false
            property real musicOpacity: 1.0
            property string musicApp: ""
            property string musicShape: "wide"
            property string musicVideo: "canvas"
            property string musicVideoFile: ""
            property string musicColor: ""
            property string musicColor2: ""
            property bool musicGradient: false
            property bool aioEnabled: false
            property string aioStyle: "wide"
            property real aioScale: 1.0
            property string aioAnchor: "top-right"
            property int aioX: 80
            property int aioY: 80
            property bool aioLocked: false
            property real aioOpacity: 1.0
            property string aioColor: ""
            property string aioColor2: ""
            property bool aioGradient: false
            property bool statsEnabled: false
            property real statsScale: 1.0
            property string statsAnchor: "bottom-right"
            property int statsX: 80
            property int statsY: 80
            property bool statsLocked: false
            property real statsOpacity: 1.0
            property string statsColor: ""
            property string statsColor2: ""
            property bool statsGradient: false
            property bool weatherEnabled: false
            property string weatherDesign: "compact"
            property real weatherScale: 1.0
            property string weatherAnchor: "top-right"
            property int weatherX: 80
            property int weatherY: 80
            property bool weatherLocked: false
            property real weatherOpacity: 1.0
            property string weatherColor: ""
            property string weatherColor2: ""
            property bool weatherGradient: false
            property bool notesEnabled: false
            property real notesScale: 1.0
            property string notesAnchor: "right"
            property int notesX: 80
            property int notesY: 80
            property bool notesLocked: false
            property real notesOpacity: 1.0
            property int notesWidth: 260
            property int notesHeight: 180
            property string notesColor: ""
            property string notesColor2: ""
            property bool notesGradient: false
        }
    }

    // brand identity master (mark + name), the cross-cutting identity shared with
    // doctor, the Hub editor and the rest of the shell. the always-on
    // pill seeds it; these defaults cover its absence, so no seed is written here.
    FileView {
        id: brandFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/brand.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        JsonAdapter {
            id: brandAdapter
            property string markText: "力"
            property string markImage: ""
            property bool markTint: true
            property string name: "Ryoku"
        }
    }

    Component.onCompleted: if (!file.text()) file.writeAdapter();
}
