.pragma library

// AnimationsPage as data. Generated from the page it replaces.
// Descriptions are written by hand; the inventory carries engineering
// notes, which are not user copy.

var rows = [
    {
        "tab": "",
        "group": "GLOBAL",
        "key": "appearance.animations",
        "label": "Animations",
        "desc": "Master switch for desktop motion; off, everything snaps into place",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "FOCUS FLASH",
        "key": "plugins.hyprfocus.enabled",
        "label": "Animate the focused window",
        "desc": "Short effect on the window that takes focus; applies on Save only",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "FOCUS FLASH",
        "key": "plugins.hyprfocus.mode",
        "label": "Style",
        "desc": "Flash dips opacity, Bounce shrinks and springs, Slide nudges it",
        "ctl": "seg",
        "src": "settings.lua",
        "opts": [
            "flash",
            "bounce",
            "slide"
        ],
        "when": { "plugins.hyprfocus.enabled": [true] }
    },
    {
        "tab": "",
        "group": "FOCUS FLASH",
        "key": "plugins.hyprfocus.opacity",
        "label": "Flash opacity",
        "desc": "Opacity the flash dips to, lower is deeper; Flash style only",
        "ctl": "slid",
        "src": "settings.lua",
        "lo": 0.0,
        "hi": 1.0,
        "unit": "%",
        "pct": true,
        "when": { "plugins.hyprfocus.enabled": [true], "plugins.hyprfocus.mode": ["flash"] }
    },
    {
        "tab": "",
        "group": "FOCUS FLASH",
        "key": "plugins.hyprfocus.bounce",
        "label": "Bounce strength",
        "desc": "Scale the window shrinks to, lower bounces harder; Bounce style only",
        "ctl": "slid",
        "src": "settings.lua",
        "lo": 0.5,
        "hi": 1.0,
        "unit": "%",
        "pct": true,
        "when": { "plugins.hyprfocus.enabled": [true], "plugins.hyprfocus.mode": ["bounce"] }
    },
    {
        "tab": "",
        "group": "FOCUS FLASH",
        "key": "plugins.hyprfocus.slide",
        "label": "Slide height",
        "desc": "How far the window hops, in pixels; Slide style only",
        "ctl": "step",
        "src": "settings.lua",
        "lo": 0.0,
        "hi": 150.0,
        "unit": "px",
        "when": { "plugins.hyprfocus.enabled": [true], "plugins.hyprfocus.mode": ["slide"] }
    },
    {
        "tab": "",
        "group": "CURVES",
        "key": "",
        "label": "Curve (selector)",
        "desc": "Picks which curve the editor edits; the choice itself is not saved",
        "ctl": "pick",
        "src": "(none - transient page state: page.selectedCurve)",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "CURVES",
        "key": "anim.curves[name=<selected>].x0",
        "label": "Bezier curve P1 x (first control point, X)",
        "desc": "Time of the first handle, 0 to 1: shapes the ease at the start",
        "ctl": "slid",
        "src": "settings.lua",
        "lo": 0.0,
        "hi": 1.0
    },
    {
        "tab": "",
        "group": "CURVES",
        "key": "anim.curves[name=<selected>].y0",
        "label": "Bezier curve P1 y (first control point, Y)",
        "desc": "Progress at the first handle; below 0 pulls back before moving",
        "ctl": "step",
        "src": "settings.lua",
        "lo": -1.0,
        "hi": 2.0
    },
    {
        "tab": "",
        "group": "CURVES",
        "key": "anim.curves[name=<selected>].x1",
        "label": "Bezier curve P2 x (second control point, X)",
        "desc": "Time of the second handle, 0 to 1: shapes the ease at the end",
        "ctl": "slid",
        "src": "settings.lua",
        "lo": 0.0,
        "hi": 1.0
    },
    {
        "tab": "",
        "group": "CURVES",
        "key": "anim.curves[name=<selected>].y1",
        "label": "Bezier curve P2 y (second control point, Y)",
        "desc": "Progress at the second handle; above 1 overshoots, then settles",
        "ctl": "step",
        "src": "settings.lua",
        "lo": -1.0,
        "hi": 2.0
    },
    {
        "tab": "",
        "group": "CURVES",
        "key": "anim.curves",
        "label": "Saved curves",
        "desc": "Curve overrides saved by name; every animation using one follows it",
        "ctl": "list",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "CURVES",
        "key": "anim.curves (append)",
        "label": "New (add curve)",
        "desc": "Adds a curve with a stock ease shape and selects it for editing",
        "ctl": "action",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "CURVES",
        "key": "anim.curves (remove by name)",
        "label": "Delete / Reset (curve)",
        "desc": "Deletes a custom curve; on a built-in, drops your override instead",
        "ctl": "action",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "(action bar)",
        "key": "anim.items = [] ; anim.curves = []",
        "label": "Reset to defaults",
        "desc": "Clears every animation override and custom curve; Save makes it stick",
        "ctl": "action",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=borderangle].enabled",
        "label": "Border gradient spin \u00b7 enabled",
        "desc": "Spins the window border gradient; can keep the GPU drawing nonstop",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=borderangle].speed",
        "label": "Border gradient spin \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=borderangle].bezier",
        "label": "Border gradient spin \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsIn].enabled",
        "label": "Window open \u00b7 enabled",
        "desc": "Motion when a window opens; off, new windows just appear",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsIn].speed",
        "label": "Window open \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsIn].bezier",
        "label": "Window open \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsIn].style",
        "label": "Window open \u00b7 style",
        "desc": "Slide in, pop from 80% scale, or gnomed; Default leaves it to Hyprland",
        "ctl": "seg",
        "src": "hypr.json",
        "opts": [
            "",
            "slide",
            "popin",
            "gnomed"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeOut].enabled",
        "label": "Window close fade \u00b7 enabled",
        "desc": "Fade-out of closing windows; off, they cut out at full opacity",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeOut].speed",
        "label": "Window close fade \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeOut].bezier",
        "label": "Window close fade \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fade].enabled",
        "label": "Fades (group) \u00b7 enabled",
        "desc": "All window fading as one group: open, close, dim, shadow",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fade].speed",
        "label": "Fades (group) \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fade].bezier",
        "label": "Fades (group) \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=border].enabled",
        "label": "Border color \u00b7 enabled",
        "desc": "Blends the border color on focus change instead of snapping",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=border].speed",
        "label": "Border color \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=border].bezier",
        "label": "Border color \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=workspaces].enabled",
        "label": "Workspace switch \u00b7 enabled",
        "desc": "Motion when switching workspaces; off, the switch is a hard cut",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=workspaces].speed",
        "label": "Workspace switch \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=workspaces].bezier",
        "label": "Workspace switch \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=workspaces].style",
        "label": "Workspace switch \u00b7 style",
        "desc": "Slide horizontally or vertically, fade, or slide and fade combined",
        "ctl": "chips",
        "src": "hypr.json",
        "opts": [
            "",
            "slide",
            "slidevert",
            "fade",
            "slidefade",
            "slidefadevert"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=global].enabled",
        "label": "All animations (root) \u00b7 enabled",
        "desc": "Root of the whole tree; rows configured below still override it",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=global].speed",
        "label": "All animations (root) \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=global].bezier",
        "label": "All animations (root) \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsOut].enabled",
        "label": "Window close \u00b7 enabled",
        "desc": "Motion when a window closes; off, windows vanish instantly",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsOut].speed",
        "label": "Window close \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsOut].bezier",
        "label": "Window close \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsOut].style",
        "label": "Window close \u00b7 style",
        "desc": "Slide out, shrink to 80%, or gnomed; Default leaves it to Hyprland",
        "ctl": "seg",
        "src": "hypr.json",
        "opts": [
            "",
            "slide",
            "popin",
            "gnomed"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=layers].enabled",
        "label": "Shell layers \u00b7 enabled",
        "desc": "Motion for shell surfaces: launcher, panels, menus, notifications",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=layers].speed",
        "label": "Shell layers \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=layers].bezier",
        "label": "Shell layers \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=layers].style",
        "label": "Shell layers \u00b7 style",
        "desc": "Slide, pop from 90% scale, or fade; Default leaves it to Hyprland",
        "ctl": "seg",
        "src": "hypr.json",
        "opts": [
            "",
            "slide",
            "popin",
            "fade"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeIn].enabled",
        "label": "Window open fade \u00b7 enabled",
        "desc": "Fade-in of opening windows; off, they appear at full opacity",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeIn].speed",
        "label": "Window open fade \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeIn].bezier",
        "label": "Window open fade \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=specialWorkspace].enabled",
        "label": "Special workspace \u00b7 enabled",
        "desc": "Motion when the special (scratchpad) workspace shows or hides",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=specialWorkspace].speed",
        "label": "Special workspace \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=specialWorkspace].bezier",
        "label": "Special workspace \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=specialWorkspace].style",
        "label": "Special workspace \u00b7 style",
        "desc": "How the scratchpad slides or fades; vert variants move vertically",
        "ctl": "chips",
        "src": "hypr.json",
        "opts": [
            "",
            "slide",
            "slidevert",
            "fade",
            "slidefade",
            "slidefadevert"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windows].enabled",
        "label": "Windows (group) \u00b7 enabled",
        "desc": "Window open, close, and move as one; the specific rows override it",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windows].speed",
        "label": "Windows (group) \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windows].bezier",
        "label": "Windows (group) \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windows].style",
        "label": "Windows (group) \u00b7 style",
        "desc": "Slide in, pop from 80% scale, or gnomed; Default leaves it to Hyprland",
        "ctl": "seg",
        "src": "hypr.json",
        "opts": [
            "",
            "slide",
            "popin",
            "gnomed"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeLayersIn].enabled",
        "label": "Shell layer fade-in \u00b7 enabled",
        "desc": "Fade-in of shell surfaces as they appear (launcher, panels, menus)",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeLayersIn].speed",
        "label": "Shell layer fade-in \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeLayersIn].bezier",
        "label": "Shell layer fade-in \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeLayersOut].enabled",
        "label": "Shell layer fade-out \u00b7 enabled",
        "desc": "Fade-out of shell surfaces as they close (launcher, panels, menus)",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeLayersOut].speed",
        "label": "Shell layer fade-out \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=fadeLayersOut].bezier",
        "label": "Shell layer fade-out \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsMove].enabled",
        "label": "Window move \u00b7 enabled",
        "desc": "Motion while windows are moved, dragged, or resized",
        "ctl": "sw",
        "src": "hypr.json"
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsMove].speed",
        "label": "Window move \u00b7 speed",
        "desc": "Duration in tenths of a second: 10 is one second, higher is slower",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.1,
        "hi": 10.0
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsMove].bezier",
        "label": "Window move \u00b7 bezier curve",
        "desc": "Easing curve it follows; edit or add shapes in the Curves section",
        "ctl": "pick",
        "src": "hypr.json",
        "opts": [
            "ryokuWobble",
            "dynamic-cursors-magnification",
            "ryokuTheme",
            "ryokuBloom",
            "almostLinear",
            "ryokuSettle",
            "quick",
            "easeOutQuint",
            "linear",
            "default"
        ]
    },
    {
        "tab": "",
        "group": "ANIMATIONS",
        "key": "anim.items[leaf=windowsMove].style",
        "label": "Window move \u00b7 style",
        "desc": "Slide, pop, or gnomed while moving; Default leaves it to Hyprland",
        "ctl": "seg",
        "src": "hypr.json",
        "opts": [
            "",
            "slide",
            "popin",
            "gnomed"
        ]
    }
];
