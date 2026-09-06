const anchorIds = ["bottom", "bottom-left", "bottom-right", "left", "right", "top", "top-left", "top-right"];
const widgets = {
    "audio-input": { id: "audio-input", nested: false },
    "audio-output": { id: "audio-output", nested: false },
    "bluetooth": { id: "bluetooth", nested: false },
    "clipboard": { id: "clipboard", nested: false },
    "clock": { id: "clock", nested: false },
    "container": { id: "container", nested: true },
    "divider": { id: "divider", nested: false },
    "spacer": { id: "spacer", nested: false },
    "network": { id: "network", nested: false },
    "notifications": { id: "notifications", nested: false },
    "power-profile": { id: "power-profile", nested: false },
    "quick-settings": { id: "quick-settings", nested: false },
    "theme": { id: "theme", nested: false },
    "wallpaper": { id: "wallpaper", nested: false },
    "weather": { id: "weather", nested: false },
    "media": { id: "media", nested: false },
    "layout-switcher": { id: "layout-switcher", nested: false },
    "quick-actions": { id: "quick-actions", nested: false }
};
const quickSettingsModules = {
    "home": { id: "home", label: "Home", icon: "space_dashboard", source: "QuickSettingsHome.qml" },
    "notifications": { id: "notifications", label: "Notifications", icon: "notifications", source: "QuickSettingsNotifications.qml" },
    "weather": { id: "weather", label: "Weather", icon: "partly_cloudy_day", source: "QuickSettingsWeather.qml" },
    "capture": { id: "capture", label: "Capture", icon: "screenshot_region", source: "QuickSettingsCapture.qml" },
    "media": { id: "media", label: "Media", icon: "music_note", source: "QuickSettingsMedia.qml" },
    "depth": { id: "depth", label: "Depth", icon: "layers", source: "QuickSettingsDepth.qml" },
    "parallax": { id: "parallax", label: "Parallax", icon: "view_in_ar", source: "QuickSettingsParallax.qml" }
};
const quickSettingsDefaults = ["home", "notifications", "weather", "capture", "depth", "parallax"];
const menus = {
    "quick-settings": { id: "quick-settings", anchor: "left", minWidth: 410, expansion: "always", widgets: ["quick-settings"], modules: quickSettingsDefaults },
    wallpaper: { id: "wallpaper", anchor: "bottom", minWidth: 1400, expansion: "always", widgets: ["theme", "wallpaper"] },
    theme: { id: "theme", anchor: "right", minWidth: 320, expansion: "never", widgets: ["theme"] },
    weather: { id: "weather", anchor: "right", minWidth: 320, expansion: "never", widgets: ["weather"] },
};
const surfaces = {
    "stash": { id: "stash", anchor: "right", minWidth: 340, panes: ["stash"] },
};
const actions = {
    "lock": { id: "lock", action: "lock" }, "logout": { id: "logout", action: "logout" },
    "reboot": { id: "reboot", action: "reboot" }, "shutdown": { id: "shutdown", action: "shutdown" },
    "lens": { id: "lens", action: "lens" }, "color": { id: "color", action: "color" },
    "ocr": { id: "ocr", action: "ocr" }, "qr": { id: "qr", action: "qr" },
    "mirror": { id: "mirror", action: "mirror" }, "clipboard": { id: "clipboard", action: "clipboard" },
    "wifi": { id: "wifi", action: "wifi" }, "bluetooth": { id: "bluetooth", action: "bluetooth" },
    "microphone": { id: "microphone", action: "microphone" }, "do-not-disturb": { id: "do-not-disturb", action: "do-not-disturb" },
    "night-light": { id: "night-light", action: "night-light" }, "keep-awake": { id: "keep-awake", action: "keep-awake" },
    "game-mode": { id: "game-mode", action: "game-mode" }
};

function anchors() { return anchorIds.slice(); }
function widgetIds() { return Object.keys(widgets); }
function widget(id) { return widgets[id] || null; }
function menu(id) { return menus[id] || null; }
function surface(id) { return surfaces[id] || null; }
function quickAction(id) { return actions[id] || null; }
function quickActionIds() { return Object.keys(actions); }
function quickSettingsModuleIds() { return Object.keys(quickSettingsModules); }
function quickSettingsModule(id) { return quickSettingsModules[id] || null; }
function defaultQuickSettingsModules() { return quickSettingsDefaults.slice(); }

if (typeof module !== "undefined" && module.exports) module.exports = {
    anchors, widgetIds, widget, menu, surface, quickAction, quickActionIds,
    quickSettingsModuleIds, quickSettingsModule, defaultQuickSettingsModules
};
