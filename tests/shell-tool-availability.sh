#!/usr/bin/env bash
# Prevent the "feature wired but its tool is not shipped" class: every external
# program a Ryoku desktop feature depends on must be shipped by a package set
# (base/dev/aur). This is a curated feature -> package map; add a row when a new
# feature starts shelling out to a new tool.
set -euo pipefail

ROOT=${RYOKU_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
pkgs="$ROOT/system/packages"

ships() {
  grep -qxF "$1" "$pkgs/base.packages" "$pkgs/dev.packages" "$pkgs/aur.packages" 2>/dev/null && return 0
  # first-party [ryoku] repo packages (ryogami, ...) ship from release/packages,
  # not the package sets.
  [[ -d "$ROOT/release/packages/$1" ]]
}

# reach: a tool merely in base.packages ships on the ISO (pacstrap) but NEVER
# reaches an already-installed box on `ryoku update` (that is a pacman -Syu, and
# base.packages is not a package) nor a shell-installer box unless it is also a
# hard depend of the ryoku-desktop umbrella. hard_depend() checks exactly that:
# is $1 in the ryoku-desktop depends=() array (version pin ignored). This is the
# guard the ddcutil regression slipped past -- ddcutil was added to base.packages
# but not to depends, so the pill DISPLAY faders were dead on every packaged box.
desktop_pkgbuild="$ROOT/release/packages/ryoku-desktop/PKGBUILD"
hard_depend() {
  # capture the block first, then grep a here-string: piping awk into `grep -q`
  # lets grep close the pipe on the first match, and under `set -o pipefail`
  # awk's SIGPIPE would make the pipeline (nondeterministically) report failure.
  local block
  block=$(awk '/^depends=\(/{d=1;next} d&&/^\)/{d=0} d' "$desktop_pkgbuild")
  grep -qE "[\"']$1(=[^\"']*)?[\"']" <<<"$block"
}
# official_repo: shipped from base/dev (an Arch repo), not AUR, not first-party
# [ryoku]. AUR tools reach boxes via the post-install AUR step; first-party
# packages are depends already. Only official-repo tools must be hard depends.
official_repo() {
  grep -qxF "$1" "$pkgs/base.packages" "$pkgs/dev.packages" 2>/dev/null \
    && ! grep -qxF "$1" "$pkgs/aur.packages" 2>/dev/null \
    && [[ ! -d "$ROOT/release/packages/$1" ]]
}
# shipped_app: the other delivery path. An application a user may delete is not a
# hard depend (pacman would put it back on the next upgrade); `ryoku doctor`
# delivers it once and then honours the removal. Membership is the doctor's own
# table, so a name cannot fall out of delivery and still pass this gate.
shipped_apps_go="$ROOT/ryoku/cli/internal/doctor/reconcile_shipped_apps.go"
shipped_app() {
  grep -qE "^[[:space:]]*\{\"$1\", " "$shipped_apps_go"
}
# deliberately neither a hard depend nor a provisioned app (documented exception):
#   chromium -- the default browser is user-swappable; base.packages ships it and
#               the ryoku-app role resolver tolerates another browser being set.
declare -A dependExempt=( [chromium]=1 )

# feature -> package that provides it
declare -A need=(
  # the wallpaper daemon is ryogami, a first-party [ryoku] package and a hard
  # ryoku-desktop depend; live wallpapers ride ryoku-livewall, which ships
  # inside the ryoku-shell package itself (phonto/mpvpaper were dropped with
  # it, 7c20f7dd; awww was retired with 25a57f57).
  [wallpaper-daemon]=ryogami
  [palette]=matugen
  [clipboard-history]=cliphist
  [color-picker]=hyprpicker
  [music-visualizer]=cava
  [led-color]=openrgb
  [screenshot]=grim
  [region-select]=slurp
  [ocr]=tesseract
  [qr-scan]=zbar
  [screen-record]=gpu-screen-recorder
  [screen-record-fallback]=wf-recorder
  [screen-share-picker]=hyprland-preview-share-picker
  [night-light]=hyprsunset
  [voice-type]=wtype
  [voice-stt]=voxtype-bin
  [media-control]=playerctl
  # the launcher's "@" live radio: mpv plays, mpv-mpris puts it on the players
  # bus (without it every now-playing surface goes blind to the broadcast),
  # yt-dlp resolves the YouTube /live pages at play time.
  [radio-player]=mpv
  [radio-mpris]=mpv-mpris
  [radio-resolver]=yt-dlp
  [brightness]=brightnessctl
  [idle]=hypridle
  [battery]=upower
  [shell]=quickshell
  [terminal]=kitty
  [browser]=chromium
  [files]=nautilus
  [editor]=neovim
  [file-cli]=yazi
  [video]=mpv
  [calc]=libqalculate
  [music-recognition]=songrec
  [display-brightness]=ddcutil
  [vibrance]=nvibrant-bin
  [network-kill-switch]=nftables
)

missing=()
for feat in "${!need[@]}"; do
  pkg=${need[$feat]}
  ships "$pkg" || missing+=("$feat -> $pkg")
done

if (( ${#missing[@]} )); then
  echo "::error::shell features whose package is not in any package set:" >&2
  printf '  %s\n' "${missing[@]}" | sort >&2
  exit 1
fi

# reach check: every official-repo feature tool must be a ryoku-desktop hard
# depend so it lands on the ISO, on `ryoku update`, and via the shell installer
# alike -- one source of truth, no ISO-only tools.
notreached=()
for feat in "${!need[@]}"; do
  pkg=${need[$feat]}
  [[ -n ${dependExempt[$pkg]:-} ]] && continue
  official_repo "$pkg" || continue
  hard_depend "$pkg" || shipped_app "$pkg" || notreached+=("$feat -> $pkg")
done
if (( ${#notreached[@]} )); then
  echo "::error::feature tools in base.packages but NOT a ryoku-desktop hard depend (ISO-only; never reach 'ryoku update' or shell-installer boxes -- the ddcutil-class drift):" >&2
  printf '  %s\n' "${notreached[@]}" | sort >&2
  exit 1
fi

echo "shell-tool-availability: all ${#need[@]} gated feature packages are shipped and reach every install path (ISO, update, shell installer)"
