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
