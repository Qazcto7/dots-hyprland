pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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

    // Area kept free for the bar and the dock, taken from their real sizes so the
    // first icon row starts right under the bar (no unusable empty strip)
    readonly property real barSpace: (Config.options?.bar.vertical ?? false) ? 0
        : Appearance.sizes.baseBarHeight + (Appearance.barCornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0) + 4
    readonly property real dockSpace: ((Config.options?.dock.enable ?? false) && (Config.options?.dock.pinnedOnStartup ?? false))
        ? (Config.options?.dock.height ?? 60) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut + 8 : 0
    readonly property bool barAtBottom: Config.options?.bar.bottom ?? false
    property real topMargin: (barAtBottom ? 0 : barSpace) + 4
    property real bottomMargin: (barAtBottom ? barSpace : 0) + dockSpace + 4
    property real sideMargin: 16
    readonly property real cellWidth: 96
    readonly property real cellHeight: 104

    readonly property int rows: Math.max(1, Math.floor((height - topMargin - bottomMargin) / cellHeight))
    readonly property int columns: Math.max(1, Math.floor((width - 2 * sideMargin) / cellWidth))

    property string desktopDir: ""
    property var selectedNames: [] // multi-selection (click, Ctrl+click, rubber band)
    function isSelected(name) { return root.selectedNames.indexOf(name) !== -1; }
    function selectOnly(name) { root.selectedNames = [name]; }
    function toggleSelected(name) {
        root.selectedNames = root.isSelected(name) ? root.selectedNames.filter(n => n !== name) : root.selectedNames.concat([name]);
    }
    function clearSelection() { root.selectedNames = []; }
    readonly property var selectedItems: root.items.filter(i => root.selectedNames.indexOf(i.name) !== -1)

    // Group drag: while one selected icon is dragged, the other selected icons follow it by this offset
    property string groupDragLeader: ""
    property real groupDragDX: 0
    property real groupDragDY: 0
    property var positions: ({}) // fileName -> { col, row }
    property var items: []       // [{ name, path, isDir, suffix, col, row }]
    // The icon Repeater is driven by file names (strings compare by value), so existing icons
    // are kept and just move (animated) instead of being destroyed and recreated on every change.
    property var itemByName: ({})
    readonly property var itemNames: root.items.map(i => i.name)

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
        folder: root.desktopDir !== "" ? root.fileUrl(root.desktopDir) : ""
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
        // The model goes Loading -> Ready on every change in the folder. Icons are kept meanwhile
        // (relayout ignores "Loading"), so they don't all get destroyed and recreated.
        onCountChanged: relayoutTimer.restart()
        onStatusChanged: relayoutTimer.restart()
        onDataChanged: relayoutTimer.restart() // rename / replace without a count change
    }
    Timer {
        id: relayoutTimer
        interval: 50
        onTriggered: root.relayout()
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
        if (folderModel.status !== FolderListModel.Ready)
            return; // keep the current icons until the folder is read again
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
        const blocked = root.blockedCells();
        for (const item of pending) {
            while (cell < totalCells && occupied[`${Math.floor(cell / root.rows)},${cell % root.rows}`])
                cell++;
            if (cell < totalCells) {
                item.col = Math.floor(cell / root.rows);
                item.row = cell % root.rows;
            } else {
                // Grid is full. Prefer a cell that is only "occupied" because a widget covers it,
                // otherwise stack on the last cell so the icon at least stays on screen.
                const spare = Object.keys(blocked).find(key => !result.some(i => `${i.col},${i.row}` === key));
                if (spare) {
                    const [c, r] = spare.split(",").map(Number);
                    item.col = c;
                    item.row = r;
                } else {
                    item.col = root.columns - 1;
                    item.row = root.rows - 1;
                }
            }
            occupied[`${item.col},${item.row}`] = true;
            result.push(item);
        }
        const byName = {};
        for (const item of result)
            byName[item.name] = item;
        root.itemByName = byName;
        root.items = result;
        root.prunePositions(byName);
    }

    // Names reserved for files that are about to appear (dropped files): name -> timestamp
    property var reservedNames: ({})
    // Forget positions of files that are gone, so desktop_icons.json doesn't grow forever
    function prunePositions(existing) {
        const now = Date.now();
        let changed = false;
        const kept = {};
        for (const name in root.positions) {
            const reservedAt = root.reservedNames[name];
            if (existing[name] || (reservedAt && now - reservedAt < 60000))
                kept[name] = root.positions[name];
            else
                changed = true;
        }
        if (changed) {
            root.positions = kept;
            root.savePositions();
        }
    }

    // Encoded, so names with spaces, # or % work in URLs (thumbnails, folder)
    function fileUrl(path) {
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }

    function cellX(col) { return root.sideMargin + col * root.cellWidth; }
    function cellY(row) { return root.topMargin + row * root.cellHeight; }

    // Drop an icon at pixel position; snaps to the nearest cell, swaps with an icon already there
    function moveItemTo(name, x, y) {
        root.pushUndo({ type: "positions", label: Translation.tr("Move icon"), positions: root.snapshotPositions() });
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

    // Move several icons by the same number of cells. Cells taken by other icons or under
    // widgets are skipped: that icon goes to the nearest free cell instead.
    function moveGroup(names, dCol, dRow) {
        if (dCol === 0 && dRow === 0) {
            root.relayout();
            return;
        }
        root.pushUndo({ type: "positions", label: Translation.tr("Move icons"), positions: root.snapshotPositions() });
        const clampCol = c => Math.max(0, Math.min(root.columns - 1, c));
        const clampRow = r => Math.max(0, Math.min(root.rows - 1, r));
        const moving = root.items.filter(i => names.indexOf(i.name) !== -1);
        const taken = root.blockedCells();
        for (const i of root.items)
            if (names.indexOf(i.name) === -1)
                taken[`${i.col},${i.row}`] = true;
        const newPositions = Object.assign({}, root.positions);
        for (const i of root.items)
            newPositions[i.name] = { col: i.col, row: i.row };
        for (const i of moving) {
            let col = clampCol(i.col + dCol);
            let row = clampRow(i.row + dRow);
            if (taken[`${col},${row}`]) {
                const free = root.nearestFreeCell(col, row, taken);
                col = free.col;
                row = free.row;
            }
            newPositions[i.name] = { col: col, row: row };
            taken[`${col},${row}`] = true;
        }
        root.positions = newPositions;
        root.savePositions();
        root.relayout();
    }

    function resetPositions() {
        root.pushUndo({ type: "positions", label: Translation.tr("Arrange icons"), positions: root.snapshotPositions() });
        root.positions = {};
        root.savePositions();
        root.relayout();
    }

    // ---------- Undo (Ctrl+Z) ----------
    // Each entry knows how to revert one desktop action: icon moves, move to trash,
    // rename, new folder/file and files dropped onto the desktop.
    property var undoStack: []
    readonly property int undoLimit: 30
    readonly property var lastUndo: root.undoStack.length > 0 ? root.undoStack[root.undoStack.length - 1] : null

    function pushUndo(entry) {
        const stack = root.undoStack.concat([entry]);
        root.undoStack = stack.length > root.undoLimit ? stack.slice(stack.length - root.undoLimit) : stack;
    }
    function snapshotPositions() {
        const copy = {};
        for (const key in root.positions)
            copy[key] = { col: root.positions[key].col, row: root.positions[key].row };
        return copy;
    }

    // Restores files moved to the trash by this desktop, newest trash entry first.
    // Uses the freedesktop trash layout directly (~/.local/share/Trash/{files,info}).
    readonly property string restoreFromTrashScript: 'import os, sys, urllib.parse, configparser\n'
        + 'base = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "Trash")\n'
        + 'infos = []\n'
        + 'for f in os.listdir(os.path.join(base, "info")):\n'
        + '    if not f.endswith(".trashinfo"): continue\n'
        + '    c = configparser.ConfigParser(interpolation=None)\n'
        + '    try: c.read(os.path.join(base, "info", f), encoding="utf-8")\n'
        + '    except Exception: continue\n'
        + '    p = urllib.parse.unquote(c.get("Trash Info", "Path", fallback=""))\n'
        + '    infos.append((c.get("Trash Info", "DeletionDate", fallback=""), p, f[:-len(".trashinfo")]))\n'
        + 'infos.sort(reverse=True)\n'
        + 'for target in sys.argv[1:]:\n'
        + '    for date, p, name in infos:\n'
        + '        if p == target and not os.path.exists(target):\n'
        + '            os.rename(os.path.join(base, "files", name), target)\n'
        + '            os.remove(os.path.join(base, "info", name + ".trashinfo"))\n'
        + '            break\n'

    function undo() {
        const entry = root.lastUndo;
        if (!entry) return;
        root.undoStack = root.undoStack.slice(0, root.undoStack.length - 1);
        if (entry.type === "positions") {
            root.positions = entry.positions;
            root.savePositions();
            root.relayout();
        } else if (entry.type === "trash") {
            Quickshell.execDetached(["python3", "-c", root.restoreFromTrashScript, ...entry.paths]);
        } else if (entry.type === "rename") {
            const current = root.itemByName[entry.newName];
            root.moveSavedPosition(entry.newName, entry.oldName, current ? { col: current.col, row: current.row } : root.positions[entry.newName]);
            Quickshell.execDetached(["mv", "-n", "--", `${root.desktopDir}/${entry.newName}`, `${root.desktopDir}/${entry.oldName}`]);
        } else if (entry.type === "moved") {
            // Pasted after "Cut": move the files back where they came from (never overwriting)
            for (const [from, to] of entry.pairs)
                Quickshell.execDetached(["mv", "-n", "--", to, from]);
        } else if (entry.type === "created") {
            // New folder/file or dropped copies: undo moves them to the trash (never deletes)
            Quickshell.execDetached(["gio", "trash", ...entry.paths]);
        }
    }

    // Runs a command and gives its stdout to a callback (used to learn what an action created)
    Component {
        id: captureProcess
        Process {
            id: proc
            property var callback: null
            property bool done: false
            stdout: StdioCollector {
                onStreamFinished: {
                    proc.done = true;
                    if (proc.callback) proc.callback(text);
                    Qt.callLater(() => proc.destroy());
                }
            }
            // A command that fails to start never ends its output stream: report "nothing" so
            // callers waiting for it (e.g. the thumbnail queue) carry on
            onRunningChanged: {
                if (proc.running || proc.done) return;
                proc.done = true;
                if (proc.callback) proc.callback("");
                Qt.callLater(() => proc.destroy());
            }
        }
    }
    function runCapture(command, callback) {
        const proc = captureProcess.createObject(root, { command: command, callback: callback });
        proc.running = true;
    }

    // Rejects names that would leave the desktop folder ("a/b", ".", "..")
    readonly property string validNameFn: 'valid() { nl="$(printf "\\nx")"; nl="${nl%x}"; case "$1" in ""|.|..|*/*|*"$nl"*) notify-send -a Desktop "$2" "$1"; return 1;; esac; return 0; }'

    // ---------- Actions ----------
    // Text prompt with kdialog (KDE) or zenity; prints the answer, empty on cancel
    // Yes/no question; returns success only on "yes". Without kdialog/zenity it says no.
    readonly property string askYesNoFn: 'askyn() { if command -v kdialog >/dev/null; then kdialog --title "$1" --warningyesno "$2"; elif command -v zenity >/dev/null; then zenity --question --title "$1" --text "$2"; else return 1; fi; }'
    readonly property string askFn: 'ask() { if command -v kdialog >/dev/null; then kdialog --title "$1" --inputbox "$2" "$3"; elif command -v zenity >/dev/null; then zenity --entry --title "$1" --text "$2" --entry-text "$3"; fi; }'

    function open(item) {
        if (!item) return;
        if (item.suffix === "desktop") {
            const entry = DesktopEntries.byId(item.name.replace(/\.desktop$/, ""));
            if (entry) {
                entry.execute();
                return;
            }
            // Launchers that are not installed apps only run if they are executable (trusted), like
            // Plasma/GNOME. Otherwise ask first; on "yes" the file is marked executable and started.
            Quickshell.execDetached(["bash", "-c", root.askYesNoFn + '; run() { gio launch "$1" || kioclient exec "$1"; }; '
                + 'if [ -x "$1" ]; then run "$1"; elif askyn "$2" "$3"; then chmod u+x -- "$1" && run "$1"; fi',
                "open", item.path, Translation.tr("Untrusted launcher"),
                Translation.tr("This launcher is not marked as trusted (executable). Only run it if you trust where it came from.\n\nRun it and mark it as trusted?")]);
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
    function copyPaths(items) {
        Quickshell.execDetached(["wl-copy", items.map(i => i.path).join("\n")]);
    }
    function trash(item) {
        root.trashMany([item]);
    }
    function trashMany(items) {
        const paths = items.map(i => i.path).filter(p => p !== "");
        if (paths.length === 0) return;
        root.pushUndo({ type: "trash", label: Translation.tr("Move to trash"), paths: paths });
        Quickshell.execDetached(["gio", "trash", ...paths]);
    }
    // The scripts print the resulting name on success so the action can be undone
    function rename(item) {
        root.runCapture(["bash", "-c", root.askFn + '; ' + root.validNameFn
            + '; new="$(ask "$3" "$4" "$2")"; [ -n "$new" ] && [ "$new" != "$2" ] && valid "$new" "$5" && [ ! -e "$1/$new" ] && mv -n -- "$1/$2" "$1/$new" && printf "%s" "$new"',
            "rename", root.desktopDir, item.name, Translation.tr("Rename"), Translation.tr("New name:"), Translation.tr("Invalid name")],
            out => {
                if (out === "") return;
                root.moveSavedPosition(item.name, out, { col: item.col, row: item.row });
                root.pushUndo({ type: "rename", label: Translation.tr("Rename"), oldName: item.name, newName: out });
            });
    }
    // The renamed file keeps the cell of the old name
    function moveSavedPosition(oldName, newName, cell) {
        const positions = Object.assign({}, root.positions);
        delete positions[oldName];
        if (cell && cell.col !== undefined) positions[newName] = { col: cell.col, row: cell.row };
        root.positions = positions;
        root.reservedNames[newName] = Date.now();
        root.savePositions();
        relayoutTimer.restart();
    }

    function newFolder() {
        root.runCapture(["bash", "-c", root.askFn + '; ' + root.validNameFn
            + '; n="$(ask "$3" "$4" "$2")"; [ -n "$n" ] && valid "$n" "$5" && [ ! -e "$1/$n" ] && mkdir -- "$1/$n" && printf "%s" "$1/$n"',
            "newfolder", root.desktopDir, Translation.tr("New Folder"), Translation.tr("New folder"), Translation.tr("Folder name:"), Translation.tr("Invalid name")],
            out => {
                if (out !== "")
                    root.pushUndo({ type: "created", label: Translation.tr("New folder"), paths: [out] });
            });
    }
    function newTextFile() {
        root.runCapture(["bash", "-c", root.askFn + '; ' + root.validNameFn
            + '; n="$(ask "$3" "$4" "$2")"; [ -n "$n" ] && valid "$n" "$5" && [ ! -e "$1/$n" ] && touch -- "$1/$n" && printf "%s" "$1/$n"',
            "newfile", root.desktopDir, Translation.tr("New Text File") + ".txt", Translation.tr("New text file"), Translation.tr("File name:"), Translation.tr("Invalid name")],
            out => {
                if (out !== "")
                    root.pushUndo({ type: "created", label: Translation.tr("New text file"), paths: [out] });
            });
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

    // ---------- Keyboard (the background layer takes keyboard focus only while icons are selected) ----------
    // A selection never outlives working in a window: as soon as a window gets focus it is cleared,
    // so Delete/Enter can't act on an old selection later.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Closing Quick Look hands the keyboard back to a window; keep the selection then
            if (Date.now() - root.quickLookClosedAt < 400) return;
            if (event.name === "activewindowv2" && event.data !== "" && event.data !== ",") {
                root.clearSelection();
                root.desktopActive = false;
            }
        }
    }
    // Hyprland sends no window event when the keyboard goes back to the window that was
    // focused before the desktop, so also follow the desktop layer's real keyboard state.
    readonly property bool windowActive: Window.active
    onWindowActiveChanged: {
        if (!root.windowActive && GlobalStates.quickLookItems.length === 0 && Date.now() - root.quickLookClosedAt > 400) {
            root.clearSelection();
            root.desktopActive = false;
        }
    }
    property real quickLookClosedAt: 0
    Connections {
        target: GlobalStates
        function onQuickLookItemsChanged() {
            if (GlobalStates.quickLookItems.length === 0) root.quickLookClosedAt = Date.now();
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                root.clearSelection();
                root.desktopActive = false;
            }
        }
    }
    // True after clicking the desktop until a window gets focus; lets Ctrl+Z reach the desktop
    property bool desktopActive: false
    readonly property bool wantsKeyboard: root.selectedNames.length > 0 || root.desktopActive
    focus: true
    Keys.onPressed: event => {
        const selection = root.selectedItems;
        if (event.key === Qt.Key_Escape) {
            root.clearSelection();
        } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
            root.undo();
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            root.selectedNames = root.items.map(i => i.name);
        } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
            root.paste();
        } else if (selection.length === 0) {
            return;
        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            root.copyFiles(selection, false);
        } else if (event.key === Qt.Key_X && (event.modifiers & Qt.ControlModifier)) {
            root.copyFiles(selection, true);
        } else if (event.key === Qt.Key_Space && (Config.options?.desktopMode.quickLook ?? true)) {
            root.quickLook(selection);
        } else if (event.key === Qt.Key_Delete) {
            root.trashMany(selection);
            root.clearSelection();
        } else if (event.key === Qt.Key_F2) {
            if (selection.length === 1)
                root.rename(selection[0]);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            for (const item of selection)
                root.open(item);
        } else {
            return;
        }
        event.accepted = true;
    }

    // ---------- Copy / cut / paste (Ctrl+C, Ctrl+X, Ctrl+V) ----------
    // Files go to the clipboard as a text/uri-list, so Dolphin and other file managers can paste
    // them, and files copied there can be pasted on the desktop. "Cut" is remembered here (the
    // icons are dimmed) and turns the next paste into a move.
    property var cutPaths: []
    function copyFiles(items, cut) {
        const paths = items.map(i => i.path).filter(p => p !== "");
        if (paths.length === 0) return;
        root.cutPaths = cut ? paths : [];
        Quickshell.execDetached(["bash", "-c", 'printf "%s" "$1" | wl-copy --type text/uri-list', "copy",
            paths.map(p => root.fileUrl(p)).join("\r\n") + "\r\n"]);
    }
    function paste(x, y) {
        if (root.desktopDir === "") return;
        // First line: "cut" or "copy" (KDE / GNOME cut markers), then the file URLs
        root.runCapture(["bash", "-c",
            't="$(wl-paste --list-types 2>/dev/null)"; mode=copy; '
            + 'if printf "%s\\n" "$t" | grep -qx "application/x-kde-cutselection" && [ "$(wl-paste --no-newline --type application/x-kde-cutselection 2>/dev/null)" = 1 ]; then mode=cut; fi; '
            + 'if printf "%s\\n" "$t" | grep -qx "text/uri-list"; then echo "$mode"; wl-paste --no-newline --type text/uri-list; '
            + 'elif printf "%s\\n" "$t" | grep -qx "x-special/gnome-copied-files"; then wl-paste --no-newline --type x-special/gnome-copied-files; fi'],
            out => {
                const lines = out.split(/\r?\n/).map(l => l.trim()).filter(l => l !== "");
                if (lines.length === 0) return;
                const cut = lines[0] === "cut";
                const paths = lines.filter(l => l.startsWith("file://"))
                    .map(l => decodeURIComponent(l.slice("file://".length).replace(/^localhost(?=\/)/, "")));
                if (paths.length === 0) return;
                const ownCut = root.cutPaths.length > 0 && paths.every(p => root.cutPaths.indexOf(p) !== -1);
                root.cutPaths = [];
                root.transferFiles(paths, (cut || ownCut) ? "move" : "unique", x, y);
            });
    }

    // Copies (or moves) files onto the desktop. mode:
    //   "skip"   - dropped files: names already on the desktop are skipped (no overwriting, no merging)
    //   "unique" - pasted copies: an existing name gets " (2)", " (3)"... like file managers do
    //   "move"   - paste after cut: moved, names already on the desktop are skipped
    // x, y: where to place the icons (optional). Every action can be undone with Ctrl+Z.
    function transferFiles(paths, mode, x, y) {
        paths = paths.filter(p => p !== "" && !p.includes("\n")); // the script reports paths line by line
        if (mode !== "unique") // already on the desktop: nothing to copy or move
            paths = paths.filter(p => p.substring(0, p.lastIndexOf("/")) !== root.desktopDir);
        if (paths.length === 0 || root.desktopDir === "") return;
        const positioned = x !== undefined && y !== undefined;
        if (positioned && mode !== "unique")
            root.placeDroppedFiles(paths.map(p => p.substring(p.lastIndexOf("/") + 1)), x, y);
        root.runCapture(["bash", "-c", 'dir="$1"; mode="$2"; msg="$3"; shift 3; skipped=0; '
            + 'for src in "$@"; do b="$(basename -- "$src")"; dest="$dir/$b"; '
            + 'if [ -e "$dest" ] || [ -L "$dest" ]; then '
            + '  if [ "$mode" = unique ]; then stem="$b"; ext=""; '
            + '    if [ ! -d "$src" ]; then case "$b" in ?*.*) stem="${b%.*}"; ext=".${b##*.}";; esac; fi; '
            + '    i=2; while [ -e "$dir/$stem ($i)$ext" ]; do i=$((i+1)); done; dest="$dir/$stem ($i)$ext"; '
            + '  else skipped=$((skipped+1)); continue; fi; '
            + 'fi; '
            + 'if [ "$mode" = move ]; then mv -n -- "$src" "$dest" && printf "%s\\t%s\\n" "$src" "$dest"; '
            + 'else cp -r -- "$src" "$dest" && printf "%s\\n" "$dest"; fi; '
            + 'done; [ "$skipped" -gt 0 ] && notify-send -a Desktop "$msg" "$skipped"; true',
            "transfer", root.desktopDir, mode, Translation.tr("Already on the desktop, not copied"), ...paths],
            out => {
                const lines = out.split("\n").filter(line => line !== "");
                if (lines.length === 0) return;
                if (mode === "move") {
                    const pairs = lines.map(l => l.split("\t")).filter(p => p.length === 2);
                    root.pushUndo({ type: "moved", label: Translation.tr("Move to desktop"), pairs: pairs });
                } else {
                    root.pushUndo({ type: "created", label: Translation.tr("Copy to desktop"), paths: lines });
                }
                // Pasted copies get their final names only now
                if (positioned && mode === "unique")
                    root.placeDroppedFiles(lines.map(p => p.substring(p.lastIndexOf("/") + 1)), x, y);
            });
    }

    // ---------- Open with ----------
    // Apps registered for the file's type (gio mime), default first. Calls back with
    // [{ id, name, icon }].
    function openWithApps(item, callback) {
        root.runCapture(["bash", "-c", 'm="$(xdg-mime query filetype "$1" 2>/dev/null)"; [ -n "$m" ] && gio mime "$m" 2>/dev/null', "openwith", item.path],
            out => {
                const ids = [];
                for (const line of out.split("\n")) {
                    const match = line.match(/([^\s:]+\.desktop)\s*$/);
                    if (match && ids.indexOf(match[1]) === -1) ids.push(match[1]);
                }
                const apps = ids.map(id => {
                    const entry = DesktopEntries.byId(id.replace(/\.desktop$/, ""));
                    return entry ? { id: id, name: entry.name, icon: entry.icon } : null;
                }).filter(app => app !== null);
                callback(apps);
            });
    }
    function openWith(item, desktopId) {
        // gio launch needs the .desktop file itself: look it up in the XDG data dirs
        Quickshell.execDetached(["bash", "-c",
            'IFS=:; for d in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do '
            + 'f="$d/applications/$1"; if [ -f "$f" ]; then exec gio launch "$f" "$2"; fi; done; exec xdg-open "$2"',
            "openwith", desktopId, item.path]);
    }

    // ---------- Thumbnails for videos and PDFs ----------
    // Uses the shared freedesktop thumbnail cache when a file manager already made one,
    // otherwise renders one (ffmpegthumbnailer/ffmpeg, pdftoppm) into its own cache.
    // One at a time, so a desktop full of videos doesn't start dozens of ffmpeg processes.
    property var thumbnails: ({}) // path -> thumbnail file
    property var thumbnailQueue: []
    property bool thumbnailBusy: false
    function requestThumbnail(path) {
        if (path === "" || root.thumbnails[path] !== undefined || root.thumbnailQueue.indexOf(path) !== -1) return;
        root.thumbnailQueue = root.thumbnailQueue.concat([path]);
        root.nextThumbnail();
    }
    readonly property string thumbnailScript: 'f="$1"; '
        + 'uri="$(python3 -c "import sys, urllib.parse; print(\\"file://\\" + urllib.parse.quote(sys.argv[1], safe=\\"/-_.!~*()&=+\\$,;:@\\x27\\"))" "$f")"; '
        + 'md5="$(printf "%s" "$uri" | md5sum | cut -d" " -f1)"; '
        + 'for t in "${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails/large/$md5.png" "${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails/normal/$md5.png"; do '
        + '  if [ -s "$t" ] && [ "$t" -nt "$f" ]; then printf "%s" "$t"; exit 0; fi; done; '
        + 'own="${XDG_CACHE_HOME:-$HOME/.cache}/qs-desktop-thumbnails"; mkdir -p "$own"; out="$own/$md5.png"; '
        + 'if [ -s "$out" ] && [ "$out" -nt "$f" ]; then printf "%s" "$out"; exit 0; fi; '
        + 'case "${f##*.}" in '
        + '  [Pp][Dd][Ff]) pdftoppm -png -singlefile -f 1 -l 1 -scale-to 256 "$f" "${out%.png}" ;; '
        // (ffmpeg exits 0 without a picture when the video is shorter than the seek, so check the file)
        + '  *) ffmpegthumbnailer -i "$f" -o "$out" -s 256; [ -s "$out" ] || ffmpeg -y -loglevel error -ss 3 -i "$f" -frames:v 1 -vf "scale=256:-2" "$out"; '
        + '     [ -s "$out" ] || ffmpeg -y -loglevel error -i "$f" -frames:v 1 -vf "scale=256:-2" "$out" ;; '
        + 'esac >/dev/null 2>&1; [ -s "$out" ] && printf "%s" "$out"'
    function nextThumbnail() {
        if (root.thumbnailBusy || root.thumbnailQueue.length === 0) return;
        const path = root.thumbnailQueue[0];
        root.thumbnailQueue = root.thumbnailQueue.slice(1);
        root.thumbnailBusy = true;
        root.runCapture(["timeout", "-k", "2", "20", "bash", "-c", root.thumbnailScript, "thumb", path], out => {
            const result = Object.assign({}, root.thumbnails);
            result[path] = out.trim(); // "" = no thumbnail (keeps the normal icon, not retried)
            root.thumbnails = result;
            root.thumbnailBusy = false;
            root.nextThumbnail();
        });
    }

    // ---------- Quick Look (Space) ----------
    // Several selected icons: browse those. One icon: browse the whole desktop in grid order,
    // and the selection follows (like Finder).
    property bool quickLookFollowsSelection: false
    function quickLook(selection) {
        if (selection.length === 0) return;
        if (selection.length > 1) {
            root.quickLookFollowsSelection = false;
            GlobalStates.quickLookIndex = 0;
            GlobalStates.quickLookItems = selection;
            return;
        }
        const ordered = root.items.slice().sort((a, b) => a.col - b.col || a.row - b.row);
        root.quickLookFollowsSelection = true;
        GlobalStates.quickLookIndex = Math.max(0, ordered.findIndex(i => i.name === selection[0].name));
        GlobalStates.quickLookItems = ordered;
    }
    Connections {
        target: GlobalStates
        function onQuickLookIndexChanged() {
            const shown = GlobalStates.quickLookItems[GlobalStates.quickLookIndex];
            if (root.quickLookFollowsSelection && shown && root.itemByName[shown.name])
                root.selectOnly(shown.name);
        }
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
                .filter(p => !p.includes("\n")) // the copy script reports paths line by line
                .filter(p => p.substring(0, p.lastIndexOf("/")) !== root.desktopDir); // already on the desktop
            if (paths.length === 0)
                return;
            root.transferFiles(paths, "skip", drop.x, drop.y);
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
            root.reservedNames[name] = Date.now();
            taken[`${cell.col},${cell.row}`] = true;
        }
        root.positions = newPositions;
        root.savePositions();
    }

    // ---------- Empty desktop area ----------
    // Left-drag on the empty desktop draws a selection rectangle (rubber band).
    // Ctrl adds to the current selection instead of replacing it.
    MouseArea {
        id: emptyArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real startX: 0
        property real startY: 0
        property bool banding: false
        property var baseSelection: []

        onPressed: event => {
            root.forceActiveFocus();
            root.desktopActive = true;
            if (event.button === Qt.RightButton) {
                root.clearSelection();
                root.desktopMenuRequested(event.x, event.y);
                return;
            }
            emptyArea.baseSelection = (event.modifiers & Qt.ControlModifier) ? root.selectedNames : [];
            root.selectedNames = emptyArea.baseSelection;
            emptyArea.startX = event.x;
            emptyArea.startY = event.y;
            emptyArea.banding = true;
            band.x = event.x;
            band.y = event.y;
            band.width = 0;
            band.height = 0;
        }
        onPositionChanged: event => {
            if (!emptyArea.banding) return;
            band.x = Math.min(emptyArea.startX, event.x);
            band.y = Math.min(emptyArea.startY, event.y);
            band.width = Math.abs(event.x - emptyArea.startX);
            band.height = Math.abs(event.y - emptyArea.startY);
            const hit = root.items.filter(i => {
                // Use the visible part of the icon (cell with a small inset)
                const x1 = root.cellX(i.col) + 8, y1 = root.cellY(i.row) + 4;
                const x2 = x1 + root.cellWidth - 16, y2 = y1 + root.cellHeight - 8;
                return x1 < band.x + band.width && x2 > band.x && y1 < band.y + band.height && y2 > band.y;
            }).map(i => i.name);
            root.selectedNames = emptyArea.baseSelection.concat(hit.filter(n => emptyArea.baseSelection.indexOf(n) === -1));
        }
        onReleased: emptyArea.banding = false
        onCanceled: emptyArea.banding = false
    }

    Rectangle {
        id: band
        visible: emptyArea.banding && (width > 2 || height > 2)
        z: 20
        radius: 4
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
        border.width: 1
        border.color: Appearance.colors.colPrimary
    }

    // ---------- Icons ----------
    Repeater {
        model: ScriptModel {
            values: root.itemNames
        }
        delegate: DesktopIcon {
            required property string modelData
            // Placeholder only for the instant between a file disappearing and its icon being removed
            item: root.itemByName[modelData] ?? ({ name: modelData, path: "", isDir: false, suffix: "", col: 0, row: 0 })
            desktop: root
            width: root.cellWidth
            height: root.cellHeight
            homeX: root.cellX(item.col)
            homeY: root.cellY(item.row)
        }
    }
}
