pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * macOS-like trash at the end of the dock.
 * Click: open the trash in the file manager. Right click: open / empty.
 * Drop files on it (e.g. from Dolphin) to move them to the trash.
 * The icon shows whether the trash has something in it.
 */
DockButton {
    id: root

    readonly property string trashDir: FileUtils.trimFileProtocol(`${Directories.home}/.local/share/Trash/files`)
    readonly property int itemCount: trashFiles.count
    readonly property bool full: itemCount > 0
    readonly property bool menuOpen: trashMenu.visible

    // The folder must exist to be watched (a fresh account has no trash yet)
    property bool trashDirReady: false
    Process {
        running: true
        command: ["mkdir", "-p", root.trashDir]
        onExited: root.trashDirReady = true
    }

    // Watches the trash folder, so the icon updates as soon as something is trashed or emptied
    FolderListModel {
        id: trashFiles
        folder: root.trashDirReady ? "file://" + root.trashDir.split("/").map(part => encodeURIComponent(part)).join("/") : ""
        showDirs: true
        showHidden: true
        showDotAndDotDot: false
    }

    function openTrash() {
        Quickshell.execDetached(["bash", "-c", "dolphin trash:/ || xdg-open trash:///"]);
    }
    function emptyTrash() {
        // Asks first (kdialog or zenity); without either it doesn't empty anything
        Quickshell.execDetached(["bash", "-c",
            'if command -v kdialog >/dev/null; then kdialog --title "$1" --warningyesno "$2"; '
            + 'elif command -v zenity >/dev/null; then zenity --question --title "$1" --text "$2"; else exit 1; fi && gio trash --empty',
            "empty-trash", Translation.tr("Empty trash"),
            Translation.tr("Permanently delete the %1 items in the trash? This can't be undone.").arg(root.itemCount)]);
    }

    onClicked: root.openTrash()
    altAction: () => {
        trashMenu.visible = true;
    }

    contentItem: Item {
        IconImage {
            anchors.centerIn: parent
            implicitSize: 35
            source: Quickshell.iconPath(root.full ? "user-trash-full" : "user-trash", "user-trash")
            scale: dropArea.containsDrag ? 1.15 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // Drop files from the file manager to trash them
    DropArea {
        id: dropArea
        anchors.fill: parent
        onEntered: drag => {
            if (drag.hasUrls) drag.accept(Qt.MoveAction);
        }
        onDropped: drop => {
            if (!drop.hasUrls) return;
            const paths = drop.urls.map(u => u.toString())
                .filter(u => u.startsWith("file://"))
                .map(u => decodeURIComponent(u.slice("file://".length)));
            if (paths.length === 0) return;
            Quickshell.execDetached(["gio", "trash", "--", ...paths]);
            drop.accept(Qt.MoveAction);
        }
    }

    PopupWindow {
        id: trashMenu
        visible: false
        grabFocus: true
        color: "transparent"
        anchor {
            item: root
            edges: Edges.Top
            gravity: Edges.Top
            adjustment: PopupAdjustment.Slide
        }
        implicitWidth: menuBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
        implicitHeight: menuBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

        StyledRectangularShadow {
            target: menuBackground
        }
        Rectangle {
            id: menuBackground
            anchors.centerIn: parent
            implicitWidth: Math.max(200, menuColumn.implicitWidth + 12)
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

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    colBackground: "transparent"
                    materialIcon: "folder_open"
                    mainText: Translation.tr("Open trash")
                    onClicked: {
                        trashMenu.visible = false;
                        root.openTrash();
                    }
                }
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    enabled: root.full
                    colBackground: "transparent"
                    materialIcon: "delete_forever"
                    mainText: root.full ? Translation.tr("Empty trash (%1 items)").arg(root.itemCount) : Translation.tr("Trash is empty")
                    onClicked: {
                        trashMenu.visible = false;
                        root.emptyTrash();
                    }
                }
            }
        }
    }
}
