import qs.services
import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int lastFocused: -1
    property real iconSize: 35
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)
    enabled: !isSeparator

    // The ripple background renders through an OpacityMask layer whose corner radius is
    // much wider than a 1px separator, which leaves garbage pixels. Separators draw no background.
    background.visible: !isSeparator
    background.layer.enabled: !isSeparator

    // ---- macOS-style magnification ----
    readonly property bool magnifyEnabled: Config.options?.dock.magnification ?? true
    readonly property real maxMagnify: magnifyEnabled ? Math.max(1, Config.options?.dock.magnificationScale ?? 1.6) : 1
    readonly property real baseWidth: implicitHeight - topInset - bottomInset
    property real magnify: 1
    Behavior on magnify {
        NumberAnimation {
            duration: 110
            easing.type: Easing.OutCubic
        }
    }
    implicitWidth: isSeparator ? 1 : baseWidth * magnify

    // Imperative update (not a binding) so our own width change can't cause a binding loop
    function updateMagnify() {
        if (isSeparator || !magnifyEnabled || !appListRoot || !appListRoot.hovering) {
            root.magnify = 1;
            return;
        }
        const center = root.mapToItem(appListRoot, root.width / 2, 0).x;
        const range = (Config.options?.dock.magnificationRange ?? 2.5) * root.baseWidth;
        const distance = Math.abs(appListRoot.hoverX - center);
        const t = distance >= range ? 0 : (Math.cos(Math.PI * distance / range) + 1) / 2;
        root.magnify = 1 + (root.maxMagnify - 1) * t;
    }
    Connections {
        target: root.appListRoot
        function onHoverXChanged() { root.updateMagnify(); }
        function onHoveringChanged() { root.updateMagnify(); }
    }

    // ---- Bounce while launching ----
    property real bounceOffset: 0
    readonly property bool hasWindows: appToplevel.toplevels.length > 0
    onHasWindowsChanged: {
        if (hasWindows) {
            bounceAnim.stop();
            root.bounceOffset = 0;
        }
    }
    SequentialAnimation {
        id: bounceAnim
        loops: 3
        NumberAnimation {
            target: root
            property: "bounceOffset"
            from: 0
            to: -14
            duration: 220
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: 0
            duration: 220
            easing.type: Easing.InQuad
        }
        onStopped: root.bounceOffset = 0
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.desktopEntry = DesktopEntries.heuristicLookup(appToplevel.appId);
        }
    }

    // Separator between pinned and running apps: a plain centered line, icon-height
    Rectangle {
        visible: root.isSeparator
        anchors.centerIn: parent
        width: 1
        height: root.iconSize * 0.8
        radius: 0
        antialiasing: false
        color: Appearance.colors.colOutlineVariant
    }

    Loader {
        anchors.fill: parent
        active: appToplevel.toplevels.length > 0
        sourceComponent: MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                appListRoot.lastHoveredButton = root
                appListRoot.buttonHovered = true
                lastFocused = appToplevel.toplevels.length - 1
            }
            onExited: {
                if (appListRoot.lastHoveredButton === root) {
                    appListRoot.buttonHovered = false
                }
            }
        }
    }

    onClicked: {
        if (appToplevel.toplevels.length === 0) {
            root.desktopEntry?.execute();
            if (Config.options?.dock.bounceOnLaunch ?? true)
                bounceAnim.restart();
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        const toplevel = appToplevel.toplevels[lastFocused];

        // Minimized windows live on the hidden "special:minimized" workspace. Bring them back to the
        // current workspace directly instead of relying on the activation request.
        const address = toplevel.HyprlandToplevel?.address;
        const client = address ? HyprlandData.windowByAddress[`0x${address}`] : null;
        if (client?.workspace?.name === "special:minimized") {
            const workspaceId = HyprlandData.activeWorkspace?.id ?? Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${workspaceId}", follow = false, window = "address:0x${address}" })`);
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${address}" })`);
            return;
        }
        toplevel.activate()
    }

    middleClickAction: () => {
        root.desktopEntry?.execute();
    }

    altAction: () => {
        TaskbarApps.togglePin(appToplevel.appId);
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.centerIn: parent

            // Rendered at max magnified size and scaled down, so icons stay sharp when they grow.
            // Its bottom edge sits where the normal-size icon's bottom would be; it grows upward from there.
            Item {
                id: iconContainer
                readonly property real renderSize: root.iconSize * root.maxMagnify
                width: renderSize
                height: renderSize
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: -(renderSize - root.iconSize) / 2
                }
                scale: root.magnify / root.maxMagnify
                transformOrigin: Item.Bottom
                transform: Translate {
                    y: root.bounceOffset
                }

                Loader {
                    id: iconImageLoader
                    anchors.fill: parent
                    active: !root.isSeparator
                    sourceComponent: IconImage {
                        source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                        implicitSize: iconContainer.renderSize
                    }
                }

                Loader {
                    active: Config.options.dock.monochromeIcons
                    anchors.fill: iconImageLoader
                    sourceComponent: Item {
                        Desaturate {
                            id: desaturatedIcon
                            visible: false // There's already color overlay
                            anchors.fill: parent
                            source: iconImageLoader
                            desaturation: 0.8
                        }
                        ColorOverlay {
                            anchors.fill: desaturatedIcon
                            source: desaturatedIcon
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                        }
                    }
                }
            }

            RowLayout {
                spacing: 3
                anchors {
                    top: iconContainer.bottom
                    topMargin: 2
                    horizontalCenter: parent.horizontalCenter
                }
                Repeater {
                    readonly property bool singleDot: Config.options?.dock.singleDotIndicator ?? true
                    model: Math.min(appToplevel.toplevels.length, singleDot ? 1 : 3)
                    delegate: Rectangle {
                        required property int index
                        radius: Appearance.rounding.full
                        implicitWidth: ((Config.options?.dock.singleDotIndicator ?? true) || appToplevel.toplevels.length > 3) ?
                            root.countDotHeight : root.countDotWidth // Circles for macOS style / too many
                        implicitHeight: root.countDotHeight
                        color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    }
                }
            }
        }
    }
}
