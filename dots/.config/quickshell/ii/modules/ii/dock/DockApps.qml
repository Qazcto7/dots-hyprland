pragma ComponentBehavior: Bound
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30
    property real buttonPadding: 5

    property Item lastHoveredButton: null
    property bool buttonHovered: false
    property bool requestDockShow: previewPopup.show || appMenu.visible

    property bool reordering: false // a pinned icon is being dragged to a new place

    // ---- Right-click menu of an app ----
    property Item menuButton: null
    function openMenu(button) {
        root.menuButton = button;
        appMenu.visible = true;
    }
    function closeMenu() {
        appMenu.visible = false;
    }

    // macOS-style magnification: cursor position over the app icons
    readonly property bool hovering: magnifyHoverHandler.hovered
    readonly property real hoverX: magnifyHoverHandler.point.position.x

    HoverHandler {
        id: magnifyHoverHandler
        enabled: Config.options?.dock.magnification ?? true
    }

    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.hyprlandGapsOut
    implicitWidth: listView.implicitWidth

    function popupCenterXForButton(button) {
        if (!button || !root.QsWindow)
            return 0;
        return root.QsWindow.mapFromItem(button, button.width / 2, 0).x;
    }

    StyledListView {
        id: listView
        spacing: 2
        orientation: ListView.Horizontal
        interactive: false // icons are dragged to reorder them, not to scroll the dock
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        implicitWidth: contentWidth

        // Not while magnifying: the dock width must follow the icons right away
        Behavior on implicitWidth {
            enabled: !root.hovering
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.apps
        }
        delegate: DockAppButton {
            required property var modelData
            appToplevel: modelData
            appListRoot: root

            topInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            bottomInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
        }
    }

    PopupWindow {
        id: previewPopup
        property var appTopLevel: root.lastHoveredButton?.appToplevel

        property bool shouldShow: !appMenu.visible && (popupMouseArea.containsMouse || root.buttonHovered) && appTopLevel && appTopLevel.toplevels && appTopLevel.toplevels.length > 0

        property bool show: false
        property real cachedCenterX: 0

        Connections {
            target: root
            function onLastHoveredButtonChanged() {
                if (root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenterX = root.popupCenterXForButton(root.lastHoveredButton);
            }
            function onButtonHoveredChanged() {
                if (root.buttonHovered && root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenterX = root.popupCenterXForButton(root.lastHoveredButton);
                updateTimer.restart();
            }
        }

        onShouldShowChanged: {
            updateTimer.restart();
        }

        Timer {
            id: updateTimer
            // Longer delay when hiding so the cursor can travel from the icon up to the preview
            interval: previewPopup.shouldShow ? 100 : 350
            onTriggered: {
                previewPopup.show = previewPopup.shouldShow;
            }
        }

        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.None
            gravity: Edges.Top | Edges.Right
            edges: Edges.Top | Edges.Left
        }

        visible: popupBackground.opacity > 0
        color: "transparent"
        implicitWidth: root.QsWindow.window?.width ?? 1
        implicitHeight: popupMouseArea.implicitHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2

        MouseArea {
            id: popupMouseArea
            anchors.bottom: parent.bottom
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: root.maxWindowPreviewHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2
            hoverEnabled: true
            x: previewPopup.cachedCenterX - width / 2

            StyledRectangularShadow {
                target: popupBackground
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                id: popupBackground
                property real padding: 5
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                clip: true
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.sizes.elevationMargin
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: previewRowLayout.implicitHeight + padding * 2
                implicitWidth: previewRowLayout.implicitWidth + padding * 2
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: previewRowLayout
                    anchors.centerIn: parent
                    Repeater {
                        model: ScriptModel {
                            values: previewPopup.appTopLevel?.toplevels ?? []
                        }
                        RippleButton {
                            id: windowButton
                            Layout.fillHeight: true
                            required property var modelData
                            padding: 0
                            middleClickAction: () => {
                                windowButton.modelData?.close();
                            }
                            onClicked: {
                                windowButton.modelData?.activate();
                            }
                            contentItem: ColumnLayout {
                                implicitWidth: screencopyView.implicitWidth
                                implicitHeight: screencopyView.implicitHeight

                                ButtonGroup {
                                    contentWidth: parent.width - anchors.margins * 2
                                    StyledText {
                                        Layout.margins: 5
                                        Layout.fillWidth: true
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        text: windowButton.modelData?.title
                                        elide: Text.ElideRight
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    GroupButton {
                                        id: closeButton
                                        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                        baseWidth: root.windowControlsHeight
                                        baseHeight: root.windowControlsHeight
                                        buttonRadius: Appearance.rounding.full
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "close"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        onClicked: {
                                            windowButton.modelData?.close();
                                        }
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    implicitHeight: screencopyView.height
                                    implicitWidth: screencopyView.width
                                    ScreencopyView {
                                        id: screencopyView
                                        anchors.centerIn: parent
                                        captureSource: windowButton.modelData
                                        live: true
                                        paintCursor: true
                                        constraintSize: Qt.size(root.maxWindowPreviewWidth, root.maxWindowPreviewHeight)
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: screencopyView.width
                                                height: screencopyView.height
                                                radius: Appearance.rounding.small
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    PopupWindow {
        id: appMenu
        visible: false
        grabFocus: true // a click anywhere else closes it
        color: "transparent"

        readonly property var app: root.menuButton?.appToplevel ?? null
        readonly property var entry: root.menuButton?.desktopEntry ?? null
        readonly property var windows: appMenu.app?.toplevels ?? []
        readonly property bool pinned: appMenu.app ? TaskbarApps.isPinned(appMenu.app.appId) : false

        anchor {
            item: root.menuButton
            edges: Edges.Top
            gravity: Edges.Top
            adjustment: PopupAdjustment.Slide
        }

        implicitWidth: menuBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
        implicitHeight: menuBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

        component MenuItem: RippleButtonWithIcon {
            Layout.fillWidth: true
            colBackground: "transparent"
        }

        StyledRectangularShadow {
            target: menuBackground
        }
        Rectangle {
            id: menuBackground
            anchors.centerIn: parent
            implicitWidth: Math.max(220, menuColumn.implicitWidth + 12)
            implicitHeight: menuColumn.implicitHeight + 12
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                id: menuColumn
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    text: appMenu.entry?.name ?? appMenu.app?.appId ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
                // The app's own actions from its .desktop file (e.g. "New Private Window")
                Repeater {
                    model: appMenu.entry?.actions ?? []
                    delegate: MenuItem {
                        required property var modelData
                        materialIcon: "bolt"
                        mainText: modelData.name
                        onClicked: {
                            root.closeMenu();
                            modelData.execute();
                        }
                    }
                }
                MenuItem {
                    visible: appMenu.entry !== null
                    materialIcon: "add"
                    mainText: Translation.tr("New window")
                    onClicked: {
                        root.closeMenu();
                        appMenu.entry.execute();
                    }
                }
                MenuItem {
                    materialIcon: "keep"
                    mainText: appMenu.pinned ? Translation.tr("Unpin from dock") : Translation.tr("Pin to dock")
                    onClicked: {
                        if (!appMenu.app) return;
                        const id = appMenu.app.appId;
                        root.closeMenu();
                        TaskbarApps.togglePin(id);
                    }
                }
                MenuItem {
                    visible: appMenu.windows.length > 0
                    materialIcon: "close"
                    mainText: appMenu.windows.length > 1 ? Translation.tr("Close all windows (%1)").arg(appMenu.windows.length) : Translation.tr("Close")
                    onClicked: {
                        const windows = [...appMenu.windows];
                        root.closeMenu();
                        for (const toplevel of windows)
                            toplevel.close();
                    }
                }
            }
        }
    }
}
