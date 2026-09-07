package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// The wallpaper backend left ryoku-shell for the Ryogami daemon, which carries
// its own config (~/.config/ryoku/ryogami.json). Three shell.json wallpaper keys
// are now dead: apply_theme_filter and theme_filter_strength (the wallpaper
// colour-filter post-process was not ported), and wallpaper_dir (Ryogami reads
// its wallpaper directory from ryogami.json paths.wallpaper, not shell.json).
// This strips those three and, so a hand-set custom directory is not silently
// lost, migrates a non-empty wallpaper_dir into ryogami.json first. content_fit
// and transition_preset stay: Ryogami reads both from shell.json per apply.
// Surgical and idempotent: a store already free of all three is left alone.
func reconcileRetiredWallpaperKeys(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no shell.json yet (seeded on first shell run)"))
	}
	migrated, wallpaperDir, changed, err := stripRetiredWallpaperKeys(raw)
	if err != nil {
		return warnRes(i18n.T("shell.json does not parse (%v); the shell falls back to defaults"), err).
			withFix(i18n.T("delete %s to re-seed it"), path)
	}
	if !changed {
		return okRes(i18n.T("shell.json carries no retired wallpaper keys"))
	}
	if checkOnly {
		return wouldRes(i18n.T("shell.json still carries retired wallpaper keys")).
			withFix(i18n.T("ryoku doctor strips them in place"))
	}
	// Preserve a custom directory before the shell.json key is dropped.
	kept := ""
	if wallpaperDir != "" {
		moved, err := migrateWallpaperDir(wallpaperDir)
		if err != nil {
			return failRes(i18n.T("could not migrate wallpaper_dir to ryogami.json: %v"), err)
		}
		if moved {
			kept = " (kept wallpaper_dir as ryogami paths.wallpaper)"
		}
	}
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, migrated, 0o644); err != nil {
		return failRes(i18n.T("could not write %s: %v"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return failRes(i18n.T("could not replace %s: %v"), path, err)
	}
	return fixedRes(i18n.T("stripped the retired wallpaper keys from shell.json%s"), kept)
}

// stripRetiredWallpaperKeys drops wallpaper_dir, apply_theme_filter and
// theme_filter_strength from a shell store's wallpaper object, keeping every
// other key (and every other wallpaper key) as its own raw bytes. It returns the
// rewritten store, the wallpaper_dir it removed (empty when absent or blank, so
// the caller only migrates a real custom path), and whether anything changed. An
// absent wallpaper object or a store already free of all three is a no-op; a
// malformed wallpaper object errors rather than being silently rewritten.
func stripRetiredWallpaperKeys(raw []byte) (out []byte, wallpaperDir string, changed bool, err error) {
	var top map[string]json.RawMessage
	if err = json.Unmarshal(raw, &top); err != nil {
		return nil, "", false, err
	}
	wpRaw, ok := top["wallpaper"]
	if !ok {
		return nil, "", false, nil
	}
	var wp map[string]json.RawMessage
	if err = json.Unmarshal(wpRaw, &wp); err != nil {
		return nil, "", false, err
	}
	// Capture a custom directory before it is dropped, so the migration keeps it.
	if dirRaw, ok := wp["wallpaper_dir"]; ok {
		var dir string
		if json.Unmarshal(dirRaw, &dir) == nil {
			wallpaperDir = dir
		}
	}
	for _, key := range []string{"wallpaper_dir", "apply_theme_filter", "theme_filter_strength"} {
		if _, ok := wp[key]; ok {
			delete(wp, key)
			changed = true
		}
	}
	if !changed {
		return nil, "", false, nil
	}
	repacked, err := json.Marshal(wp)
	if err != nil {
		return nil, "", false, err
	}
	top["wallpaper"] = repacked
	out, err = json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, "", false, err
	}
	return append(out, '\n'), wallpaperDir, true, nil
}

// migrateWallpaperDir writes a custom wallpaper directory into ryogami.json's
// paths.wallpaper, so retiring shell.json's wallpaper_dir does not lose it.
// Ryogami's own value wins: an existing paths.wallpaper is left untouched
// (moved=false). Every other key is preserved as its own raw bytes.
func migrateWallpaperDir(dir string) (moved bool, err error) {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "ryogami.json")
	top := map[string]json.RawMessage{}
	if raw, rerr := os.ReadFile(path); rerr == nil {
		if err = json.Unmarshal(raw, &top); err != nil {
			return false, err
		}
	}
	paths := map[string]json.RawMessage{}
	if pathsRaw, ok := top["paths"]; ok {
		if err = json.Unmarshal(pathsRaw, &paths); err != nil {
			return false, err
		}
	}
	if _, ok := paths["wallpaper"]; ok {
		return false, nil // ryogami already has its own wallpaper dir; keep it
	}
	val, err := json.Marshal(dir)
	if err != nil {
		return false, err
	}
	paths["wallpaper"] = val
	repackedPaths, err := json.Marshal(paths)
	if err != nil {
		return false, err
	}
	top["paths"] = repackedPaths
	out, err := json.MarshalIndent(top, "", "  ")
	if err != nil {
		return false, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, err
	}
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, append(out, '\n'), 0o644); err != nil {
		return false, err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return false, err
	}
	return true, nil
}
