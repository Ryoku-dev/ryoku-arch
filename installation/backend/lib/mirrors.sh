#!/usr/bin/env bash
# shellcheck shell=bash
# Prepare the package mirrors before pacstrap. A user far from every shipped
# origin otherwise stalls: pacstrap aborts with "failed retrieving file ...
# Operation too slow. Less than 1 bytes/sec" and the whole install dies at
# "failed to install packages to new root" (issue #21).
#
# Bounded four tiers, tried in order, no loops and no daemons:
#   1. reflector, https, synced in the last 24h, top 10 by measured rate;
#   2. on ANY tier-1 failure, the mirror-status API ranked by score;
#   3. the ISO's bundled mirrorlist (installation/iso/airootfs/etc/pacman.d/
#      mirrorlist), which is exactly what lives at $list on the live system;
#   4. three reachable-from-anywhere emergency mirrors, appended to EVERY tier.
#
# runs under the orchestrator's `set -euo pipefail`, so every fallible step is
# guarded: ranking is an optimization and must NEVER abort the install.
# RYOKU_MIRRORLIST / RYOKU_PACMAN_CONF override the paths (tests only).

ryoku_rank_mirrors() {
  local list=${RYOKU_MIRRORLIST:-/etc/pacman.d/mirrorlist}
  RYOKU_MIRROR_TIER=0
  RYOKU_MIRROR_TIERS_TRIED=""

  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    log 'mirrors: would set ParallelDownloads + DisableDownloadTimeout + ILoveCandy, then rank %s (tier 1 reflector, else tier 2 status API, else tier 3 the shipped list) and always append the emergency mirrors' "$list"
    return 0
  fi

  ryoku_pacman_tuning

  # snapshot the shipped list up front so a later tier-3 fallback can restore the
  # ISO's bundled mirrors even after a higher tier has overwritten them.
  RYOKU_MIRROR_SHIPPED=$(mktemp) && cp -- "$list" "$RYOKU_MIRROR_SHIPPED" 2>/dev/null || RYOKU_MIRROR_SHIPPED=""

  if [[ ${RYOKU_ONLINE:-1} != 1 ]]; then
    RYOKU_MIRROR_TIER=3
    RYOKU_MIRROR_TIERS_TRIED="tier 3 (shipped list)"
    log "mirrors: offline install, keeping the shipped mirrorlist (tier 3)"
    ryoku_mirror_emergency "$list"
    return 0
  fi

  local ranked
  if ! ranked=$(mktemp); then
    RYOKU_MIRROR_TIER=3
    RYOKU_MIRROR_TIERS_TRIED="tier 3 (shipped list)"
    log "mirrors: no scratch space, keeping the shipped mirrorlist (tier 3)"
    ryoku_mirror_emergency "$list"
    return 0
  fi

  if command -v reflector >/dev/null 2>&1 && ryoku_mirror_tier1_reflector "$ranked"; then
    ryoku_mirror_replace "$list" "$ranked"
    RYOKU_MIRROR_TIER=1
    RYOKU_MIRROR_TIERS_TRIED="tier 1 (reflector)"
    log "mirrors: ranked by reflector download rate (tier 1)"
  elif ryoku_mirror_tier2_status "$ranked"; then
    ryoku_mirror_replace "$list" "$ranked"
    RYOKU_MIRROR_TIER=2
    RYOKU_MIRROR_TIERS_TRIED="tier 2 (mirror-status API)"
    log "mirrors: ranked by the mirror-status API score (tier 2)"
  else
    RYOKU_MIRROR_TIER=3
    RYOKU_MIRROR_TIERS_TRIED="tier 3 (shipped list)"
    log "mirrors: reflector and the status API both failed, keeping the shipped mirrorlist (tier 3)"
  fi
  rm -f -- "$ranked"

  ryoku_mirror_emergency "$list"
}

# tier 1: reflector's own download-rate probe, bounded by `timeout 60` so a slow
# or hung probe can never stall the install.
ryoku_mirror_tier1_reflector() {
  local out=$1
  timeout 60 reflector --protocol https --age 24 --sort rate --latest 10 --save "$out" 2>/dev/null \
    && grep -q '^Server' "$out"
}

# tier 2: the mirror-status API. archinstall polls this with a few retries and
# ranks by score/completion; I copy that (curl --retry 3), keeping only https
# mirrors that are active and fully synced, then take the ten best scores.
ryoku_mirror_tier2_status() {
  local out=$1 json
  command -v jq >/dev/null 2>&1 || return 1
  json=$(curl -fsSL --retry 3 --max-time 30 https://archlinux.org/mirrors/status/json/ 2>/dev/null) || return 1
  printf '%s' "$json" | jq -er '
    [.urls[] | select(.protocol == "https" and .active and (.completion_pct // 0) == 1)]
    | sort_by(.score) | .[:10][] | "Server = " + .url + "$repo/os/$arch"
  ' >"$out" 2>/dev/null || return 1
  grep -q '^Server' "$out"
}

# tier 3: restore the shipped list snapshotted before ranking. used only on the
# pacstrap fallback, when a higher tier has already overwritten $list.
ryoku_mirror_tier3_restore() {
  local list=$1
  [[ -n ${RYOKU_MIRROR_SHIPPED:-} && -s ${RYOKU_MIRROR_SHIPPED:-} ]] \
    && cp -- "$RYOKU_MIRROR_SHIPPED" "$list" 2>/dev/null || true
  RYOKU_MIRROR_TIER=3
  RYOKU_MIRROR_TIERS_TRIED="${RYOKU_MIRROR_TIERS_TRIED:+$RYOKU_MIRROR_TIERS_TRIED, }tier 3 (shipped list)"
  log "mirrors: fell back to the shipped mirrorlist (tier 3) for the retry"
}

# replace the live list with a freshly ranked one; keep what was there if the
# copy fails (ranking must never leave the install with no mirrors at all).
ryoku_mirror_replace() {
  local list=$1 ranked=$2 n
  n=$(grep -c '^Server' "$ranked" 2>/dev/null) || n=0
  if cp -- "$ranked" "$list" 2>/dev/null; then
    log 'mirrors: using %s ranked mirror(s)' "$n"
  else
    log "mirrors: could not replace the mirrorlist, keeping what was there"
  fi
}

# tier 4, appended to every tier: three reachable-from-anywhere mirrors, kept
# last so pacman still has a CDN-backed origin to fall through to when the ranked
# list above is stale or the box sits somewhere reflector's data never covered.
# idempotent via the marker so a same-session retry does not stack duplicates.
ryoku_mirror_emergency() {
  local list=$1
  local marker='# ryoku emergency mirrors'
  grep -qF "$marker" "$list" 2>/dev/null && return 0
  # shellcheck disable=SC2016  # pacman expands $repo/$arch itself; literal on purpose
  if {
    printf '\n%s\n' "$marker"
    printf '# I keep these last: reachable from anywhere, so pacman never runs out of\n'
    printf '# origins even when the ranked list is stale or blank.\n'
    printf 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n'
    printf 'Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch\n'
    printf 'Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch\n'
  } >>"$list" 2>/dev/null; then
    log "mirrors: appended the emergency fallback mirrors"
  else
    log "mirrors: could not append the emergency mirrors"
  fi
}

# after a failed pacstrap: rebuild the mirrorlist from the NEXT tier down so the
# retry pulls from a different source than the one that just failed. non-zero
# when the shipped list (the lowest tier) is already in use.
ryoku_mirrors_fallback() {
  local list=${RYOKU_MIRRORLIST:-/etc/pacman.d/mirrorlist} ranked
  case ${RYOKU_MIRROR_TIER:-1} in
    1)
      if ranked=$(mktemp) && ryoku_mirror_tier2_status "$ranked"; then
        ryoku_mirror_replace "$list" "$ranked"
        RYOKU_MIRROR_TIER=2
        RYOKU_MIRROR_TIERS_TRIED="${RYOKU_MIRROR_TIERS_TRIED:+$RYOKU_MIRROR_TIERS_TRIED, }tier 2 (mirror-status API)"
        log "mirrors: fell back to the mirror-status API (tier 2) for the retry"
      else
        ryoku_mirror_tier3_restore "$list"
      fi
      rm -f -- "$ranked" 2>/dev/null || true
      ;;
    2)
      ryoku_mirror_tier3_restore "$list"
      ;;
    *)
      log "mirrors: already on the shipped list (tier 3); no lower tier to fall back to"
      return 1
      ;;
  esac
  ryoku_mirror_emergency "$list"
}

# ParallelDownloads + DisableDownloadTimeout for the install-time pacman.conf:
# five parallel streams recover far faster when one mirror crawls, and dropping
# the low-speed timeout stops a slow-but-alive mirror from aborting pacstrap.
# ILoveCandy rides along as Ryoku's progress bar (`ryoku doctor` seeds it on a
# box installed before this shipped). pacstrap copies this config into the
# target, so the first updates benefit too.
ryoku_pacman_tuning() {
  local conf=${RYOKU_PACMAN_CONF:-/etc/pacman.conf}
  [[ -f $conf ]] || { log 'mirrors: no %s to tune' "$conf"; return 0; }
  if grep -qE '^[[:space:]]*#?[[:space:]]*ParallelDownloads' "$conf" 2>/dev/null; then
    sed -i 's/^[[:space:]]*#\?[[:space:]]*ParallelDownloads.*/ParallelDownloads = 5/' "$conf"
  else
    sed -i '/^\[options\]/a ParallelDownloads = 5' "$conf"
  fi
  grep -qE '^[[:space:]]*DisableDownloadTimeout' "$conf" 2>/dev/null \
    || sed -i '/^\[options\]/a DisableDownloadTimeout' "$conf"
  grep -qE '^[[:space:]]*ILoveCandy' "$conf" 2>/dev/null \
    || sed -i '/^\[options\]/a ILoveCandy' "$conf"
  log "mirrors: set ParallelDownloads=5 + DisableDownloadTimeout + ILoveCandy for the install"
}
