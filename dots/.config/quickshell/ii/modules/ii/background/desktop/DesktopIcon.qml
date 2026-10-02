import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    required property var item
    required property var desktop
    required property real homeX
    required property real homeY

    readonly property bool selected: desktop.selectedNames.indexOf(item.name) !== -1
    readonly property bool isImage: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg"].indexOf(item.suffix) !== -1
    readonly property var desktopEntry: item.suffix === "desktop" ? DesktopEntries.byId(item.name.replace(/\.desktop$/, "")) : null

    // .desktop files that are not installed apps (e.g. copied launchers): read Name/Icon from the file
    property var parsedDesktop: ({})
    FileView {
        id: desktopFile
        path: (root.item.suffix === "desktop" && !root.desktopEntry) ? root.item.path : ""
        onLoaded: root.parsedDesktop = root.parseDesktopFile(desktopFile.text())
    }
    function parseDesktopFile(text) {
        const result = {};
        let inMain = false;
        for (const rawLine of text.split("\n")) {
            const line = rawLine.trim();
            if (line.startsWith("[")) {
                inMain = (line === "[Desktop Entry]");
                continue;
            }
            if (!inMain) continue;
            const eq = line.indexOf("=");
            if (eq < 0) continue;
            const key = line.slice(0, eq).trim();
            const value = line.slice(eq + 1).trim();
            if (key === "Name[tr_TR]" || key === "Name[tr]") result.localName = value;
            else if (key === "Name" && result.name === undefined) result.name = value;
            else if (key === "Icon" && result.icon === undefined) result.icon = value;
        }
        return result;
    }

    readonly property string displayName: desktopEntry?.name ?? parsedDesktop.localName ?? parsedDesktop.name ?? item.name
    readonly property string iconName: {
        if (desktopEntry) return desktopEntry.icon;
        if (parsedDesktop.icon) return parsedDesktop.icon;
        if (item.isDir) return "folder";
        const byType = {
            "pdf": "application-pdf",
            "txt": "text-x-generic", "md": "text-x-generic", "log": "text-x-generic",
            "sh": "text-x-script", "py": "text-x-python", "lua": "text-x-script", "js": "text-x-javascript",
            "zip": "package-x-generic", "tar": "package-x-generic", "gz": "package-x-generic", "xz": "package-x-generic", "7z": "package-x-generic", "rar": "package-x-generic",
            "mp3": "audio-x-generic", "ogg": "audio-x-generic", "flac": "audio-x-generic", "wav": "audio-x-generic",
            "mp4": "video-x-generic", "mkv": "video-x-generic", "webm": "video-x-generic", "mov": "video-x-generic",
            "doc": "x-office-document", "docx": "x-office-document", "odt": "x-office-document",
            "xls": "x-office-spreadsheet", "xlsx": "x-office-spreadsheet", "ods": "x-office-spreadsheet",
            "ppt": "x-office-presentation", "pptx": "x-office-presentation", "odp": "x-office-presentation",
            "appimage": "application-x-executable", "exe": "application-x-ms-dos-executable",
            "html": "text-html", "desktop": "application-x-executable",
        };
        return byType[item.suffix] ?? "text-x-generic";
    }

    x: homeX
    y: homeY
    Behavior on x { enabled: !mouseArea.drag.active; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !mouseArea.drag.active; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    z: mouseArea.drag.active ? 10 : 0

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Appearance.rounding.small
        color: root.selected ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
            : (mouseArea.containsMouse ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85) : "transparent")
        border.width: root.selected ? 1 : 0
        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.3)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 52
            implicitHeight: 52

            IconImage {
                anchors.fill: parent
                visible: !root.isImage
                implicitSize: 52
                source: root.iconName.startsWith("/") ? `file://${root.iconName}` : Quickshell.iconPath(root.iconName, "application-x-executable")
            }
            Image {
                anchors.fill: parent
                visible: root.isImage
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 104
                sourceSize.height: 104
                source: root.isImage ? `file://${root.item.path}` : ""
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.displayName
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: "white"
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.7)
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        drag.target: root
        drag.threshold: 8
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.ArrowCursor

        onPressed: event => {
            root.desktop.forceActiveFocus();
            if (event.modifiers & Qt.ControlModifier)
                root.desktop.toggleSelected(root.item.name);
            else if (!root.selected) // keep a multi-selection when pressing one of its icons
                root.desktop.selectOnly(root.item.name);
            if (event.button === Qt.RightButton) {
                const p = mapToItem(root.desktop, event.x, event.y);
                root.desktop.itemMenuRequested(root.item, p.x, p.y);
            }
        }
        onDoubleClicked: event => {
            if (event.button === Qt.LeftButton)
                root.desktop.open(root.item);
        }
        onReleased: {
            if (drag.active || root.x !== root.homeX || root.y !== root.homeY) {
                root.desktop.moveItemTo(root.item.name, root.x, root.y);
                // If nothing changed, snap back
                root.x = Qt.binding(() => root.homeX);
                root.y = Qt.binding(() => root.homeY);
            }
        }
    }
}
