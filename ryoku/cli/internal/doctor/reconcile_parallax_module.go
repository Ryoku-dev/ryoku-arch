package doctor

import (
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"
)

// Same shape as the Depth tab before it: the Parallax panel is a quick-settings
// module, so a fresh install gets it from the catalog default while a box that
// persisted an older rail never sees the tab, however correctly the update
// landed the QML. Appends "parallax" to any persisted rail carrying the base
// Home module. Runs after the depth reconciler so a rail several releases
// behind gains capture, depth and parallax in one pass.
func reconcileParallaxModule(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes("no shell.json yet (seeded on first shell run)")
	}
	migrated, changed, err := addQuickSettingsModule(raw, "parallax")
	if err != nil {
		return warnRes("shell.json does not parse (%v); the shell falls back to defaults", err).
			withFix("delete %s to re-seed it", path)
	}
	if !changed {
		return okRes("quick-settings rail carries the parallax tab (or a custom module list)")
	}
	if checkOnly {
		return wouldRes("quick-settings rail predates the Parallax tab").
			withFix("ryoku doctor adds it after Depth")
	}
	if err := writeShellStore(path, migrated); err != nil {
		return failRes("%v", err)
	}
	return fixedRes("added the parallax tab to the quick-settings rail after Depth")
}
