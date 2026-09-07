# system/boot/

The boot chain: what runs from power-on to the login screen, and how Ryoku
puts its name and colors on it.

## The chain

1. **Limine** is the bootloader. It draws the Ryoku-branded menu, then loads
   the kernel as a single signed image (a UKI, see below).
2. **The kernel** starts and unpacks the **initramfs**, a tiny early system
   that finds the disk, unlocks it if encrypted, and mounts the real root.
3. **Plymouth** shows the Ryoku splash over that whole early stage, so the
   user sees the logo and a progress bar instead of scrolling boot text.
4. Control passes to systemd, then to SDDM for login.

## What's here

- `limine/limine.conf` The bootloader's look: the "Ryoku Bootloader" branding,
  the orange accent, and the Greek Noir terminal palette. Deployed to
  `/boot/limine.conf` (the ESP root), the ONE config `limine-entry-tool`
  manages: the boot entries (kernels, snapshots) are regenerated into that
  same file around these globals. A limine.conf anywhere else on the ESP
  (`/boot/limine/`, `EFI/limine/`, ...) shadows it -- Limine stops at its
  first match -- so the installer removes those candidates.
- `limine/default.conf` Settings for the tool that builds the boot entries
  (deployed to `/etc/default/limine`). It names the OS "Ryoku", builds a UKI
  called `ryoku`, sets the kernel command line, and wires up snapshot entries.
- `plymouth/ryoku/` The splash theme: the manifest, the animation script, and
  the image assets (logo, progress bar, password prompt). Vendored as-is.
- `mkinitcpio/ryoku.conf` The list of initramfs hooks, including `plymouth`
  for the splash, `kms` for an early, flicker-free GPU handoff, and `resume`
  (right after `encrypt`) so a hibernated system is restored from its swapfile.
- `mkinitcpio/install/ryoku-gpu-trim` A mkinitcpio install hook, named by that
  HOOKS list between `autodetect` and `kms`. `nvidia.sh` denylists nouveau, but
  autodetect still matches it against the card, so `kms` would pull nouveau in
  along with the GSP firmware linux-firmware ships for every Turing/Ampere/Ada
  chip: about 107 MiB per kernel image, on a boot partition that holds one image
  plus one history copy per kernel. The hook drops nouveau from autodetect's
  allowlist, so both stay out.

## UKI, in one line

A Unified Kernel Image bundles the kernel, the initramfs, and the command line
into one EFI file (`EFI/Linux/ryoku_linux.efi`). One file to load, easy to sign.

## How the installer uses this

During install the backend copies these files into place: `limine/limine.conf`
to `/boot/limine.conf`, `limine/default.conf` to `/etc/default/limine`,
`plymouth/ryoku/` to `/usr/share/plymouth/themes/ryoku`, and the hooks into
`/etc/mkinitcpio.conf`. The Limine binary lands on
`EFI/limine/limine_x64.efi` (+ the `EFI/BOOT/BOOTX64.EFI` fallback), the same
paths `limine-install` refreshes on every `limine` package upgrade, so the
booted bootloader never goes stale. The `encrypt` hook and the `cryptdevice=`
command line are kept only when the user chose disk encryption.

### Hibernation (swapfile)

When a swapfile is created (`RYOKU_SWAP_GIB > 0`), the backend appends
`resume=<dev> resume_offset=<n>` to the kernel command line so the `resume`
hook can find and restore the hibernation image. `<dev>` mirrors `root=`
(`/dev/mapper/root` under LUKS, else the root filesystem `UUID=`), and `<n>`
is the swapfile's physical offset within the Btrfs, read with
`btrfs inspect-internal map-swapfile -r`. That subcommand needs
btrfs-progs >= 5.16 (the release that also added the `mkswapfile` the
installer builds with); on an older toolchain the offset lookup is skipped and
`resume=` is omitted -- the system still boots, only hibernate-resume is off.

### Intel VMD carry-over

If the live installer kernel had to load the `vmd` module to see the NVMe
(Intel RST "VMD" mode, common on Intel laptops), the installed initramfs needs
it too, or the target cannot find its own root disk at boot. The backend
detects this on the live system (`/sys/module/vmd`) and, before building the
initramfs, writes `/etc/mkinitcpio.conf.d/ryoku-vmd.conf` with `MODULES+=(vmd)`
(appended, so it stacks with the NVIDIA early-KMS drop-in).

### Firmware NVRAM is best-effort

Registering the "Ryoku" boot entry with `efibootmgr` is best-effort: some
firmware (HP / Insyde-class) exposes NVRAM as readonly or reports it full, and
a failure there must not abort a finished install. The install continues with a
loud warning -- the UEFI removable-path fallback `EFI/BOOT/BOOTX64.EFI` on our
ESP keeps the machine bootable. Writing that fallback is always safe now:
both partitioning strategies install onto Ryoku's *own* ESP (the alongside path
creates a dedicated ESP, never touching the Windows one), so it can never
clobber a foreign fallback loader. Before writing anything the backend also
asserts the ESP has >= 64 MiB free -- a last-line guard that should never fire
with the dedicated >= 1 GiB ESP, but fails clearly instead of half-writing.
