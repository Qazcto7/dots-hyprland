local MINIMIZED = "special:minimized"

-- Minimize = move to a hidden special workspace. Used by SUPER + H, the title bar button and the
-- dock (through `hyprctl eval`). Animated macOS-like: the window fades out while sliding down
-- towards the dock, then it is hidden; bringing it back (dock, Alt+Tab...) slides it up to where
-- it was while it fades in.
-- `delay_ms` lets the title bar button release its click before the window moves away (otherwise
-- hyprbars misses the release); the window is taken at click time, so moving the mouse onto
-- another window during the delay doesn't minimize that one instead.
local ANIM_MS = 260 -- matches the fadeSwitch / windowsMove animations below
-- address -> { x, y } where the window was before minimizing. Kept in a file so it survives
-- `hyprctl reload` (a reload starts a fresh Lua state); addresses stay the same all session.
local FROM_FILE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-desktop-minimized-"
    .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "default")
local minimizedFrom = {}
do
    local f = io.open(FROM_FILE, "r")
    if f then
        for line in f:lines() do
            local addr, x, y = line:match("^(%S+) (%-?%d+) (%-?%d+)$")
            if addr then minimizedFrom[addr] = { x = tonumber(x), y = tonumber(y) } end
        end
        f:close()
    end
end
local function saveMinimizedFrom()
    local f = io.open(FROM_FILE, "w")
    if not f then return end
    for addr, p in pairs(minimizedFrom) do
        f:write(string.format("%s %d %d\n", addr, p.x, p.y))
    end
    f:close()
end
local animating = {} -- address -> true while the minimize animation runs

-- Opacity fades use "fadeSwitch" (only used for active/inactive opacity otherwise, which is 1 for
-- both here). Without its own config it would inherit the slow global speed.
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.6, bezier = "emphasizedDecel" })

local function setOpacity(win, value)
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = value, window = win }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_inactive", value = value, window = win }))
end

-- Where the minimize animation takes the window: down to the dock (bottom middle of the screen),
-- mostly below the screen edge
local function dockTarget(win)
    local mon, at, size = win.monitor, win.at, win.size
    if not mon or not at or not size then return nil end
    local scale = mon.scale or 1
    local monW, monH = mon.width, mon.height
    if (mon.transform or 0) % 2 == 1 then monW, monH = monH, monW end
    monW, monH = monW / scale, monH / scale
    local centerX = mon.x + monW / 2
    local x = at.x + ((centerX - size.x / 2) - at.x) * 0.5
    local y = mon.y + monH - size.y * 0.3
    return math.floor(x), math.floor(math.max(y, at.y + 80))
end

-- After minimizing, the keyboard focus can stay on the hidden window (with click to focus
-- nothing takes it). Give it to the most recently used window still on screen instead.
local function focusNextWindow(win, mon)
    local active = hl.get_active_window()
    if not active or active.address ~= win.address then return end
    local ws = mon and mon.active_workspace
    if not ws then return end
    local best
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.address ~= win.address and w.mapped and not w.hidden and w.workspace and w.workspace.id == ws.id
            and (not best or (tonumber(w.focus_history_id) or 9999) < (tonumber(best.focus_history_id) or 9999)) then
            best = w
        end
    end
    if best then hl.dispatch(hl.dsp.focus({ window = best })) end
end

local function animated(win)
    local enabled = hl.get_config("animations:enabled")
    return win.floating and (tonumber(win.fullscreen) or 0) == 0
        and enabled ~= false and enabled ~= 0 and enabled ~= "0" and enabled ~= "false"
end

function desktop_minimize(win, delay_ms)
    win = win or hl.get_active_window()
    if not win or not win.address or animating[win.address] then return end
    local function hide()
        animating[win.address] = nil
        if win.address and win.workspace and win.workspace.name ~= MINIMIZED then
            local mon = win.monitor
            hl.dispatch(hl.dsp.window.move({ workspace = MINIMIZED, follow = false, window = win }))
            hl.timer(function() focusNextWindow(win, mon) end, { timeout = 1, type = "oneshot" })
        end
    end
    local function go()
        if not win.address or not win.workspace or win.workspace.name == MINIMIZED then return end
        if not animated(win) then
            hide()
            return
        end
        animating[win.address] = true
        minimizedFrom[win.address] = { x = math.floor(win.at.x), y = math.floor(win.at.y) }
        saveMinimizedFrom()
        setOpacity(win, "0")
        local x, y = dockTarget(win)
        if x then
            hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = win }))
        end
        hl.timer(hide, { timeout = ANIM_MS, type = "oneshot" })
    end
    if delay_ms and delay_ms > 0 then
        hl.timer(go, { timeout = delay_ms, type = "oneshot" })
    else
        go()
    end
end

-- Same, by address (for Quickshell's dock: hyprctl eval 'desktop_minimize_address("0x...")')
function desktop_minimize_address(address)
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.address == address then
            desktop_minimize(w)
            return
        end
    end
end

-- A window leaving the minimized workspace (however it is brought back) slides up to where it was
-- and fades in. Done on a short timer, after the move that brought it back has finished.
hl.on("window.move_to_workspace", function(win, ws)
    if not win or not win.address or not ws or ws.name == MINIMIZED then return end
    local from = minimizedFrom[win.address]
    if from then
        minimizedFrom[win.address] = nil
        saveMinimizedFrom()
    end
    hl.timer(function()
        if not win.address then return end
        -- Always made visible again, even without a saved position
        if from and win.floating and (tonumber(win.fullscreen) or 0) == 0 then
            hl.dispatch(hl.dsp.window.move({ x = from.x, y = from.y, window = win }))
        end
        setOpacity(win, "1")
    end, { timeout = 1, type = "oneshot" })
end)

hl.on("window.close", function(win)
    if win and win.address then
        if minimizedFrom[win.address] then
            minimizedFrom[win.address] = nil
            saveMinimizedFrom()
        end
        animating[win.address] = nil
    end
end)

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
