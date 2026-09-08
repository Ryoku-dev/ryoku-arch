#!/usr/bin/env bash
# hermetic test for bin/ryoku-recovery, the curl|bash panic button. it must
# always drag a machine back to stable main, even when RYOKU_CHANNEL is leaked
# to unstable-dev (the failure that bricked a user: an old ISO updater flipped
# the checkout to unstable-dev, where the new tree has none of the old helper
# commands). recovery converges the box on the one checkout `ryoku track`
# clones and `ryoku` (sys.ResolveRepo) tracks -- ~/ryoku-arch -- repairing it
# in place onto main, consolidating the retired data-root checkouts beside it
# so nothing re-strands the box, and dropping the dangling runtime-env bridge.
#
# no network, no pacman, no real build. origin = a local bare repo whose
# deploy.sh is a stub, and a fake `go` satisfies the recovery preflight.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RECOVERY="$ROOT/bin/ryoku-recovery"
[[ -x $RECOVERY ]] || { echo "::error::missing or non-executable $RECOVERY" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# fake `go` so the recovery preflight `need go` passes on a CI runner with no
# Go toolchain. the stub deploy.sh below never actually calls it.
mkdir -p "$work/fakebin"
printf '#!/bin/sh\nexit 0\n' >"$work/fakebin/go"
chmod +x "$work/fakebin/go"
export PATH="$work/fakebin:$PATH"

git_q() { git -c init.defaultBranch=main -c user.name=t -c user.email=t@t -c advice.detachedHead=false "$@"; }

# local origin with main + unstable-dev. main carries a stub deploy.sh that
# records which checkout it ran from = stands in for the real build.
origin="$work/origin.git"
seed="$work/seed"
git_q init -q "$seed"
mkdir -p "$seed/ryoku/shell" "$seed/system/packages"
cat >"$seed/ryoku/shell/deploy.sh" <<'EOF'
#!/usr/bin/env bash
printf 'deployed-from %s\n' "$(cd "$(dirname "$0")/../.." && pwd -P)" >"${RYOKU_TEST_MARKER:?}"
EOF
chmod +x "$seed/ryoku/shell/deploy.sh"
echo "# packages" >"$seed/system/packages/base.packages"
git_q -C "$seed" add -A
git_q -C "$seed" commit -qm "main seed"
git_q -C "$seed" checkout -q -b unstable-dev
echo "unstable only" >"$seed/UNSTABLE_MARKER"
git_q -C "$seed" add -A
git_q -C "$seed" commit -qm "unstable work"
git_q -C "$seed" checkout -q main
git_q init -q --bare "$origin"
git_q -C "$seed" remote add origin "$origin"
git_q -C "$seed" push -q origin main unstable-dev

fail=0
check() {
  if [[ $1 == "$2" ]]; then echo "  ok: $3"; else
    echo "::error::FAIL: $3 (got '$1' want '$2')" >&2
    fail=1
  fi
}
absent() { if [[ ! -e $1 && ! -L $1 ]]; then echo "  ok: $2"; else echo "::error::FAIL: $2" >&2; fail=1; fi; }
present() { if [[ -e $1 || -L $1 ]]; then echo "  ok: $2"; else echo "::error::FAIL: $2" >&2; fail=1; fi; }

# case 1: the box's tracked checkout (~/ryoku-arch, what `ryoku track` clones
# and sys.ResolveRepo tracks) is stranded on unstable-dev while RYOKU_CHANNEL is
# leaked to unstable-dev, and retired data-root checkouts still sit beside it.
# recovery must drag ~/ryoku-arch back to main in place and consolidate the
# stray data-root trees so `ryoku update` can never re-strand the box.
home1="$work/home1"
arch1="$home1/ryoku-arch"
data1="$home1/.local/share/ryoku"
mkdir -p "$home1/.local/lib" "$data1"
git_q clone -q "$origin" "$arch1"
git_q -C "$arch1" checkout -q unstable-dev
# the old updater stash-pops before switching = tree can land dirty or
# conflicted. dirty it on purpose so the test proves the rescue forces past.
echo "stray local edit" >>"$arch1/system/packages/base.packages"
echo "stray" >"$arch1/stray-untracked"
ln -s "$arch1/lib/runtime-env.sh" "$home1/.local/lib/runtime-env.sh" # dangling bridge
# retired data-root checkouts the pre-rewrite ISO left behind; recovery drops
# them so only ~/ryoku-arch remains for update and recovery to track.
git_q clone -q "$origin" "$data1/repo"
mkdir -p "$data1/dev-switch"
# an unrelated checkout the box keeps under its data root. consolidation is
# scoped to the two retired paths above; recovery must never wipe the data root
# wholesale (it can hold saved looks and user data), so this survives untouched.
git_q clone -q "$origin" "$data1/keep"
git_q -C "$data1/keep" checkout -q unstable-dev

HOME="$home1" XDG_DATA_HOME="$home1/.local/share" \
  XDG_STATE_HOME="$home1/.local/state" XDG_CONFIG_HOME="$home1/.config" \
  RYOKU_RECOVERY_URL="$origin" RYOKU_CHANNEL="unstable-dev" \
  RYOKU_RECOVERY_FORCE=1 RYOKU_TEST_MARKER="$work/marker1" \
  "$RECOVERY" --yes --no-packages >/dev/null

check "$(git_q -C "$arch1" rev-parse --abbrev-ref HEAD)" "main" \
  "tracked checkout repaired in place onto main despite RYOKU_CHANNEL=unstable-dev"
check "$(sed -n 's/^deployed-from //p' "$work/marker1" 2>/dev/null)" "$(cd "$arch1" && pwd -P)" \
  "deploy ran from the repaired in-place checkout"
absent "$arch1/UNSTABLE_MARKER" "unstable-dev content cleaned from the checkout"
absent "$home1/.local/lib/runtime-env.sh" "dangling pre-rewrite runtime-env bridge removed"
check "$(git_q -C "$arch1" status --porcelain)" "" \
  "rescue forces a dirty stranded checkout clean"
absent "$data1/repo" "retired data-root checkout consolidated away"
absent "$data1/dev-switch" "retired dev-switch checkout consolidated away"
present "$data1/keep/.git" "unrelated data-root checkout preserved (consolidation is scoped, not a data-root wipe)"
check "$(git_q -C "$data1/keep" rev-parse --abbrev-ref HEAD)" "unstable-dev" \
  "preserved checkout left untouched (recovery resets only the tracked ~/ryoku-arch)"

# case 2: clean machine, no prior checkout. clones ~/ryoku-arch on main.
home2="$work/home2"
arch2="$home2/ryoku-arch"
HOME="$home2" XDG_DATA_HOME="$home2/.local/share" \
  XDG_STATE_HOME="$home2/.local/state" XDG_CONFIG_HOME="$home2/.config" \
  RYOKU_RECOVERY_URL="$origin" RYOKU_CHANNEL="unstable-dev" \
  RYOKU_RECOVERY_FORCE=1 RYOKU_TEST_MARKER="$work/marker2" \
  "$RECOVERY" --yes --no-packages >/dev/null

check "$(git_q -C "$arch2" rev-parse --abbrev-ref HEAD)" "main" \
  "clean machine clones ~/ryoku-arch on main"

if ((fail)); then echo "ryoku-recovery: FAILED" >&2; exit 1; fi
echo "ryoku-recovery: all checks passed"
