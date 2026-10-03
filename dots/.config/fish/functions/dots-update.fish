# Applies the downloaded patches to the dots repo, installs and reloads (see dots-update in the repo)
function dots-update --description 'Apply downloaded dots patches, install, reload, push'
    set -l dir ~/dots-hyprland
    set -q DOTS_DIR; and set dir $DOTS_DIR
    if not test -x $dir/dots-update
        echo "dots-update: $dir/dots-update not found (set DOTS_DIR to the repo folder)" >&2
        return 1
    end
    $dir/dots-update $argv
end
