package doctor

import (
	"os/exec"
	"strings"

	i18n "ryoku-i18n"
)

// ---- reconciler: stale GPU render pin ---------------------------------------
//
// ryoku-gpu once pinned the strongest GPU as Hyprland's primary renderer on
// every multi-GPU machine; today's policy leaves laptops unpinned, because the
// pin drags the whole desktop onto the discrete GPU, which then can never
// runtime-suspend: ~10 W of parasitic draw, a hot idle floor, and a GPU that
// reports busy while showing a static wallpaper. A machine installed before
// the policy change (or switched between modes) keeps the stale hl.env line in
// ~/.config/hypr/gpu.lua forever, since nothing else owns that file.
//
// The verdict lives in `ryoku-gpu check-pin`, right beside the policy it
// audits, so this reconciler never re-implements laptop or GPU detection:
//   ok               no pin, or one today's policy would also write
//   forced           the pin carries the RYOKU_GPU_FORCE marker; user intent
//   stale-pin SLOT   policy says unpinned; `ryoku-gpu disable` clears it
//
// The repair rewrites only the managed gpu.lua (through the owning tool) and
// takes effect at the next Hyprland login; doctor never restarts the session.

var (
	gpuPinVerdict = func() (string, error) {
		out, err := exec.Command("ryoku-gpu", "check-pin").Output()
		return strings.TrimSpace(string(out)), err
	}
	gpuPinDisable = func() error {
		return exec.Command("ryoku-gpu", "disable").Run()
	}
)

// planGpuPin turns the tool's verdict into a result. pure over its inputs, so
// every branch is unit-testable without a real config or GPU.
func planGpuPin(verdict string, verdictErr error, checkOnly bool, disable func() error) recResult {
	if verdictErr != nil {
		// No ryoku-gpu on PATH (partial install) or the probe failed: there is
		// nothing this check can safely audit, and inventing a fault helps no
		// one. The GPU tooling has its own delivery checks.
		return okRes(i18n.T("ryoku-gpu is not available to audit the render pin (%v)"), verdictErr)
	}
	switch {
	case verdict == "ok":
		return okRes(i18n.T("the Hyprland GPU render pin matches ryoku-gpu policy"))
	case verdict == "forced":
		return okRes(i18n.T("the GPU render pin is a deliberate RYOKU_GPU_FORCE override; kept"))
	case strings.HasPrefix(verdict, "stale-pin"):
		slot := strings.TrimSpace(strings.TrimPrefix(verdict, "stale-pin"))
		if checkOnly {
			return wouldRes(i18n.T("gpu.lua still pins %s as the primary renderer, but ryoku-gpu policy leaves this machine unpinned: the pin keeps the discrete GPU awake at idle. `ryoku-gpu disable` clears it (takes effect on the next Hyprland login; re-force with RYOKU_GPU_FORCE=1 ryoku-gpu persist)"), slot)
		}
		if err := disable(); err != nil {
			return failRes(i18n.T("could not clear the stale GPU render pin: %v (clear it by hand with `ryoku-gpu disable`)"), err)
		}
		return fixedRes(i18n.T("cleared the stale GPU render pin on %s; the discrete GPU can runtime-suspend after the next Hyprland login (re-force with RYOKU_GPU_FORCE=1 ryoku-gpu persist)"), slot)
	default:
		return warnRes(i18n.T("ryoku-gpu check-pin answered %q, which this ryoku version does not understand; update ryoku or run `ryoku-gpu status`"), verdict)
	}
}

func reconcileGpuPin(checkOnly bool) recResult {
	verdict, err := gpuPinVerdict()
	return planGpuPin(verdict, err, checkOnly, gpuPinDisable)
}
