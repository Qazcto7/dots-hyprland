-- Title bars with minimize / maximize / close buttons via the hyprbars plugin.
-- Styled like Firefox's own title bar: round grey buttons on the right.
-- One-time setup:  sudo pacman -S hyprpm && hyprpm update && hyprpm add https://github.com/hyprwm/hyprland-plugins && hyprpm enable hyprbars
-- The plugin is loaded by `hyprpm reload` in execs.lua. Loading it reloads the
-- config, so this file runs again and the guard below passes.

if not (hl.plugin and hl.plugin.hyprbars) then
    return
end

-- Title bars belong to the Plasma-like desktop mode: with floating windows turned off
-- (stock end-4 tiling) the windows get no bars.
-- GTK/Chromium/Electron apps that draw their own title bar (client-side decorations) read
-- which window buttons to draw from this GNOME setting. With hyprbars every window gets our
-- buttons, so theirs are turned off (':' = no buttons); otherwise e.g. Claude desktop or Chrome
-- show a second row of minimize/maximize/close. Set a few seconds late so KDE's GTK settings
-- sync (kded6, started at login) doesn't overwrite it; put back when title bars are off.
local BUTTON_LAYOUT_KEY = "org.gnome.desktop.wm.preferences button-layout"

local mode = require("hyprland.desktop_mode_state")
if not mode.floating then
    hl.config({ plugin = { hyprbars = { enabled = false } } })
    hl.exec_cmd("command -v gsettings >/dev/null && [ \"$(gsettings get " .. BUTTON_LAYOUT_KEY .. ")\" = \"':'\" ] && gsettings reset " .. BUTTON_LAYOUT_KEY)
    return
end
hl.exec_cmd("command -v gsettings >/dev/null && sleep 5 && gsettings set " .. BUTTON_LAYOUT_KEY .. " ':'")

hl.config({
    plugin = {
        hyprbars = {
            bar_height = 36,
            bar_color = "rgba(1d1b20ee)",
            col = { text = "rgba(e6e0e9ff)" },
            inactive_button_color = "rgba(ffffff0f)",
            bar_text_font = "Google Sans Flex",
            bar_text_size = 10,
            bar_text_weight = "medium",
            bar_text_align = "left",
            bar_buttons_alignment = "right",
            bar_padding = 10,
            bar_button_padding = 10,
            bar_part_of_window = true,
            bar_precedence_over_border = true,
            icon_on_hover = false, -- icons always visible
            on_double_click = [[hyprctl eval 'desktop_toggle_maximize()']],
        },
    },
})

-- Maximize (button and double-click) calls desktop_toggle_maximize() from desktop_mode.lua,
-- which needs to know how tall the bar above the window is.
DESKTOP_TITLEBAR_HEIGHT = 36

-- Apps that draw their own window buttons in their own interface (not through GTK, so the
-- setting above doesn't remove them) get no hyprbars bar, otherwise they show two rows of
-- buttons (Discord, Steam, VS Code...). Exact window classes. GTK/GNOME apps and Chromium-based
-- browsers drop their buttons with the setting above and get a hyprbars bar like the others.
local OWN_TITLEBAR_CLASSES = {
    "discord", "vesktop", "WebCord", "legcord", "armcord",
    "Spotify", "spotify", "steam", "obsidian", "Slack", "Element",
    "code", "code-oss", "Code", "codium", "VSCodium",
}
DESKTOP_TITLEBAR_EXCLUDED = {}
local escaped = {}
for _, class in ipairs(OWN_TITLEBAR_CLASSES) do
    DESKTOP_TITLEBAR_EXCLUDED[class] = true
    escaped[#escaped + 1] = (class:gsub("([%.%-])", "\\%1"))
end
hl.window_rule({ match = { class = "^(" .. table.concat(escaped, "|") .. ")$" }, ["hyprbars:no_bar"] = true })

-- Used by desktop_mode.lua (maximize/snap geometry): does this window have a hyprbars bar?
function desktop_has_titlebar(win)
    local class = (win and win.class) or ""
    return not DESKTOP_TITLEBAR_EXCLUDED[class]
end

-- Right alignment: the first button added is the rightmost one.
local button_bg = "rgba(ffffff1f)"
local button_fg = "rgba(e6e0e9ff)"

-- Close
hl.plugin.hyprbars.add_button({
    bg_color = button_bg,
    fg_color = button_fg,
    size = 24,
    icon = "󰅖", -- nf-md-close
    action = [[hyprctl dispatch 'hl.dsp.window.close()']],
})
-- Maximize (toggle)
hl.plugin.hyprbars.add_button({
    bg_color = button_bg,
    fg_color = button_fg,
    size = 24,
    icon = "◇",
    -- Windowed fullscreen (whole screen, the app keeps its normal interface); SUPER + F leaves it.
    -- Double-clicking the title bar still maximizes.
    action = [[hyprctl eval 'desktop_windowed_fullscreen()']],
})
-- Minimize: Hyprland has no real minimize, so the window goes to a hidden
-- special workspace. Clicking its dock icon brings it back.
hl.plugin.hyprbars.add_button({
    bg_color = button_bg,
    fg_color = button_fg,
    size = 24,
    icon = "󰅀", -- nf-md-chevron_down
    -- The short delay lets hyprbars see the button release before the window disappears
    action = [[hyprctl eval 'desktop_minimize(nil, 150)']],
})

-- Firefox uses these title bars too (its own minimize button cannot work on Hyprland).
-- In Firefox set about:config > browser.tabs.inTitlebar = 0 so it does not draw its own buttons.
