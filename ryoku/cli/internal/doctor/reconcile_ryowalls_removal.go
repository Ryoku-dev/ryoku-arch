package doctor

import (
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: sweep the sunset ryowalls app's per-user leftovers ---------
//
// ryowalls (a Quickshell wallpaper app on PATH) was folded into the ryogami
// picker and deleted from the repo. pacman drops the packaged /usr/bin and
// /usr/share copies on `ryoku update`, but a box that ran the dev deploy or
// materialized the app keeps per-user leftovers pacman never owned: the launcher
// on PATH, its launcher entry (.desktop + hicolor icon), the app's Quickshell
// config, and its thumbnail cache. They are inert but clutter the launcher and
// the apps grid. Only paths that are unmistakably ryowalls' are swept; the
// daemon still reads ryoku-ryowalls.json and the shared ryoku-wallpaper state,
// and ryogami owns the wallpaper data, so none of those are touched. No-op once
// clean; idempotent.

// ryowallsLeftovers lists the per-user paths the sunset ryowalls app leaves
// behind. Every entry is app-specific, so removing it can never hit ryogami,
// the shared wallpaper state, or a user's wallpapers.
func ryowallsLeftovers() []string {
	data := sys.Xdg("XDG_DATA_HOME", ".local/share")
	return []string{
		filepath.Join(homeDir(), ".local", "bin", "ryowalls"),
		filepath.Join(data, "applications", "ryowalls.desktop"),
		filepath.Join(data, "icons", "hicolor", "scalable", "apps", "ryowalls.svg"),
		filepath.Join(configHome(), "quickshell", "ryowalls"),
		filepath.Join(sys.Xdg("XDG_CACHE_HOME", ".cache"), "ryoku", "ryowalls"),
	}
}

func reconcileRyowallsRemoval(checkOnly bool) recResult {
	var present []string
	for _, p := range ryowallsLeftovers() {
		if sys.Exists(p) {
			present = append(present, p)
		}
	}
	if len(present) == 0 {
		return okRes(i18n.T("no ryowalls leftovers to sweep"))
	}
	if checkOnly {
		return wouldRes(i18n.T("stale ryowalls leftovers from the sunset app remain: %s"), tildeList(present)).
			withFix(i18n.T("ryoku doctor removes the ryowalls launcher, launcher entry, config and cache"))
	}
	var removed []string
	for _, p := range present {
		if err := os.RemoveAll(p); err != nil {
			return failRes(i18n.T("could not remove %s: %v"), tildeOf(p), err)
		}
		removed = append(removed, tildeOf(p))
	}
	return fixedRes(i18n.T("swept the sunset ryowalls app leftovers: %s"), strings.Join(removed, ", "))
}

func tildeList(paths []string) string {
	short := make([]string, len(paths))
	for i, p := range paths {
		short[i] = tildeOf(p)
	}
	return strings.Join(short, ", ")
}
