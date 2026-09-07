#!/usr/bin/env bash
# Put the translation catalog where a dev checkout's surfaces look for it, so a
# locally run shell, Hub, app or installer speaks the same languages a packaged
# one does. Mirrors ryoku/ui/install.sh; on a packaged system the same files
# land at /usr/share/ryoku/i18n from the ryoku-desktop PKGBUILD, which is the
# next candidate the runtimes try.
#
#   install.sh [<data-root>]     (default: ~/.local/share)
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
root="${1:-${XDG_DATA_HOME:-$HOME/.local/share}}"
dest="$root/ryoku/i18n"

rm -rf "$dest"
mkdir -p "$dest"
install -m0644 "$here/langs.json" "$dest/langs.json"
install -m0644 "$here"/catalog/*.json "$dest/"
echo "installed the Ryoku i18n catalog -> $dest"
