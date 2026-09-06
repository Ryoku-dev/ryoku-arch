.pragma library

// AppearancePage as data. Generated from the page it replaces.
// Descriptions are written by hand; the inventory carries engineering
// notes, which are not user copy.

var rows = [{
        "tab": "Pointer",
        "group": "CURSOR",
        "key": "cursor.theme",
        "label": "Theme",
        "desc": "From installed icon sets, applies now and to newly opened apps",
        "ctl": "seg",
        "src": "hypr.json",
        "opts": [
            "DYNAMIC"
        ]
    },{
        "tab": "Pointer",
        "group": "CURSOR",
        "key": "cursor.material",
        "label": "Material Bibata",
        "desc": "Swap the pointer for the Bibata cursor recolored in the Ryoku vermillion accent",
        "ctl": "sw",
        "src": "hypr.json"
    },{
        "tab": "Pointer",
        "group": "CURSOR",
        "key": "cursor.size",
        "label": "Size",
        "desc": "How large the pointer is drawn",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 12.0,
        "hi": 64.0,
        "unit": "px"
    },{
        "tab": "Pointer",
        "group": "CURSOR",
        "key": "cursor.inactiveTimeout",
        "label": "Hide after idle",
        "desc": "Seconds of stillness before the pointer hides, 0 never hides",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 0.0,
        "hi": 30.0,
        "unit": "s"
    },{
        "tab": "Pointer",
        "group": "CURSOR",
        "key": "cursor.hideOnKeyPress",
        "label": "Hide while typing",
        "desc": "The pointer vanishes on a keypress and returns when moved",
        "ctl": "sw",
        "src": "hypr.json"
    },{
        "tab": "Motion",
        "group": "MOTION",
        "key": "plugins.dynamicCursors.enabled",
        "label": "Realistic cursor motion",
        "desc": "The pointer tilts, turns, or stretches as it moves, applies on Save",
        "ctl": "sw",
        "src": "hypr.json"
    },{
        "tab": "Motion",
        "group": "MOTION",
        "key": "plugins.dynamicCursors.mode",
        "label": "Style",
        "desc": "Which deformation the motion uses",
        "ctl": "seg",
        "src": "hypr.json",
        "opts": [
            "rotate",
            "tilt",
            "stretch"
        ],
        "when": { "plugins.dynamicCursors.enabled": [true] }
    },{
        "tab": "Motion",
        "group": "MOTION",
        "key": "plugins.dynamicCursors.shake",
        "label": "Shake to find (magnify)",
        "desc": "Shaking the mouse briefly grows the pointer so you can find it",
        "ctl": "sw",
        "src": "hypr.json",
        "when": { "plugins.dynamicCursors.enabled": [true] }
    },{
        "tab": "Motion",
        "group": "MOTION",
        "key": "plugins.dynamicCursors.magnify",
        "label": "Magnify on shake",
        "desc": "How much the cursor grows when you shake it to find it",
        "ctl": "step",
        "src": "hypr.json",
        "lo": 1.0,
        "hi": 10.0,
        "when": { "plugins.dynamicCursors.enabled": [true], "plugins.dynamicCursors.shake": [true] }
    }
];
