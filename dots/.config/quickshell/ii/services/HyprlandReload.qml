pragma Singleton

import QtQuick
import Quickshell

/**
 * One debounced `hyprctl reload` for the services that write generated Hyprland config
 * (DesktopMode, KeyboardLayout), so several changes at once (e.g. first start) reload once.
 */
Singleton {
    id: root

    function request() {
        reloadTimer.restart();
    }

    Timer {
        id: reloadTimer
        interval: 250
        onTriggered: Quickshell.execDetached(["hyprctl", "reload"])
    }
}
