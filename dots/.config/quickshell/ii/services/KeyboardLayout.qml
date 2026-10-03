pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.common
import qs.modules.common.functions

/**
 * Keyboard layout chosen in Settings > General > Language.
 * Writes the layout to a small file that ~/.config/hypr/hyprland/keyboard.lua reads, then
 * reloads Hyprland (only when the file actually changes). "auto" follows the interface language.
 */
Singleton {
    id: root

    readonly property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/hyprland/keyboard.lua`)

    // value: "layout" or "layout:variant" (xkb names)
    readonly property var layouts: [
        { value: "tr", name: Translation.tr("Turkish (Q)") },
        { value: "tr:f", name: Translation.tr("Turkish (F)") },
        { value: "us", name: Translation.tr("English (US)") },
        { value: "us:intl", name: Translation.tr("English (US, international)") },
        { value: "gb", name: Translation.tr("English (UK)") },
        { value: "de", name: Translation.tr("German") },
        { value: "fr", name: Translation.tr("French") },
        { value: "es", name: Translation.tr("Spanish") },
        { value: "it", name: Translation.tr("Italian") },
        { value: "pt", name: Translation.tr("Portuguese") },
        { value: "br", name: Translation.tr("Portuguese (Brazil)") },
        { value: "nl", name: Translation.tr("Dutch") },
        { value: "pl", name: Translation.tr("Polish") },
        { value: "ru", name: Translation.tr("Russian") },
        { value: "ua", name: Translation.tr("Ukrainian") },
        { value: "az", name: Translation.tr("Azerbaijani") },
        { value: "ara", name: Translation.tr("Arabic") },
        { value: "ir", name: Translation.tr("Persian") },
        { value: "gr", name: Translation.tr("Greek") },
        { value: "jp", name: Translation.tr("Japanese") },
        { value: "kr", name: Translation.tr("Korean") },
        { value: "cn", name: Translation.tr("Chinese") },
        { value: "vn", name: Translation.tr("Vietnamese") },
    ]
    readonly property var switchKeys: [
        { value: "grp:win_space_toggle", name: Translation.tr("Super + Space") },
        { value: "grp:alt_shift_toggle", name: Translation.tr("Alt + Shift") },
        { value: "grp:ctrl_shift_toggle", name: Translation.tr("Ctrl + Shift") },
        { value: "grp:caps_toggle", name: Translation.tr("Caps Lock") },
    ]

    // Interface language (e.g. tr_TR) -> keyboard layout
    readonly property var localeLayouts: ({
        "tr": "tr", "en_US": "us", "en_GB": "gb", "en": "us", "de": "de", "fr": "fr", "es": "es", "it": "it",
        "pt_BR": "br", "pt": "pt", "nl": "nl", "pl": "pl", "ru": "ru", "uk": "ua", "az": "az", "ar": "ara",
        "fa": "ir", "el": "gr", "ja": "jp", "ko": "kr", "zh": "cn", "vi": "vn", "he": "il",
    })
    function layoutForLocale(locale) {
        const name = (locale === "auto" || !locale) ? Qt.locale().name : locale;
        const lang = name.split("_")[0];
        return root.localeLayouts[name] ?? root.localeLayouts[lang] ?? "us";
    }

    readonly property string chosen: Config.options?.language.keyboard.layout ?? "auto"
    readonly property string primary: root.chosen === "auto" ? root.layoutForLocale(Config.options?.language.ui ?? "auto") : root.chosen
    readonly property string secondary: Config.options?.language.keyboard.secondLayout ?? ""
    readonly property string switchKey: Config.options?.language.keyboard.switchKey ?? "grp:win_space_toggle"

    function split(value) {
        const [layout, variant] = value.split(":");
        return { layout: layout ?? "", variant: variant ?? "" };
    }
    readonly property string content: {
        // "system": leave the layout to the Hyprland config (general.lua / custom/general.lua)
        if (root.chosen === "system")
            return "return {}";
        const first = root.split(root.primary);
        if (root.secondary === "" || root.secondary === root.primary)
            return `return { layout = "${first.layout}", variant = "${first.variant}" }`;
        const second = root.split(root.secondary);
        return `return { layout = "${first.layout},${second.layout}", variant = "${first.variant},${second.variant}", options = "${root.switchKey}" }`;
    }

    // Only the main shell writes the file. The settings app (a separate Quickshell process) also
    // creates this singleton when it shows these options, but never calls load().
    property bool active: false
    function load() {
        root.active = true;
    }

    onContentChanged: applyTimer.restart()

    Timer {
        id: applyTimer
        interval: 300
        running: Config.ready && root.active
        onTriggered: {
            if (!Config.ready || !root.active) return;
            applyProc.running = false;
            applyProc.command = ["bash", "-c",
                'mkdir -p "$(dirname "$1")" && if [ "$(cat "$1" 2>/dev/null)" != "$2" ]; then printf "%s\\n" "$2" > "$1" && exit 10; fi',
                "keyboard-layout", root.filePath, root.content];
            applyProc.running = true;
        }
    }

    Process {
        id: applyProc
        // 10 = the file changed: reload Hyprland (shared and debounced with the other services)
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 10) HyprlandReload.request();
        }
    }
}
