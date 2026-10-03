-- Keyboard layout chosen in the Quickshell settings app (Settings > General > Language).
-- Quickshell writes it to
--   ~/.local/state/quickshell/user/generated/hyprland/keyboard.lua
-- and runs `hyprctl reload`. Loaded after the custom files, so the settings app wins.
-- With "Don't change" in the settings (empty file) the layout from hyprland/general.lua or
-- custom/general.lua is kept.

local file = io.open(HOME .. "/.local/state/quickshell/user/generated/hyprland/keyboard.lua", "r")
if file then
    local text = file:read("*a") or ""
    file:close()

    -- Only parsed for key = "value" pairs, never executed
    local kb = {}
    for key, value in text:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
        kb[key] = value
    end

    local function valid(value) return value ~= nil and value:match("^[%w,_:%-]*$") ~= nil end

    if kb.layout and kb.layout ~= "" and valid(kb.layout) and valid(kb.variant or "") then
        local input = { kb_layout = kb.layout, kb_variant = kb.variant or "" }
        if kb.options and kb.options ~= "" and valid(kb.options) then
            -- Keep the user's other xkb options (caps:escape, compose:...), replace only the
            -- layout switch ("grp:") option
            local ok, current = pcall(hl.get_config, "input:kb_options")
            local keep = {}
            if ok and type(current) == "string" and current ~= "[[EMPTY]]" then
                for opt in current:gmatch("[^,]+") do
                    if not opt:match("^grp:") then keep[#keep + 1] = opt end
                end
            end
            keep[#keep + 1] = kb.options
            input.kb_options = table.concat(keep, ",")
        end
        hl.config({ input = input })
    end
end
