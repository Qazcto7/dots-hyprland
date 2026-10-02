-- Title bars with minimize / maximize / close buttons via the hyprbars plugin.
-- Styled like Firefox's own title bar: round grey buttons on the right.
-- One-time setup:  sudo pacman -S hyprpm && hyprpm update && hyprpm add https://github.com/hyprwm/hyprland-plugins && hyprpm enable hyprbars
-- The plugin is loaded by `hyprpm reload` in execs.lua. Loading it reloads the
-- config, so this file runs again and the guard below passes.

if not (hl.plugin and hl.plugin.hyprbars) then
    return
end

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
            on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
        },
    },
})

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
    action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
})
-- Minimize: Hyprland has no real minimize, so the window goes to a hidden
-- special workspace. Clicking its dock icon brings it back.
hl.plugin.hyprbars.add_button({
    bg_color = button_bg,
    fg_color = button_fg,
    size = 24,
    icon = "󰅀", -- nf-md-chevron_down
    action = [[sleep 0.3; hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:minimized", follow = false })']],
})

-- Apps that already draw their own title bar buttons (client-side decorations).
-- Without this they would show two sets of buttons.
hl.window_rule({ match = { class = "^(firefox|org.mozilla.firefox)$" }, ["hyprbars:no_bar"] = true })
