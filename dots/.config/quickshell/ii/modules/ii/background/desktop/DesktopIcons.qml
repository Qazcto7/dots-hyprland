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
            Quickshell.execDetached(["mv", "-n", "--", `${root.desktopDir}/${entry.newName}`, `${root.desktopDir}/${entry.oldName}`]);
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
            stdout: StdioCollector {
                onStreamFinished: {
                    if (proc.callback) proc.callback(text);
                    proc.destroy();
                }
            }
        }
    }
    function runCapture(command, callback) {
        const proc = captureProcess.createObject(root, { command: command, callback: callback });
        proc.running = true;
    }

    // Rejects names that would leave the desktop folder ("a/b", ".", "..")
    readonly property string validNameFn: 'valid() { case "$1" in ""|.|..|*/*) notify-send -a Desktop "$2" "$1"; return 1;; esac; return 0; }'

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
                if (out !== "")
                    root.pushUndo({ type: "rename", label: Translation.tr("Rename"), oldName: item.name, newName: out });
            });
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
            if (event.name === "activewindowv2" && event.data !== "" && event.data !== ",") {
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
        } else if (selection.length === 0) {
            return;
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
            // Items whose name already exists on the desktop are skipped (no overwriting, no merging
            // folders); the script prints the copied paths, one per line, for undo.
            root.runCapture(["bash", "-c", 'dir="$1"; msg="$2"; shift 2; skipped=0; '
                + 'for src in "$@"; do b="$(basename -- "$src")"; '
                + 'if [ -e "$dir/$b" ]; then skipped=$((skipped+1)); elif cp -r -- "$src" "$dir/$b"; then printf "%s\\n" "$dir/$b"; fi; done; '
                + '[ "$skipped" -gt 0 ] && notify-send -a Desktop "$msg" "$skipped"; true',
                "drop", root.desktopDir, Translation.tr("Already on the desktop, not copied"), ...paths],
                out => {
                    const copied = out.split("\n").filter(line => line !== "");
                    if (copied.length > 0)
                        root.pushUndo({ type: "created", label: Translation.tr("Copy to desktop"), paths: copied });
                });
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
