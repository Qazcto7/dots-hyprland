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
            readonly property bool hoverRevealEnabled: (Config.options?.dock.hoverToReveal ?? true) || fullscreenActive
            WlrLayershell.layer: fullscreenActive ? WlrLayer.Overlay : WlrLayer.Top

            property bool reveal: fullscreenActive
                ? (dockMouseArea.containsMouse || dockApps.requestDockShow)
                : (root.pinned || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse) || dockApps.requestDockShow || (!ToplevelManager.activeToplevel?.activated))

            anchors {
                bottom: true
                left: true
                right: true
            }

            exclusiveZone: (root.pinned && !fullscreenActive) ? implicitHeight - root.headroom - (Appearance.sizes.hyprlandGapsOut) - (Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut) : 0

            implicitWidth: dockBackground.implicitWidth
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            implicitHeight: (Config.options?.dock.height ?? 70) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut + root.headroom

            // Input only on the dock itself, not on the transparent headroom above it
            mask: Region {
                item: dockInputRegion
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
                    id: dockInputRegion
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        topMargin: dockRoot.reveal ? root.headroom : 0
                    }
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
                        }
                    }
                }
            }
        }
    }
}
