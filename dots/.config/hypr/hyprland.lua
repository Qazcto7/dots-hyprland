-- This file sources other files in `hyprland` and `custom` folders
-- You wanna add your stuff in files in `custom`

-- Internal stuff --
require("hyprland.lib")
require("hyprland.services")

-- Version check: these dots target Hyprland >= 0.56.2 --
do
    local MIN_VERSION = { 0, 56, 2 }
    local ok, ver = pcall(function() return hl.version() end)
    if ok and type(ver) == "string" then
        local cur = {}
        for n in ver:gmatch("%d+") do cur[#cur + 1] = tonumber(n) end
        local older = false
        for i = 1, 3 do
            local a, b = cur[i] or 0, MIN_VERSION[i]
            if a ~= b then older = a < b break end
        end
        if older then
            pcall(hl.notification.create, {
                text = "Hyprland " .. ver .. " is older than 0.56.2 - some features of these dotfiles may not work. Please update.",
                duration = 10000,
                icon = "warning",
            })
        end
    end
end

-- Environment variables --
require("hyprland.env")
if is_file_exists(HOME .. "/.config/hypr/custom/env.lua") then
    require("custom.env")
end

-- Default configurations --
require("hyprland.execs")
require("hyprland.general")
require("hyprland.rules")
require("hyprland.colors")
require("hyprland.keybinds")

-- Custom configurations --
if is_file_exists(HOME .. "/.config/hypr/custom/execs.lua") then
    require("custom.execs")
end
if is_file_exists(HOME .. "/.config/hypr/custom/general.lua") then
    require("custom.general")
end
if is_file_exists(HOME .. "/.config/hypr/custom/rules.lua") then
    require("custom.rules")
end
if is_file_exists(HOME .. "/.config/hypr/custom/keybinds.lua") then
    require("custom.keybinds")
end

-- nwg-displays support --
if is_file_exists(HOME .. "/.config/hypr/workspaces.lua") then
    require("workspaces")
end
if is_file_exists(HOME .. "/.config/hypr/monitors.lua") then
    require("monitors")
end

-- Shell overrides --
require("hyprland.shellOverrides.main")
