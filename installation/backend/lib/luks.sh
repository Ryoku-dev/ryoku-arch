#!/usr/bin/env bash
# shellcheck shell=bash
# optional LUKS2 on the root partition. RYOKU_ENCRYPT=1 = format root as a
# LUKS2 container and open it as /dev/mapper/root, so the filesystem lives
# on the mapper. always sets ROOT_DEV; sets LUKS_PART when encrypting
# (consumed by crypttab + the kernel cmdline).

ryoku_luks() {
  if [[ ${RYOKU_ENCRYPT:-} != 1 ]]; then
    ROOT_DEV=$ROOT_PART
    log 'encryption: off (root on %s)' "$ROOT_DEV"
    return 0
  fi
  [[ -n ${RYOKU_LUKS_PASSPHRASE:-} ]] || die "RYOKU_ENCRYPT=1 but RYOKU_LUKS_PASSPHRASE is unset"

  # hard safety: LUKS only ever formats ROOT_PART. if ROOT_PART is unset, is
  # the whole disk, or matches the reused ESP, the partition step set
  # something dangerous, so refuse. better to abort than to luksFormat a
  # Windows partition or the ESP.
  [[ -n ${ROOT_PART:-} ]] || die "LUKS: ROOT_PART is unset; refusing to format."
  [[ $ROOT_PART != "${RYOKU_DISK:-}" ]] || die 'LUKS: refusing to format whole disk (%s); ROOT_PART must be a partition.' "$ROOT_PART"
  [[ $ROOT_PART != "${ESP_DEV:-}" ]] || die 'LUKS: refusing to format ESP (%s); ROOT_PART must be the new root partition.' "$ROOT_PART"

  LUKS_PART=$ROOT_PART
  log 'encryption: LUKS2 on %s -> /dev/mapper/root' "$LUKS_PART"

  # free a /dev/mapper/root a prior run left open, else the open below aborts
  # with "Device root already exists".
  ryoku_free_mapper root

  # passphrase stays on stdin, never on the command line, never in a log. pin
  # --pbkdf argon2id: it is the LUKS2 default but explicit here so a distro
  # cryptsetup built with a different default can't silently weaken the KDF.
  printf '%s' "$RYOKU_LUKS_PASSPHRASE" | run_secret \
    "cryptsetup luksFormat --type luks2 --pbkdf argon2id --batch-mode $LUKS_PART (passphrase via stdin)" \
    cryptsetup luksFormat --type luks2 --pbkdf argon2id --batch-mode "$LUKS_PART"
  printf '%s' "$RYOKU_LUKS_PASSPHRASE" | run_secret \
    "cryptsetup open $LUKS_PART root (passphrase via stdin)" \
    cryptsetup open "$LUKS_PART" root

  ROOT_DEV=/dev/mapper/root
}
