.pragma library

// HyprStore as data. Generated from the page it replaces.
// Descriptions are written by hand; the inventory carries engineering
// notes, which are not user copy.

var rows = [
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.gapsIn",
        "label": "Inner gaps",
        "desc": "Space in pixels between adjacent tiled windows",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.gapsOut",
        "label": "Outer gaps",
        "desc": "Space in pixels between windows and the screen edge",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.borderSize",
        "label": "Border width",
        "desc": "Thickness of the frame drawn around every window, in pixels",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.rounding",
        "label": "Corner radius",
        "desc": "Corner radius of windows in pixels, 0 keeps corners square",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.roundingPower",
        "label": "Corner curve",
        "desc": "Corner curve: 2 is a true circle, higher flattens into a squircle",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.activeOpacity",
        "label": "Active opacity",
        "desc": "Opacity of the focused window, 1 is fully opaque",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.inactiveOpacity",
        "label": "Inactive opacity",
        "desc": "Opacity of unfocused windows, lower lets the desktop show through",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.dimInactive",
        "label": "Dim inactive",
        "desc": "Darkens every window except the focused one",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.dimStrength",
        "label": "Dim strength",
        "desc": "How dark unfocused windows get, only used while dimming is on",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.blurEnabled",
        "label": "Blur",
        "desc": "Blurs whatever shows through translucent windows and surfaces",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.blurSize",
        "label": "Blur size",
        "desc": "Blur radius per pass, larger smears the background further",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.blurPasses",
        "label": "Blur passes",
        "desc": "Times the blur runs, more passes spread it wider but cost GPU",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.blurXray",
        "label": "Blur X-ray",
        "desc": "Blur samples the wallpaper only, skipping windows underneath",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.blurVibrancy",
        "label": "Blur vibrancy",
        "desc": "Saturation boost applied to the blurred backdrop",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.blurNoise",
        "label": "Blur noise",
        "desc": "Grain mixed into the blur to hide color banding",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.shadowEnabled",
        "label": "Shadows",
        "desc": "Drop shadow under every window",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.shadowRange",
        "label": "Shadow range",
        "desc": "How far the shadow extends from the window, in pixels",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.shadowPower",
        "label": "Shadow sharpness",
        "desc": "Falloff sharpness, 1 to 4: higher fades the shadow out faster",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.glowEnabled",
        "label": "Glow",
        "desc": "Colored halo drawn around window edges",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.glowRange",
        "label": "Glow range",
        "desc": "How far the glow spreads from the window edge, in pixels",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.glowColor",
        "label": "Glow color",
        "desc": "Color of the glow halo",
        "ctl": "color",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.animations",
        "label": "animations",
        "desc": "Master switch for all window, fade and workspace animations",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.layout",
        "label": "Tiling layout",
        "desc": "How new windows tile: dwindle splits, master stacks, scrolling pans",
        "ctl": "seg",
        "src": "settings.lua",
        "opts": [
            "dwindle",
            "master",
            "scrolling"
        ]
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.activeBorder",
        "label": "Active border color",
        "desc": "Focused window border, ignored while the theme follows the wallpaper",
        "ctl": "color",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.inactiveBorder",
        "label": "Inactive border color",
        "desc": "Unfocused window border, ignored while the theme follows the wallpaper",
        "ctl": "color",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.resizeOnBorder",
        "label": "Resize on borders",
        "desc": "Drag a window border or gap to resize instead of using a keybind",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.snapEnabled",
        "label": "Window snapping",
        "desc": "Dragged floating windows snap to screen edges and other windows",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.wobblyWindows",
        "label": "Wobbly windows",
        "desc": "Dragged windows overshoot and spring back when they settle",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.windowStyle",
        "label": "Open/close style",
        "desc": "How windows open and close: pop grows in place, slide and gnomed sweep",
        "ctl": "seg",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.animatedBorder",
        "label": "Animated border",
        "desc": "Spins a gradient of the two border colors around the focused window",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "appearance",
        "key": "appearance.borderAngleSpeed",
        "label": "Border spin speed",
        "desc": "Rotation speed of the animated border, 1 to 10, higher spins faster",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.kbLayout",
        "label": "Keyboard layout",
        "desc": "XKB layout code such as us or de, pinned over the base once saved",
        "ctl": "text",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.kbVariant",
        "label": "Layout variant",
        "desc": "Layout variant such as intl or dvorak, empty for the plain layout",
        "ctl": "text",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.kbOptions",
        "label": "Keyboard options",
        "desc": "Comma-separated XKB tweaks, e.g. caps:escape to remap Caps Lock",
        "ctl": "text",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.numlockByDefault",
        "label": "Numlock at start",
        "desc": "Numlock comes on when the session starts",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.followMouse",
        "label": "Focus follows mouse",
        "desc": "How focus tracks the pointer: 0 click to focus, 1 follow, 2-3 detached",
        "ctl": "seg",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.sensitivity",
        "label": "sensitivity",
        "desc": "Pointer speed offset, -1 slow to 1 fast, 0 leaves the device alone",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.accelProfile",
        "label": "Acceleration profile",
        "desc": "Pointer acceleration: flat is raw 1:1, adaptive scales with speed",
        "ctl": "seg",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.leftHanded",
        "label": "Left-handed mode",
        "desc": "Swaps left and right mouse buttons",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.mouseNaturalScroll",
        "label": "Mouse natural scroll",
        "desc": "Reverses wheel direction: content follows the fingers",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.mouseScrollFactor",
        "label": "Mouse scroll speed",
        "desc": "Multiplier on wheel scroll distance, above 1 scrolls further per notch",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.middleClickPaste",
        "label": "Middle-click paste",
        "desc": "Middle button pastes the primary selection, off frees it for apps",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.naturalScroll",
        "label": "Touchpad natural scroll",
        "desc": "Reverses touchpad scroll: content follows the fingers",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.tapToClick",
        "label": "Tap to click",
        "desc": "A light touchpad tap counts as a left click",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.tapAndDrag",
        "label": "Tap and drag",
        "desc": "Tap twice and keep the finger down to drag",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.clickfinger",
        "label": "Clicks by finger count",
        "desc": "Clicking with 2 or 3 fingers means right or middle click, not corners",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.middleEmulation",
        "label": "Middle-click emulation",
        "desc": "Pressing left and right buttons together makes a middle click",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.touchScrollFactor",
        "label": "Touchpad scroll speed",
        "desc": "Multiplier on touchpad scroll distance",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.disableWhileTyping",
        "label": "Disable while typing",
        "desc": "Ignores the touchpad briefly while keys are being pressed",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.repeatRate",
        "label": "Key repeat rate",
        "desc": "Held-key repeats per second",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.repeatDelay",
        "label": "Key repeat delay",
        "desc": "Milliseconds a key is held before it starts repeating",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.workspaceSwipe",
        "label": "Workspace swipe",
        "desc": "Horizontal touchpad swipe switches workspaces",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.swipeFingers",
        "label": "Swipe fingers",
        "desc": "Fingers for the workspace swipe, values below 3 clamp to 3",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.swipeInvert",
        "label": "Invert swipe",
        "desc": "Reverses which way the swipe moves through workspaces",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.swipeCreateNew",
        "label": "Swipe creates workspaces",
        "desc": "Swiping past the last workspace opens a fresh empty one",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "input",
        "key": "input.swipeDistance",
        "label": "Swipe distance",
        "desc": "Pixels of finger travel for a full workspace switch",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "cursor",
        "key": "cursor.theme",
        "label": "Cursor theme",
        "desc": "Pointer look, applies now; already-running apps keep the old cursor",
        "ctl": "text",
        "src": "settings.lua (also env + `hyprctl setcursor`)"
    },
    {
        "tab": "",
        "group": "cursor",
        "key": "cursor.size",
        "label": "Cursor size",
        "desc": "Pointer size in pixels, exported so new apps match the compositor",
        "ctl": "step",
        "src": "settings.lua (also env + `hyprctl setcursor`)"
    },
    {
        "tab": "",
        "group": "cursor",
        "key": "cursor.inactiveTimeout",
        "label": "Hide when idle",
        "desc": "Seconds without movement before the pointer hides, 0 never hides",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "cursor",
        "key": "cursor.hideOnKeyPress",
        "label": "Hide while typing",
        "desc": "Pointer disappears when a key is pressed, back on the next move",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.dynamicCursors",
        "key": "plugins.dynamicCursors.enabled",
        "label": "Dynamic cursors",
        "desc": "Cursor leans into motion; applies on Save, not the live preview",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.dynamicCursors",
        "key": "plugins.dynamicCursors.mode",
        "label": "Cursor effect",
        "desc": "rotate turns toward travel, tilt leans with speed, stretch deforms",
        "ctl": "seg",
        "src": "settings.lua",
        "opts": [
            "rotate",
            "tilt",
            "stretch"
        ]
    },
    {
        "tab": "",
        "group": "plugins.dynamicCursors",
        "key": "plugins.dynamicCursors.shake",
        "label": "Shake to find",
        "desc": "Shaking the pointer grows it so it is easy to find",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.dynamicCursors",
        "key": "plugins.dynamicCursors.magnify",
        "label": "Shake magnification",
        "desc": "How large the pointer grows during a shake, as a size multiplier",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprbars",
        "key": "plugins.hyprbars.enabled",
        "label": "Title bars",
        "desc": "Draws a title bar on every window; applies on Save",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprbars",
        "key": "plugins.hyprbars.height",
        "label": "Bar height",
        "desc": "Title bar height in pixels, 12 to 48",
        "ctl": "step",
        "src": "settings.lua",
        "lo": 12.0,
        "hi": 48.0
    },
    {
        "tab": "",
        "group": "plugins.hyprbars",
        "key": "plugins.hyprbars.textSize",
        "label": "Title text size",
        "desc": "Title text height in the bar, 8 to 20",
        "ctl": "step",
        "src": "settings.lua",
        "lo": 8.0,
        "hi": 20.0
    },
    {
        "tab": "",
        "group": "plugins.hyprbars",
        "key": "plugins.hyprbars.blur",
        "label": "Bar blur",
        "desc": "Blurs what shows through the bar background",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprbars",
        "key": "plugins.hyprbars.buttons",
        "label": "Bar buttons",
        "desc": "Adds close and fullscreen buttons, traffic-light style",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.imgborders",
        "key": "plugins.imgborders.enabled",
        "label": "Image borders",
        "desc": "Wraps windows in a frame cut from an image; applies on Save",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.imgborders",
        "key": "plugins.imgborders.image",
        "label": "Frame image",
        "desc": "Path to the image the frame is sliced from",
        "ctl": "text",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.imgborders",
        "key": "plugins.imgborders.sizes",
        "label": "Frame edge sizes",
        "desc": "Pixel width of each frame edge as left,right,top,bottom",
        "ctl": "text",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.imgborders",
        "key": "plugins.imgborders.insets",
        "label": "Frame insets",
        "desc": "How far the frame intrudes on each edge, left,right,top,bottom px",
        "ctl": "text",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.imgborders",
        "key": "plugins.imgborders.scale",
        "label": "Frame scale",
        "desc": "Multiplier on the frame's drawn size",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.imgborders",
        "key": "plugins.imgborders.smooth",
        "label": "Smooth scaling",
        "desc": "Filters the frame when scaling, off keeps pixel art crisp",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprglass",
        "key": "plugins.hyprglass.enabled",
        "label": "Glass effect",
        "desc": "Frosted-glass look for windows; applies on Save",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprglass",
        "key": "plugins.hyprglass.preset",
        "label": "Glass preset",
        "desc": "Starting look: clear, subtle, high_contrast or glass",
        "ctl": "seg",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprglass",
        "key": "plugins.hyprglass.blurStrength",
        "label": "Glass blur",
        "desc": "How strongly the glass blurs whatever is behind it",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprglass",
        "key": "plugins.hyprglass.opacity",
        "label": "Glass opacity",
        "desc": "Opacity of the glass layer itself",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprglass",
        "key": "plugins.hyprglass.tint",
        "label": "Glass tint",
        "desc": "Tint as RRGGBBAA hex, alpha included; bad values fall back to default",
        "ctl": "color",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprfocus",
        "key": "plugins.hyprfocus.enabled",
        "label": "Focus animation",
        "desc": "Animates a window when it gains focus; applies on Save",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprfocus",
        "key": "plugins.hyprfocus.mode",
        "label": "Focus effect",
        "desc": "flash dips opacity, bounce scales, slide nudges the window",
        "ctl": "seg",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprfocus",
        "key": "plugins.hyprfocus.opacity",
        "label": "Flash opacity",
        "desc": "How far the flash dips, only used in flash mode",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprfocus",
        "key": "plugins.hyprfocus.bounce",
        "label": "Bounce strength",
        "desc": "How hard the window bounces, only used in bounce mode",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprfocus",
        "key": "plugins.hyprfocus.slide",
        "label": "Slide distance",
        "desc": "Pixels the window slides, only used in slide mode",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.keysounds",
        "key": "plugins.keysounds.enabled",
        "label": "Keyboard sounds",
        "desc": "Loads the keysounds plugin: a sound on every key press",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.keysounds",
        "key": "plugins.keysounds.profile",
        "label": "Sound profile",
        "desc": "A shipped switch recording (cherry-mx-blue, topre, creamy, holy-panda, ...) or a profile of your own",
        "ctl": "seg",
        "src": "settings.lua",
        "opts": [
            "cherry-mx-blue",
            "cherry-mx-brown",
            "cherry-mx-black",
            "cherry-mx-red",
            "topre",
            "creamy",
            "nk-cream",
            "holy-panda",
            "tealios",
            "crystal-purple",
            "oreo"
        ]
    },
    {
        "tab": "",
        "group": "plugins.keysounds",
        "key": "plugins.keysounds.volume",
        "label": "Volume",
        "desc": "Playback volume, 0 to 1",
        "ctl": "slid",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.keysounds",
        "key": "plugins.keysounds.release",
        "label": "Key release sound",
        "desc": "Also play the key-up sample",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprscrolling",
        "key": "plugins.hyprscrolling.columnWidth",
        "label": "Column width",
        "desc": "Width of new columns as a screen fraction, scrolling layout only",
        "ctl": "step",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "plugins.hyprscrolling",
        "key": "plugins.hyprscrolling.followFocus",
        "label": "Follow focus",
        "desc": "View scrolls to the window you focus or hover, scrolling layout only",
        "ctl": "sw",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "lists",
        "key": "env",
        "label": "Environment variables",
        "desc": "Session environment variables, seen by apps launched after Save",
        "ctl": "list",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "lists",
        "key": "windowRules",
        "label": "Window rules",
        "desc": "Per-app rules by class or title: float, size, workspace, opacity, more",
        "ctl": "list",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "lists",
        "key": "layerRules",
        "label": "Layer rules",
        "desc": "Rules for shell surfaces (bar, launcher) by namespace: blur, alpha, more",
        "ctl": "list",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "lists",
        "key": "appOverrides",
        "label": "App overrides",
        "desc": "Per-app looks that beat the global theme, unset fields inherit",
        "ctl": "list",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "lists",
        "key": "autostart",
        "label": "autostart",
        "desc": "Commands run once at every session start",
        "ctl": "list",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "lists",
        "key": "keybinds",
        "label": "keybinds",
        "desc": "Your shortcuts: run a command, or close, fullscreen, float a window",
        "ctl": "list",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "lists (anim)",
        "key": "anim.items",
        "label": "Animation overrides",
        "desc": "Per-animation speed, curve and style overrides; previews live",
        "ctl": "list",
        "src": "settings.lua"
    },
    {
        "tab": "",
        "group": "lists (anim)",
        "key": "anim.curves",
        "label": "Animation curves",
        "desc": "Custom bezier curves for overrides; reusing a base name replaces it",
        "ctl": "list",
        "src": "settings.lua"
    }
];
