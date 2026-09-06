package doctor

import (
	"encoding/json"
	"testing"
)

// addQuickSettingsModule appends "depth" to any quick-settings rail carrying the base Home
// module, preserves every sibling and top-level key, and no-ops on a rail already
// carrying depth or one with no Home module.
func TestAddDepthModule(t *testing.T) {
	full := []byte(`{"frameBars":{"menus":{"quick-settings":{"anchor":"left","minWidth":410,"modules":["home","notifications","weather","capture"]},"weather":{"anchor":"right"}},"style":"slate-frame"},"weatherLocation":"Oslo"}`)
	out, changed, err := addQuickSettingsModule(full, "depth")
	if err != nil || !changed {
		t.Fatalf("the pre-depth default must gain depth: changed=%v err=%v", changed, err)
	}
	if got, want := captureModules(t, out), []string{"home", "notifications", "weather", "capture", "depth"}; !sameStrings(got, want) {
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

	// idempotent once depth is present.
	if _, changed, err := addQuickSettingsModule(out, "depth"); err != nil || changed {
		t.Errorf("re-running on a migrated store must be a no-op: changed=%v err=%v", changed, err)
	}

	// any home-carrying rail gains depth, whatever its era: the capture reconciler
	// runs first, so a [home, notifications, weather] rail is already +capture by
	// the time this runs, and a custom superset still gains it.
	for _, rail := range []struct {
		in   string
		want []string
	}{
		{`{"frameBars":{"menus":{"quick-settings":{"modules":["home","notifications","weather"]}}}}`, []string{"home", "notifications", "weather", "depth"}},
		{`{"frameBars":{"menus":{"quick-settings":{"modules":["home","notifications","weather","capture","media"]}}}}`, []string{"home", "notifications", "weather", "capture", "media", "depth"}},
	} {
		out, changed, err := addQuickSettingsModule([]byte(rail.in), "depth")
		if err != nil || !changed {
			t.Errorf("a home-carrying rail must gain depth: changed=%v err=%v (%s)", changed, err, rail.in)
			continue
		}
		if got := captureModules(t, out); !sameStrings(got, rail.want) {
			t.Errorf("modules = %v, want %v", got, rail.want)
		}
	}

	// a rail with no base Home module is foreign; leave it alone.
	if _, changed, err := addQuickSettingsModule([]byte(`{"frameBars":{"menus":{"quick-settings":{"modules":["notifications","weather"]}}}}`), "depth"); err != nil || changed {
		t.Errorf("a rail without home must be untouched: changed=%v err=%v", changed, err)
	}

	if _, changed, err := addQuickSettingsModule([]byte(`{"bars":{}}`), "depth"); err != nil || changed {
		t.Errorf("a store with no frameBars must be untouched: changed=%v err=%v", changed, err)
	}
	if _, _, err := addQuickSettingsModule([]byte("not json"), "depth"); err == nil {
		t.Fatal("garbage must error, not silently rewrite")
	}
}
