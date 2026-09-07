#!/usr/bin/env bash
# Translation for the installer's shell output: the same catalog the desktop and
# the TUI read (ryoku/i18n/catalog/<lang>.json), looked up by English source
# string, so a developer only ever writes English here too.
#
#   t  "Formatting the root filesystem"        -> the translation, or the English
#   tf "formatting %s as btrfs" "$ROOT_DEV"    -> translate, then printf
#
# log() and die() in common.sh take a format plus arguments and run everything
# through tf, so a call site reads `log 'locale: %s' "$RYOKU_LOCALE"` and the
# sentence stays one translatable unit instead of being spliced at runtime.
#
# The whole catalog is loaded once, with one jq pass, into an associative array:
# a per-line jq would cost hundreds of processes over an install. jq is on the
# live ISO (installation/iso/packages.x86_64) and in the base set, and a missing
# catalog simply leaves every string English.

declare -gA RYOKU_I18N=()
# exported: a step that runs a command through arch-chroot passes the language
# on, so anything the target prints back speaks it too.
declare -gx RYOKU_I18N_LANG=en

# _i18n_dir: where the catalog is. RYOKU_I18N_DIR wins (tests, a dev checkout),
# then the ISO/installed location, then this checkout's own catalog.
_i18n_dir() {
  local here
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  for d in "${RYOKU_I18N_DIR:-}" /usr/share/ryoku/i18n "$here/../../../ryoku/i18n/catalog"; do
    [[ -n $d && -d $d ]] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

# _i18n_code: the language to speak. RYOKU_LANG is what the TUI resolved and
# exported; otherwise the live environment's locale, trimmed to its language
# tag. A tag with no catalog of its own falls back to its base language.
_i18n_code() {
  local dir=$1 want=${RYOKU_LANG:-} v
  if [[ -z $want ]]; then
    v=${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}
    want=${v%%.*}
    want=${want%%@*}
  fi
  want=${want//-/_}
  [[ -z $want || $want == C || $want == POSIX || $want == auto ]] && return 1
  [[ -f $dir/$want.json ]] && { printf '%s\n' "$want"; return 0; }
  want=${want%%_*}
  [[ -f $dir/$want.json ]] && { printf '%s\n' "$want"; return 0; }
  return 1
}

# i18n_init: load the catalog for the resolved language. Idempotent, and a
# no-op for English (whose keys are the strings).
i18n_init() {
  local dir code rec
  dir=$(_i18n_dir) || return 0
  code=$(_i18n_code "$dir") || return 0
  [[ $code == en ]] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  # NUL between records and \x01 between key and value, so a string containing
  # a newline (several do) still loads as one entry.
  while IFS= read -r -d '' rec; do
    RYOKU_I18N[${rec%%$'\x01'*}]=${rec#*$'\x01'}
  done < <(jq -j 'to_entries[] | .key + "\u0001" + .value + "\u0000"' "$dir/$code.json" 2>/dev/null)
  RYOKU_I18N_LANG=$code
  ((${#RYOKU_I18N[@]})) || RYOKU_I18N_LANG=en
}

# t: one English source string in, its translation (or itself) out.
t() {
  local s=$1
  printf '%s' "${RYOKU_I18N[$s]-$s}"
}

# tf: translate a format string, then fill it. The placeholders travel with the
# translation (sync.py drops any translation that mangles them), so a target
# language is free to reorder them: many cannot keep English word order.
#
# Reordering needs a positional specifier (%2$s), which bash's builtin printf
# rejects outright ("invalid format character") rather than ignoring, so a
# reordered translation would print nothing but an error. coreutils printf does
# support them, so a format that reorders is handed to that binary and
# everything else stays on the builtin, which is the common case and costs no
# process.
tf() {
  local f
  f=$(t "$1")
  shift
  # shellcheck disable=SC2059  # the format IS the argument: that is the point
  if [[ $f == *%[1-9]'$'* ]] && [[ -x /usr/bin/printf ]]; then
    /usr/bin/printf -- "$f" "$@"
  else
    printf -- "$f" "$@"
  fi
}
