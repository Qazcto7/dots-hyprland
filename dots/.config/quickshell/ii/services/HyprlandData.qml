pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // Convenient stuff

    // True if a fullscreen window is shown on the monitor with this name
    // (on its active workspace or on a special workspace open on it)
    function hasFullscreenOn(monitorName) {
        // The Wayland toplevel state updates instantly, the hyprctl data below only after a query;
        // don't let a stale query keep things (like the dock) in fullscreen mode.
        if (!ToplevelManager.toplevels.values.some(t => t.fullscreen)) return false;
        const mon = root.monitors.find(m => m.name === monitorName);
        if (!mon) return false;
        const workspaceIds = [mon.activeWorkspace?.id, mon.specialWorkspace?.id].filter(id => id !== undefined && id !== 0);
        return root.windowList.some(w => workspaceIds.indexOf(w.workspace?.id) !== -1 && ((w.fullscreen ?? 0) & 2) !== 0);
    }

    // True if a maximized window is shown on the monitor with this name: Hyprland's maximize, or a
    // floating window spanning the screen width that starts at the very top (desktop mode's
    // maximize when it takes the bar's place). A maximized window dragged away stops counting.
    function hasMaximizedOn(monitorName) {
        const mon = root.monitors.find(m => m.name === monitorName);
        if (!mon) return false;
        const workspaceIds = [mon.activeWorkspace?.id, mon.specialWorkspace?.id].filter(id => id !== undefined && id !== 0);
        const rotated = ((mon.transform ?? 0) % 2) === 1;
        const scale = mon.scale || 1;
        const width = (rotated ? mon.height : mon.width) / scale;
        return root.windowList.some(w => {
            if (workspaceIds.indexOf(w.workspace?.id) === -1 || w.hidden || w.mapped === false) return false;
            const fs = w.fullscreen ?? 0;
            if ((fs & 2) !== 0) return false; // fullscreen is handled separately
            if ((fs & 1) !== 0) return true;
            return w.floating && (w.size?.[0] ?? 0) >= width * 0.9 && ((w.at?.[1] ?? 9999) - mon.y) <= 50;
        });
    }

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    // Internals

    // Setting running = true on a Process that is still running does nothing, so an event arriving
    // while a query is in flight used to be lost and the data stayed stale (e.g. a window still
    // reported as fullscreen after leaving fullscreen). Remember it and query again when done.
    function requestRun(proc) {
        if (proc.running) proc.pending = true;
        else proc.running = true;
    }

    function updateWindowList() {
        requestRun(getClients);
    }

    function updateLayers() {
        requestRun(getLayers);
    }

    function updateMonitors() {
        requestRun(getMonitors);
    }

    function updateWorkspaces() {
        requestRun(getWorkspaces);
        requestRun(getActiveWorkspace);
    }

    component QueryProcess: Process {
        id: queryProcess
        property bool pending: false
        onRunningChanged: {
            if (!queryProcess.running && queryProcess.pending) {
                queryProcess.pending = false;
                Qt.callLater(() => { queryProcess.running = true; });
            }
        }
    }

    function updateAll() {
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        updateAll();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            // console.log("Hyprland raw event:", event.name);
            if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
            updateAll()
        }
    }

    QueryProcess {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                root.windowList = JSON.parse(clientsCollector.text)
                let tempWinByAddress = {};
                for (var i = 0; i < root.windowList.length; ++i) {
                    var win = root.windowList[i];
                    tempWinByAddress[win.address] = win;
                }
                root.windowByAddress = tempWinByAddress;
                root.addresses = root.windowList.map(win => win.address);
            }
        }
    }

    QueryProcess {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                root.monitors = JSON.parse(monitorsCollector.text);
            }
        }
    }

    QueryProcess {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                root.layers = JSON.parse(layersCollector.text);
            }
        }
    }

    QueryProcess {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                var rawWorkspaces = JSON.parse(workspacesCollector.text);
                // Filter out invalid workspace ids (e.g. lock-screen temp workspace 2147483647 - N)
                root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                let tempWorkspaceById = {};
                for (var i = 0; i < root.workspaces.length; ++i) {
                    var ws = root.workspaces[i];
                    tempWorkspaceById[ws.id] = ws;
                }
                root.workspaceById = tempWorkspaceById;
                root.workspaceIds = root.workspaces.map(ws => ws.id);
            }
        }
    }

    QueryProcess {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);
            }
        }
    }
}
