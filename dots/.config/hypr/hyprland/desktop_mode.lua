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

    local mon = win.monitor
    if not mon then return end
    local scale = mon.scale or 1
    local reserved = mon.reserved or { top = 0, right = 0, bottom = 0, left = 0 }
    local border = tonumber(hl.get_config("general:border_size")) or 1
    local gap = 6
    local bar = 0
    if DESKTOP_TITLEBAR_HEIGHT and not (DESKTOP_TITLEBAR_EXCLUDED or {})[win.class] then
        bar = DESKTOP_TITLEBAR_HEIGHT
    end

    local areaX = mon.x + reserved.left
    local areaY = mon.y + reserved.top
    -- Rotated monitors (transform 1, 3, 5, 7) report width/height of the unrotated panel
    local pixelW, pixelH = mon.width, mon.height
    if (mon.transform or 0) % 2 == 1 then
        pixelW, pixelH = pixelH, pixelW
    end
    local areaW = pixelW / scale - reserved.left - reserved.right
    local areaH = pixelH / scale - reserved.top - reserved.bottom

    local targetX, targetY = math.floor(areaX + gap + border), math.floor(areaY + border + bar)
    maximizedGeometry[key] = { x = math.floor(win.at.x), y = math.floor(win.at.y), w = math.floor(win.size.x), h = math.floor(win.size.y), mx = targetX, my = targetY }
    saveMaximizedGeometry()
    -- Resize first: Hyprland resizes floating windows around their center and keeps them on
    -- screen, which would shift an already-moved window. Then move to the exact position.
    -- No gap at the top: the window (with its title bar) sits right under the top bar
    hl.dispatch(hl.dsp.window.resize({
        x = math.floor(areaW - 2 * (gap + border)),
        y = math.floor(areaH - gap - 2 * border - bar),
        window = win,
    }))
    hl.dispatch(hl.dsp.window.move({ x = targetX, y = targetY, window = win }))
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

-- Forget saved geometry of closed windows
hl.on("window.close", function(win)
    if win and win.address and maximizedGeometry[win.address] then
        maximizedGeometry[win.address] = nil
        saveMaximizedGeometry()
    end
end)

if mode.floating then
    -- SUPER + D maximizes directly (smooth, no detour through Hyprland's maximized state)
    hl.unbind("SUPER + D")
    hl.bind("SUPER + D", function() desktop_toggle_maximize() end, { description = "Window: Maximize" })

    hl.on("window.fullscreen", function(win)
        if not win or not win.floating or win.fullscreen ~= FS_MAXIMIZED then return end
        -- Let Hyprland finish its own fullscreen change before undoing it
        hl.timer(function()
            if not win.address or win.fullscreen ~= FS_MAXIMIZED then return end
            desktop_toggle_maximize(win)
        end, { timeout = 30, type = "oneshot" })
    end)
end
