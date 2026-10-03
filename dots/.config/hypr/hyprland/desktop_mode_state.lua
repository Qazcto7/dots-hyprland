-- Reads the desktop-mode settings written by Quickshell (Settings > Interface > Desktop mode):
--   ~/.local/state/quickshell/user/generated/hyprland/desktop_mode.lua
-- Shared by desktop_mode.lua and titlebars.lua. The file is only parsed for
-- "key = true/false" pairs, never executed.

local defaults = { floating = true, snap = true, kde_services = true, alt_tab = true, snap_zones = true, auto_game_mode = true }

local mode = {}
local file = io.open(HOME .. "/.local/state/quickshell/user/generated/hyprland/desktop_mode.lua", "r")
if file then
    local text = file:read("*a") or ""
    file:close()
    for key, value in text:gmatch("([%w_]+)%s*=%s*(%a+)") do
        if value == "true" then mode[key] = true elseif value == "false" then mode[key] = false end
    end
end
for key, value in pairs(defaults) do
    if mode[key] == nil then
        mode[key] = value
    end
end

return mode
