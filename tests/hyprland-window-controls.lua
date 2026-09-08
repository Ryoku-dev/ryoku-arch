package.path = "ryoku/hyprland/?.lua;" .. package.path

local calls, events, active, workspace, controls
local function eq(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end
local function reset(width, layout)
    calls, events = {}, {}
    workspace = { id = 1, tiled_layout = layout or "scrolling" }
    active = { address = "0x1", floating = false, size = { x = 800, y = 700 },
        layout = { column = { width = width or 0.42 } } }
    hl = {
        get_active_window = function() return active end,
        get_active_workspace = function() return workspace end,
        on = function(event, callback) events[event] = callback end,
        dsp = { window = {} },
        dispatch = function(action)
            calls[#calls + 1] = action
            if action.kind == "layout" then
                local value = action.arg:match("^colresize (.+)$")
                if value then
                    local n = tonumber(value)
                    if value:match("^[+-]") then n = active.layout.column.width + n end
                    active.layout.column.width = n
                end
            elseif action.kind == "float" then
                active.floating = not active.floating
                if not active.floating then active.layout.column.width = 0.5 end
            end
        end,
    }
    hl.dsp.layout = function(arg) return { kind = "layout", arg = arg } end
    for _, name in ipairs({ "float", "resize", "center", "cycle_next" }) do
        hl.dsp.window[name] = function(arg) return { kind = name, arg = arg } end
    end
    controls = dofile("ryoku/hyprland/modules/window_controls.lua")
end

reset()
controls.toggle_float()
eq(active.floating, true)
eq(#calls, 3)
eq(calls[2].kind, "resize")
eq(calls[2].arg.x, 1000)
eq(calls[2].arg.y, 660)
eq(calls[2].arg.relative, false)
eq(calls[3].kind, "center")
controls.toggle_float()
eq(active.floating, false)
eq(#calls, 5)
eq(calls[4].kind, "float")
eq(calls[5].kind, "layout")
eq(active.layout.column.width, 0.42)
print("ok: float enters centered and restores column without pixel resize on return")

reset()
controls.toggle_width()
eq(active.layout.column.width, 1)
controls.toggle_width()
eq(active.layout.column.width, 0.42)
active.layout.column.width = 0.63
controls.toggle_width()
controls.toggle_width()
eq(active.layout.column.width, 0.63)
controls.toggle_width()
active.layout.column.width = 0.72 -- A mouse resize supersedes the old expansion.
controls.toggle_width()
eq(active.layout.column.width, 1)
controls.toggle_width()
eq(active.layout.column.width, 0.72)
print("ok: full width restores the immediate fraction, including manual resizes")

reset(0.37)
controls.toggle_width()
controls.toggle_float()
controls.toggle_float()
eq(active.layout.column.width, 1)
controls.toggle_width()
eq(active.layout.column.width, 0.37)
print("ok: floating an expanded column preserves both return widths")

for _, event in ipairs({ "window.close", "window.move_to_workspace" }) do
    reset(0.37)
    controls.toggle_width()
    events[event](active)
    controls.toggle_width()
    eq(active.layout.column.width, 1)
    reset(0.37)
    controls.toggle_float()
    events[event](active)
    controls.toggle_float()
    eq(active.layout.column.width, 0.5)
end
print("ok: closed and moved windows cannot inherit old saved widths")

reset(0.42)
controls.toggle_width()
controls.resize(-1)
eq(calls[#calls].arg, "colresize -0.02")
controls.resize(1)
eq(calls[#calls].arg, "colresize +0.02")
controls.toggle_width()
eq(active.layout.column.width, 1) -- Resizing cancels the expansion transaction.
controls.focus(-1)
eq(calls[#calls].arg, "focus l")
controls.focus(1)
eq(calls[#calls].arg, "focus r")
print("ok: resize uses animated layout dispatch in both directions; focus stays in layout")

for _, layout in ipairs({ "dwindle", "master", "monocle" }) do
    reset(0.42, layout)
    controls.toggle_width()
    controls.focus(1)
    eq(#calls, 0)
    controls.resize(-1)
    eq(calls[1].kind, "resize")
    eq(calls[1].arg.x, -40)
    eq(calls[1].arg.relative, true)
    controls.toggle_float()
    controls.toggle_float()
    eq(calls[#calls].kind, "float")
end
reset()
active.floating = true
controls.toggle_width()
controls.focus(1)
eq(#calls, 0)
controls.resize(1)
eq(calls[1].arg.x, 40)
print("ok: other layouts and floating windows keep pixel resizing")

reset(0.31)
local first = active
controls.toggle_width()
active = { address = "0x2", floating = false, layout = { column = { width = 0.67 } } }
controls.toggle_width()
controls.toggle_width()
eq(active.layout.column.width, 0.67)
active = first
controls.toggle_width()
eq(active.layout.column.width, 0.31)
print("ok: per-window expansion state is isolated")

reset()
active = nil
controls.toggle_width()
controls.toggle_float()
controls.resize(1)
controls.focus(1)
eq(#calls, 0)
reset()
hl.get_active_window = nil
controls.toggle_float()
controls.toggle_width()
controls.resize(1)
controls.focus(1)
eq(#calls, 0)
for _, bad in ipairs({ false, "0.5", 0, -1, 2, math.huge, 0/0 }) do
    reset()
    active.layout.column.width = bad
    controls.toggle_width()
    eq(#calls, 0)
end
reset()
active.layout = nil
controls.toggle_width()
eq(#calls, 0)
reset()
hl.dsp.layout = nil
controls.toggle_width()
controls.focus(1)
controls.resize(1)
eq(#calls, 1)
eq(calls[1].kind, "resize")
reset()
hl.get_active_workspace = function() error("unsupported") end
controls.toggle_width()
controls.resize(1)
eq(#calls, 1)
eq(calls[1].kind, "resize")
print("ok: absent windows, invalid widths and unavailable APIs degrade safely")

reset(0.31)
hl.on = nil
controls = dofile("ryoku/hyprland/modules/window_controls.lua")
local oldest = active
controls.toggle_width()
for i = 2, 130 do
    active = { address = "0x" .. i, floating = false, layout = { column = { width = 0.42 } } }
    controls.toggle_width()
end
active = oldest
controls.toggle_width()
eq(active.layout.column.width, 1)
print("ok: state is bounded even when lifecycle events are unavailable")

for _, rebound in ipairs({ false, true }) do
    reset()
    local binds = {}
    hl.bind = function(chord, action, options)
        assert(not binds[chord], "duplicate binding: " .. chord)
        binds[chord] = { action = action, options = options or {} }
    end
    local function dispatcher(_, name)
        return function(arg) return { kind = name, arg = arg } end
    end
    setmetatable(hl.dsp, { __index = dispatcher })
    setmetatable(hl.dsp.window, { __index = dispatcher })
    local chords = { "ALT + Tab", "ALT + SHIFT + Tab", "SUPER + ALT + F", "SUPER + A",
        "SUPER + CTRL + Left", "SUPER + CTRL + Right",
        "SUPER + SHIFT + mouse_up", "SUPER + SHIFT + mouse_down" }
    local rebinds = {}
    if rebound then
        for i, chord in ipairs(chords) do rebinds[chord] = "SUPER + F" .. i end
    end
    package.loaded.rebinds = rebinds
    package.loaded["modules.window_controls"] = controls
    dofile("ryoku/hyprland/modules/binds.lua")
    local function bound(chord) return assert(binds[rebinds[chord] or chord]) end
    if rebound then for _, chord in ipairs(chords) do eq(binds[chord], nil) end end
    eq(bound("ALT + Tab").action.kind, "cycle_next")
    eq(bound("ALT + Tab").action.arg.next, true)
    eq(bound("ALT + SHIFT + Tab").action.arg.next, false)
    bound("SUPER + ALT + F").action()
    eq(active.layout.column.width, 1)
    bound("SUPER + A").action()
    eq(active.floating, true)
    bound("SUPER + A").action()
    eq(active.layout.column.width, 1)
    for _, side in ipairs({ "Left", "Right" }) do
        local b = bound("SUPER + CTRL + " .. side)
        eq(b.options.repeating, true)
        b.action()
        eq(calls[#calls].arg, side == "Left" and "colresize -0.02" or "colresize +0.02")
    end
    bound("SUPER + SHIFT + mouse_up").action()
    eq(calls[#calls].arg, "focus l")
    bound("SUPER + SHIFT + mouse_down").action()
    eq(calls[#calls].arg, "focus r")
    eq(binds["SUPER + mouse_up"].action.arg.workspace, "r-1")
    eq(binds["SUPER + CTRL + Up"].action.arg.y, -40)
    eq(binds["SUPER + Tab"].action.arg, "ryoku:overview")
end
print("ok: shipped binds cycle, repeat and retain System rebinding and existing shortcuts")
