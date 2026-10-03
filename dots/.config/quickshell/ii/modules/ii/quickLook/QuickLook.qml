pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * macOS-like Quick Look for desktop icons: select an icon and press Space.
 * Shows images, text/code, the first page of PDFs, a frame of videos, folder contents,
 * otherwise the icon and file details. Space/Esc closes, arrow keys go to the previous/next file,
 * Enter opens the file with its default app.
 * Opened by setting GlobalStates.quickLookItems (items: { name, path, isDir, suffix }).
 */
Scope {
    id: root

    readonly property bool open: GlobalStates.quickLookItems.length > 0
    readonly property var item: GlobalStates.quickLookItems[GlobalStates.quickLookIndex] ?? null

    function close() {
        GlobalStates.quickLookItems = [];
        GlobalStates.quickLookIndex = 0;
    }
    function go(delta) {
        const n = GlobalStates.quickLookItems.length;
        if (n < 2) return;
        GlobalStates.quickLookIndex = ((GlobalStates.quickLookIndex + delta) % n + n) % n;
    }
    function openItem() {
        if (root.item) Quickshell.execDetached(["xdg-open", root.item.path]);
        root.close();
    }

    readonly property var imageTypes: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "ico"]
    readonly property var textTypes: ["txt", "md", "log", "sh", "bash", "fish", "zsh", "py", "lua", "js", "ts", "json", "qml",
        "conf", "cfg", "ini", "toml", "yaml", "yml", "xml", "csv", "html", "htm", "css", "c", "h", "cpp", "hpp", "cc",
        "rs", "go", "java", "kt", "cs", "rb", "php", "sql", "desktop", "patch", "diff", "srt", "nfo", "tex", "rst"]
    readonly property var videoTypes: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv"]
    readonly property var audioTypes: ["mp3", "ogg", "flac", "wav", "m4a", "opus", "aac"]

    function kindOf(item) {
        if (!item) return "none";
        if (item.isDir) return "folder";
        const suffix = (item.suffix ?? "").toLowerCase();
        if (root.imageTypes.indexOf(suffix) !== -1) return "image";
        if (root.textTypes.indexOf(suffix) !== -1) return "text";
        if (suffix === "pdf") return "pdf";
        if (root.videoTypes.indexOf(suffix) !== -1) return "video";
        if (root.audioTypes.indexOf(suffix) !== -1) return "audio";
        return "other";
    }
    function iconFor(kind, item) {
        switch (kind) {
        case "folder": return "folder";
        case "image": return "image-x-generic";
        case "text": return "text-x-generic";
        case "pdf": return "application-pdf";
        case "video": return "video-x-generic";
        case "audio": return "audio-x-generic";
        }
        return (item?.suffix === "desktop") ? "application-x-executable" : "text-x-generic";
    }
    // Encoded, so names with spaces, # or % still load
    function fileUrl(path) {
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }
    function formatSize(bytes) {
        if (bytes < 1024) return `${bytes} B`;
        const units = ["KB", "MB", "GB", "TB"];
        let value = bytes / 1024, unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return `${value.toFixed(value < 10 ? 1 : 0)} ${units[unit]}`;
    }

    // ---------- Preview data (loaded per file) ----------
    readonly property string kind: root.kindOf(root.item)
    property string previewText: ""
    property var folderEntries: []
    property int folderCount: 0
    property string previewImage: ""
    property bool loading: false
    property string details: ""
    property int requestId: 0
    readonly property string cacheDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/qs-quicklook`

    onItemChanged: root.reload()

    // One Process per request, so a slow old request can never overwrite a newer preview
    Component {
        id: captureProcess
        Process {
            id: proc
            property int request: 0
            property var callback: null
            stdout: StdioCollector {
                onStreamFinished: {
                    if (proc.request === root.requestId && proc.callback)
                        proc.callback(text);
                    proc.destroy();
                }
            }
        }
    }
    function run(command, callback) {
        const proc = captureProcess.createObject(root, { command: command, request: root.requestId, callback: callback });
        proc.running = true;
    }

    function reload() {
        root.requestId++;
        root.previewText = "";
        root.folderEntries = [];
        root.folderCount = 0;
        root.previewImage = "";
        root.details = "";
        const item = root.item;
        if (!item) return;
        const path = item.path;

        root.run(["stat", "-L", "-c", "%s|%Y", path], out => {
            const [size, mtime] = out.trim().split("|");
            const date = new Date(Number(mtime) * 1000);
            const parts = [];
            if (!item.isDir && size !== undefined && size !== "") parts.push(root.formatSize(Number(size)));
            if (!isNaN(date.getTime())) parts.push(date.toLocaleString(Qt.locale(), Locale.ShortFormat));
            root.details = parts.join("  ·  ");
        });

        root.loading = root.kind !== "image" && root.kind !== "audio" && root.kind !== "other";
        const out = `${root.cacheDir}/preview-${root.requestId}.png`;
        switch (root.kind) {
        case "text":
            root.run(["head", "-c", "200000", path], text => {
                root.previewText = text;
                root.loading = false;
            });
            break;
        case "folder":
            root.run(["bash", "-c", 'cd -- "$1" || exit; ls -A | wc -l; ls -A -p --group-directories-first | head -n 300', "ql", path], text => {
                const lines = text.split("\n").filter(l => l !== "");
                root.folderCount = Number(lines.shift() ?? 0);
                root.folderEntries = lines;
                root.loading = false;
            });
            break;
        case "pdf":
            root.run(["bash", "-c", 'mkdir -p "$3" && rm -f -- "${3:?}"/preview-*.png; pdftoppm -png -r 110 -f 1 -l 1 -singlefile "$1" "${2%.png}" 2>/dev/null && printf "%s" "$2"',
                "ql", path, out, root.cacheDir], text => {
                root.previewImage = text.trim();
                root.loading = false;
            });
            break;
        case "video":
            root.run(["bash", "-c", 'mkdir -p "$3" && rm -f -- "${3:?}"/preview-*.png; '
                + '{ ffmpegthumbnailer -i "$1" -o "$2" -s 1024 || ffmpeg -y -loglevel error -ss 1 -i "$1" -frames:v 1 -vf "scale=1024:-2" "$2"; } >/dev/null 2>&1 && [ -s "$2" ] && printf "%s" "$2"',
                "ql", path, out, root.cacheDir], text => {
                root.previewImage = text.trim();
                root.loading = false;
            });
            break;
        }
    }

    Loader {
        active: root.open && !GlobalStates.screenLocked

        sourceComponent: PanelWindow {
            id: panel
            screen: Quickshell.screens[0]
            WlrLayershell.namespace: "quickshell:quickLook"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Dim backdrop; clicking it closes
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.25)
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onClicked: root.close()
                }
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: Math.min(panel.width * 0.7, 1100)
                height: Math.min(panel.height * 0.78, 820)
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Space || event.key === Qt.Key_Escape) {
                        root.close();
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                        root.go(-1);
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                        root.go(1);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.openItem();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                // Swallow clicks so they don't reach the backdrop
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // ---- Header: icon, name, position, open, close ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        IconImage {
                            implicitSize: 28
                            source: Quickshell.iconPath(root.iconFor(root.kind, root.item), "text-x-generic")
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.item?.name ?? ""
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            visible: GlobalStates.quickLookItems.length > 1
                            text: `${GlobalStates.quickLookIndex + 1} / ${GlobalStates.quickLookItems.length}`
                            color: Appearance.colors.colSubtext
                        }
                        RippleButton {
                            implicitWidth: openRow.implicitWidth + 24
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.openItem()
                            contentItem: RowLayout {
                                id: openRow
                                spacing: 6
                                MaterialSymbol {
                                    Layout.leftMargin: 12
                                    text: "open_in_new"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    Layout.rightMargin: 12
                                    text: Translation.tr("Open")
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }
                        RippleButton {
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.close()
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "close"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    // ---- Content ----
                    Rectangle {
                        id: contentArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        clip: true

                        // Images: the file itself; PDFs and videos: the generated picture
                        readonly property string pictureFile: root.kind === "image" ? (root.item?.path ?? "") : root.previewImage
                        readonly property bool isGif: root.kind === "image" && (root.item?.suffix ?? "").toLowerCase() === "gif"
                        readonly property bool pictureReady: (picture.visible && picture.status === Image.Ready) || (gif.visible && gif.status === Image.Ready)
                        readonly property bool pictureLoading: picture.status === Image.Loading || gif.status === Image.Loading
                        Image {
                            id: picture
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: !contentArea.isGif && contentArea.pictureFile !== "" && status === Image.Ready
                            source: (!contentArea.isGif && contentArea.pictureFile !== "") ? root.fileUrl(contentArea.pictureFile) : ""
                            sourceSize: Qt.size(width * 2, height * 2)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                        }
                        AnimatedImage {
                            id: gif
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: contentArea.isGif && status === Image.Ready
                            source: contentArea.isGif ? root.fileUrl(contentArea.pictureFile) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                        }

                        StyledFlickable {
                            id: textView
                            anchors.fill: parent
                            anchors.margins: 12
                            visible: root.kind === "text" && !root.loading
                            contentWidth: width
                            contentHeight: textContent.implicitHeight
                            clip: true
                            TextEdit {
                                id: textContent
                                width: textView.width
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                text: root.previewText
                                color: Appearance.colors.colOnLayer1
                                selectionColor: Appearance.colors.colPrimary
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }

                        ListView {
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: root.kind === "folder" && !root.loading
                            clip: true
                            model: root.folderEntries
                            delegate: RowLayout {
                                id: folderRow
                                required property string modelData
                                readonly property bool isDir: modelData.endsWith("/")
                                width: ListView.view.width
                                height: 30
                                spacing: 8
                                IconImage {
                                    Layout.leftMargin: 6
                                    implicitSize: 20
                                    source: Quickshell.iconPath(folderRow.isDir ? "folder" : "text-x-generic", "text-x-generic")
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: folderRow.isDir ? folderRow.modelData.slice(0, -1) : folderRow.modelData
                                    elide: Text.ElideRight
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }

                        // Loading / no preview: big icon
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 12
                            visible: !contentArea.pictureReady && !textView.visible
                                && !(root.kind === "folder" && !root.loading && root.folderEntries.length > 0)
                            IconImage {
                                Layout.alignment: Qt.AlignHCenter
                                implicitSize: 128
                                source: Quickshell.iconPath(root.iconFor(root.kind, root.item), "text-x-generic")
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                color: Appearance.colors.colSubtext
                                text: (root.loading || contentArea.pictureLoading) ? Translation.tr("Loading…")
                                    : root.kind === "folder" ? Translation.tr("Empty folder")
                                    : root.kind === "pdf" ? Translation.tr("No preview (needs pdftoppm from poppler)")
                                    : root.kind === "video" ? Translation.tr("No preview (needs ffmpegthumbnailer or ffmpeg)")
                                    : Translation.tr("No preview available")
                            }
                        }
                    }

                    // ---- Footer: details ----
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: root.kind === "folder"
                            ? [Translation.tr("%1 items").arg(root.folderCount), root.details].filter(s => s !== "").join("  ·  ")
                            : root.details
                    }
                }
            }
        }
    }
}
