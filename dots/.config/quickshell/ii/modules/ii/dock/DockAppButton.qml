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
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true) && !root.isMinimized(t)) !== undefined

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
        // No magnification while an icon is dragged to a new place: equal widths keep the
        // drop position predictable
        if (isSeparator || !magnifyEnabled || !appListRoot || !appListRoot.hovering || appListRoot.reordering) {
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
        function onReorderingChanged() { root.updateMagnify(); }
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

    // Plasma/Windows-like: click a running app to bring it to the front, click it again while it
    // is the active window to minimize it. With several windows, clicks go through them in turn.
    function windowTarget(toplevel) {
        const address = toplevel?.HyprlandToplevel?.address;
        return address ? `address:0x${address}` : "";
    }
    function isMinimized(toplevel) {
        const address = toplevel?.HyprlandToplevel?.address;
        return !!address && HyprlandData.windowByAddress[`0x${address}`]?.workspace?.name === "special:minimized";
    }
    function minimize(toplevel) {
        const address = toplevel?.HyprlandToplevel?.address;
        // Through Hyprland's Lua config (minimize.lua), which animates it like the title bar button
        if (address)
            Quickshell.execDetached(["hyprctl", "eval", `desktop_minimize_address("0x${address}")`]);
    }
    function bringToFront(toplevel) {
        const target = root.windowTarget(toplevel);
        if (target === "") {
            toplevel.activate();
            return;
        }
        // Minimized windows live on the hidden "special:minimized" workspace: bring them back
        // to the current workspace first
        const client = HyprlandData.windowByAddress[target.slice("address:".length)];
        if (client?.workspace?.name === "special:minimized") {
            const ws = HyprlandData.activeWorkspace;
            // Named workspaces have negative ids, which Hyprland would read as a relative offset
            const workspace = (ws?.id ?? 1) > 0 ? `${ws?.id ?? 1}` : `name:${ws.name}`;
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${workspace}", follow = false, window = "${target}" })`);
        }
        Hyprland.dispatch(`hl.dsp.focus({ window = "${target}" })`);
        // Focusing does not raise a floating window
        Hyprland.dispatch(`hl.dsp.window.alter_zorder({ mode = "top", window = "${target}" })`);
    }

    onClicked: {
        const toplevels = appToplevel.toplevels;
        if (toplevels.length === 0) {
            root.desktopEntry?.execute();
            if (Config.options?.dock.bounceOnLaunch ?? true)
                bounceAnim.restart();
            return;
        }
        // A minimized window can still be reported as the active one (nothing else took the focus
        // after it was hidden): it doesn't count, so the click brings it back instead of trying
        // to minimize it again
        const activeIndex = toplevels.findIndex(t => t.activated && !root.isMinimized(t));
        if (toplevels.length === 1 && activeIndex === 0) {
            root.minimize(toplevels[0]);
            return;
        }
        // Next window after the active one (or after the last one clicked)
        lastFocused = ((activeIndex !== -1 ? activeIndex : lastFocused) + 1) % toplevels.length;
        root.bringToFront(toplevels[lastFocused]);
    }

    middleClickAction: () => {
        root.desktopEntry?.execute();
    }

    // Right click: app menu (new window, its own actions, pin, close)
    altAction: () => {
        appListRoot.openMenu(root);
    }

    // ---- Drag pinned apps sideways to reorder them ----
    property real reorderShift: 0
    z: reorderDrag.active ? 10 : 0
    transform: Translate {
        x: reorderDrag.active ? root.reorderShift : 0
    }
    DragHandler {
        id: reorderDrag
        target: null
        enabled: !root.isSeparator && (root.appToplevel?.pinned ?? false)
        yAxis.enabled: false
        onActiveTranslationChanged: if (active) root.reorderShift = activeTranslation.x
        onActiveChanged: {
            appListRoot.reordering = active;
            if (active) {
                appListRoot.closeMenu();
                return;
            }
            const steps = Math.round(root.reorderShift / (root.baseWidth + 2));
            root.reorderShift = 0;
            if (steps !== 0)
                root.movePin(steps);
        }
    }
    function movePin(steps) {
        const pins = [...Config.options.dock.pinnedApps];
        const id = root.appToplevel.appId.toLowerCase();
        const from = pins.findIndex(p => p.toLowerCase() === id);
        if (from === -1) return;
        const to = Math.max(0, Math.min(pins.length - 1, from + steps));
        if (to === from) return;
        const [moved] = pins.splice(from, 1);
        pins.splice(to, 0, moved);
        Config.options.dock.pinnedApps = pins;
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
