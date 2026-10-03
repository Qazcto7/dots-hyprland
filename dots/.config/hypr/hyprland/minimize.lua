local MINIMIZED = "special:minimized"

-- Minimize = move to a hidden special workspace. Used by SUPER + H and the title bar button.
-- `delay_ms` lets the title bar button release its click before the window disappears (otherwise
-- hyprbars misses the release); the window is taken at click time, so moving the mouse onto
-- another window during the delay doesn't minimize that one instead.
function desktop_minimize(win, delay_ms)
    win = win or hl.get_active_window()
    if not win then return end
    local function go()
        if win.address and win.workspace and win.workspace.name ~= MINIMIZED then
            hl.dispatch(hl.dsp.window.move({ workspace = MINIMIZED, follow = false, window = win }))
        end
    end
    if delay_ms and delay_ms > 0 then
        hl.timer(go, { timeout = delay_ms, type = "oneshot" })
    else
        go()
    end
end

hl.bind("SUPER + H", function() desktop_minimize() end, { description = "Window: Minimize" })

-- Activating a minimized window (dock, Alt+Tab, app activation request) brings it back to the
-- current workspace of its monitor. Done on a short timer: focusing it makes Hyprland open the
-- special workspace, and closing that again from inside the same event leaves Hyprland (and
-- its IPC listeners) thinking it is still open.
hl.on("window.active", function(win)
    if not win or not win.workspace or win.workspace.name ~= MINIMIZED then return end
    hl.timer(function()
        if not win.address or not win.workspace or win.workspace.name ~= MINIMIZED then return end

        local mon = win.monitor
        local target = mon and mon.active_workspace
        if not target then return end

        local special = mon.active_special_workspace
        if special and special.name == MINIMIZED then
            hl.dispatch(hl.dsp.workspace.toggle_special("minimized"))
        end

        -- Named workspaces have negative ids, which would be read as a relative offset
        local workspace = (target.id or 0) > 0 and tostring(target.id) or ("name:" .. target.name)
        hl.dispatch(hl.dsp.window.move({ workspace = workspace, follow = false, window = win }))
        hl.dispatch(hl.dsp.focus({ window = win }))
    end, { timeout = 1, type = "oneshot" })
end)
