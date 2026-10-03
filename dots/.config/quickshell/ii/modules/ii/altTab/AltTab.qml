pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Plasma/macOS-like Alt+Tab window switcher with live window previews.
 * Hyprland binds (desktop_mode.lua): ALT+Tab -> altTabNext, ALT+SHIFT+Tab -> altTabPrev,
 * releasing Alt -> altTabRelease. Windows are listed most recently used first, minimized
 * windows included. A quick Alt+Tab tap switches to the previous window without showing anything.
 */
Scope {
    id: root

    property bool active: false
    property var windows: []
    property int index: 0
    property bool shown: false // the UI only appears when Alt is held a moment, like macOS/Plasma

    readonly property var selectedWindow: root.windows[root.index] ?? null

    function collectWindows() {
        return HyprlandData.windowList
            .filter(w => w.mapped !== false && w.hidden !== true
                && ((w.workspace?.id ?? 0) > 0 || w.workspace?.name === "special:minimized"))
            .sort((a, b) => (a.focusHistoryID ?? 9999) - (b.focusHistoryID ?? 9999));
    }

    function start(step) {
        // A switch from a quick previous Alt+Tab may still be pending: do it now, and treat that
        // window as the current one (the window list from hyprctl may not know about it yet)
        let front = "";
        if (switchTimer.running) {
            switchTimer.stop();
            const pending = root.pendingWindow;
            root.pendingWindow = null;
            if (pending) {
                root.switchTo(pending);
                front = pending.address;
            }
        }
        const active = ToplevelManager.activeToplevel;
        if (front === "" && active?.activated && active.HyprlandToplevel)
            front = `0x${active.HyprlandToplevel.address}`;

        const list = root.collectWindows();
        if (list.length === 0) return;
        const frontIndex = list.findIndex(w => w.address === front);
        if (frontIndex > 0) list.unshift(list.splice(frontIndex, 1)[0]);
        root.windows = list;
        // Start on the previous window; if no window is focused, the most recent one is the target
        root.index = step > 0 ? (frontIndex !== -1 ? Math.min(1, list.length - 1) : 0) : list.length - 1;
        root.screenName = Hyprland.focusedMonitor?.name ?? "";
        root.hoverOrigin = Qt.point(-1, -1);
        root.active = true;
        showTimer.restart();
    }
    // Fixed when the switcher opens: following the focused monitor live would recreate the
    // window (and cancel the focus grab) when the mouse crosses to another screen
    property string screenName: ""
    // Hover only selects after the mouse really moved (the card appearing under a still cursor
    // also sends hover events)
    property point hoverOrigin: Qt.point(-1, -1)

    function step(delta) {
        if (!root.active) {
            root.start(delta);
            return;
        }
        const n = root.windows.length;
        if (n === 0) return;
        root.index = ((root.index + delta) % n + n) % n;
    }

    function close() {
        showTimer.stop();
        root.active = false;
        root.shown = false;
        root.windows = [];
    }

    // Switching waits a moment so the switcher's focus grab is gone first: while the grab is
    // active Hyprland keeps keyboard focus on the switcher and the chosen window would not get it.
    property var pendingWindow: null
    function commit() {
        let win = root.selectedWindow;
        // The window may have closed while the switcher was open
        if (win && !root.toplevelFor(win)) win = null;
        root.pendingWindow = win;
        root.close();
        if (root.pendingWindow) switchTimer.restart();
    }
    function switchTo(win) {
        const target = `address:${win.address}`;
        if (win.workspace?.name === "special:minimized") {
            // Same as the dock: bring a minimized window back to the current workspace
            const ws = HyprlandData.activeWorkspace;
            // Named workspaces have negative ids, which Hyprland would read as a relative offset
            const workspace = (ws?.id ?? 1) > 0 ? `${ws?.id ?? 1}` : `name:${ws.name}`;
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${workspace}", follow = false, window = "${target}" })`);
        }
        Hyprland.dispatch(`hl.dsp.focus({ window = "${target}" })`);
        // Focusing does not raise a floating window; bring it in front of the others
        Hyprland.dispatch(`hl.dsp.window.alter_zorder({ mode = "top", window = "${target}" })`);
    }
    Timer {
        id: switchTimer
        interval: 60
        onTriggered: {
            const win = root.pendingWindow;
            root.pendingWindow = null;
            if (win) root.switchTo(win);
        }
    }

    readonly property real thumbHeight: 130
    function thumbWidth(win) {
        const aspect = (win?.size?.[0] ?? 16) / Math.max(1, win?.size?.[1] ?? 9);
        return Math.max(100, Math.min(240, root.thumbHeight * aspect));
    }

    function toplevelFor(win) {
        if (!win) return null;
        return ToplevelManager.toplevels.values.find(t => `0x${t.HyprlandToplevel?.address}` === win.address) ?? null;
    }

    Timer {
        id: showTimer
        interval: 120
        onTriggered: if (root.active) root.shown = true
    }

    GlobalShortcut {
        name: "altTabNext"
        description: "Window switcher: next window"
        onPressed: root.step(1)
    }
    GlobalShortcut {
        name: "altTabPrev"
        description: "Window switcher: previous window"
        onPressed: root.step(-1)
    }
    GlobalShortcut {
        name: "altTabRelease"
        description: "Window switcher: Alt released, switch to the chosen window"
        onReleased: if (root.active) root.commit()
    }

    Loader {
        active: root.active && root.shown && !GlobalStates.screenLocked

        sourceComponent: PanelWindow {
            id: panel
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
            WlrLayershell.namespace: "quickshell:altTab"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            implicitWidth: card.implicitWidth
            implicitHeight: card.implicitHeight

            // Clicking outside cancels (in case the Alt release was missed)
            HyprlandFocusGrab {
                active: true
                windows: [panel]
                onCleared: root.close()
            }

            Rectangle {
                id: card
                readonly property real maxWidth: (panel.screen?.width ?? 1366) * 0.85
                implicitWidth: flow.width + 24
                implicitHeight: flow.implicitHeight + 24
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                Flow {
                    id: flow
                    anchors.centerIn: parent
                    // Flow only wraps at its width, so give it the width of one row (or the max)
                    readonly property real rowWidth: root.windows.reduce((sum, w) => sum + root.thumbWidth(w) + 16 + spacing, 0) - spacing
                    width: Math.min(rowWidth, card.maxWidth)
                    spacing: 10

                    Repeater {
                        model: root.windows

                        delegate: Rectangle {
                            id: entry
                            required property var modelData
                            required property int index
                            readonly property bool selected: entry.index === root.index
                            readonly property real thumbHeight: root.thumbHeight
                            readonly property real thumbWidth: root.thumbWidth(modelData)
                            readonly property string iconPath: Quickshell.iconPath(AppSearch.guessIcon(modelData.class), "image-missing")

                            width: thumbWidth + 16
                            height: thumbHeight + 48
                            radius: Appearance.rounding.normal
                            color: selected ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.75)
                                : (entryMouse.containsMouse ? Appearance.colors.colLayer0Hover : "transparent")
                            border.width: selected ? 2 : 0
                            border.color: Appearance.colors.colPrimary

                            Item {
                                id: thumb
                                x: 8
                                y: 8
                                width: entry.thumbWidth
                                height: entry.thumbHeight

                                ScreencopyView {
                                    id: preview
                                    anchors.fill: parent
                                    captureSource: root.toplevelFor(entry.modelData)
                                    // Live previews cost a capture per frame each; with many windows only the selected one is live
                                    live: entry.selected || root.windows.length <= 6
                                    constraintSize: Qt.size(entry.thumbWidth * 2, entry.thumbHeight * 2)
                                }
                                // Minimized windows may have no picture: show the app icon instead
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !preview.hasContent
                                    implicitSize: 64
                                    source: entry.iconPath
                                }
                                IconImage {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 4
                                    visible: preview.hasContent
                                    implicitSize: 28
                                    source: entry.iconPath
                                }
                            }

                            StyledText {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                    margins: 8
                                }
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: entry.modelData.title || entry.modelData.class
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            MouseArea {
                                id: entryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                // Only real mouse movement selects, not the card appearing under the cursor
                                onPositionChanged: mouse => {
                                    const p = entryMouse.mapToItem(null, mouse.x, mouse.y);
                                    if (root.hoverOrigin.x < 0) {
                                        root.hoverOrigin = p;
                                        return;
                                    }
                                    if (Math.abs(p.x - root.hoverOrigin.x) + Math.abs(p.y - root.hoverOrigin.y) < 6)
                                        return;
                                    root.index = entry.index;
                                }
                                onClicked: {
                                    root.index = entry.index;
                                    root.commit();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
