package doctor

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"sort"
	"strings"
)

// ---- reconciler: Hyprland plugin builds -------------------------------------
//
// A compositor plugin is ABI-locked to the exact Hyprland build: the commit
// plus the major.minor of aquamarine, hyprutils, hyprgraphics, hyprcursor and
// hyprlang. Arch can bump any of those between two Ryoku releases, and then
// the plugin copies on the box (the [ryoku] package, a local build) no longer
// load: Hyprland refuses each with "version mismatch" on every reload, and a
// cursor effect or title bar the user turned on silently stops. Each copy
// carries an .abi receipt, so the Hub's backend can tell without loading.
//
// Enabled plugins are what the user will miss at the next login, so those are
// converged here: `ryoku-hub hypr plugins rebuild --stale` rebuilds every
// enabled plugin whose receipts no longer match the installed headers (what the
// next session runs), from upstream, with the same builder the Plugins page
// uses. A disabled stale plugin costs nothing and is left for the page. A box
// without a toolchain is told what to install; the page then offers Rebuild.

// hyprPluginState is what the verdict needs, lifted so the plan is pure.
type hyprPluginState struct {
	hubPresent bool
	listed     bool     // the backend answered
	stale      []string // enabled, installed, rebuildable, and built for another Hyprland
	enabled    int
	toolchain  bool
	missing    []string
}

var gatherHyprPlugins = func() hyprPluginState {
	var s hyprPluginState
	if _, err := exec.LookPath("ryoku-hub"); err != nil {
		return s
	}
	s.hubPresent = true
	out, err := exec.Command("ryoku-hub", "hypr", "plugins", "list").Output()
	if err != nil {
		return s
	}
	var roster struct {
		Toolchain struct {
			OK      bool     `json:"ok"`
			Missing []string `json:"missing"`
		} `json:"toolchain"`
		Plugins []struct {
			ID          string `json:"id"`
			Enabled     bool   `json:"enabled"`
			Installed   bool   `json:"installed"`
			Current     bool   `json:"current"`
			Rebuildable bool   `json:"rebuildable"`
		} `json:"plugins"`
	}
	if json.Unmarshal(out, &roster) != nil {
		return s
	}
	s.listed = true
	s.toolchain, s.missing = roster.Toolchain.OK, roster.Toolchain.Missing
	for _, p := range roster.Plugins {
		if !p.Enabled {
			continue
		}
		s.enabled++
		if p.Installed && !p.Current && p.Rebuildable {
			s.stale = append(s.stale, p.ID)
		}
	}
	sort.Strings(s.stale)
	return s
}

// repairHyprPlugins rebuilds the stale enabled plugins and reports which ones
// the builder could not.
var repairHyprPlugins = func() (map[string]string, error) {
	out, err := exec.Command("ryoku-hub", "hypr", "plugins", "rebuild", "--stale").Output()
	if err != nil {
		return nil, err
	}
	var res struct {
		Failed map[string]string `json:"failed"`
	}
	if err := json.Unmarshal(out, &res); err != nil {
		return nil, fmt.Errorf("unreadable builder result: %w", err)
	}
	return res.Failed, nil
}

// planHyprPlugins turns observed state into a result. pure.
func planHyprPlugins(s hyprPluginState, checkOnly bool, repair func() (map[string]string, error)) recResult {
	if !s.hubPresent {
		return warnRes("ryoku-hub is not installed, so Hyprland plugin builds cannot be checked").withFix("ryoku update")
	}
	if !s.listed {
		return noteRes("Hyprland plugin builds not checked (no Hyprland headers or the backend did not answer)")
	}
	if len(s.stale) == 0 {
		if s.enabled == 0 {
			return okRes("no Hyprland plugin enabled")
		}
		return okRes("%d enabled Hyprland plugin(s) built for the installed Hyprland", s.enabled)
	}
	list := strings.Join(s.stale, ", ")
	if !s.toolchain {
		return warnRes("enabled Hyprland plugin(s) built for another Hyprland and this box cannot rebuild them (missing %s): %s", strings.Join(s.missing, ", "), list).
			withFix("sudo pacman -S --needed base-devel cmake git hyprland, then Settings > Plugins > Rebuild")
	}
	if checkOnly {
		return wouldRes("enabled Hyprland plugin(s) built for another Hyprland: %s", list).
			withFix("ryoku doctor rebuilds them via ryoku-hub hypr plugins rebuild --stale")
	}
	failed, err := repair()
	if err != nil {
		return failRes("could not rebuild Hyprland plugins (%s): %v", list, err).
			withFix("open Settings > Plugins and use Rebuild, which shows the build log")
	}
	if len(failed) > 0 {
		names := make([]string, 0, len(failed))
		for id, why := range failed {
			names = append(names, id+": "+why)
		}
		sort.Strings(names)
		return failRes("rebuilt Hyprland plugins, except %s", strings.Join(names, "; ")).
			withFix("open Settings > Plugins and use Rebuild, which shows the build log")
	}
	return fixedRes("rebuilt Hyprland plugin(s) for the installed Hyprland: %s", list)
}

func reconcileHyprPlugins(checkOnly bool) recResult {
	return planHyprPlugins(gatherHyprPlugins(), checkOnly, repairHyprPlugins)
}
