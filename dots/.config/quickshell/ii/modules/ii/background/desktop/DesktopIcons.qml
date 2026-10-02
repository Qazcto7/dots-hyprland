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

    // Background widgets (clock, weather) that icons must not be placed under
    property var obstacleItems: []
    // Changes whenever an obstacle moves/resizes/shows/hides, to trigger a relayout
    readonly property string obstacleKey: obstacleItems.map(i => i ? `${i.x},${i.y},${i.width},${i.height},${i.visible}` : "").join(";")
    onObstacleKeyChanged: obstacleTimer.restart()
    Timer {
        id: obstacleTimer
        interval: 400 // widgets animate into place; wait for them to settle
        onTriggered: root.relayout()
    }

    // Cells ("col,row") covered by an obstacle
    function blockedCells() {
        const blocked = {};
        for (const obstacle of root.obstacleItems) {
            if (!obstacle || !obstacle.visible || obstacle.width <= 0 || obstacle.height <= 0)
                continue;
            const r = obstacle.mapToItem(root, 0, 0, obstacle.width, obstacle.height);
            for (let col = 0; col < root.columns; col++) {
                for (let row = 0; row < root.rows; row++) {
                    const cx = root.cellX(col), cy = root.cellY(row);
                    const overlaps = cx < r.x + r.width && cx + root.cellWidth > r.x && cy < r.y + r.height && cy + root.cellHeight > r.y;
                    if (overlaps)
                        blocked[`${col},${row}`] = true;
                }
            }
        }
        return blocked;
    }

    // Nearest cell to (col,row) that is neither blocked nor taken
    function nearestFreeCell(col, row, taken) {
        let best = null;
        let bestDistance = Infinity;
        for (let c = 0; c < root.columns; c++) {
            for (let r = 0; r < root.rows; r++) {
                if (taken[`${c},${r}`])
                    continue;
                const d = (c - col) * (c - col) + (r - row) * (r - row);
                if (d < bestDistance) {
                    bestDistance = d;
                    best = { col: c, row: r };
                }
            }
        }
        return best ?? { col: col, row: row };
    }

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
        const occupied = root.blockedCells(); // blocked cells count as occupied
        const result = [];
        const pending = [];
        for (let i = 0; i < folderModel.count; i++) {
            const name = folderModel.get(i, "fileName");
            const item = {
                name: name,
                path: FileUtils.trimFileProtocol(folderModel.get(i, "filePath")),
                isDir: folderModel.get(i, "fileIsDir"),
                // FolderListModel's fileSuffix is the *complete* suffix ("hgl.desktop" for
                // "com.heroicgameslauncher.hgl.desktop"), so take the last extension ourselves
                suffix: name.lastIndexOf(".") > 0 ? name.slice(name.lastIndexOf(".") + 1).toLowerCase() : ""
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
        const totalCells = root.columns * root.rows;
        for (const item of pending) {
            while (cell < totalCells && occupied[`${Math.floor(cell / root.rows)},${cell % root.rows}`])
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
        let col = Math.max(0, Math.min(root.columns - 1, Math.round((x - root.sideMargin) / root.cellWidth)));
        let row = Math.max(0, Math.min(root.rows - 1, Math.round((y - root.topMargin) / root.cellHeight)));
        // Dropped under a widget: use the nearest cell that is not under one
        const blocked = root.blockedCells();
        if (blocked[`${col},${row}`]) {
            const free = root.nearestFreeCell(col, row, blocked);
            col = free.col;
            row = free.row;
        }
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

    // ---------- Keyboard (the background layer takes keyboard focus when clicked) ----------
    readonly property var selectedItem: root.items.find(i => i.name === root.selectedName) ?? null
    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.selectedName = "";
        } else if (!root.selectedItem) {
            return;
        } else if (event.key === Qt.Key_Delete) {
            root.trash(root.selectedItem);
            root.selectedName = "";
        } else if (event.key === Qt.Key_F2) {
            root.rename(root.selectedItem);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.open(root.selectedItem);
        } else {
            return;
        }
        event.accepted = true;
    }

    // ---------- Drop files from a file manager (Dolphin...) ----------
    // Always copies (never moves, so nothing disappears from its original place by accident).
    // Dropped files land where they were dropped.
    DropArea {
        id: dropArea
        anchors.fill: parent
        onEntered: drag => {
            if (drag.hasUrls) drag.accept(Qt.CopyAction);
        }
        onDropped: drop => {
            if (!drop.hasUrls || root.desktopDir === "")
                return;
            const paths = drop.urls
                .map(u => decodeURIComponent(u.toString()))
                .filter(u => u.startsWith("file://"))
                .map(u => u.slice("file://".length))
                .filter(p => p.substring(0, p.lastIndexOf("/")) !== root.desktopDir); // already on the desktop
            if (paths.length === 0)
                return;
            root.placeDroppedFiles(paths.map(p => p.substring(p.lastIndexOf("/") + 1)), drop.x, drop.y);
            Quickshell.execDetached(["bash", "-c", 'dir="$1"; shift; cp -rn -- "$@" "$dir"/', "drop", root.desktopDir, ...paths]);
            drop.accept(Qt.CopyAction);
        }
    }
    Rectangle { // drop highlight
        anchors.fill: parent
        anchors.margins: 6
        visible: dropArea.containsDrag
        color: "transparent"
        radius: Appearance.rounding.normal
        border.width: 2
        border.color: Appearance.colors.colPrimary
    }

    // Reserve cells at the drop point for files that are about to appear
    function placeDroppedFiles(names, x, y) {
        const taken = root.blockedCells();
        for (const i of root.items)
            taken[`${i.col},${i.row}`] = true;
        let col = Math.max(0, Math.min(root.columns - 1, Math.round((x - root.sideMargin - root.cellWidth / 2) / root.cellWidth)));
        let row = Math.max(0, Math.min(root.rows - 1, Math.round((y - root.topMargin - root.cellHeight / 2) / root.cellHeight)));
        const newPositions = Object.assign({}, root.positions);
        for (const name of names) {
            if (root.items.some(i => i.name === name))
                continue; // name already exists on the desktop; cp/mv -n won't overwrite it
            const cell = root.nearestFreeCell(col, row, taken);
            newPositions[name] = cell;
            taken[`${cell.col},${cell.row}`] = true;
        }
        root.positions = newPositions;
        root.savePositions();
    }

    // ---------- Empty desktop area ----------
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: event => {
            root.forceActiveFocus();
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
