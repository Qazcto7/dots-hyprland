import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * KDE Plasma (Kickoff)-like start menu.
 * Opens above the dock (dock's app button, ALT+F1). Toggle in Settings > Interface > Desktop mode.
 */
Scope {
    id: root

    Loader {
        id: panelLoader
        active: GlobalStates.startMenuOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:startMenu"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.bottom: true
            margins.bottom: 8

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight

            HyprlandFocusGrab {
                active: true
                windows: [panelWindow]
                onCleared: GlobalStates.startMenuOpen = false
            }

            StartMenuContent {
                id: content
                anchors.fill: parent
                focus: true
                onClosed: GlobalStates.startMenuOpen = false
            }
        }
    }

    IpcHandler {
        target: "startMenu"

        function toggle(): void {
            GlobalStates.startMenuOpen = !GlobalStates.startMenuOpen;
        }
        function open(): void {
            GlobalStates.startMenuOpen = true;
        }
        function close(): void {
            GlobalStates.startMenuOpen = false;
        }
    }

    GlobalShortcut {
        name: "startMenuToggle"
        description: "Toggles the Plasma-like start menu"

        onPressed: {
            GlobalStates.startMenuOpen = !GlobalStates.startMenuOpen;
        }
    }
}
