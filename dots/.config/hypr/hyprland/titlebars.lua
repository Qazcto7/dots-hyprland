-- macOS-style title bars (close / minimize / maximize) via the hyprbars plugin.
-- One-time setup:  hyprpm update && hyprpm add https://github.com/hyprwm/hyprland-plugins && hyprpm enable hyprbars
-- The plugin is loaded by `hyprpm reload` in execs.lua. Loading it reloads the
-- config, so this file runs again and the guard below passes.

if not (hl.plugin and hl.plugin.hyprbars) then
    return
end

hl.config({
    plugin = {
        hyprbars = {
            bar_height = 28,
            bar_color = "rgba(1d1b20ee)",
            col = { text = "rgba(e6e0e9ff)" },
            inactive_button_color = "rgba(5a5560ff)",
            bar_text_font = "Google Sans Flex",
            bar_text_size = 10,
            bar_text_weight = "medium",
            bar_text_align = "center",
            bar_buttons_alignment = "left", -- macOS: buttons on the left
            bar_padding = 12,
            bar_button_padding = 8,
            bar_part_of_window = true,
            bar_precedence_over_border = true,
            icon_on_hover = true, -- macOS: symbols only appear on hover
            on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
        },
    },
})

-- With left alignment the first button added is the leftmost one.
-- Close
hl.plugin.hyprbars.add_button({
    bg_color = "rgb(ff5f57)",
    fg_color = "rgb(4d0000)",
    size = 13,
    icon = "×",
    action = [[hyprctl dispatch 'hl.dsp.window.close()']],
})
-- Minimize: Hyprland has no real minimize, so the window goes to a hidden
-- special workspace. Clicking its dock icon brings it back.
hl.plugin.hyprbars.add_button({
    bg_color = "rgb(febc2e)",
    fg_color = "rgb(5a3e00)",
    size = 13,
    icon = "−",
    action = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:minimized", follow = false })']],
})
-- Maximize (toggle)
hl.plugin.hyprbars.add_button({
    bg_color = "rgb(28c840)",
    fg_color = "rgb(004d00)",
    size = 13,
    icon = "+",
    action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
})
