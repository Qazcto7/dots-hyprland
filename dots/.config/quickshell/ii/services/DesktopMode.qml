pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.common
import qs.modules.common.functions

/**
 * Plasma-like desktop mode for Hyprland (floating windows, snapping, KDE services).
 * Writes the options from Config.options.desktopMode to a small Lua file that
 * ~/.config/hypr/hyprland/desktop_mode.lua reads, then reloads Hyprland.
 * Hyprland is only reloaded when the file content actually changes.
 */
Singleton {
    id: root

    readonly property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/hyprland/desktop_mode.lua`)

    readonly property bool floating: Config.options?.desktopMode.floatingWindows ?? true
    readonly property bool snap: Config.options?.desktopMode.snapping ?? true
    readonly property bool kdeServices: Config.options?.desktopMode.kdeServices ?? true

    readonly property string content: `return { floating = ${root.floating}, snap = ${root.snap}, kde_services = ${root.kdeServices} }`

    function load() {
        // Referencing the singleton instantiates it; the timer does the first write.
    }

    onContentChanged: applyTimer.restart()

    Timer {
        id: applyTimer
        interval: 300
        running: Config.ready
        onTriggered: {
            if (!Config.ready) return;
            applyProc.running = false;
            applyProc.command = ["bash", "-c",
                'mkdir -p "$(dirname "$1")" && if [ "$(cat "$1" 2>/dev/null)" != "$2" ]; then printf "%s\\n" "$2" > "$1" && hyprctl reload; fi',
                "desktop-mode", root.filePath, root.content];
            applyProc.running = true;
        }
    }

    Process {
        id: applyProc
    }
}
