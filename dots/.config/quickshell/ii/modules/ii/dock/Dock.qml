import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    // Extra transparent space above the dock so magnified/bouncing icons are not clipped
    readonly property real iconBaseSize: 35
    readonly property real bounceHeight: 14
    readonly property real headroom: ((Config.options?.dock.magnification ?? true)
            ? root.iconBaseSize * Math.max(0, (Config.options?.dock.magnificationScale ?? 1.6) - 1) : 0)
        + ((Config.options?.dock.bounceOnLaunch ?? true) ? root.bounceHeight : 0)

    Variants {
        // For each monitor
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            // Window
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked

            // macOS-like: while a window is fullscreen on this screen, the dock hides and slides in
            // when the mouse reaches the bottom edge (drawn above the fullscreen window).
            readonly property bool fullscreenActive: HyprlandData.hasFullscreenOn(dockRoot.screen?.name ?? "")
            // Same for a maximized window when "maximized windows hide the bar" is on: it then uses
            // the dock's space too, even with a pinned dock
            readonly property bool maximizedActive: (Config.options?.desktopMode.maximizeHidesBar ?? true)
                && HyprlandData.hasMaximizedOn(dockRoot.screen?.name ?? "")
            readonly property bool coveredActive: fullscreenActive || maximizedActive
            readonly property bool hoverRevealEnabled: (Config.options?.dock.hoverToReveal ?? true) || coveredActive || overlappedActive
            WlrLayershell.layer: fullscreenActive ? WlrLayer.Overlay : WlrLayer.Top

            // The dock also shows by itself on an empty workspace. That used to be "no window has
            // focus", which is also true right after switching workspaces (SUPER + 1/2) until the
            // mouse moves onto a window, so the dock stayed up over maximized/fullscreen windows.
            // Now it checks whether this screen's workspace really has no windows.
            readonly property int workspaceId: HyprlandData.monitors.find(m => m.name === dockRoot.screen?.name)?.activeWorkspace?.id ?? -1
            readonly property bool emptyWorkspace: !HyprlandData.windowList.some(w =>
                w.workspace?.id === dockRoot.workspaceId && w.mapped !== false && w.hidden !== true)

            // Plasma's "dodge windows": a window over the dock (dragged down, or an app whose minimum
            // size doesn't fit between bar and dock) hides it; it slides in at the bottom edge, like
            // over maximized windows. The pinned dock keeps its reserved space, so this only happens
            // for windows that really reach into it.
            readonly property bool overlappedActive: {
                if (!(Config.options?.dock.hideOverWindows ?? true)) return false;
                const mon = HyprlandData.monitors.find(m => m.name === dockRoot.screen?.name);
                if (!mon || !dockRoot.screen) return false;
                const ids = [mon.activeWorkspace?.id, mon.specialWorkspace?.id].filter(id => id !== undefined && id !== 0);
                // Where the dock body is when shown (global coordinates)
                const bodyWidth = dockBackground.implicitWidth;
                const left = mon.x + (dockRoot.width - bodyWidth) / 2;
                const right = left + bodyWidth;
                const bottom = mon.y + dockRoot.screen.height;
                const top = bottom - dockRoot.implicitHeight + root.headroom + Appearance.sizes.elevationMargin;
                return HyprlandData.windowList.some(w => {
                    if (ids.indexOf(w.workspace?.id) === -1 || w.hidden || w.mapped === false) return false;
                    if (((w.fullscreen ?? 0) & 2) !== 0) return false; // fullscreen is handled separately
                    const x = w.at?.[0] ?? 0, y = w.at?.[1] ?? 0;
                    const wd = w.size?.[0] ?? 0, ht = w.size?.[1] ?? 0;
                    return x < right && x + wd > left && y < bottom && y + ht > top;
                });
            }

            property bool reveal: (coveredActive || overlappedActive)
                ? (dockMouseArea.containsMouse || dockApps.requestDockShow || dockTrash.menuOpen)
                : (root.pinned || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse) || dockApps.requestDockShow || dockTrash.menuOpen || dockRoot.emptyWorkspace)

            anchors {
                bottom: true
                left: true
                right: true
            }

            exclusiveZone: (root.pinned && !coveredActive) ? implicitHeight - root.headroom - (Appearance.sizes.hyprlandGapsOut) - (Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut) : 0

            implicitWidth: dockBackground.implicitWidth
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            implicitHeight: (Config.options?.dock.height ?? 70) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut + root.headroom

            // Input only on the dock itself, not on the transparent headroom above it
            mask: Region {
                item: dockInputRegion
            }

            // Input region: the dock without the transparent headroom above it.
            // Must be a direct child bound to dockMouseArea's position: Region only follows its
            // item's own x/y/size, so an item nested inside the sliding MouseArea kept a stale
            // mask after reveal/hide (e.g. after leaving fullscreen) and the dock ignored the mouse.
            // It follows the sliding dock body continuously (no jump by the headroom when reveal
            // flips, which made the pointer leave/enter in a loop), but never shrinks above the
            // bottom hover strip that reveals the dock.
            Item {
                id: dockInputRegion
                readonly property real strip: dockRoot.hoverRevealEnabled ? (Config.options?.dock.hoverRegionHeight ?? 2) : 0
                x: dockMouseArea.x
                width: dockMouseArea.width
                y: Math.min(dockMouseArea.y + root.headroom, dockRoot.height - strip)
                height: Math.max(0, dockRoot.height - y)
            }

            MouseArea {
                id: dockMouseArea
                height: parent.height
                anchors {
                    top: parent.top
                    topMargin: dockRoot.reveal ? 0 : dockRoot.hoverRevealEnabled ? (dockRoot.implicitHeight - Config.options.dock.hoverRegionHeight) : (dockRoot.implicitHeight + 1)
                    horizontalCenter: parent.horizontalCenter
                }
                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true

                Behavior on anchors.topMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth

                    Item { // Wrapper for the dock background
                        id: dockBackground
                        anchors {
                            top: parent.top
                            topMargin: root.headroom
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                        }

                        implicitWidth: dockRow.implicitWidth + 5 * 2

                        StyledRectangularShadow {
                            target: dockVisualBackground
                        }
                        Rectangle { // The real rectangle that is visible
                            id: dockVisualBackground
                            property real margin: Appearance.sizes.elevationMargin
                            anchors.fill: parent
                            anchors.topMargin: Appearance.sizes.elevationMargin
                            anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
                            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 1 - (Config.options?.dock.backgroundOpacity ?? 0.72))
                            border.width: 1
                            border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.3)
                            radius: Appearance.rounding.large
                        }

                        RowLayout {
                            id: dockRow
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            property real padding: 5

                            VerticalButtonGroup {
                                visible: Config.options?.dock.showPinButton ?? false
                                Layout.topMargin: Appearance.sizes.hyprlandGapsOut // why does this work
                                GroupButton {
                                    // Pin button
                                    baseWidth: 35
                                    baseHeight: 35
                                    clickedWidth: baseWidth
                                    clickedHeight: baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
                                        text: "keep"
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: root.pinned ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                            DockSeparator {
                                visible: Config.options?.dock.showPinButton ?? false
                            }
                            DockApps {
                                id: dockApps
                                buttonPadding: dockRow.padding
                            }
                            DockSeparator {}
                            DockButton {
                                Layout.fillHeight: true
                                onClicked: {
                                    if (!(Config.options?.startMenu.enable ?? false)) {
                                        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
                                        return;
                                    }
                                    // The start menu's focus grab already closed it when this button was pressed
                                    if (!GlobalStates.startMenuOpen && Date.now() - GlobalStates.startMenuLastClosed < 300)
                                        return;
                                    GlobalStates.startMenuOpen = !GlobalStates.startMenuOpen;
                                }
                                topInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                bottomInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: parent.width / 2
                                    text: "apps"
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                            // macOS-like trash after the apps button
                            DockTrash {
                                id: dockTrash
                                visible: Config.options?.dock.showTrash ?? true
                                Layout.fillHeight: true
                                topInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                bottomInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                            }
                        }
                    }
                }
            }
        }
    }
}
