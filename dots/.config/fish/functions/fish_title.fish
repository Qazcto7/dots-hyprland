# Overrides /usr/share/fish/vendor_functions.d/fish_title.fish, which passes an
# empty length to prompt_pwd and prints "Invalid number" on every prompt.
# Lives in the repo because `./setup install-files` syncs ~/.config/fish.
function fish_title
    set -l cmd (status current-command)
    test "$cmd" = fish; and set cmd
    echo -- $cmd (prompt_pwd -d 1)
end
