#!/usr/bin/env bash
# TuxAide uninstaller (installed as ~/.local/bin/tuxaide-uninstall).
# The work is done by `tuxaide uninstall`: it removes only the lines TuxAide
# added to your shell rc files (keeping a backup) and TuxAide's own files.
#   tuxaide-uninstall [--yes] [--keep-data]
for agent in "${HOME}/.local/bin/tuxaide" "$(command -v tuxaide 2>/dev/null)"; do
    if [[ -n "$agent" && -x "$agent" ]]; then
        exec "$agent" uninstall "$@"
    fi
done
echo "TuxAide's program wasn't found, so there is nothing to uninstall." >&2
echo "If your shell rc still loads it, delete the lines between '# >>> TuxAide >>>' and '# <<< TuxAide <<<'." >&2
exit 1
