#!/usr/bin/env bash
# resize.sh: carve free space out of an existing partition so Ryoku can install
# alongside on a disk with no unallocated room (a full Windows drive, or another
# Ryoku). It runs before partitioning when RYOKU_RESIZE_PART is set. The doctrine
# is fixed: shrink the filesystem FIRST, the partition table SECOND, touch ONLY
# the one selected partition, preserve its identity, and fail closed at the first
# doubt. This makes a user's Windows disk smaller, so a wrong move is unrecoverable.
#
# Contract (the TUI sets these; full list in installation/backend/README.md):
#   RYOKU_RESIZE_PART=/dev/...   the partition to shrink
#   RYOKU_RESIZE_TAKE_MIB=<n>    MiB to free for the new Ryoku region
# On success it exports RYOKU_REGION_START/END (the carved gap, in sectors) so the
# existing alongside flow places boot+root there exactly as on a naturally-free disk.

# ryoku_carve: shrink RYOKU_RESIZE_PART by RYOKU_RESIZE_TAKE_MIB, verify, and hand
# the freed region to alongside. A no-op when RYOKU_RESIZE_PART is unset.
ryoku_carve() {
  [[ -n ${RYOKU_RESIZE_PART:-} ]] || return 0
  local part=$RYOKU_RESIZE_PART take=${RYOKU_RESIZE_TAKE_MIB:-0} disk=$RYOKU_DISK

  [[ ${RYOKU_DISK_STRATEGY:-} == alongside ]] \
    || die 'RYOKU_RESIZE_PART is set but strategy is '\''%s'\''; carve runs only under the alongside strategy.' "${RYOKU_DISK_STRATEGY:-}"
  { [[ $take =~ ^[0-9]+$ ]] && (( take > 0 )); } \
    || die 'RYOKU_RESIZE_TAKE_MIB must be a positive MiB count; got '\''%s'\''.' "${take}"

  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    log 'DRYRUN: would carve %s MiB out of %s: shrink its filesystem, then its partition table in place, verify PARTUUID + sgdisk clean, and hand the freed region to alongside' "${take}" "$part"
    return 0
  fi

  [[ -b $part ]] || die 'carve target %s is not a block device.' "$part"
  local parent; parent=$(lsblk -no PKNAME "$part" 2>/dev/null | head -n1)
  [[ /dev/$parent == "$disk" ]] || die 'carve target %s is not a partition of %s (parent is %s); refusing.' "$part" "$disk" "${parent:-unknown}"
  ! findmnt -rno TARGET -S "$part" >/dev/null 2>&1 \
    || die 'carve target %s is mounted; unmount it first. Refusing to shrink a mounted filesystem.' "$part"

  local fstype size_mib
  fstype=$(blkid -o value -s TYPE "$part" 2>/dev/null || true)
  size_mib=$(( $(blockdev --getsize64 "$part") / 1048576 ))

  # C3.1: re-verify shrinkability NOW, with the same judge the probe used, so a
  # disk that changed since the probe (mounted, went dirty, BitLocker) is caught.
  local info min_mib shrink reason
  info=$(ryoku_part_shrink_info "$part" "$fstype" "$size_mib")
  read -r _ min_mib shrink reason <<<"$info"
  [[ $shrink == yes ]] || die 'carve refused: %s (%s) is not shrinkable now: %s.' "$part" "$fstype" "${reason}"

  # Geometry: move the partition end down by TAKE, aligned down to 1 MiB. The
  # filesystem then targets 1 MiB under the new partition so it always fits.
  local ss spm pstart psize pend take_s pnew_end new_size_s part_new_mib fs_new_mib gap_mib need_gib
  ss=$(blockdev --getss "$disk"); spm=$(( 1048576 / ss ))
  read -r pstart psize < <(sfdisk --json "$disk" | jq -r --arg n "$part" '.partitiontable.partitions[] | select(.node==$n) | "\(.start) \(.size)"')
  [[ $pstart =~ ^[0-9]+$ && $psize =~ ^[0-9]+$ ]] || die 'carve could not read %s geometry from sfdisk.' "$part"
  pend=$(( pstart + psize - 1 ))
  take_s=$(( take * spm ))
  pnew_end=$(( pend - take_s ))
  pnew_end=$(( (pnew_end + 1) / spm * spm - 1 ))
  new_size_s=$(( pnew_end - pstart + 1 ))
  (( pnew_end > pstart )) || die 'carve of %s MiB would leave %s with no room; take less.' "${take}" "$part"
  part_new_mib=$(( new_size_s / spm ))
  fs_new_mib=$(( part_new_mib - 1 ))
  gap_mib=$(( (pend - pnew_end) / spm ))
  need_gib=$(( 2 + $(ryoku_min_root_gib) ))

  # the TUI's max drag lands part_new at exactly min_mib; accept that and let the
  # filesystem take the 1 MiB slack (min_mib already folds in a used+margin buffer,
  # so the fs floor sits below it). only a genuinely-below-min take is refused.
  (( part_new_mib >= min_mib )) \
    || die 'carve of %s MiB is too large: %s needs at least %s MiB (used + margin), which would leave only %s MiB. Take less.' "${take}" "$part" "${min_mib}" "${part_new_mib}"
  (( gap_mib >= need_gib * 1024 )) \
    || die 'carve of %s MiB frees only %s MiB, below the %s GiB Ryoku needs (2 GiB boot + %s GiB root). Take more.' "${take}" "${gap_mib}" "${need_gib}" "$(ryoku_min_root_gib)"

  # Capture identity to prove sfdisk -N preserved it (fstab/boot on the other OS
  # keys off PARTUUID; a change there silently breaks the neighbour).
  local pnum partuuid_before typeguid_before
  pnum=$(part_num "$part")
  partuuid_before=$(sgdisk -i "$pnum" "$disk" | sed -n 's/^Partition unique GUID: //p')
  typeguid_before=$(sgdisk -i "$pnum" "$disk" | sed -n 's/^Partition GUID code: \([0-9A-Fa-f-]*\).*/\1/p')
  [[ -n $partuuid_before && -n $typeguid_before ]] \
    || die 'carve could not read %s identity (PARTUUID/typeGUID) before the shrink; refusing (cannot prove it is preserved).' "$part"

  log 'carve: %s (%s) %s MiB -> %s MiB (filesystem to %s MiB), freeing ~%s MiB for Ryoku' "$part" "$fstype" "${size_mib}" "${part_new_mib}" "${fs_new_mib}" "${gap_mib}"

  # STEP 1 -- filesystem shrink FIRST (swap has no data; it is recreated after the
  # table move so its smaller size and preserved UUID land together).
  local swap_uuid=""
  case $fstype in
    ntfs)           ryoku_carve_shrink_ntfs "$part" "$fs_new_mib" ;;
    ext4|ext3|ext2) ryoku_carve_shrink_ext "$part" "$fs_new_mib" ;;
    btrfs)          ryoku_carve_shrink_btrfs "$part" "$fs_new_mib" ;;
    swap)           swap_uuid=$(blkid -o value -s UUID "$part" 2>/dev/null || true)
                    run_sh "swapoff '$part' 2>/dev/null || true" ;;
    *)              die 'carve does not support filesystem '\''%s'\'' on %s.' "${fstype:-none}" "$part" ;;
  esac

  # STEP 2 -- table shrink, in place. sfdisk -N keeps PARTUUID/typeGUID/attrs/name;
  # --force skips the interactive confirm (which would otherwise hang the install).
  run_sh "printf '%s,%s\n' '$pstart' '$new_size_s' | sfdisk -N $pnum --force '$disk'"
  run partprobe "$disk"
  run_sh 'udevadm settle || true'

  if [[ $fstype == swap ]]; then
    if [[ -n $swap_uuid ]]; then run mkswap -U "$swap_uuid" "$part"; else run mkswap "$part"; fi
  fi

  # STEP 3 -- verify: GPT clean, identity unchanged, filesystem still consistent.
  sgdisk -v "$disk" 2>&1 | grep -q 'No problems found' \
    || die 'carve left the GPT in a bad state on %s (sgdisk -v not clean); refusing to continue.' "$disk"
  local partuuid_after typeguid_after
  partuuid_after=$(sgdisk -i "$pnum" "$disk" | sed -n 's/^Partition unique GUID: //p')
  typeguid_after=$(sgdisk -i "$pnum" "$disk" | sed -n 's/^Partition GUID code: \([0-9A-Fa-f-]*\).*/\1/p')
  [[ $partuuid_after == "$partuuid_before" ]] \
    || die 'carve changed %s PARTUUID (%s -> %s); refusing (would break the other OS).' "$part" "$partuuid_before" "${partuuid_after:-gone}"
  [[ $typeguid_after == "$typeguid_before" ]] \
    || die 'carve changed %s type GUID (%s -> %s); refusing.' "$part" "$typeguid_before" "${typeguid_after:-gone}"
  ryoku_carve_verify_fs "$part" "$fstype"

  # STEP 4 -- re-probe and REQUIRE the carved gap at the expected start, then hand
  # its exact sectors to the alongside flow through the region contract.
  local carved_start=$(( pnew_end + 1 )) rs re found=""
  while read -r rs re _; do
    (( rs == carved_start )) && { found="$rs $re"; break; }
  done < <(ryoku_free_regions "$disk")
  [[ -n $found ]] \
    || die 'carve finished but no free region appeared at sector %s on %s (expected the ~%s MiB gap); refusing to hand off to alongside.' "${carved_start}" "$disk" "${gap_mib}"
  read -r RYOKU_REGION_START RYOKU_REGION_END <<<"$found"
  export RYOKU_REGION_START RYOKU_REGION_END
  log 'carve done: freed region sectors %s-%s; alongside installs Ryoku there' "${RYOKU_REGION_START}" "${RYOKU_REGION_END}"
}

# ryoku_carve_shrink_ntfs <dev> <targetMiB>: dry-run then real ntfsresize. --size
# takes bytes; a bare number is exact bytes. The dry-run MUST pass first. The real
# run schedules the NTFS consistency check, so Windows runs chkdsk once on next
# boot; that is expected and harmless.
ryoku_carve_shrink_ntfs() {
  local dev=$1 mib=$2 bytes=$(( $2 * 1048576 ))
  run ntfsresize --no-action --size "$bytes" "$dev"
  run_sh "ntfsresize --force --force --size $bytes '$dev'"
  log 'NTFS shrunk to %s MiB. Windows will run a disk check (chkdsk) once on its next boot -- this is normal after a resize.' "${mib}"
}

# ryoku_carve_shrink_ext <dev> <targetMiB>: e2fsck -f (mandatory before an offline
# shrink; rc 1 means it fixed something and is fine), then resize2fs to MiB.
ryoku_carve_shrink_ext() {
  local dev=$1 mib=$2 rc=0
  run_sh "e2fsck -fy '$dev'" || rc=$?
  (( rc <= 1 )) || die 'e2fsck found errors it could not fix on %s (rc=%s); refusing to shrink.' "$dev" "$rc"
  run resize2fs "$dev" "${mib}M"
}

# ryoku_carve_shrink_btrfs <dev> <targetMiB>: btrfs shrinks online only, so mount
# read-write briefly, resize (bytes, exact), and unmount. If the target sits below
# allocated chunks btrfs refuses; we surface the balance guidance and do NOT balance
# automatically (a balance rewrites data and is the user's call).
ryoku_carve_shrink_btrfs() {
  local dev=$1 mib=$2 mp rc=0
  mp=$(mktemp -d)
  run mount "$dev" "$mp"
  run_sh "btrfs filesystem resize $(( mib * 1048576 )) '$mp'" || rc=$?
  run_sh "umount '$mp' 2>/dev/null || true"
  rmdir "$mp" 2>/dev/null || true
  (( rc == 0 )) \
    || die 'btrfs could not shrink %s to %s MiB: allocated chunks likely sit past the target. In a live session run '\''btrfs balance start -dusage=50 <mountpoint>'\'', then retry the carve. Ryoku will not balance automatically.' "$dev" "${mib}"
}

# ryoku_carve_verify_fs <dev> <fstype>: post-shrink consistency read per filesystem.
# The shrink already succeeded here, so NTFS (which now carries the scheduled-check
# flag) is logged, not treated as a fault.
ryoku_carve_verify_fs() {
  local dev=$1 fstype=$2 rc=0
  case $fstype in
    ntfs)
      if ntfsresize --info -f "$dev" 2>&1 | grep -q 'You might resize at'; then
        log 'carve verify: NTFS on %s reads consistent' "$dev"
      else
        log 'carve verify: NTFS on %s is scheduled for its next-boot check (normal after a resize)' "$dev"
      fi
      ;;
    ext4|ext3|ext2)
      e2fsck -n "$dev" >/dev/null 2>&1 || rc=$?
      (( rc <= 1 )) || die 'carve verify: e2fsck -n found errors on %s after the shrink (rc=%s).' "$dev" "$rc"
      ;;
    btrfs)
      btrfs filesystem show "$dev" >/dev/null 2>&1 || die 'carve verify: btrfs show failed on %s after the shrink.' "$dev"
      ;;
    swap)
      [[ $(blkid -o value -s TYPE "$dev" 2>/dev/null) == swap ]] || die 'carve verify: %s is not swap after the recreate.' "$dev"
      ;;
  esac
}
