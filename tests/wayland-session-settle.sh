#!/usr/bin/env bash
# hermetic test for ryoku-wayland-session, the SDDM [Wayland] SessionCommand
# wrapper that waits for the greeter (weston) to release the GPU before the
# session compositor probes KMS (issue #174: a hybrid-GPU laptop otherwise misses
# its iGPU and lands on a black headless dGPU).
#
# Nothing here starts weston or a compositor. A fake pgrep on PATH reports weston
# "present" for a controlled number of polls, and RYOKU_WAYLAND_SESSION_DEFAULT
# points at a fake session that records that it ran and with which arguments.
#
# The load-bearing assertions: the wrapper does NOT hand off while weston is
# still present, always hands off eventually (login never hangs), and passes the
# session arguments through untouched.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
wrapper="$here/../ryoku/lockscreen/sddm/ryoku-wayland-session"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

bin="$tmp/bin"; mkdir -p "$bin"

# fake pgrep: reports weston present until it has been polled "$tmp/pglimit"
# times, then gone. Every call bumps "$tmp/pgcount" so the test can see whether
# the wrapper actually waited.
cat >"$bin/pgrep" <<EOF
#!/bin/sh
c=\$(cat "$tmp/pgcount" 2>/dev/null || echo 0); c=\$((c + 1)); echo "\$c" >"$tmp/pgcount"
limit=\$(cat "$tmp/pglimit" 2>/dev/null || echo 0)
[ "\$c" -le "\$limit" ] && exit 0   # weston present
exit 1                              # weston gone
EOF
chmod +x "$bin/pgrep"
export PATH="$bin:$PATH"

# fake session: records the arguments it was handed and that it ran at all.
cat >"$bin/fake-session" <<EOF
#!/bin/sh
printf '%s' "\$*" >"$tmp/session-args"
: >"$tmp/session-ran"
EOF
chmod +x "$bin/fake-session"
export RYOKU_WAYLAND_SESSION_DEFAULT="$bin/fake-session"

reset() { rm -f "$tmp/pgcount" "$tmp/session-ran" "$tmp/session-args"; }
polls() { cat "$tmp/pgcount" 2>/dev/null || echo 0; }

# ---- greeter still up: wait for it, then hand off with args intact -----------
reset
echo 3 >"$tmp/pglimit"   # weston present for the first three polls
RYOKU_SESSION_SETTLE_DEADLINE=10 "$wrapper" Hyprland --foo
[[ -e "$tmp/session-ran" ]] || fail "wrapper never handed off to the session"
[[ "$(cat "$tmp/session-args")" == "Hyprland --foo" ]] \
  || fail "session arguments were not passed through: '$(cat "$tmp/session-args")'"
(( "$(polls)" >= 2 )) || fail "wrapper handed off without waiting for weston (polled $(polls)x)"

# ---- no greeter: hand off at once, no wasted polling -------------------------
reset
echo 0 >"$tmp/pglimit"   # weston already gone
"$wrapper" Hyprland
[[ -e "$tmp/session-ran" ]] || fail "wrapper did not hand off when weston was absent"
(( "$(polls)" == 1 )) || fail "wrapper polled $(polls)x when weston was already gone; expected 1"

# ---- greeter never exits: the deadline caps the wait so login never hangs ----
reset
echo 100000 >"$tmp/pglimit"   # weston "present" forever
start=$SECONDS
RYOKU_SESSION_SETTLE_DEADLINE=1 "$wrapper" Hyprland
[[ -e "$tmp/session-ran" ]] || fail "wrapper hung on a greeter that never exits (must cap and hand off)"
(( SECONDS - start <= 4 )) || fail "wrapper waited past its deadline"

echo "wayland-session-settle: all checks passed"
