-- A floating window sized past the monitor reads as a broken fullscreen (issue
-- 147: Files on a 1366x768 panel). Every fixed size below is capped to the
-- monitor the window opens on; Hyprland evaluates the expressions per window.
local function fit(w, h)
    return {
        "min(" .. w .. ", monitor_w * 0.92)",
        "min(" .. h .. ", monitor_h * 0.88)",
    }
end

hl.window_rule({
    name           = "suppress-maximize",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

hl.window_rule({
    name  = "float-system-dialogs",
    match = { class = "(pavucontrol|nm-connection-editor|blueman-manager|org.kde.polkit-kde-authentication-agent-1|xdg-desktop-portal-gtk)" },
    float = true,
})

hl.window_rule({
    name   = "float-polkit-agent",
    match  = { class = "hyprpolkitagent" },
    float  = true,
    center = true,
})

hl.window_rule({
    name  = "float-file-pickers",
    match = { title = "(Open File|Save File|Save As|Choose Files|Open Folder)" },
    float = true,
})

hl.window_rule({
    name  = "float-ghosttype",
    match = { class = "Ghosttype-app" },
    float = true,
})

hl.window_rule({
    name  = "float-spotify",
    match = { class = "[Ss]potify" },
    float = true,
})

hl.window_rule({
    name   = "float-nautilus",
    match  = { class = "org.gnome.Nautilus" },
    float  = true,
    size   = fit(1500, 850),
    center = true,
})

hl.window_rule({
	name   = "float-ryoku-settings",
	match  = { title = "^(Ryoku Settings)$" },
	float  = true,
	size   = fit(1360, 880),
	center = true,
})

hl.window_rule({
    name   = "float-ryostore",
    match  = { title = "^(Ryostore)$" },
    float  = true,
    size   = fit(1180, 760),
    center = true,
})

hl.window_rule({
    name   = "float-ryovm",
    match  = { title = "^(ryovm)$" },
    float  = true,
    size   = fit(1180, 760),
    center = true,
    -- qs paints its first frame slowly on this hybrid GPU (Mesa falls back off
    -- the NVIDIA node), so the pop-in would reveal the uninitialised surface as
    -- horizontal streaks; skip it and the (opaque, see shell.qml) window snaps in.
    no_anim = true,
})

hl.window_rule({
    name   = "float-ryoport-ssh",
    match  = { class = "ryoport-ssh" },
    float  = true,
    size   = fit(900, 560),
    center = true,
})

hl.window_rule({
    name   = "float-ryoport-console",
    match  = { class = "spicy" },
    float  = true,
    center = true,
})

hl.window_rule({
    name   = "float-ryostore",
    match  = { class = "ryostore" },
    float  = true,
    size   = fit(900, 600),
    center = true,
})

hl.window_rule({
    name   = "float-ryoku-rashin-setup",
    match  = { class = "ryoku-rashin-setup" },
    float  = true,
    size   = fit(900, 600),
    center = true,
})

hl.window_rule({
    name   = "float-looking-glass",
    match  = { class = "looking-glass-client" },
    float  = true,
    size   = fit(1600, 900),
    center = true,
})

hl.window_rule({
    name   = "float-qemu",
    match  = { class = "[Qq]emu" },
    float  = true,
    size   = fit(1280, 800),
    center = true,
})

hl.window_rule({
    name   = "float-ryoku-welcome",
    match  = { title = "^(Welcome to Ryoku)$" },
    float  = true,
    size   = fit(1180, 760),
    center = true,
})

-- Steam is an XWayland app: Big Picture and the client (both class "steam"),
-- launched games (steam_app_<id>) and gamescope otherwise inherit the desktop's
-- blur and shadow (per-frame GPU cost, a floating-card look) and the 0.94
-- inactive opacity, which turns a game translucent the moment focus leaves it.
-- Strip that chrome and force them opaque so they read like a native fullscreen
-- app, and inhibit idle while fullscreen so controller-only play never dims or
-- locks (hypridle has no fullscreen exception). steamwebhelper stays untouched.
hl.window_rule({
    name         = "steam-native",
    match        = { class = "^(steam|steam_app_.*|gamescope)$" },
    no_blur      = true,
    no_shadow    = true,
    opaque       = true,
    idle_inhibit = "fullscreen",
    -- low-latency presentation: let an unthrottled fullscreen game tear instead
    -- of vsyncing through the compositor, which cuts input lag and the frame-time
    -- hit when the Steam overlay composites on top. Pairs with
    -- general.allow_tearing; Game Mode already forces this path at runtime.
    immediate    = true,
})

-- Ryotunes, the music app ([ryoku] package, ryoku-dev/ryotunes). Float it like
-- the other music players (Spotify above); the app sizes and centres its own
-- floating window. The Tauri app maps with class "ryotunes"; the native
-- Quickshell client (ryotunes-qml) maps with Quickshell's class and the title
-- "Ryotunes" (its mini player is "Ryotunes Mini", which stays tiled).
hl.window_rule({
    name  = "float-ryotunes",
    match = { class = "^ryotunes$" },
    float = true,
})
hl.window_rule({
    name  = "float-ryotunes-qml",
    match = { class = "^org\\.quickshell$", title = "^Ryotunes$" },
    float = true,
})

-- Chromium's "<site> is sharing a window." bar. On native Wayland it maps with an
-- empty app_id and its geometry computed against the wrong work area (Chromium
-- 517327175), so it lands mid-screen and takes no pointer input at all: verified
-- with the cursor on Stop sharing and on Hide, neither fires. Hyprland's Lua
-- rules have no positioning key, so parking it on a special workspace nobody
-- opens is the only way to stop a dead widget covering the desktop. Chromium's
-- own tab indicator and the site's stop control still show a capture is live.
-- The patterns are FULL matches, not searches, hence the .* on both ends.
hl.window_rule({
    name  = "park-chromium-share-indicator",
    match = {
        class = "^$",
        title = "^(.*is sharing.*)$",
    },
    -- "silent" is load-bearing: without it the rule OPENS special:sharebar on the
    -- monitor and the bar stays on screen, parked but visible.
    workspace = "special:sharebar silent",
    no_focus  = true,
})
