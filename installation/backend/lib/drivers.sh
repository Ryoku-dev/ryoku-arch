#!/usr/bin/env bash
# shellcheck shell=bash
# install the generation-correct GPU drivers in the target. the per-vendor
# scripts in system/hardware/drivers self-gate on the detected GPU (so
# running all of them is safe), are idempotent, and call pacman directly as
# root inside the chroot. configure stage, after the base system, before
# the initramfs so kernel modules (e.g. nvidia-dkms) are there for mkinitcpio.

ryoku_drivers() {
	log "installing GPU drivers for the detected hardware"
	local dir="$RYOKU_REPO/system/hardware/drivers" vendor name
	# offline: hand the scripts the [offline]-only pacman config, the only one that
	# resolves in a target whose other repos have no synced db. Empty online.
	local pmconf=""
	if declare -f ryoku_offline_active >/dev/null && ryoku_offline_active; then
		pmconf=$RYOKU_OFFLINE_CHROOT_CONF
	fi
	for vendor in amd intel nvidia vulkan; do
		[[ -f "$dir/$vendor.sh" ]] || {
			log 'skip: %s.sh not present' "$vendor"
			continue
		}
		name="ryoku-driver-$vendor.sh"
		run cp "$dir/$vendor.sh" "/mnt/root/$name"
		if ! run timeout 900 arch-chroot /mnt env RYOKU_DRYRUN="${RYOKU_DRYRUN:-}" RYOKU_PACMAN_CONF="$pmconf" bash "/root/$name"; then
			log 'drivers: WARNING, the %s driver install timed out (>15m) or failed and was skipped; the desktop will run on the integrated GPU. Run '\''ryoku doctor'\'' after first boot to install the %s driver. Continuing so the install finishes.' "$vendor" "$vendor"
		fi
		run rm -f "/mnt/root/$name"
	done

	# ASUS AMD+NVIDIA panels register only nvidia_wmi_ec_backlight and hide
	# amdgpu_bl0; ryoku-hw-backlight-fix adds acpi_backlight=native (gated on that
	# exact case) so brightness works after reboot. self-gating -> safe everywhere.
	local bl="$RYOKU_REPO/system/hardware/display/ryoku-hw-backlight-fix"
	if [[ -f $bl ]]; then
		run cp "$bl" /mnt/root/ryoku-hw-backlight-fix
		if ! run timeout 300 arch-chroot /mnt env RYOKU_DRYRUN="${RYOKU_DRYRUN:-}" bash /root/ryoku-hw-backlight-fix; then
			log "drivers: ryoku-hw-backlight-fix failed; continuing (set the backlight kernel param after first boot)"
		fi
		run rm -f /mnt/root/ryoku-hw-backlight-fix
	fi

	# apply the TUI's GPU-mode pick now the desktop + drivers are in place.
	ryoku_gpu_mode
}

# ryoku_gpu_mode: apply the TUI's GPU-mode pick (RYOKU_GPU_MODE) end-to-end --
# the TUI collects it on hybrid (iGPU + dGPU) machines but nothing consumed it.
# map the UI names to ryoku-gpu's host graphics modes:
#   offload -> hybrid       (no pin; Hyprland's iGPU-first default, for battery)
#   sync    -> performance  (pin the dGPU as the primary renderer)
#   vfio    -> passthrough  (pin the iGPU alone, freeing the dGPU for a VM)
# run `ryoku-gpu mode <mapped>` as the user against their Hyprland pin file, via
# runuser like deploy.sh's materialize. ryoku-gpu's analyze reads /sys/class/drm,
# which arch-chroot bind-mounts, so detection sees the real target GPUs; the tool
# self-gates (a single GPU no-ops, a missing iGPU refuses passthrough), so a
# non-hybrid box is harmless. best-effort: a failure only skips the pin.
#
# config path = gpu.lua (GPU_CONF_DEFAULT), NOT user.lua. Hyprland autostart runs
# `ryoku-gpu persist` every login, which rewrites gpu.lua ONLY when a discrete
# pin is "beneficial" (see ryoku-gpu-detect beneficial(): an eGPU, or a DESKTOP
# whose strongest GPU is discrete). on the hybrid LAPTOP this feature targets,
# persist is NOT beneficial, so it leaves gpu.lua alone and our pick survives.
# gpu.lua is also the single file the Hub GPU page, `ryoku doctor`, and `ryoku
# materialize` all manage; user.lua would survive persist on every box but the
# Hub can neither see nor rewrite it, stranding the mode as an override no tool
# owns (a worse trap than the desktop/eGPU re-pin, which the Hub still governs).
ryoku_gpu_mode() {
	[[ -n ${RYOKU_GPU_MODE:-} ]] || return 0
	local mapped
	case $RYOKU_GPU_MODE in
		offload) mapped=hybrid ;;
		sync)    mapped=performance ;;
		vfio)    mapped=passthrough ;;
		*) log 'GPU mode: ignoring unknown RYOKU_GPU_MODE='\''%s'\'' (want offload|sync|vfio)' "$RYOKU_GPU_MODE"; return 0 ;;
	esac
	local u=$RYOKU_USERNAME dest="/home/$RYOKU_USERNAME/.config/hypr/gpu.lua"
	if [[ -n ${RYOKU_DRYRUN:-} ]]; then
		log "DRYRUN: arch-chroot /mnt runuser -u $u -- env HOME=/home/$u ryoku-gpu mode $mapped $dest"
		return 0
	fi
	if [[ ! -x /mnt/usr/bin/ryoku-gpu ]]; then
		log "GPU mode: skipped (ryoku-gpu not installed; offline or partial desktop set)"
		return 0
	fi
	log 'GPU mode: applying '\''%s'\'' -> ryoku-gpu mode %s for %s' "$RYOKU_GPU_MODE" "$mapped" "$u"
	arch-chroot /mnt runuser -u "$u" -- env "HOME=/home/$u" "USER=$u" "LOGNAME=$u" \
		ryoku-gpu mode "$mapped" "$dest" \
		|| log 'GPU mode: warning, '\''ryoku-gpu mode %s'\'' failed (continuing; set it later from Ryoku Settings > GPU)' "$mapped"
}
