package doctor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// Depth and Parallax merged into one Stage tab, so a machine that persisted a
// rail carrying the retired depth and/or parallax modules must fold them into a
// single stage module, and a rail from before either existed must gain stage.
// New installs get the stage tab from the catalog default; this migration keeps
// an upgraded box's persisted rail in step. Runs after reconcileCaptureModule so
// a rail several releases behind gains capture first, then stage, in one pass.
func reconcileStageModule(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no shell.json yet (seeded on first shell run)"))
	}
	migrated, changed, err := replaceQuickSettingsModules(raw, []string{"depth", "parallax"}, "stage")
	if err != nil {
		return warnRes(i18n.T("shell.json does not parse (%v); the shell falls back to defaults"), err).
			withFix(i18n.T("delete %s to re-seed it"), path)
	}
	if !changed {
		return okRes(i18n.T("quick-settings rail carries the stage tab (or a custom module list)"))
	}
	if checkOnly {
		return wouldRes(i18n.T("quick-settings rail predates the Stage tab (retired depth/parallax, or missing entirely)")).
			withFix(i18n.T("ryoku doctor puts a single stage tab on the rail"))
	}
	if err := writeShellStore(path, migrated); err != nil {
		return failRes("%v", err)
	}
	return fixedRes(i18n.T("put a single stage tab on the quick-settings rail"))
}

// replaceQuickSettingsModules folds the retired `from` modules of a quick-settings
// rail into a single `to` module placed where the first of them sat, preserving
// every other key as its own raw bytes. A rail already carrying `to` is a no-op;
// a rail with none of `from` gains `to` appended when it carries the base Home
// module (the addQuickSettingsModule path); a foreign rail is left alone.
func replaceQuickSettingsModules(raw []byte, from []string, to string) ([]byte, bool, error) {
	top, frame, menus, qs, modules, ok, err := readQuickSettingsRail(raw)
	if err != nil || !ok {
		return nil, false, err
	}
	retired := make(map[string]bool, len(from))
	for _, f := range from {
		retired[f] = true
	}
	insertAt := -1
	kept := make([]string, 0, len(modules))
	for _, m := range modules {
		if m == to {
			return nil, false, nil // already folded
		}
		if retired[m] {
			if insertAt < 0 {
				insertAt = len(kept)
			}
			continue
		}
		kept = append(kept, m)
	}
	if insertAt < 0 {
		// none of the retired modules present: append to a home-carrying rail.
		return addQuickSettingsModule(raw, to)
	}
	next := make([]string, 0, len(kept)+1)
	next = append(next, kept[:insertAt]...)
	next = append(next, to)
	next = append(next, kept[insertAt:]...)
	return writeQuickSettingsRail(top, frame, menus, qs, next)
}

// addQuickSettingsModule appends id to the quick-settings module rail of a shell
// store whose rail carries the base Home module and lacks id, preserving every
// other key as its own raw bytes. An empty or foreign rail is left alone.
func addQuickSettingsModule(raw []byte, id string) ([]byte, bool, error) {
	top, frame, menus, qs, modules, ok, err := readQuickSettingsRail(raw)
	if err != nil || !ok {
		return nil, false, err
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
	return writeQuickSettingsRail(top, frame, menus, qs, append(modules, id))
}

// readQuickSettingsRail unwraps frameBars.menus.quick-settings.modules from a
// shell store, returning each enclosing map so a rewrite can put the modules back
// while every sibling key survives as its own raw bytes. ok is false (with a nil
// error) when the store simply has no such rail; a genuine parse failure returns
// the error so a caller never silently rewrites garbage.
func readQuickSettingsRail(raw []byte) (top, frame, menus, qs map[string]json.RawMessage, modules []string, ok bool, err error) {
	if err = json.Unmarshal(raw, &top); err != nil {
		return nil, nil, nil, nil, nil, false, err
	}
	frameRaw, has := top["frameBars"]
	if !has {
		return nil, nil, nil, nil, nil, false, nil
	}
	if err = json.Unmarshal(frameRaw, &frame); err != nil {
		return nil, nil, nil, nil, nil, false, err
	}
	menusRaw, has := frame["menus"]
	if !has {
		return nil, nil, nil, nil, nil, false, nil
	}
	if err = json.Unmarshal(menusRaw, &menus); err != nil {
		return nil, nil, nil, nil, nil, false, err
	}
	qsRaw, has := menus["quick-settings"]
	if !has {
		return nil, nil, nil, nil, nil, false, nil
	}
	if err = json.Unmarshal(qsRaw, &qs); err != nil {
		return nil, nil, nil, nil, nil, false, err
	}
	if err = json.Unmarshal(qs["modules"], &modules); err != nil {
		return nil, nil, nil, nil, nil, false, nil
	}
	return top, frame, menus, qs, modules, true, nil
}

// writeQuickSettingsRail rewrites the modules list back through the enclosing
// maps and re-marshals the store, leaving every untouched key as its own bytes.
func writeQuickSettingsRail(top, frame, menus, qs map[string]json.RawMessage, modules []string) ([]byte, bool, error) {
	modBytes, err := json.Marshal(modules)
	if err != nil {
		return nil, false, err
	}
	qs["modules"] = modBytes
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
		return fmt.Errorf(i18n.T("could not write %s: %w"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return fmt.Errorf(i18n.T("could not replace %s: %w"), path, err)
	}
	return nil
}

// reconcileRyostageCache reclaims a legacy depth or parallax runtime tree left in
// the state dir once the unified ryostage cache is provisioned. The ryostage
// helper adopts the first pre-split tree by rename on its first run; a second,
// now-orphaned tree is dead weight (the venvs and model caches run to hundreds of
// MB). Guarded on an existing ryostage venv python so the doctor never deletes a
// tree the engine is still using.
func reconcileRyostageCache(checkOnly bool) recResult {
	state := sys.StateDir()
	if !sys.Exists(filepath.Join(state, "ryostage", "venv", "bin", "python")) {
		return okRes(i18n.T("no ryostage runtime yet; legacy caches left untouched"))
	}
	var leftover []string
	for _, legacy := range []string{"depth", "parallax"} {
		if sys.Exists(filepath.Join(state, legacy)) {
			leftover = append(leftover, legacy)
		}
	}
	if len(leftover) == 0 {
		return okRes(i18n.T("no legacy depth/parallax runtime cache to reclaim"))
	}
	if checkOnly {
		return wouldRes(i18n.T("legacy %s runtime cache under %s is reclaimable now ryostage is provisioned"), joinLegacy(leftover), state).
			withFix(i18n.T("ryoku doctor removes it"))
	}
	for _, legacy := range leftover {
		if err := os.RemoveAll(filepath.Join(state, legacy)); err != nil {
			return failRes(i18n.T("could not remove %s: %v"), filepath.Join(state, legacy), err)
		}
	}
	return fixedRes(i18n.T("reclaimed the legacy %s runtime cache under %s"), joinLegacy(leftover), state)
}

// joinLegacy renders one or two legacy cache names for a message ("depth" or
// "depth and parallax").
func joinLegacy(names []string) string {
	if len(names) == 2 {
		return names[0] + " and " + names[1]
	}
	return names[0]
}

// reconcileStageLeftovers reclaims the superseded settings and registry files the
// daemon's start-up fold reads but never deletes, so a migrated box does not keep
// depth.json/parallax.json/depth-walls.json/layers.pz forever. Gated strictly on
// the daemon's migration marker: it is written only after the registry fold
// persists, so a file that still exists without the marker is one the daemon may
// yet fold, and is left alone. User pictures are never touched.
func reconcileStageLeftovers(checkOnly bool) recResult {
	state := sys.StateDir()
	if !sys.Exists(filepath.Join(state, "migrations", "ryostage")) {
		return okRes(i18n.T("stage migration has not run; superseded settings left untouched"))
	}
	cfg := filepath.Join(sys.ConfigHome(), "ryoku")
	candidates := []string{
		filepath.Join(cfg, "depth.json"),
		filepath.Join(cfg, "parallax.json"),
		filepath.Join(state, "depth-walls.json"),
		filepath.Join(sys.Home(), "Pictures", "Parallax", "layers.pz"),
	}
	var present []string
	for _, p := range candidates {
		if sys.Exists(p) {
			present = append(present, p)
		}
	}
	if len(present) == 0 {
		return okRes(i18n.T("no superseded stage settings to reclaim"))
	}
	if checkOnly {
		return wouldRes(i18n.T("superseded stage settings remain after migration: %s"), strings.Join(present, ", ")).
			withFix(i18n.T("ryoku doctor removes them"))
	}
	for _, p := range present {
		if err := os.Remove(p); err != nil {
			return failRes(i18n.T("could not remove %s: %v"), p, err)
		}
	}
	return fixedRes(i18n.T("reclaimed %d superseded stage file(s) after migration"), len(present))
}
