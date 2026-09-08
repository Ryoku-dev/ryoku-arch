local M = {}
local states = {}
local serial = 0

local function read(fn)
    local ok, value = pcall(fn)
    if ok then return value end
end

local function window()
    return read(function() return hl.get_active_window() end)
end

local function scrolling(w)
    local ws = read(function() return hl.get_active_workspace() end)
    return ws and ws.tiled_layout == "scrolling"
end

local function width(w)
    local value = read(function() return w.layout.column.width end)
    if type(value) == "number" and value >= 0.1 and value <= 1 then return value end
end

local function colresize(value)
    hl.dispatch(hl.dsp.layout("colresize " .. string.format("%.10g", value)))
end

local function state(w)
    local id = w.address
    if not id then return {} end
    if not states[id] then
        -- Bound retention on older compositors without lifecycle callbacks.
        local count, oldest = 0, nil
        for key, saved in pairs(states) do
            count = count + 1
            if not oldest or saved.used < states[oldest].used then oldest = key end
        end
        if count >= 128 then states[oldest] = nil end
        states[id] = {}
    end
    serial = serial + 1
    states[id].used = serial
    return states[id]
end

local function forget(w)
    local id = read(function() return w.address end)
    if id then states[id] = nil end
end

for _, event in ipairs({ "window.close", "window.move_to_workspace" }) do
    if hl.on then pcall(hl.on, event, forget) end
end

function M.toggle_width()
    local w = window()
    if not w or w.floating or not scrolling(w) or not hl.dsp.layout then return end
    local current = width(w)
    if not current or not w.address then return end
    local saved = state(w)
    if math.abs(current - 1) < 0.000001 then
        if saved.expanded then colresize(saved.expanded) end
        saved.expanded = nil
    else
        -- Read the column fraction, not animated pixels or a remembered default.
        saved.expanded = current
        colresize(1)
    end
end

function M.toggle_float()
    local w = window()
    if not w then return end
    local saved = state(w)
    if w.floating then
        hl.dispatch(hl.dsp.window.float({ action = "disable" }))
        if saved.floated and scrolling(w) and hl.dsp.layout then colresize(saved.floated) end
        saved.floated = nil
    else
        saved.floated = scrolling(w) and width(w) or nil
        if saved.floated ~= 1 then saved.expanded = nil end
        hl.dispatch(hl.dsp.window.float({ action = "enable" }))
        hl.dispatch(hl.dsp.window.resize({ x = 1000, y = 660, relative = false }))
        hl.dispatch(hl.dsp.window.center())
    end
end

function M.resize(direction)
    local w = window()
    if not w then return end
    state(w).expanded = nil
    if not w.floating and scrolling(w) and hl.dsp.layout then
        hl.dispatch(hl.dsp.layout(direction < 0 and "colresize -0.02" or "colresize +0.02"))
    else
        hl.dispatch(hl.dsp.window.resize({ x = direction * 40, y = 0, relative = true }))
    end
end

function M.focus(direction)
    local w = window()
    if w and not w.floating and scrolling(w) and hl.dsp.layout then
        hl.dispatch(hl.dsp.layout(direction < 0 and "focus l" or "focus r"))
    end
end

return M
