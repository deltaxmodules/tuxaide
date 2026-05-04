#!/usr/bin/env bash
set -euo pipefail

# Backward-compatibility entrypoint.
# Preferred public installer: curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/install.sh | bash

TMP_INSTALL="$(mktemp)"
trap 'rm -f "$TMP_INSTALL"' EXIT

echo "[TuxAide] Downloading installer..."
if curl -fSL --progress-bar "https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/install.sh" -o "$TMP_INSTALL"; then
    echo "[TuxAide] Starting installer..."
    bash "$TMP_INSTALL"
else
    echo "Failed to download install.sh from GitHub." >&2
    echo "Try: git clone https://github.com/deltaxmodules/tuxaide ~/.tuxaide && ~/.tuxaide/install.sh" >&2
    exit 1
fi
