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

    // The screen is picked when the menu opens (the focused one, i.e. where the dock button or
    // ALT+F1 was used) and kept, so it doesn't jump when focus follows the mouse
    property var openScreen: null
    Connections {
        target: GlobalStates
        function onStartMenuOpenChanged() {
            root.openScreen = GlobalStates.startMenuOpen
                ? (Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0])
                : null;
        }
    }

    Loader {
        id: panelLoader
        active: GlobalStates.startMenuOpen && root.openScreen !== null

        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            screen: root.openScreen
            WlrLayershell.namespace: "quickshell:startMenu"
            // Overlay: a Top layer would be hidden behind a fullscreen window while taking the keyboard
            WlrLayershell.layer: WlrLayer.Overlay
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
