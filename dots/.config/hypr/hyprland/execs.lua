-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function ()

    -- Bar, wallpaper
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
    hl.exec_cmd("qs -c $qsConfig")
    hl.exec_cmd("hyprpm reload -n") -- Plugins (hyprbars title bars), see hyprland/titlebars.lua
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")

    -- Core components (authentication, lock screen, notification daemon)
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("dbus-update-activation-environment --all")
    hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP") -- Some fix idk

    -- Audio
    hl.exec_cmd("easyeffects --hide-window --service-mode")

    -- Clipboard: history
    --hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")
    hl.exec_cmd("wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")

    -- Cursor
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")

    -- CachyOS updater (cachy-update). Hyprland does not run XDG autostart entries, so its tray
    -- icon is started here. Its update window is opened through gio/xdg-terminal-exec, which
    -- needs to know the terminal: use kitty in Hyprland sessions (only if nothing is set yet;
    -- this list is read only when XDG_CURRENT_DESKTOP=Hyprland, Plasma is not affected).
    hl.exec_cmd([[f="${XDG_CONFIG_HOME:-$HOME/.config}/hyprland-xdg-terminals.list"; [ -e "$f" ] || printf 'kitty.desktop\n' > "$f"]])
    hl.exec_cmd("command -v cachy-update >/dev/null && sleep 3 && cachy-update --tray")
end)
