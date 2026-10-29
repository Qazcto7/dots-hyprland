import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    implicitWidth: rowLayout.implicitWidth

    RowLayout {
        id: rowLayout

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        StyledText {
            id: mainText
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
            text: {
                var app = (root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow) ? 
                    (root.activeWindow?.appId || root.activeWindow?.title) :
                    ((root.biggestWindow?.class) ?? Translation.tr("Desktop"));
                if (!app || app.length === 0) return Translation.tr("Desktop");
                return app.charAt(0).toUpperCase() + app.slice(1);
            }
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: {
                var title = (root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow) ? 
                    root.activeWindow?.title :
                    ((root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`);
                if (!title || title.toLowerCase() === mainText.text.toLowerCase()) return "";
                return title;
            }
        }
    }

}
