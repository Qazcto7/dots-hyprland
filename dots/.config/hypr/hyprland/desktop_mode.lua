-- Plasma-like "desktop mode", controlled from the Quickshell settings app
-- (Settings > Interface > Desktop mode). Quickshell writes the chosen values to
--   ~/.local/state/quickshell/user/generated/hyprland/desktop_mode.lua
-- and runs `hyprctl reload`. Turning everything off gives the stock end-4 behavior.

local mode = require("hyprland.desktop_mode_state")

-- Floating windows: new windows open centered and free-floating instead of tiled.
-- SUPER + ALT + Space still toggles float/tile for a single window.
if mode.floating then
    -- (No global center rule: the floating layout already centers windows that don't ask for a
    -- position, and a center rule would override the PiP / screen-share placement rules.)
    hl.window_rule({ match = { class = ".*" }, float = true })
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
    -- kded6's own tray watcher (statusnotifierwatcher) is unloaded in this session: Quickshell's
    -- bar provides the system tray. Only unloaded at runtime, so Plasma sessions are unaffected.
    local KDED = "(pgrep -x kded6 >/dev/null || kded6) & sleep 3; "
        .. "busctl --user call org.kde.kded6 /kded org.kde.kded6 unloadModule s statusnotifierwatcher >/dev/null 2>&1"
    -- At login it must wait for the session environment (WAYLAND_DISPLAY, D-Bus) to be ready.
    -- On a reload (e.g. the setting was just turned on) the session is running: start it now.
    if os.getenv("WAYLAND_DISPLAY") then
        hl.exec_cmd(KDED)
    else
        hl.on("hyprland.start", function()
            hl.exec_cmd(KDED)
        end)
    end
    hl.bind("SUPER + CTRL + I", hl.dsp.exec_cmd("env XDG_CURRENT_DESKTOP=KDE systemsettings"),
        { description = "App: KDE System Settings" })
end

-- Alt+Tab window switcher (Quickshell, modules/ii/altTab). Tab / Shift+Tab move through the windows
-- (most recently used first), releasing Alt focuses the chosen one. The Alt release bind must not
-- consume the key, so Alt keeps working normally in apps.
if mode.alt_tab then
    hl.bind("ALT + Tab", hl.dsp.global("quickshell:altTabNext"), { description = "Shell: Window switcher" })
    hl.bind("ALT + SHIFT + Tab", hl.dsp.global("quickshell:altTabPrev"), { description = "Shell: Window switcher (back)" })
    -- transparent: must not be shadowed by the ALT + Tab bind while Alt is still held
    hl.bind("ALT_L", hl.dsp.global("quickshell:altTabRelease"), { ignore_mods = true, non_consuming = true, transparent = true })
    hl.bind("ALT_R", hl.dsp.global("quickshell:altTabRelease"), { ignore_mods = true, non_consuming = true, transparent = true })
end

-- Plasma-like maximize for floating windows: the window is resized to fill the free area
-- (between bar and dock) and stays a normal floating window, so other windows on top of it
-- still get mouse focus. Hyprland's own "maximized" mode is a fullscreen state that blocks
-- focus-follows-mouse for every other window. Doing it again restores the previous geometry.
-- Used by the title bar's maximize button / double-click (hyprctl eval 'desktop_toggle_maximize()'),
-- and in floating mode every Hyprland maximize (SUPER + D, an app's own maximize button) is
-- converted to this one.
local FS_MAXIMIZED = 1

-- address -> { x, y, w, h (geometry before maximizing), mx, my (position while maximized) }.
-- Kept in a file so it survives `hyprctl reload` (Quickshell reloads when settings change);
-- window addresses stay the same for the whole session.
local GEOMETRY_FILE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-desktop-maximized-"
    .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "default")
local maximizedGeometry = {}
do
    local f = io.open(GEOMETRY_FILE, "r")
    if f then
        for line in f:lines() do
            local addr, x, y, w, h, mx, my = line:match("^(%S+) (%-?%d+) (%-?%d+) (%d+) (%d+) (%-?%d+) (%-?%d+)$")
            if addr then
                maximizedGeometry[addr] = { x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h), mx = tonumber(mx), my = tonumber(my) }
            end
        end
        f:close()
    end
end
local function saveMaximizedGeometry()
    local f = io.open(GEOMETRY_FILE, "w")
    if not f then return end
    for addr, g in pairs(maximizedGeometry) do
        f:write(string.format("%s %d %d %d %d %d %d\n", addr, g.x, g.y, g.w, g.h, g.mx, g.my))
    end
    f:close()
end

-- Free area of a monitor for a window with title bar and borders (between bar and dock):
-- x, y = where the window content starts, w, h = content size, with the usual gaps.
-- ignoreBars: use the space of the top bar and the dock too (maximized windows hide them, see below)
local function desktopWorkArea(win, mon, ignoreBars)
    mon = mon or win.monitor
    if not mon then return nil end
    local scale = mon.scale or 1
    local r = mon.reserved or { top = 0, right = 0, bottom = 0, left = 0 }
    local reserved = { top = ignoreBars and 0 or r.top, right = r.right, bottom = ignoreBars and 0 or r.bottom, left = r.left }
    local border = tonumber(hl.get_config("general:border_size")) or 1
    local gap = 6
    local bar = 0
    if DESKTOP_TITLEBAR_HEIGHT and (desktop_has_titlebar == nil or desktop_has_titlebar(win)) then
        bar = DESKTOP_TITLEBAR_HEIGHT
    end
    -- Rotated monitors (transform 1, 3, 5, 7) report width/height of the unrotated panel
    local pixelW, pixelH = mon.width, mon.height
    if (mon.transform or 0) % 2 == 1 then
        pixelW, pixelH = pixelH, pixelW
    end
    local areaW = pixelW / scale - reserved.left - reserved.right
    local areaH = pixelH / scale - reserved.top - reserved.bottom
    -- No gap at the top: the window (with its title bar) sits right under the top bar
    return {
        x = mon.x + reserved.left + gap + border,
        y = mon.y + reserved.top + border + bar,
        w = areaW - 2 * (gap + border),
        h = areaH - gap - 2 * border - bar,
        gap = gap, border = border, bar = bar,
    }
end

-- Puts a floating window at rect (content geometry) and remembers where it was before, so
-- maximize / double-click on the title bar brings the old size back. Snapping an already
-- maximized or snapped window keeps the original geometry.
local function placeWindow(win, rect)
    local x, y = math.floor(rect.x), math.floor(rect.y)
    local saved = maximizedGeometry[win.address]
    -- Keep the original geometry only while the window is still where it was snapped/maximized;
    -- if it was moved away and resized since, its current geometry is the one to come back to
    local at = win.at or { x = 0, y = 0 }
    if saved and math.abs(at.x - saved.mx) <= 4 and math.abs(at.y - saved.my) <= 4 then
        saved.mx, saved.my = x, y
    else
        maximizedGeometry[win.address] = {
            x = math.floor(win.at.x), y = math.floor(win.at.y),
            w = math.floor(win.size.x), h = math.floor(win.size.y),
            mx = x, my = y,
        }
    end
    saveMaximizedGeometry()
    -- Resize first: Hyprland resizes floating windows around their center and keeps them on
    -- screen, which would shift an already-moved window. Then move to the exact position.
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(rect.w), y = math.floor(rect.h), window = win }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = win }))
end

local function geometricMaximizeToggle(win)
    local key = win.address
    local saved = maximizedGeometry[key]
    if saved then
        maximizedGeometry[key] = nil
        saveMaximizedGeometry()
        -- Only restore if the window is still where maximizing put it. If it was dragged,
        -- snapped or moved to another monitor since, maximize it again instead.
        local at = win.at or { x = 0, y = 0 }
        if math.abs(at.x - saved.mx) <= 4 and math.abs(at.y - saved.my) <= 4 then
            hl.dispatch(hl.dsp.window.resize({ x = saved.w, y = saved.h, window = win }))
            hl.dispatch(hl.dsp.window.move({ x = saved.x, y = saved.y, window = win }))
            return
        end
    end

    -- With "maximized windows hide the bar" the window also takes the place of the bar and the
    -- dock; both (Quickshell) hide while such a window is on screen and slide in at the edges.
    local area = desktopWorkArea(win, nil, mode.maximize_hides_bar)
    if not area then return end
    placeWindow(win, area)
end

function desktop_toggle_maximize(win)
    win = win or hl.get_active_window()
    if not win then return end
    local fs = win.fullscreen or 0

    -- Real fullscreen (SUPER + F): just leave it
    if fs ~= 0 and fs ~= FS_MAXIMIZED then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset", window = win }))
        return
    end

    -- Tiled windows, or floating mode off: Hyprland's maximize as before
    if not (mode.floating and win.floating) then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = win }))
        return
    end

    if fs == FS_MAXIMIZED then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = win }))
    end
    geometricMaximizeToggle(win)
end

-- "Windowed fullscreen": the window covers the whole screen (bar and dock hide and slide in at
-- the screen edges) but the app itself is not told it is fullscreen, so it keeps its normal
-- interface (tabs, toolbars...). Works for every app. Used by the title bar's ◇ button and by
-- SUPER + F; the title bar is not drawn while fullscreen, so SUPER + F (or the button's window
-- being toggled again from the keyboard) brings it back.
local windowedFullscreen = {} -- address -> true while in windowed fullscreen

-- enable: true / false, or nil to toggle
function desktop_windowed_fullscreen(win, enable)
    win = win or hl.get_active_window()
    if not win or not win.address then return end
    if enable == nil then
        -- Any fullscreen/maximized state counts as "on": the toggle brings back a normal window
        enable = (tonumber(win.fullscreen) or 0) == 0
    end
    windowedFullscreen[win.address] = enable or nil
    hl.dispatch(hl.dsp.window.fullscreen_state({ internal = enable and 2 or 0, client = 0, action = "set", window = win }))
end

-- Forget saved geometry of closed windows
hl.on("window.close", function(win)
    if win and win.address then windowedFullscreen[win.address] = nil end
    if win and win.address and maximizedGeometry[win.address] then
        maximizedGeometry[win.address] = nil
        saveMaximizedGeometry()
    end
end)

if mode.floating then
    -- SUPER + D maximizes directly (smooth, no detour through Hyprland's maximized state)
    hl.unbind("SUPER + D")
    hl.bind("SUPER + D", function() desktop_toggle_maximize() end, { description = "Window: Maximize" })

    -- An app's own maximize button (Discord, Steam, GNOME apps... and anything else asking to be
    -- maximized) does the same as the title bar's ◇ button: windowed fullscreen, and the next
    -- request goes back to normal. (Such apps think they are not maximized, so they ask again.)
    hl.on("window.fullscreen", function(win)
        if not win or not win.floating or win.fullscreen ~= FS_MAXIMIZED then return end
        local wasWindowedFullscreen = windowedFullscreen[win.address] == true
        -- Let Hyprland finish its own fullscreen change before undoing it
        hl.timer(function()
            if not win.address or win.fullscreen ~= FS_MAXIMIZED then return end
            desktop_windowed_fullscreen(win, not wasWindowedFullscreen)
        end, { timeout = 30, type = "oneshot" })
    end)
end

-- Plasma/Windows-like snap zones: drag a floating window to the left/right screen edge for half
-- the screen, into a corner for a quarter, to the top edge to maximize. A preview shows the target
-- (Quickshell, modules/ii/snapPreview); keeping the window there a moment snaps it.
-- Hyprland gives the config no mouse button events (and hyprbars swallows them), so a drag is
-- recognized by the window moving together with the cursor, and the snap happens after a short
-- pause at the edge instead of on release. Moving on afterwards just drags the snapped window.
if mode.floating and mode.snap_zones then
    local TICK_MS = 40
    local EDGE = 3         -- px from the screen edge that count as "at the edge"
    local CORNER = 120     -- px from a corner (along an edge) that count as that corner
    local PREVIEW_MS = 120 -- pause at the edge before the preview appears
    local SNAP_MS = 550    -- pause at the edge before the window snaps

    local now = 0
    local prev = nil       -- window and cursor position at the last tick
    local lastDragMove = -1e9
    local zone, zoneSince, previewShown = nil, 0, false

    local function monitorRect(mon)
        local scale = mon.scale or 1
        local w, h = mon.width, mon.height
        if (mon.transform or 0) % 2 == 1 then w, h = h, w end
        return mon.x, mon.y, w / scale, h / scale
    end

    local function zoneAt(cursor, mon)
        local mx, my, mw, mh = monitorRect(mon)
        local left, right = cursor.x <= mx + EDGE, cursor.x >= mx + mw - 1 - EDGE
        local top, bottom = cursor.y <= my + EDGE, cursor.y >= my + mh - 1 - EDGE
        local nearLeft, nearRight = cursor.x <= mx + CORNER, cursor.x >= mx + mw - CORNER
        local nearTop, nearBottom = cursor.y <= my + CORNER, cursor.y >= my + mh - CORNER
        if (left and nearTop) or (top and nearLeft) then return "top_left" end
        if (right and nearTop) or (top and nearRight) then return "top_right" end
        if (left and nearBottom) or (bottom and nearLeft) then return "bottom_left" end
        if (right and nearBottom) or (bottom and nearRight) then return "bottom_right" end
        if left then return "left" end
        if right then return "right" end
        if top then return "maximize" end
        return nil
    end

    local function zoneRect(name, win, mon)
        if name == "maximize" then return desktopWorkArea(win, mon, mode.maximize_hides_bar) end
        local a = desktopWorkArea(win, mon)
        if not a then return nil end
        -- Two windows side by side / stacked, with a gap, their borders and the lower one's title bar between
        local halfW = (a.w - a.gap - 2 * a.border) / 2
        local halfH = (a.h - a.gap - 2 * a.border - a.bar) / 2
        local rightX = a.x + halfW + a.gap + 2 * a.border
        local lowerY = a.y + halfH + a.gap + 2 * a.border + a.bar
        local rects = {
            left = { x = a.x, y = a.y, w = halfW, h = a.h },
            right = { x = rightX, y = a.y, w = halfW, h = a.h },
            top_left = { x = a.x, y = a.y, w = halfW, h = halfH },
            top_right = { x = rightX, y = a.y, w = halfW, h = halfH },
            bottom_left = { x = a.x, y = lowerY, w = halfW, h = halfH },
            bottom_right = { x = rightX, y = lowerY, w = halfW, h = halfH },
        }
        local r = rects[name]
        if r then r.border, r.bar = a.border, a.bar end
        return r
    end

    -- Each IPC call is its own process, so calls can arrive out of order: they carry a sequence
    -- number and the overlay ignores older ones. Coordinates are sent offset by +100000 so a
    -- monitor left of/above the origin never produces a "-123" that looks like an option.
    local OFFSET = 100000
    local seq = 0
    local function showPreview(r)
        -- Outline of the whole window: content plus its title bar and borders
        local b, bar = r.border or 0, r.bar or 0
        seq = seq + 1
        hl.exec_cmd(string.format("qs -c $qsConfig ipc call snapPreview show %d %d %d %d %d", seq,
            math.floor(r.x - b) + OFFSET, math.floor(r.y - bar - b) + OFFSET, math.floor(r.w + 2 * b), math.floor(r.h + bar + 2 * b)))
        previewShown = true
    end
    local function hidePreview()
        if previewShown then
            seq = seq + 1
            hl.exec_cmd(string.format("qs -c $qsConfig ipc call snapPreview hide %d", seq))
            previewShown = false
        end
    end

    hl.timer(function()
        now = now + TICK_MS
        local win = hl.get_active_window()
        local cursor = hl.get_cursor_pos()
        if not win or not cursor or not win.floating or (win.fullscreen or 0) ~= 0 or not win.at then
            prev, lastDragMove, zone = nil, -1e9, nil
            hidePreview()
            return
        end

        local size = win.size or { x = 0, y = 0 }
        if not prev or prev.addr ~= win.address then
            prev = { addr = win.address, x = win.at.x, y = win.at.y, w = size.x, h = size.y, cx = cursor.x, cy = cursor.y }
            lastDragMove, zone = -1e9, nil
            hidePreview()
            return
        end
        -- Window and cursor moving together = the window is being dragged. The cursor moving on
        -- its own means it was let go. Both still (e.g. pushing against the screen edge) keeps
        -- the state. Comparing movement rather than the exact cursor offset also works while
        -- Hyprland's edge snapping nudges the window during the drag.
        -- A resize from the left/top border also moves the window with the cursor: only count it
        -- as a drag while the size stays the same.
        local resized = size.x ~= prev.w or size.y ~= prev.h
        local windowMoved = (win.at.x ~= prev.x or win.at.y ~= prev.y) and not resized
        local cursorMoved = math.abs(cursor.x - prev.cx) > 2 or math.abs(cursor.y - prev.cy) > 2
        if windowMoved and cursorMoved then
            lastDragMove = now
        elseif cursorMoved or resized then
            lastDragMove = -1e9
        end
        prev.x, prev.y, prev.w, prev.h, prev.cx, prev.cy = win.at.x, win.at.y, size.x, size.y, cursor.x, cursor.y

        local mon = hl.get_monitor_at_cursor()
        local newZone = (now - lastDragMove < 1500 and mon) and zoneAt(cursor, mon) or nil
        if newZone ~= zone then
            zone = newZone
            zoneSince = now
            hidePreview()
        elseif cursorMoved then
            -- Snapping needs a pause: sliding along the edge keeps restarting the wait
            zoneSince = now
        end
        if not zone then return end

        local held = now - zoneSince
        if held >= PREVIEW_MS and not previewShown then
            local r = zoneRect(zone, win, mon)
            if r then showPreview(r) end
        end
        if held >= SNAP_MS then
            local r = zoneRect(zone, win, mon)
            hidePreview()
            zone = nil
            if r then
                placeWindow(win, r)
                -- The window jumped on its own: don't count that as dragging it further
                prev, lastDragMove = nil, -1e9
            end
        end
    end, { timeout = TICK_MS, type = "repeat" })
end

-- Automatic game mode: while any window is really fullscreen (a game, a fullscreen video),
-- animations, blur and shadows are off; they come back when it leaves fullscreen.
if mode.auto_game_mode then
    local fullscreenWindows = {}
    local saved = nil
    local KEYS = { "animations:enabled", "decoration:blur:enabled", "decoration:shadow:enabled" }

    local function isFullscreen(win)
        -- Fullscreen modes are bit masks: 1 = maximized, 2 = fullscreen. The app itself must be
        -- fullscreen too (a game, F11, a video), not just covering the screen like Firefox's
        -- windowed fullscreen (SUPER + F), where you keep working normally.
        local fs = tonumber(win and win.fullscreen) or 0
        local client = tonumber(win and win.fullscreen_client) or fs
        return math.floor(fs / 2) % 2 == 1 and math.floor(client / 2) % 2 == 1
    end
    local function truthy(v)
        return v == true or v == 1 or v == "1" or v == "true"
    end
    local function update()
        local any = next(fullscreenWindows) ~= nil
        if any and not saved then
            saved = {}
            for _, key in ipairs(KEYS) do
                local ok, value = pcall(hl.get_config, key)
                saved[key] = ok and truthy(value)
            end
            hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false }, shadow = { enabled = false } } })
        elseif not any and saved then
            hl.config({
                animations = { enabled = saved["animations:enabled"] },
                decoration = {
                    blur = { enabled = saved["decoration:blur:enabled"] },
                    shadow = { enabled = saved["decoration:shadow:enabled"] },
                },
            })
            saved = nil
        end
    end

    hl.on("window.fullscreen", function(win)
        if not win or not win.address then return end
        fullscreenWindows[win.address] = isFullscreen(win) or nil
        update()
    end)
    local function forget(win)
        if win and win.address and fullscreenWindows[win.address] then
            fullscreenWindows[win.address] = nil
            update()
        end
    end
    hl.on("window.close", forget)
    hl.on("window.destroy", forget)

    -- After a config reload a game may already be fullscreen. Checked once the whole config has
    -- been read, so later files (custom, shell overrides) are part of the values saved/restored.
    hl.timer(function()
        for _, win in ipairs(hl.get_windows() or {}) do
            if isFullscreen(win) and win.address then fullscreenWindows[win.address] = true end
        end
        update()
    end, { timeout = 1, type = "oneshot" })
end
