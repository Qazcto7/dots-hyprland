pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    signal closed()

    implicitWidth: 700
    implicitHeight: 560

    component BottomButton: RippleButton {
        id: bottomButton
        property string symbol
        property string tooltip
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: bottomButton.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer0
        }
        StyledToolTip {
            text: bottomButton.tooltip
        }
    }

    component ContextItem: RippleButtonWithIcon {
        Layout.fillWidth: true
        colBackground: "transparent"
    }

    // ---------- Data ----------
    property string query: ""
    property string category: (Config.options?.startMenu.favorites ?? []).length > 0 ? "favorites" : "all"

    // Freedesktop main categories -> menu entries. "match" lists the .desktop categories that belong to it.
    readonly property var categoryDefs: [
        { id: "favorites", name: Translation.tr("Favorites"), icon: "star" },
        { id: "all", name: Translation.tr("All applications"), icon: "apps" },
        { id: "Development", name: Translation.tr("Development"), icon: "code", match: ["Development"] },
        { id: "Game", name: Translation.tr("Games"), icon: "sports_esports", match: ["Game"] },
        { id: "Graphics", name: Translation.tr("Graphics"), icon: "palette", match: ["Graphics"] },
        { id: "Network", name: Translation.tr("Internet"), icon: "language", match: ["Network"] },
        { id: "AudioVideo", name: Translation.tr("Multimedia"), icon: "music_video", match: ["AudioVideo", "Audio", "Video"] },
        { id: "Office", name: Translation.tr("Office"), icon: "description", match: ["Office"] },
        { id: "Education", name: Translation.tr("Education"), icon: "school", match: ["Education", "Science"] },
        { id: "Settings", name: Translation.tr("Settings"), icon: "settings", match: ["Settings"] },
        { id: "System", name: Translation.tr("System"), icon: "memory", match: ["System"] },
        { id: "Utility", name: Translation.tr("Utilities"), icon: "build", match: ["Utility"] },
    ]

    readonly property var allApps: [...AppSearch.list].sort((a, b) => a.name.localeCompare(b.name))

    function appsInCategory(def) {
        if (def.id === "all") return root.allApps;
        if (def.id === "favorites") {
            return (Config.options?.startMenu.favorites ?? [])
                .map(id => root.allApps.find(app => app.id === id))
                .filter(app => app !== undefined);
        }
        return root.allApps.filter(app => (app.categories ?? []).some(cat => def.match.indexOf(cat) !== -1));
    }

    // Hide categories that have no apps (except favorites/all)
    readonly property var visibleCategories: categoryDefs.filter(def =>
        def.id === "favorites" || def.id === "all" || appsInCategory(def).length > 0)

    readonly property var shownApps: {
        if (root.query.trim() !== "")
            return AppSearch.fuzzyQuery(root.query.trim());
        const def = root.categoryDefs.find(d => d.id === root.category) ?? root.categoryDefs[1];
        return root.appsInCategory(def);
    }

    function isFavorite(id) {
        return (Config.options?.startMenu.favorites ?? []).indexOf(id) !== -1;
    }
    function toggleFavorite(id) {
        const favs = Config.options.startMenu.favorites;
        Config.options.startMenu.favorites = isFavorite(id) ? favs.filter(f => f !== id) : favs.concat([id]);
    }

    // The id the dock uses for this app (its window class / Wayland app id, lowercased).
    // An existing pin or a running window of the app decides; otherwise the .desktop
    // StartupWMClass when the app sets one (e.g. "firefox"), else the desktop id.
    function dockId(entry) {
        const ids = [entry?.id, entry?.startupClass].filter(s => !!s).map(s => s.toLowerCase());
        if (ids.length === 0) return "";
        const pinned = (Config.options?.dock.pinnedApps ?? []).find(p => ids.indexOf(p.toLowerCase()) !== -1);
        if (pinned) return pinned.toLowerCase();
        const running = ToplevelManager.toplevels.values.find(t => ids.indexOf((t.appId ?? "").toLowerCase()) !== -1);
        if (running) return running.appId.toLowerCase();
        return (entry?.startupClass || entry?.id || "").toLowerCase();
    }

    function launch(entry) {
        if (!entry) return;
        entry.execute();
        root.closed();
    }

    onQueryChanged: appList.currentIndex = 0
    onCategoryChanged: appList.currentIndex = 0

    // ---------- Look ----------
    StyledRectangularShadow {
        target: background
    }
    Rectangle {
        id: background
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.windowRounding
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (contextMenu.visible) contextMenu.close();
            else root.closed();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Search
        ToolbarTextField {
            id: searchField
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: 42
            focus: true
            placeholderText: Translation.tr("Search applications…")
            onTextChanged: root.query = text
            Component.onCompleted: forceActiveFocus()

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down) {
                    appList.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    appList.decrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (contextMenu.visible) contextMenu.close();
                    else root.launch(root.shownApps[appList.currentIndex]);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    // Escape first closes the right-click menu, then the start menu
                    if (contextMenu.visible) contextMenu.close();
                    else root.closed();
                    event.accepted = true;
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // Categories
            ListView {
                id: categoryList
                Layout.fillHeight: true
                Layout.preferredWidth: 200
                clip: true
                spacing: 2
                opacity: root.query.trim() === "" ? 1 : 0.4
                model: root.visibleCategories
                delegate: RippleButton {
                    id: categoryButton
                    required property var modelData
                    width: ListView.view.width
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    readonly property bool selected: root.query.trim() === "" && root.category === modelData.id
                    colBackground: selected ? Appearance.colors.colSecondaryContainer : "transparent"
                    colBackgroundHover: selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1Hover
                    onClicked: {
                        searchField.text = "";
                        root.category = modelData.id;
                        searchField.forceActiveFocus();
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            Layout.leftMargin: 8
                            text: categoryButton.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            fill: categoryButton.selected ? 1 : 0
                            color: categoryButton.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: categoryButton.modelData.name
                            elide: Text.ElideRight
                            color: categoryButton.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Appearance.colors.colOutlineVariant
            }

            // Apps
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: appList
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    currentIndex: 0
                    highlightMoveDuration: 0
                    model: root.shownApps
                    ScrollBar.vertical: StyledScrollBar {}
                    delegate: StartMenuAppRow {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        entry: modelData
                        current: ListView.isCurrentItem
                        onLaunched: root.closed()
                        onContextRequested: (x, y) => {
                            const p = mapToItem(root, x, y);
                            contextMenu.openFor(modelData, p.x, p.y);
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.shownApps.length === 0
                    text: root.category === "favorites" && root.query.trim() === ""
                        ? Translation.tr("Right-click an app to add it to favorites")
                        : Translation.tr("No results")
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        // Bottom row: user + system buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "account_circle"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                text: SystemInfo.username
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }

            BottomButton {
                symbol: "settings"
                tooltip: Translation.tr("System Settings")
                onClicked: {
                    Quickshell.execDetached(["bash", "-c", "env XDG_CURRENT_DESKTOP=KDE systemsettings"]);
                    root.closed();
                }
            }
            BottomButton {
                symbol: "lock"
                tooltip: Translation.tr("Lock")
                onClicked: {
                    root.closed();
                    Session.lock();
                }
            }
            BottomButton {
                symbol: "power_settings_new"
                tooltip: Translation.tr("Power / Session")
                onClicked: {
                    root.closed();
                    GlobalStates.sessionOpen = true;
                }
            }
        }
    }

    // ---------- Right-click menu for apps ----------
    MouseArea {
        anchors.fill: parent
        visible: contextMenu.visible
        acceptedButtons: Qt.AllButtons
        onPressed: contextMenu.close()
    }
    Rectangle {
        id: contextMenu
        property var entry: null
        visible: entry !== null
        function openFor(entry, x, y) {
            contextMenu.entry = entry;
            contextMenu.x = Math.min(x, root.width - width - 8);
            contextMenu.y = Math.min(y, root.height - height - 8);
        }
        function close() {
            contextMenu.entry = null;
            searchField.forceActiveFocus();
        }
        width: 230
        height: contextColumn.implicitHeight + 12
        color: Appearance.colors.colLayer2
        radius: Appearance.rounding.small
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: contextColumn
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            ContextItem {
                materialIcon: "rocket_launch"
                mainText: Translation.tr("Open")
                onClicked: root.launch(contextMenu.entry)
            }
            ContextItem {
                materialIcon: root.isFavorite(contextMenu.entry?.id ?? "") ? "star_rate_half" : "star"
                mainText: root.isFavorite(contextMenu.entry?.id ?? "") ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
                onClicked: {
                    root.toggleFavorite(contextMenu.entry.id);
                    contextMenu.close();
                }
            }
            ContextItem {
                materialIcon: "keep"
                mainText: TaskbarApps.isPinned(root.dockId(contextMenu.entry)) ? Translation.tr("Unpin from dock") : Translation.tr("Pin to dock")
                onClicked: {
                    TaskbarApps.togglePin(root.dockId(contextMenu.entry));
                    contextMenu.close();
                }
            }
        }
    }
}
