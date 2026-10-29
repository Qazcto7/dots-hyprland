pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    // Extra headroom space above the dock so magnified/bouncing icons are not clipped
    readonly property real iconBaseSize: 35
    readonly property real bounceHeight: 14
    readonly property real headroom: ((Config.options?.dock.magnification ?? true)
            ? root.iconBaseSize * Math.max(0, (Config.options?.dock.magnificationScale ?? 1.6) - 1) : 0)
        + ((Config.options?.dock.bounceOnLaunch ?? true) ? root.bounceHeight : 0)

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked

            readonly property real dockHeight: Config.options?.dock.height ?? 60

            readonly property bool fullscreenActive: HyprlandData.hasFullscreenOn(dockRoot.screen?.name ?? "")
            readonly property bool coveredActive: fullscreenActive
            readonly property bool hoverRevealEnabled: (Config.options?.dock.hoverToReveal ?? false) || coveredActive || overlappedActive
            WlrLayershell.layer: fullscreenActive ? WlrLayer.Overlay : WlrLayer.Top

            readonly property int workspaceId: HyprlandData.monitors.find(m => m.name === dockRoot.screen?.name)?.activeWorkspace?.id ?? -1
            readonly property bool emptyWorkspace: !HyprlandData.windowList.some(w =>
                w.workspace?.id === dockRoot.workspaceId && w.mapped !== false && w.hidden !== true)

            readonly property bool overlappedActive: {
                if (!(Config.options?.dock.hideOverWindows ?? false)) return false;
                if (root.pinned) return false;
                const mon = HyprlandData.monitors.find(m => m.name === dockRoot.screen?.name);
                if (!mon || !dockRoot.screen) return false;
                const ids = [mon.activeWorkspace?.id, mon.specialWorkspace?.id].filter(id => id !== undefined && id !== 0);
                const bodyWidth = dockVisualBackground.implicitWidth;
                const left = mon.x + (dockRoot.screen.width - bodyWidth) / 2;
                const right = left + bodyWidth;
                const bottom = mon.y + dockRoot.screen.height;
                const top = bottom - dockHeight - Appearance.sizes.hyprlandGapsOut;
                return HyprlandData.windowList.some(w => {
                    if (ids.indexOf(w.workspace?.id) === -1 || w.hidden || w.mapped === false) return false;
                    if (((w.fullscreen ?? 0) & 2) !== 0) return false;
                    const x = w.at?.[0] ?? 0, y = w.at?.[1] ?? 0;
                    const wd = w.size?.[0] ?? 0, ht = w.size?.[1] ?? 0;
                    return x < right && x + wd > left && y < bottom && y + ht > top;
                });
            }

            property bool reveal: coveredActive
                ? (dockMouseArea.containsMouse || dockApps.requestDockShow || dockTrash.menuOpen)
                : (root.pinned || (overlappedActive ? (dockMouseArea.containsMouse || dockApps.requestDockShow || dockTrash.menuOpen) : ((Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse) || dockApps.requestDockShow || dockTrash.menuOpen || dockRoot.emptyWorkspace)))

            anchors {
                bottom: true
            }
            margins {
                bottom: Appearance.sizes.hyprlandGapsOut
            }

            exclusiveZone: (root.pinned && !coveredActive) ? dockHeight + Appearance.sizes.hyprlandGapsOut : 0
            exclusionMode: exclusiveZone > 0 ? ExclusionMode.Normal : ExclusionMode.Ignore

            implicitHeight: dockRoot.reveal ? (dockHeight + root.headroom) : (Config.options?.dock.hoverRegionHeight ?? 2)
            implicitWidth: dockRow.implicitWidth + dockRow.padding * 2 + 10

            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"
            surfaceFormat.opaque: false

            mask: Region {
                item: dockVisualBackground
            }

            MouseArea {
                id: dockMouseArea
                anchors.fill: parent
                hoverEnabled: true

                Rectangle {
                    id: dockVisualBackground
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: dockRoot.dockHeight

                    color: ColorUtils.transparentize(Appearance.colors.colLayer0, 1 - (Config.options?.dock.backgroundOpacity ?? 0.72))
                    border.width: 1
                    border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.3)
                    radius: Appearance.rounding.large

                    RowLayout {
                        id: dockRow
                        anchors.fill: parent
                        anchors.leftMargin: padding
                        anchors.rightMargin: padding
                        property real padding: 6
                        spacing: 4

                        VerticalButtonGroup {
                            visible: Config.options?.dock.showPinButton ?? false
                            GroupButton {
                                baseWidth: 35
                                baseHeight: 35
                                clickedWidth: baseWidth
                                clickedHeight: baseHeight + 10
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
                                if (!GlobalStates.startMenuOpen && Date.now() - GlobalStates.startMenuLastClosed < 300)
                                    return;
                                GlobalStates.startMenuOpen = !GlobalStates.startMenuOpen;
                            }
                            contentItem: MaterialSymbol {
                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: parent.width / 2
                                text: "apps"
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                        DockTrash {
                            id: dockTrash
                            visible: Config.options?.dock.showTrash ?? true
                            Layout.fillHeight: true
                        }
                    }
                }
            }
        }
    }
}
