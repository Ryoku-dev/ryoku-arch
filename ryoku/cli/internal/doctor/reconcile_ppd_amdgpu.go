package doctor

import (
	"os/exec"
	"strings"

	i18n "ryoku-i18n"
)

// ---- reconciler: power-profiles-daemon vs the AMD compositor GPU ------------
//
// power-profiles-daemon 0.30 ships two optional actions aimed at amdgpu. Both
// default off, and both are wrong for a Ryoku desktop whose compositor renders
// on the AMD iGPU (the default once no render pin exists):
//
//   amdgpu_dpm          forces the GPU's dynamic power management level down in
//                       the power-saver profile: the profile meant to save the
//                       battery clamps the very GPU drawing every frame, and the
//                       whole desktop turns to syrup the moment saver engages.
//   amdgpu_panel_power  drives the panel's adaptive backlight (ABM), which
//                       visibly washes out colours on the shipped themes.
//
// Field reports pin exactly this: "saver mode lags the desktop" with a healthy
// system, and the culprit is the enabled dpm action. Toggling ppd actions is
// the user's policy (a distro config or a deliberate choice), so this check
// REPORTS only and never rewrites power-profiles-daemon configuration.

// ppdAmdgpuState is what the verdict needs: whether an amdgpu card drives a
// connected connector, and ppd's action list output ("" when ppd is absent).
type ppdAmdgpuState struct {
	amdgpuDrivesPanel bool
	actionsOut        string
}

var gatherPpdAmdgpu = func() ppdAmdgpuState {
	var s ppdAmdgpuState
	cards := drmCards()
	for _, connected := range connectedConnectorCards() {
		if cards[connected].driver == "amdgpu" {
			s.amdgpuDrivesPanel = true
			break
		}
	}
	if out, err := exec.Command("powerprofilesctl", "list-actions").Output(); err == nil {
		s.actionsOut = string(out)
	}
	return s
}

// ppdActionEnabled parses `powerprofilesctl list-actions` blocks (Name: /
// Enabled: pairs) for one action's state. pure, so the parse is testable
// without ppd installed.
func ppdActionEnabled(out, action string) bool {
	current := ""
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if v, ok := strings.CutPrefix(line, "Name:"); ok {
			current = strings.TrimSpace(v)
			continue
		}
		if v, ok := strings.CutPrefix(line, "Enabled:"); ok {
			if current == action && strings.EqualFold(strings.TrimSpace(v), "true") {
				return true
			}
		}
	}
	return false
}

// planPpdAmdgpu turns observed state into a result. pure.
func planPpdAmdgpu(s ppdAmdgpuState) recResult {
	if !s.amdgpuDrivesPanel || s.actionsOut == "" {
		return okRes(i18n.T("no amdgpu-driven panel with power-profiles-daemon actions to audit"))
	}
	dpm := ppdActionEnabled(s.actionsOut, "amdgpu_dpm")
	abm := ppdActionEnabled(s.actionsOut, "amdgpu_panel_power")
	switch {
	case dpm && abm:
		return warnRes(i18n.T("power-profiles-daemon has amdgpu_dpm and amdgpu_panel_power enabled: power-saver will clamp the GPU rendering the desktop (visible lag) and ABM will wash panel colours. Disable them in the power-profiles-daemon action configuration"))
	case dpm:
		return warnRes(i18n.T("power-profiles-daemon has amdgpu_dpm enabled: the power-saver profile clamps the GPU rendering the desktop, which shows up as whole-desktop lag in saver mode. Disable the action in the power-profiles-daemon configuration"))
	case abm:
		return warnRes(i18n.T("power-profiles-daemon has amdgpu_panel_power enabled: adaptive backlight (ABM) visibly washes out panel colours. Disable the action in the power-profiles-daemon configuration"))
	default:
		return okRes(i18n.T("power-profiles-daemon leaves the AMD compositor GPU alone (amdgpu actions disabled)"))
	}
}

func reconcilePpdAmdgpu(_ bool) recResult {
	return planPpdAmdgpu(gatherPpdAmdgpu())
}
