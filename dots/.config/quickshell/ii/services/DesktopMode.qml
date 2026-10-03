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
    // The Alt+Tab switcher only exists in the "ii" panel family
    readonly property bool snapZones: Config.options?.desktopMode.snapZones ?? true
    readonly property bool autoGameMode: Config.options?.desktopMode.autoGameMode ?? true
    readonly property bool maximizeHidesBar: Config.options?.desktopMode.maximizeHidesBar ?? true
    readonly property bool altTab: (Config.options?.desktopMode.altTab ?? true) && (Config.options?.panelFamily ?? "ii") === "ii"

    readonly property string content: `return { floating = ${root.floating}, snap = ${root.snap}, kde_services = ${root.kdeServices}, alt_tab = ${root.altTab}, snap_zones = ${root.snapZones}, auto_game_mode = ${root.autoGameMode}, maximize_hides_bar = ${root.maximizeHidesBar} }`

    // Only the main shell writes the file. The settings app (a separate Quickshell process) also
    // creates this singleton when it shows these options, but never calls load().
    property bool active: false
    function load() {
        root.active = true;
    }

    onContentChanged: applyTimer.restart()

    Timer {
        id: applyTimer
        interval: 300
        running: Config.ready && root.active
        onTriggered: {
            if (!Config.ready || !root.active) return;
            applyProc.running = false;
            applyProc.command = ["bash", "-c",
                'mkdir -p "$(dirname "$1")" && if [ "$(cat "$1" 2>/dev/null)" != "$2" ]; then printf "%s\\n" "$2" > "$1" && exit 10; fi',
                "desktop-mode", root.filePath, root.content];
            applyProc.running = true;
        }
    }

    Process {
        id: applyProc
        // 10 = the file changed: reload Hyprland (shared and debounced with the other services)
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 10) HyprlandReload.request();
        }
    }
}
