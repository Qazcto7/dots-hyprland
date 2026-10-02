
local MINIMIZED = "special:minimized"

hl.bind("SUPER + H", hl.dsp.window.move({ workspace = MINIMIZED, follow = false }),
    { description = "Window: Minimize" })

hl.on("window.active", function(win)
    if not win then return end
    local ws = win.workspace
    if not ws or ws.name ~= MINIMIZED then return end

    local mon = win.monitor
    local target = mon and mon.active_workspace
    if not target then return end

    local special = mon.active_special_workspace
    if special and special.name == MINIMIZED then
        hl.dispatch(hl.dsp.workspace.toggle_special("minimized"))
    end

    hl.dispatch(hl.dsp.window.move({ workspace = tostring(target.id), follow = false, window = win }))
    hl.dispatch(hl.dsp.focus({ window = win }))
end)
