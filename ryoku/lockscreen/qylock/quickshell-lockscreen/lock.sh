#!/usr/bin/env bash

# Current directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set library paths
export QML2_IMPORT_PATH="$DIR/imports:$QML2_IMPORT_PATH"
export QML_XHR_ALLOW_FILE_READ=1

# The lock is spawned by the shell daemon, a systemd user service whose env is
# whatever was imported at login; a daemon (re)started outside that import has
# no XCURSOR_*, Qt falls back to the "default" theme, and where that resolves to
# nothing the lock surface sets a null cursor: no visible pointer. Default to
# the shipped Bibata set (ryoku-cursors) at the size env.lua uses. A session
# that exported its own theme keeps it.
export XCURSOR_THEME="${XCURSOR_THEME:-Bibata-Modern-Ice}"
export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
export HYPRCURSOR_THEME="${HYPRCURSOR_THEME:-$XCURSOR_THEME}"
export HYPRCURSOR_SIZE="${HYPRCURSOR_SIZE:-$XCURSOR_SIZE}"

# Get session type: the env when set, else this session's logind record.
# XDG_SESSION_ID pins the right session; scraping `loginctl | grep user`
# picked the first of several (re-login, nested session) and could misread.
if [ -z "${XDG_SESSION_TYPE:-}" ]; then
    sid="${XDG_SESSION_ID:-$(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$(id -un)" '$3 == u {print $1; exit}')}"
    XDG_SESSION_TYPE="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
    [ -n "$XDG_SESSION_TYPE" ] || XDG_SESSION_TYPE=wayland
fi
export XDG_SESSION_TYPE

# User theme preference
# Get user theme
CONFIG_FILE="$HOME/.config/qylock/theme"
if [ -n "$1" ]; then
    export QS_THEME="$1"
elif [ -f "$CONFIG_FILE" ]; then
    QS_THEME=$(cat "$CONFIG_FILE")
    export QS_THEME
else
    export QS_THEME="clockwork/orbital"
fi

# Set theme path
if [ -d "$DIR/../themes" ] && [ ! -d "$DIR/themes_link" ]; then
    export QS_THEME_PATH="$DIR/../themes/$QS_THEME"
else
    export QS_THEME_PATH="$DIR/themes_link/$QS_THEME"
fi

# A theme that vanished (an uninstalled skin still named by the config, a
# broken themes_link) must never lock into a black screen with no unlock UI:
# fall back to the stock theme before launching.
if [ ! -f "$QS_THEME_PATH/Main.qml" ]; then
    echo "qylock: theme '$QS_THEME' not found at $QS_THEME_PATH; falling back to clockwork/orbital" >&2
    for fb in "$DIR/themes_link/clockwork/orbital" "$DIR/../themes/clockwork/orbital"; do
        if [ -f "$fb/Main.qml" ]; then
            export QS_THEME="clockwork/orbital"
            export QS_THEME_PATH="$fb"
            break
        fi
    done
fi

echo "Locking with Quickshell using theme: $QS_THEME"
echo "Theme path: $QS_THEME_PATH"


# Hyprland draws the lock-surface pointer from the theme set with
# `hyprctl setcursor` (autostart.lua does this at login). The lock is spawned by
# the shell daemon, whose imported env can predate that call, and a downloaded
# theme carries no cursor fix of its own, so the lock could come up with no
# visible pointer. Re-assert it here, best-effort, from the same theme/size the
# client uses, so every theme shows a usable cursor.
if [ "$XDG_SESSION_TYPE" = wayland ] && command -v hyprctl >/dev/null 2>&1; then
    hyprctl setcursor "$XCURSOR_THEME" "$XCURSOR_SIZE" >/dev/null 2>&1 || true
fi
# Kill active lockers
killall -9 hyprlock swaylock wlogout 2>/dev/null || true

# Execute lock screen. Whatever way it ends (unlock or crash), drop the
# "compositor confirmed the lock" marker lock_shell.qml wrote: a stale marker
# would let a later `ryoku-shell lock` read a starting locker as already
# covering the screen.
quickshell -p "$DIR/lock_shell.qml"
rc=$?
rm -f "${XDG_RUNTIME_DIR:-/tmp}/qylock.locked"
exit "$rc"
