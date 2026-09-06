package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ryoku-cli/internal/sys"
)

// replaceQuickSettingsModules folds the retired depth/parallax modules of a rail
// into a single stage module where the first of them sat, appends stage to a rail
// that carries neither (via the Home rule), preserves every sibling and top-level
// key, and no-ops on a rail already carrying stage or a foreign rail.
func TestReplaceQuickSettingsModulesStage(t *testing.T) {
	from, to := []string{"depth", "parallax"}, "stage"

	// both retired modules collapse to one stage in the first one's slot, and
	// every sibling menu and top-level key survives.
	full := []byte(`{"frameBars":{"menus":{"quick-settings":{"anchor":"left","minWidth":410,"modules":["home","notifications","weather","capture","depth","parallax"]},"weather":{"anchor":"right"}},"style":"slate-frame"},"weatherLocation":"Oslo"}`)
	out, changed, err := replaceQuickSettingsModules(full, from, to)
	if err != nil || !changed {
		t.Fatalf("a depth+parallax rail must fold to stage: changed=%v err=%v", changed, err)
	}
	if got, want := captureModules(t, out), []string{"home", "notifications", "weather", "capture", "stage"}; !sameStrings(got, want) {
		t.Fatalf("modules = %v, want %v", got, want)
	}
	var cfg map[string]any
	if err := json.Unmarshal(out, &cfg); err != nil {
		t.Fatalf("migrated JSON does not parse: %v", err)
	}
	frame := cfg["frameBars"].(map[string]any)
	if _, ok := frame["menus"].(map[string]any)["weather"]; !ok {
		t.Error("sibling weather menu was lost")
	}
	if frame["style"] != "slate-frame" {
		t.Errorf("frameBars.style was lost: %v", frame["style"])
	}
	if cfg["weatherLocation"] != "Oslo" {
		t.Errorf("passthrough key weatherLocation was lost: %v", cfg)
	}

	// idempotent once stage is present.
	if _, changed, err := replaceQuickSettingsModules(out, from, to); err != nil || changed {
		t.Errorf("re-running on a folded store must be a no-op: changed=%v err=%v", changed, err)
	}

	for _, rail := range []struct {
		name string
		in   string
		want []string
	}{
		// depth alone -> stage in its slot.
		{"depth only", `{"frameBars":{"menus":{"quick-settings":{"modules":["home","notifications","weather","capture","depth"]}}}}`, []string{"home", "notifications", "weather", "capture", "stage"}},
		// parallax alone -> stage in its slot.
		{"parallax only", `{"frameBars":{"menus":{"quick-settings":{"modules":["home","notifications","weather","capture","parallax"]}}}}`, []string{"home", "notifications", "weather", "capture", "stage"}},
		// neither present -> stage appended to a home-carrying rail.
		{"neither", `{"frameBars":{"menus":{"quick-settings":{"modules":["home","notifications","weather","capture"]}}}}`, []string{"home", "notifications", "weather", "capture", "stage"}},
		// stage keeps the slot of the first retired module, not the last.
		{"depth mid-rail", `{"frameBars":{"menus":{"quick-settings":{"modules":["home","depth","notifications","parallax","weather"]}}}}`, []string{"home", "stage", "notifications", "weather"}},
	} {
		out, changed, err := replaceQuickSettingsModules([]byte(rail.in), from, to)
		if err != nil || !changed {
			t.Errorf("%s: rail must gain stage: changed=%v err=%v", rail.name, changed, err)
			continue
		}
		if got := captureModules(t, out); !sameStrings(got, rail.want) {
			t.Errorf("%s: modules = %v, want %v", rail.name, got, rail.want)
		}
	}

	// a rail already carrying stage is untouched, even with a stray retired entry.
	if _, changed, err := replaceQuickSettingsModules([]byte(`{"frameBars":{"menus":{"quick-settings":{"modules":["home","notifications","weather","capture","stage"]}}}}`), from, to); err != nil || changed {
		t.Errorf("a stage rail must be a no-op: changed=%v err=%v", changed, err)
	}

	// a custom rail with neither retired module and no base Home is foreign.
	if _, changed, err := replaceQuickSettingsModules([]byte(`{"frameBars":{"menus":{"quick-settings":{"modules":["notifications","weather"]}}}}`), from, to); err != nil || changed {
		t.Errorf("a rail without home and without depth/parallax must be untouched: changed=%v err=%v", changed, err)
	}

	if _, changed, err := replaceQuickSettingsModules([]byte(`{"bars":{}}`), from, to); err != nil || changed {
		t.Errorf("a store with no frameBars must be untouched: changed=%v err=%v", changed, err)
	}
	if _, _, err := replaceQuickSettingsModules([]byte("not json"), from, to); err == nil {
		t.Fatal("garbage must error, not silently rewrite")
	}
}

// A rail persisted with the retired depth+parallax tabs is folded into one stage
// tab in place, keeping its other keys, and a second pass is idempotent.
func TestReconcileStageModuleFoldsPersistedRail(t *testing.T) {
	ueSetup(t)
	store := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	ueWrite(t, store, `{"frameBars":{"menus":{"quick-settings":{"anchor":"left","modules":["home","notifications","weather","capture","depth","parallax"]}}}}`)

	if r := reconcileStageModule(false); r.status != recFixed {
		t.Fatalf("status=%s, detail=%s", r.status.label(), r.detail)
	}
	got := mustRead(t, store)
	if !strings.Contains(got, `"stage"`) || strings.Contains(got, `"depth"`) || strings.Contains(got, `"parallax"`) {
		t.Fatalf("rail did not fold depth/parallax into stage:\n%s", got)
	}
	if !strings.Contains(got, `"anchor": "left"`) {
		t.Fatalf("rail lost its other keys:\n%s", got)
	}
	if r := reconcileStageModule(false); r.status != recOK {
		t.Fatalf("second run = %s (must be idempotent)", r.status.label())
	}
}

// The cache reconciler reclaims a legacy runtime tree only once the ryostage
// venv exists beside it, and never touches a tree the engine may still be using.
func TestReconcileRyostageCache(t *testing.T) {
	seedTree := func(t *testing.T, dir string) {
		t.Helper()
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "marker"), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	// present beside a provisioned ryostage venv: reclaimed on apply.
	t.Run("reclaimed beside ryostage", func(t *testing.T) {
		ueSetup(t)
		state := sys.StateDir()
		seedTree(t, filepath.Join(state, "ryostage", "venv", "bin"))
		if err := os.WriteFile(filepath.Join(state, "ryostage", "venv", "bin", "python"), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
		seedTree(t, filepath.Join(state, "depth", "venv"))
		seedTree(t, filepath.Join(state, "parallax", "models"))

		if r := reconcileRyostageCache(true); r.status != recWouldFix {
			t.Fatalf("check-only: status=%s detail=%q, want todo", r.status.label(), r.detail)
		}
		if !sys.Exists(filepath.Join(state, "depth")) {
			t.Fatal("check-only must not remove the legacy tree")
		}
		if r := reconcileRyostageCache(false); r.status != recFixed {
			t.Fatalf("apply: status=%s detail=%q, want fixed", r.status.label(), r.detail)
		}
		if sys.Exists(filepath.Join(state, "depth")) || sys.Exists(filepath.Join(state, "parallax")) {
			t.Fatal("legacy depth/parallax trees must be removed on apply")
		}
		if !sys.Exists(filepath.Join(state, "ryostage", "venv", "bin", "python")) {
			t.Fatal("the ryostage runtime must never be touched")
		}
	})

	// present alone, no ryostage venv yet: left exactly where it is.
	t.Run("left when alone", func(t *testing.T) {
		ueSetup(t)
		state := sys.StateDir()
		seedTree(t, filepath.Join(state, "depth", "venv"))

		if r := reconcileRyostageCache(false); r.status != recOK {
			t.Fatalf("no ryostage yet: status=%s detail=%q, want ok", r.status.label(), r.detail)
		}
		if !sys.Exists(filepath.Join(state, "depth")) {
			t.Fatal("a legacy tree with no adopted ryostage runtime must be left in place")
		}
	})
}

// The leftovers reconciler reclaims the superseded settings/registry files only
// once the daemon's migration marker is set, never touches a live stage.json or a
// user picture, and is a no-op before the fold or when nothing is left.
func TestReconcileStageLeftovers(t *testing.T) {
	marker := func(t *testing.T) {
		t.Helper()
		ueWrite(t, filepath.Join(sys.StateDir(), "migrations", "ryostage"), "1")
	}

	// no marker yet: the daemon may still fold these, so they are left in place.
	t.Run("untouched before migration", func(t *testing.T) {
		ueSetup(t)
		dj := filepath.Join(sys.ConfigHome(), "ryoku", "depth.json")
		ueWrite(t, dj, "{}")
		if r := reconcileStageLeftovers(false); r.status != recOK {
			t.Fatalf("no marker: status=%s detail=%q, want ok", r.status.label(), r.detail)
		}
		if !sys.Exists(dj) {
			t.Fatal("a superseded file must survive until the daemon migration marker is set")
		}
	})

	// marker set: reclaimed on apply, not on check; stage.json and pictures survive.
	t.Run("reclaimed after migration", func(t *testing.T) {
		ueSetup(t)
		marker(t)
		cfg := filepath.Join(sys.ConfigHome(), "ryoku")
		files := []string{
			filepath.Join(cfg, "depth.json"),
			filepath.Join(cfg, "parallax.json"),
			filepath.Join(sys.StateDir(), "depth-walls.json"),
			filepath.Join(sys.Home(), "Pictures", "Parallax", "layers.pz"),
		}
		for _, f := range files {
			ueWrite(t, f, "{}")
		}
		keep := filepath.Join(cfg, "stage.json")
		ueWrite(t, keep, `{"quality":"draft"}`)
		png := filepath.Join(sys.Home(), "Pictures", "Depth", "wall-depth.png")
		ueWrite(t, png, "png")

		if r := reconcileStageLeftovers(true); r.status != recWouldFix {
			t.Fatalf("check-only: status=%s detail=%q, want todo", r.status.label(), r.detail)
		}
		for _, f := range files {
			if !sys.Exists(f) {
				t.Fatalf("check-only must not remove %s", f)
			}
		}
		if r := reconcileStageLeftovers(false); r.status != recFixed {
			t.Fatalf("apply: status=%s detail=%q, want fixed", r.status.label(), r.detail)
		}
		for _, f := range files {
			if sys.Exists(f) {
				t.Fatalf("apply must reclaim superseded %s", f)
			}
		}
		if !sys.Exists(keep) {
			t.Fatal("a live stage.json must never be reclaimed")
		}
		if !sys.Exists(png) {
			t.Fatal("user pictures must never be touched")
		}
	})

	// marker set but nothing superseded left: a no-op.
	t.Run("noop when nothing left", func(t *testing.T) {
		ueSetup(t)
		marker(t)
		if r := reconcileStageLeftovers(false); r.status != recOK {
			t.Fatalf("nothing to reclaim: status=%s, want ok", r.status.label())
		}
	})
}
