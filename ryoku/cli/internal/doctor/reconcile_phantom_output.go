package doctor

import (
	"encoding/json"
	"os/exec"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: phantom Wayland output --------------------------------------
//
// Ryoku's monitors.lua ends in a catch-all `hl.monitor({ output = "", ... })`
// so a freshly plugged display comes up without a hand-written rule. The cost
// is that Hyprland enables EVERY connector it reports as `connected`, and on
// some machines that includes a connector with no display on it: a port routed
// through the discrete GPU on a hybrid laptop, a KVM or dock that keeps a dead
// EDID line alive, or a driver that lights a ghost after a MUX/kernel change.
// Hyprland lights it as a blank second desktop -- windows open onto it and get
// lost, and the user is left wondering what the extra "screen" is. This is the
// exact confusion behind the field report that prompted the reconciler.
//
// The tell of a ghost is an ENABLED, non-internal output whose EDID is empty
// (no make AND no model) AND whose physical size is zero -- a real display with
// a working EDID always reports at least a make/model and a physical size. To
// stay conservative the check also requires a genuinely real display to be
// present: a single-output machine whose only panel has a broken EDID is that
// user's actual screen, not a phantom, so it is left alone.
//
// Report-only. Disabling an output is a display change that could black out a
// real-but-EDID-less monitor, so doctor never writes it: it names the ghost and
// the one-line monitors_user.lua rule that pins it off (or forces its mode, if
// it turns out to be a real panel). Silent with no live session, no hyprctl, or
// when every enabled output has a real EDID.

// phantomMon is the slice of `hyprctl monitors all -j` this check reads, lifted
// to a value so planPhantomOutput is a pure function of it, testable through the
// gatherMonitors seam without a live compositor.
type phantomMon struct {
	Name          string `json:"name"`
	Make          string `json:"make"`
	Model         string `json:"model"`
	Serial        string `json:"serial"`
	PhysicalWidth int    `json:"physicalWidth"`
	Disabled      bool   `json:"disabled"`
}

// gatherMonitors reads the live monitor list. A var so a test can drive every
// branch through the one seam. Any failure (no hyprctl, bad JSON) yields nil,
// which planPhantomOutput reads as "nothing to flag" -- doctor never invents a
// fault it cannot see.
var gatherMonitors = func() []phantomMon {
	out, err := exec.Command("hyprctl", "monitors", "all", "-j").Output()
	if err != nil {
		return nil
	}
	var mons []phantomMon
	if json.Unmarshal(out, &mons) != nil {
		return nil
	}
	return mons
}

// isInternalPanel reports whether a connector name is a built-in laptop panel
// (eDP/LVDS/DSI). Internal panels are always real, so they are never phantoms.
// pure.
func isInternalPanel(name string) bool {
	for _, p := range []string{"eDP-", "LVDS-", "DSI-"} {
		if strings.HasPrefix(name, p) {
			return true
		}
	}
	return false
}

// looksPhantom reports whether an enabled output is almost certainly a ghost:
// non-internal, no EDID (empty make and model), and zero physical size. pure.
func looksPhantom(m phantomMon) bool {
	return !m.Disabled &&
		!isInternalPanel(m.Name) &&
		strings.TrimSpace(m.Make) == "" &&
		strings.TrimSpace(m.Model) == "" &&
		m.PhysicalWidth <= 0
}

// planPhantomOutput turns the monitor list into a result. pure, so every branch
// is unit-testable without a compositor.
func planPhantomOutput(mons []phantomMon) recResult {
	var ghosts []string
	realEnabled := 0
	for _, m := range mons {
		if m.Disabled {
			continue
		}
		if looksPhantom(m) {
			ghosts = append(ghosts, m.Name)
		} else {
			realEnabled++
		}
	}
	if len(ghosts) == 0 {
		return okRes(i18n.T("no phantom outputs; every enabled display reports a real EDID"))
	}
	// A machine whose only enabled output is EDID-less is running on that panel
	// -- it is the user's real (if quirky) screen, not a phantom. Leave it.
	if realEnabled == 0 {
		return okRes(i18n.T("the sole enabled output has no EDID; treating it as a real display, not a phantom"))
	}
	names := strings.Join(ghosts, ", ")
	line := "hl.monitor({ output = \"" + ghosts[0] + "\", disabled = true })"
	return warnRes(i18n.T("a phantom Wayland output is enabled with no display on it: %s (no EDID, zero physical size). Windows can open onto this blank second desktop and get lost; it is usually a dual-GPU, KVM, or dock connector Hyprland lit through the catch-all monitor rule"), names).
		withFix(i18n.T("turn it off in ~/.config/hypr/monitors_user.lua (one line per output): %s. If it is really a display with a broken EDID, force its mode there instead"), line)
}

func reconcilePhantomOutput(_ bool) recResult {
	if !sys.HyprLive() {
		return okRes(i18n.T("no live Hyprland session; phantom outputs cannot be checked"))
	}
	return planPhantomOutput(gatherMonitors())
}
