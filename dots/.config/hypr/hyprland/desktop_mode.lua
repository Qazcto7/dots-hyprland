-- Plasma-like "desktop mode", controlled from the Quickshell settings app
-- (Settings > Interface > Desktop mode). Quickshell writes the chosen values to
--   ~/.local/state/quickshell/user/generated/hyprland/desktop_mode.lua
-- and runs `hyprctl reload`. Turning everything off gives the stock end-4 behavior.

local defaults = { floating = true, snap = true, kde_services = true }

local mode = {}
local ok, generated = pcall(dofile, HOME .. "/.local/state/quickshell/user/generated/hyprland/desktop_mode.lua")
if ok and type(generated) == "table" then
    mode = generated
end
for key, value in pairs(defaults) do
    if mode[key] == nil then
        mode[key] = value
    end
end

-- Floating windows: new windows open centered and free-floating instead of tiled.
-- SUPER + ALT + Space still toggles float/tile for a single window.
if mode.floating then
    hl.window_rule({ match = { class = ".*" }, float = true })
    hl.window_rule({ match = { class = ".*" }, center = true })
    hl.config({ cursor = { no_warps = true } }) -- Plasma-like: focusing a window never moves the mouse
end

-- Snap floating windows to screen edges and to each other while dragging
if mode.snap then
    hl.config({
        general = {
            snap = {
                enabled = true,
                window_gap = 10,
                monitor_gap = 10,
                respect_gaps = true,
            },
        },
    })
end

-- KDE background services (Bluetooth / network integration for KDE settings modules)
-- and a shortcut for KDE System Settings with all modules visible.
if mode.kde_services then
    hl.on("hyprland.start", function()
        hl.exec_cmd("kded6")
    end)
    hl.bind("SUPER + CTRL + I", hl.dsp.exec_cmd("env XDG_CURRENT_DESKTOP=KDE systemsettings"),
        { description = "App: KDE System Settings" })
end

-- Plasma-like maximize for floating windows: the window is resized to fill the free area
-- (between bar and dock) and stays a normal floating window, so other windows on top of it
-- still get mouse focus. Hyprland's own "maximized" mode is a fullscreen state that blocks
-- focus-follows-mouse for every other window. Doing it again restores the previous geometry.
-- Used by the title bar's maximize button / double-click (hyprctl eval 'desktop_toggle_maximize()'),
-- and in floating mode every Hyprland maximize (SUPER + D, an app's own maximize button) is
-- converted to this one.
local FS_MAXIMIZED = 1
local maximizedGeometry = {}

local function geometricMaximizeToggle(win)
    local key = win.address
    local saved = maximizedGeometry[key]
    if saved then
        maximizedGeometry[key] = nil
        hl.dispatch(hl.dsp.window.resize({ x = saved.w, y = saved.h, window = win }))
        hl.dispatch(hl.dsp.window.move({ x = saved.x, y = saved.y, window = win }))
        return
    end

    local mon = win.monitor
    if not mon then return end
    local scale = mon.scale or 1
    local reserved = mon.reserved or { top = 0, right = 0, bottom = 0, left = 0 }
    local border = tonumber(hl.get_config("general:border_size")) or 1
    local gap = 6
    local bar = 0
    if DESKTOP_TITLEBAR_HEIGHT and not (DESKTOP_TITLEBAR_EXCLUDED or {})[win.class] then
        bar = DESKTOP_TITLEBAR_HEIGHT
    end

    local areaX = mon.x + reserved.left
    local areaY = mon.y + reserved.top
    local areaW = mon.width / scale - reserved.left - reserved.right
    local areaH = mon.height / scale - reserved.top - reserved.bottom

    maximizedGeometry[key] = { x = win.at.x, y = win.at.y, w = win.size.x, h = win.size.y }
    -- Resize first: Hyprland resizes floating windows around their center and keeps them on
    -- screen, which would shift an already-moved window. Then move to the exact position.
    hl.dispatch(hl.dsp.window.resize({
        x = math.floor(areaW - 2 * (gap + border)),
        y = math.floor(areaH - 2 * (gap + border) - bar),
        window = win,
    }))
    hl.dispatch(hl.dsp.window.move({ x = areaX + gap + border, y = areaY + gap + border + bar, window = win }))
end

function desktop_toggle_maximize(win)
    win = win or hl.get_active_window()
    if not win then return end
    local fs = win.fullscreen or 0

    -- Real fullscreen (SUPER + F): just leave it
    if fs ~= 0 and fs ~= FS_MAXIMIZED then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset", window = win }))
        return
    end

    -- Tiled windows, or floating mode off: Hyprland's maximize as before
    if not (mode.floating and win.floating) then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = win }))
        return
    end

    if fs == FS_MAXIMIZED then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = win }))
    end
    geometricMaximizeToggle(win)
end

if mode.floating then
    hl.on("window.fullscreen", function(win)
        if not win or not win.floating or win.fullscreen ~= FS_MAXIMIZED then return end
        -- Let Hyprland finish its own fullscreen change before undoing it
        hl.timer(function()
            if not win.address or win.fullscreen ~= FS_MAXIMIZED then return end
            desktop_toggle_maximize(win)
        end, { timeout = 30, type = "oneshot" })
    end)
end
