pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Right-click menus for DesktopIcons. Lives above the background widgets so menus are not covered.
 * Invisible (and click-through) unless a menu is open.
 */
Item {
    id: root
    required property var desktop

    property var targetItem: null // null = desktop menu
    property bool open: false
    visible: open

    function close() {
        root.open = false;
        root.openWithApps = null;
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) root.close();
        }
    }

    Connections {
        target: root.desktop
        function onItemMenuRequested(item, x, y) {
            root.targetItem = item;
            root.showAt(x, y);
        }
        function onDesktopMenuRequested(x, y) {
            root.targetItem = null;
            root.showAt(x, y);
        }
    }

    // Where the menu was opened (paste puts the files there)
    property real menuX: 0
    property real menuY: 0
    function showAt(x, y) {
        root.openWithApps = null;
        root.menuX = x;
        root.menuY = y;
        root.open = true;
        menu.x = Math.max(8, Math.min(x, root.width - menu.width - 8));
        menu.y = Math.max(8, Math.min(y, root.height - menu.height - 8));
    }

    // Click anywhere else closes the menu
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }

    // With several icons selected, Open / Copy path / Move to trash act on all of them
    readonly property var actionTargets: {
        const selection = root.desktop?.selectedItems ?? [];
        if (root.targetItem && selection.some(i => i.name === root.targetItem.name))
            return selection;
        return root.targetItem ? [root.targetItem] : [];
    }
    readonly property bool multiple: actionTargets.length > 1
    readonly property var itemActions: [
        { icon: "open_in_new", text: Translation.tr("Open"), run: () => root.actionTargets.forEach(i => root.desktop.open(i)) },
        ...(root.multiple ? [] : [
            { icon: "apps", text: Translation.tr("Open with…"), keepOpen: true, run: () => root.showOpenWith(root.targetItem) },
        ]),
        { icon: "content_copy", text: Translation.tr("Copy") + "  (Ctrl+C)", run: () => root.desktop.copyFiles(root.actionTargets, false) },
        { icon: "content_cut", text: Translation.tr("Cut") + "  (Ctrl+X)", run: () => root.desktop.copyFiles(root.actionTargets, true) },
        ...((Config.options?.desktopMode.quickLook ?? true) ? [
            { icon: "visibility", text: Translation.tr("Quick Look") + "  (Space)", run: () => root.desktop.quickLook(root.actionTargets) },
        ] : []),
        ...(root.multiple ? [] : [
            { icon: "folder_open", text: Translation.tr("Show in file manager"), run: () => root.desktop.showInFileManager(root.targetItem) },
            { icon: "edit", text: Translation.tr("Rename"), run: () => root.desktop.rename(root.targetItem) },
        ]),
        { icon: "content_copy", text: Translation.tr("Copy path"), run: () => root.desktop.copyPaths(root.actionTargets) },
        { icon: "delete", text: root.multiple ? Translation.tr("Move %1 items to trash").arg(root.actionTargets.length) : Translation.tr("Move to trash"),
            run: () => { root.desktop.trashMany(root.actionTargets); root.desktop.clearSelection(); } },
    ]
    readonly property var desktopActions: [
        ...(root.desktop?.lastUndo ? [
            { icon: "undo", text: Translation.tr("Undo: %1").arg(root.desktop.lastUndo.label) + "  (Ctrl+Z)", run: () => root.desktop.undo() },
        ] : []),
        { icon: "content_paste", text: Translation.tr("Paste") + "  (Ctrl+V)", run: () => root.desktop.paste(root.menuX, root.menuY) },
        { icon: "create_new_folder", text: Translation.tr("New folder"), run: () => root.desktop.newFolder() },
        { icon: "note_add", text: Translation.tr("New text file"), run: () => root.desktop.newTextFile() },
        { icon: "terminal", text: Translation.tr("Open terminal here"), run: () => root.desktop.openTerminalHere() },
        { icon: "folder_open", text: Translation.tr("Open desktop folder"), run: () => root.desktop.openDesktopFolder() },
        { icon: "wallpaper", text: Translation.tr("Change wallpaper"), run: () => root.desktop.changeWallpaper() },
        { icon: "grid_view", text: Translation.tr("Arrange icons"), run: () => root.desktop.resetPositions() },
        { icon: "monitor", text: Translation.tr("Display settings"), run: () => root.desktop.displaySettings() },
        { icon: "settings", text: Translation.tr("System Settings"), run: () => root.desktop.systemSettings() },
    ]

    // ---- "Open with" page: apps registered for the file type, default first ----
    property var openWithApps: null // null = normal menu
    property var openWithTarget: null
    function showOpenWith(item) {
        root.openWithTarget = item;
        root.desktop.openWithApps(item, apps => {
            if (!root.open || root.openWithTarget !== item) return;
            root.openWithApps = apps;
            // The list can be taller than the menu was: keep it on screen
            Qt.callLater(() => { menu.y = Math.max(8, Math.min(menu.y, root.height - menu.height - 8)); });
        });
    }
    readonly property var openWithActions: [
        { icon: "arrow_back", text: Translation.tr("Back"), keepOpen: true, run: () => { root.openWithApps = null; } },
        ...(root.openWithApps ?? []).map(app => ({ icon: "open_in_new", text: app.name, run: () => root.desktop.openWith(root.openWithTarget, app.id) })),
        ...((root.openWithApps ?? []).length === 0 ? [{ icon: "block", text: Translation.tr("No apps found for this file type"), keepOpen: true, run: () => {} }] : []),
    ]

    StyledRectangularShadow {
        target: menu
    }
    Rectangle {
        id: menu
        width: 250
        height: menuColumn.implicitHeight + 12
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            Repeater {
                model: root.openWithApps !== null ? root.openWithActions : (root.targetItem ? root.itemActions : root.desktopActions)
                delegate: RippleButtonWithIcon {
                    required property var modelData
                    Layout.fillWidth: true
                    colBackground: "transparent"
                    materialIcon: modelData.icon
                    mainText: modelData.text
                    // Keep keyboard focus on the desktop (Ctrl+Z, Delete... after using the menu)
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        if (modelData.keepOpen) {
                            modelData.run();
                            return;
                        }
                        root.close();
                        root.desktop.forceActiveFocus();
                        modelData.run();
                    }
                }
            }
        }
    }
}
