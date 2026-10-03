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
    readonly property bool isVideo: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv"].indexOf(item.suffix) !== -1
    readonly property bool wantsThumbnail: (isVideo || item.suffix === "pdf") && !item.isDir && item.path !== ""
    readonly property string thumbnail: wantsThumbnail ? (desktop.thumbnails[item.path] ?? "") : ""
    onWantsThumbnailChanged: if (wantsThumbnail) desktop.requestThumbnail(item.path)
    Component.onCompleted: if (wantsThumbnail) desktop.requestThumbnail(item.path)
    // Cut (Ctrl+X) and not pasted yet: dimmed, like in file managers
    opacity: desktop.cutPaths.indexOf(item.path) !== -1 ? 0.5 : 1
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

    // Follows the dragged icon when it is part of a multi-selection being dragged
    readonly property bool followsGroup: selected && desktop.groupDragLeader !== "" && desktop.groupDragLeader !== item.name
    readonly property bool groupDragging: desktop.groupDragLeader !== ""

    x: homeX + (followsGroup ? desktop.groupDragDX : 0)
    y: homeY + (followsGroup ? desktop.groupDragDY : 0)
    Behavior on x { enabled: !mouseArea.drag.active && !root.groupDragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !mouseArea.drag.active && !root.groupDragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    z: (mouseArea.drag.active || followsGroup) ? 10 : 0

    // A drag that is cut short (icon removed mid-drag) must not leave the others offset
    Component.onDestruction: {
        if (root.desktop && root.item && root.desktop.groupDragLeader === root.item.name) {
            root.desktop.groupDragLeader = "";
            root.desktop.groupDragDX = 0;
            root.desktop.groupDragDY = 0;
        }
    }

    // Only a real drag moves the icon, not a click while it is still animating into place
    property bool wasDragged: false
    Connections {
        target: mouseArea.drag
        function onActiveChanged() {
            if (mouseArea.drag.active) root.wasDragged = true;
            if (mouseArea.drag.active && root.selected && root.desktop.selectedNames.length > 1) {
                root.desktop.groupDragDX = 0;
                root.desktop.groupDragDY = 0;
                root.desktop.groupDragLeader = root.item.name;
            }
        }
    }
    onXChanged: if (desktop.groupDragLeader === item.name) desktop.groupDragDX = x - homeX
    onYChanged: if (desktop.groupDragLeader === item.name) desktop.groupDragDY = y - homeY

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
                visible: !root.isImage && !thumbnailImage.visible
                implicitSize: 52
                source: root.iconName.startsWith("/") ? root.desktop.fileUrl(root.iconName) : Quickshell.iconPath(root.iconName, "application-x-executable")
            }
            // Video / PDF thumbnail
            Image {
                id: thumbnailImage
                anchors.fill: parent
                visible: root.thumbnail !== "" && status === Image.Ready
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 104
                sourceSize.height: 104
                source: root.thumbnail !== "" ? root.desktop.fileUrl(root.thumbnail) : ""
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: thumbnailImage.visible && root.isVideo
                text: "play_circle"
                fill: 1
                iconSize: 24
                color: "white"
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.6)
            }
            Image {
                anchors.fill: parent
                visible: root.isImage
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 104
                sourceSize.height: 104
                source: (root.isImage && root.item.path !== "") ? root.desktop.fileUrl(root.item.path) : ""
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
            const dragged = root.wasDragged;
            root.wasDragged = false;
            if (root.desktop.groupDragLeader === root.item.name) {
                const dCol = Math.round((root.x - root.homeX) / root.desktop.cellWidth);
                const dRow = Math.round((root.y - root.homeY) / root.desktop.cellHeight);
                const names = root.desktop.selectedNames;
                root.desktop.groupDragLeader = "";
                root.desktop.groupDragDX = 0;
                root.desktop.groupDragDY = 0;
                root.desktop.moveGroup(names, dCol, dRow);
                root.x = Qt.binding(() => root.homeX + (root.followsGroup ? root.desktop.groupDragDX : 0));
                root.y = Qt.binding(() => root.homeY + (root.followsGroup ? root.desktop.groupDragDY : 0));
                return;
            }
            if (dragged) {
                root.desktop.moveItemTo(root.item.name, root.x, root.y);
                // If nothing changed, snap back
                root.x = Qt.binding(() => root.homeX + (root.followsGroup ? root.desktop.groupDragDX : 0));
                root.y = Qt.binding(() => root.homeY + (root.followsGroup ? root.desktop.groupDragDY : 0));
            }
        }
    }
}
