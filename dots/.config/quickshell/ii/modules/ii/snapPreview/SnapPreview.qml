pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * Preview of where a dragged window will snap (half / quarter / maximized).
 * Shown and hidden by hyprland/desktop_mode.lua through IPC:
 *   qs -c ii ipc call snapPreview show <seq> <x+100000> <y+100000> <width> <height>
 *   qs -c ii ipc call snapPreview hide <seq>
 * (global layout coordinates, offset so they are never negative; calls with an older sequence
 * number than the last one are ignored, as separate processes can arrive out of order)
 * Click-through: the window has an empty input region.
 */
Scope {
    id: root

    property bool shown: false
    property rect target: Qt.rect(0, 0, 0, 0)
    readonly property var targetScreen: Quickshell.screens.find(s =>
        root.target.x + root.target.width / 2 >= s.x && root.target.x + root.target.width / 2 < s.x + s.width
        && root.target.y + root.target.height / 2 >= s.y && root.target.y + root.target.height / 2 < s.y + s.height) ?? null

    property int lastSeq: -1
    readonly property int offset: 100000

    IpcHandler {
        target: "snapPreview"

        function show(seq: int, x: int, y: int, width: int, height: int): void {
            if (seq < root.lastSeq) return;
            root.lastSeq = seq;
            root.target = Qt.rect(x - root.offset, y - root.offset, width, height);
            root.shown = true;
            watchdog.restart();
        }
        function hide(seq: int): void {
            if (seq < root.lastSeq) return;
            root.lastSeq = seq;
            root.shown = false;
        }
    }
    // Hyprland restarting (sequence back to 1) or a lost hide must not leave it on screen
    Timer {
        id: watchdog
        interval: 3000
        onTriggered: {
            root.shown = false;
            root.lastSeq = -1;
        }
    }

    Loader {
        active: root.shown && root.targetScreen !== null && !GlobalStates.screenLocked

        sourceComponent: PanelWindow {
            id: panel
            screen: root.targetScreen
            WlrLayershell.namespace: "quickshell:snapPreview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {}

            Rectangle {
                id: preview
                x: root.target.x - (panel.screen?.x ?? 0)
                y: root.target.y - (panel.screen?.y ?? 0)
                width: root.target.width
                height: root.target.height
                radius: Appearance.rounding.windowRounding
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                border.width: 2
                border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.2)

                // Grows in from its center
                scale: 0.94
                opacity: 0
                Component.onCompleted: {
                    scale = 1;
                    opacity = 1;
                }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
    }
}
