#!/usr/bin/env bash
set -euo pipefail

# Entry point for:  curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
# Arguments go to install.sh:  … | bash -s -- --yes
# It runs the installer of the latest release, falling back to main while
# no release carries one.

REPO="${TUXAIDE_REPO:-deltaxmodules/tuxaide}"
TMP_INSTALL="$(mktemp)"
trap 'rm -f "$TMP_INSTALL"' EXIT

echo "[TuxAide] Downloading installer..."
if curl -fsSL "https://github.com/${REPO}/releases/latest/download/install.sh" -o "$TMP_INSTALL" 2>/dev/null \
   || curl -fSL --progress-bar "https://raw.githubusercontent.com/${REPO}/main/install.sh" -o "$TMP_INSTALL"; then
    echo "[TuxAide] Starting installer..."
    bash "$TMP_INSTALL" "$@"
else
    echo "Failed to download install.sh from GitHub." >&2
    echo "Try: git clone https://github.com/${REPO} ~/.tuxaide && ~/.tuxaide/install.sh" >&2
    exit 1
fi
