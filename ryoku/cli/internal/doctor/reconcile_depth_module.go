package doctor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"
)

// The Depth tab is a quick-settings module. New installs get it from the catalog
// default, but a machine that persisted a pre-depth rail would never see it, and
// that rail varies by install era ([home, notifications, weather], then +capture).
// Runs after reconcileCaptureModule so a two-releases-behind rail gains capture
// first, then depth, in the same pass.
func reconcileDepthModule(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes("no shell.json yet (seeded on first shell run)")
	}
	migrated, changed, err := addQuickSettingsModule(raw, "depth")
	if err != nil {
		return warnRes("shell.json does not parse (%v); the shell falls back to defaults", err).
			withFix("delete %s to re-seed it", path)
	}
	if !changed {
		return okRes("quick-settings rail carries the depth tab (or a custom module list)")
	}
	if checkOnly {
		return wouldRes("quick-settings rail predates the Depth tab").
			withFix("ryoku doctor adds it after Capture")
	}
	if err := writeShellStore(path, migrated); err != nil {
		return failRes("%v", err)
	}
	return fixedRes("added the depth tab to the quick-settings rail after Capture")
}

// addQuickSettingsModule appends id to the quick-settings module rail of a shell
// store whose rail carries the base Home module and lacks id, preserving every
// other key as its own raw bytes. An empty or foreign rail is left alone.
func addQuickSettingsModule(raw []byte, id string) ([]byte, bool, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		return nil, false, err
	}
	frameRaw, ok := top["frameBars"]
	if !ok {
		return nil, false, nil
	}
	var frame map[string]json.RawMessage
	if err := json.Unmarshal(frameRaw, &frame); err != nil {
		return nil, false, err
	}
	menusRaw, ok := frame["menus"]
	if !ok {
		return nil, false, nil
	}
	var menus map[string]json.RawMessage
	if err := json.Unmarshal(menusRaw, &menus); err != nil {
		return nil, false, err
	}
	qsRaw, ok := menus["quick-settings"]
	if !ok {
		return nil, false, nil
	}
	var qs map[string]json.RawMessage
	if err := json.Unmarshal(qsRaw, &qs); err != nil {
		return nil, false, err
	}
	var modules []string
	if err := json.Unmarshal(qs["modules"], &modules); err != nil {
		return nil, false, nil
	}
	hasHome := false
	for _, m := range modules {
		if m == id {
			return nil, false, nil
		}
		if m == "home" {
			hasHome = true
		}
	}
	if !hasHome {
		return nil, false, nil
	}
	next, err := json.Marshal(append(modules, id))
	if err != nil {
		return nil, false, err
	}
	qs["modules"] = next
	qsBytes, err := json.Marshal(qs)
	if err != nil {
		return nil, false, err
	}
	menus["quick-settings"] = qsBytes
	menusBytes, err := json.Marshal(menus)
	if err != nil {
		return nil, false, err
	}
	frame["menus"] = menusBytes
	frameBytes, err := json.Marshal(frame)
	if err != nil {
		return nil, false, err
	}
	top["frameBars"] = frameBytes
	out, err := json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}

// writeShellStore replaces shell.json atomically, so a torn write never leaves
// the shell without a config.
func writeShellStore(path string, body []byte) error {
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, body, 0o644); err != nil {
		return fmt.Errorf("could not write %s: %w", tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("could not replace %s: %w", path, err)
	}
	return nil
}
