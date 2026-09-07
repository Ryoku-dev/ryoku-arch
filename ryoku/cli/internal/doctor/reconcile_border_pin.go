package doctor

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"ryoku-cli/internal/sys"
	"strings"

	i18n "ryoku-i18n"
)

// ---- reconciler: stale window-border pin ------------------------------------
//
// The window border follows the wallpaper palette: decoration.lua reads
// ~/.cache/ryoku/hypr-colors.lua, and while colours are palette-driven the
// Hub's generated hypr/settings.lua deliberately omits col.active_border so
// the palette wins. A settings.lua generated before that rule existed (or by a
// path that once pinned fixed colours) carries a hard col.active_border
// forever, because the file only regenerates when the user changes a Hub
// setting: the palette keeps rendering fresh colours nobody applies and every
// window wears the stale pin ("the border colour is stuck on red").
//
// The Hub owns the file, so the repair asks it to re-emit from today's state
// (`ryoku-hub hypr get` re-renders settings.lua as a side effect) and then
// reloads Hyprland config-only. Silent when colours are user-fixed: a pinned
// border is exactly what fixed mode means.

// borderPinState is what the verdict needs, lifted so planBorderPin is pure.
type borderPinState struct {
	paletteDriven bool
	settingsLua   string // "" when the generated file is absent
	hubPresent    bool
}

var gatherBorderPin = func() borderPinState {
	var s borderPinState
	s.paletteDriven = themeFollowsPalette()
	b, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "hypr", "settings.lua"))
	if err == nil {
		s.settingsLua = string(b)
	}
	_, lookErr := exec.LookPath("ryoku-hub")
	s.hubPresent = lookErr == nil
	return s
}

// themeFollowsPalette mirrors the Hub's paletteDriven(): colours come from a
// live palette when theme.json follows the wallpaper (absent file defaults to
// following, the shipped look) or shell.json locks a named static scheme.
func themeFollowsPalette() bool {
	follow := true
	if b, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "ryoku", "theme.json")); err == nil {
		var t struct {
			FollowWallpaper bool `json:"followWallpaper"`
		}
		if json.Unmarshal(b, &t) == nil {
			follow = t.FollowWallpaper
		}
	}
	if follow {
		return true
	}
	if b, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")); err == nil {
		var s struct {
			Theme struct {
				Theme string `json:"theme"`
			} `json:"theme"`
		}
		if json.Unmarshal(b, &s) == nil {
			switch s.Theme.Theme {
			case "", "Default", "Wallpaper":
			default:
				return true
			}
		}
	}
	return false
}

var repairBorderPin = func() error {
	if err := exec.Command("ryoku-hub", "hypr", "get").Run(); err != nil {
		return err
	}
	// Config keywords re-read; best-effort, a headless run has no compositor.
	_ = exec.Command("hyprctl", "reload", "config-only").Run()
	return nil
}

// planBorderPin turns observed state into a result. pure.
func planBorderPin(s borderPinState, checkOnly bool, repair func() error) recResult {
	if !s.paletteDriven {
		return okRes(i18n.T("window colours are user-fixed; a pinned border is the chosen look"))
	}
	if !strings.Contains(s.settingsLua, "col.active_border") {
		return okRes(i18n.T("no stale border pin; the palette drives the window border"))
	}
	if !s.hubPresent {
		return warnRes(i18n.T("hypr/settings.lua pins col.active_border while colours follow the palette, and ryoku-hub is not installed to regenerate it; the border is stuck on a stale colour")).
			withFix("ryoku update")
	}
	if checkOnly {
		return wouldRes(i18n.T("hypr/settings.lua pins col.active_border while colours follow the palette, so the window border is stuck on a stale colour")).
			withFix(i18n.T("ryoku doctor regenerates it via ryoku-hub"))
	}
	if err := repair(); err != nil {
		return failRes(i18n.T("could not regenerate hypr/settings.lua: %v"), err).
			withFix(i18n.T("run `ryoku-hub hypr get` by hand, then `hyprctl reload config-only`"))
	}
	return fixedRes(i18n.T("regenerated hypr/settings.lua; the window border follows the palette again"))
}

func reconcileBorderPin(checkOnly bool) recResult {
	return planBorderPin(gatherBorderPin(), checkOnly, repairBorderPin)
}
