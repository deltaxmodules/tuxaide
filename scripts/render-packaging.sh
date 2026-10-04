#!/usr/bin/env bash
# Fill in the Homebrew formula and the AUR PKGBUILD for a release.
#   scripts/render-packaging.sh <version> [<tarball-url>] [<out-dir>]
# The tarball (GitHub's archive of tag v<version> by default) is downloaded to
# compute its sha256. Output: <out-dir>/tuxaide.rb, PKGBUILD, .SRCINFO-less.
set -euo pipefail

version="${1:?usage: render-packaging.sh <version> [<tarball-url>] [<out-dir>]}"
url="${2:-https://github.com/deltaxmodules/tuxaide/archive/refs/tags/v${version}.tar.gz}"
out="${3:-dist}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$out"
tarball="$(mktemp)"
trap 'rm -f "$tarball"' EXIT
curl -fsSL "$url" -o "$tarball"
if command -v sha256sum >/dev/null; then sha="$(sha256sum "$tarball" | cut -d' ' -f1)"
else sha="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"; fi

render() {
    sed -e "s|@VERSION@|${version}|g" -e "s|@URL@|${url}|g" -e "s|@SHA256@|${sha}|g" "$1" > "$2"
}
render "$here/packaging/homebrew/tuxaide.rb.in" "$out/tuxaide.rb"
render "$here/packaging/aur/PKGBUILD.in" "$out/PKGBUILD"
cp "$here/packaging/aur/tuxaide.install" "$out/tuxaide.install"
echo "tarball sha256: $sha"
echo "wrote $out/tuxaide.rb $out/PKGBUILD $out/tuxaide.install"
