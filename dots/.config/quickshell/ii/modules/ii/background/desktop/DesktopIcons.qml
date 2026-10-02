pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * Plasma-like desktop icons for the files in the XDG desktop folder (~/Masaüstü, ~/Desktop...).
 * Icons sit on a grid (column by column from the top-left), can be dragged to another
 * cell (positions are remembered), double-click opens, right-click shows a menu.
 * The menus themselves are drawn by DesktopContextMenu, which sits above the background widgets.
 */
Item {
    id: root

    // Area kept free for the bar (top) and the dock (bottom)
    property real topMargin: 70
    property real bottomMargin: 110
    property real sideMargin: 16
    readonly property real cellWidth: 96
    readonly property real cellHeight: 104

    readonly property int rows: Math.max(1, Math.floor((height - topMargin - bottomMargin) / cellHeight))
    readonly property int columns: Math.max(1, Math.floor((width - 2 * sideMargin) / cellWidth))

    property string desktopDir: ""
    property string selectedName: ""
    property var positions: ({}) // fileName -> { col, row }
    property var items: []       // [{ name, path, isDir, suffix, col, row }]

    // Menu requests, handled by DesktopContextMenu
    signal itemMenuRequested(var item, real x, real y)
    signal desktopMenuRequested(real x, real y)

    // ---------- Desktop folder ----------
    Process {
        id: findDesktopDir
        running: true
        command: ["bash", "-c", 'd="$(xdg-user-dir DESKTOP 2>/dev/null)"; [ -z "$d" ] || [ "$d" = "$HOME" ] && d="$HOME/Desktop"; mkdir -p "$d"; printf "%s" "$d"']
        stdout: StdioCollector {
            onStreamFinished: root.desktopDir = text.trim()
        }
    }

    FolderListModel {
        id: folderModel
        folder: root.desktopDir !== "" ? `file://${root.desktopDir}` : ""
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
        onCountChanged: root.relayout()
        onStatusChanged: root.relayout()
    }

    // ---------- Remembered positions ----------
    readonly property string positionsPath: FileUtils.trimFileProtocol(`${Directories.state}/user/desktop_icons.json`)
    FileView {
        id: positionsFile
        path: root.positionsPath
        onLoaded: {
            try {
                root.positions = JSON.parse(positionsFile.text()) ?? {};
            } catch (e) {
                root.positions = {};
            }
            root.relayout();
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound)
                positionsFile.setText("{}");
        }
    }
    function savePositions() {
        positionsFile.setText(JSON.stringify(root.positions));
    }

    onRowsChanged: relayout()
    onColumnsChanged: relayout()

    function relayout() {
        if (folderModel.status !== FolderListModel.Ready) {
            root.items = [];
            return;
        }
        const occupied = {};
        const result = [];
        const pending = [];
        for (let i = 0; i < folderModel.count; i++) {
            const name = folderModel.get(i, "fileName");
            const item = {
                name: name,
                path: FileUtils.trimFileProtocol(folderModel.get(i, "filePath")),
                isDir: folderModel.get(i, "fileIsDir"),
                suffix: (folderModel.get(i, "fileSuffix") ?? "").toLowerCase()
            };
            const saved = root.positions[name];
            if (saved && saved.col < root.columns && saved.row < root.rows && !occupied[`${saved.col},${saved.row}`]) {
                item.col = saved.col;
                item.row = saved.row;
                occupied[`${item.col},${item.row}`] = true;
                result.push(item);
            } else {
                pending.push(item);
            }
        }
        // Remaining icons fill free cells column by column, like Plasma
        let cell = 0;
        for (const item of pending) {
            while (occupied[`${Math.floor(cell / root.rows)},${cell % root.rows}`])
                cell++;
            item.col = Math.floor(cell / root.rows);
            item.row = cell % root.rows;
            occupied[`${item.col},${item.row}`] = true;
            result.push(item);
        }
        root.items = result;
    }

    function cellX(col) { return root.sideMargin + col * root.cellWidth; }
    function cellY(row) { return root.topMargin + row * root.cellHeight; }

    // Drop an icon at pixel position; snaps to the nearest cell, swaps with an icon already there
    function moveItemTo(name, x, y) {
        const col = Math.max(0, Math.min(root.columns - 1, Math.round((x - root.sideMargin) / root.cellWidth)));
        const row = Math.max(0, Math.min(root.rows - 1, Math.round((y - root.topMargin) / root.cellHeight)));
        const moving = root.items.find(i => i.name === name);
        const other = root.items.find(i => i.col === col && i.row === row && i.name !== name);
        const newPositions = Object.assign({}, root.positions);
        for (const i of root.items)
            newPositions[i.name] = { col: i.col, row: i.row };
        if (other && moving)
            newPositions[other.name] = { col: moving.col, row: moving.row };
        newPositions[name] = { col: col, row: row };
        root.positions = newPositions;
        root.savePositions();
        root.relayout();
    }

    function resetPositions() {
        root.positions = {};
        root.savePositions();
        root.relayout();
    }

    // ---------- Actions ----------
    // Text prompt with kdialog (KDE) or zenity; prints the answer, empty on cancel
    readonly property string askFn: 'ask() { if command -v kdialog >/dev/null; then kdialog --title "$1" --inputbox "$2" "$3"; elif command -v zenity >/dev/null; then zenity --entry --title "$1" --text "$2" --entry-text "$3"; fi; }'

    function open(item) {
        if (!item) return;
        if (item.suffix === "desktop") {
            const entry = DesktopEntries.byId(item.name.replace(/\.desktop$/, ""));
            if (entry) {
                entry.execute();
                return;
            }
            Quickshell.execDetached(["bash", "-c", 'gio launch "$1" || kioclient exec "$1" || xdg-open "$1"', "open", item.path]);
            return;
        }
        Quickshell.execDetached(["xdg-open", item.path]);
    }
    function showInFileManager(item) {
        Quickshell.execDetached(["bash", "-c", 'dolphin --select "$1" || xdg-open "$(dirname "$1")"', "show", item.path]);
    }
    function copyPath(item) {
        Quickshell.execDetached(["wl-copy", item.path]);
    }
    function trash(item) {
        Quickshell.execDetached(["bash", "-c", 'gio trash "$1" || kioclient move "$1" trash:/', "trash", item.path]);
    }
    function rename(item) {
        Quickshell.execDetached(["bash", "-c", root.askFn + '; new="$(ask "$3" "$4" "$2")"; [ -n "$new" ] && [ "$new" != "$2" ] && mv -n -- "$1/$2" "$1/$new"',
            "rename", root.desktopDir, item.name, Translation.tr("Rename"), Translation.tr("New name:")]);
    }
    function newFolder() {
        Quickshell.execDetached(["bash", "-c", root.askFn + '; n="$(ask "$3" "$4" "$2")"; [ -n "$n" ] && mkdir -p -- "$1/$n"',
            "newfolder", root.desktopDir, Translation.tr("New Folder"), Translation.tr("New folder"), Translation.tr("Folder name:")]);
    }
    function newTextFile() {
        Quickshell.execDetached(["bash", "-c", root.askFn + '; n="$(ask "$3" "$4" "$2")"; [ -n "$n" ] && [ ! -e "$1/$n" ] && touch -- "$1/$n"',
            "newfile", root.desktopDir, Translation.tr("New Text File") + ".txt", Translation.tr("New text file"), Translation.tr("File name:")]);
    }
    function openTerminalHere() {
        Quickshell.execDetached(["bash", "-c", 'cd "$1" && (kitty --directory "$1" || foot || konsole --workdir "$1")', "term", root.desktopDir]);
    }
    function openDesktopFolder() {
        Quickshell.execDetached(["bash", "-c", 'dolphin "$1" || xdg-open "$1"', "folder", root.desktopDir]);
    }
    function changeWallpaper() {
        GlobalStates.wallpaperSelectorOpen = true;
    }
    function displaySettings() {
        Quickshell.execDetached(["bash", "-c", "command -v nwg-displays >/dev/null && exec nwg-displays; env XDG_CURRENT_DESKTOP=KDE systemsettings kcm_kscreen"]);
    }
    function systemSettings() {
        Quickshell.execDetached(["bash", "-c", "env XDG_CURRENT_DESKTOP=KDE systemsettings"]);
    }

    // ---------- Empty desktop area ----------
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: event => {
            root.selectedName = "";
            if (event.button === Qt.RightButton)
                root.desktopMenuRequested(event.x, event.y);
        }
    }

    // ---------- Icons ----------
    Repeater {
        model: root.items
        delegate: DesktopIcon {
            required property var modelData
            item: modelData
            desktop: root
            width: root.cellWidth
            height: root.cellHeight
            homeX: root.cellX(modelData.col)
            homeY: root.cellY(modelData.row)
        }
    }
}
