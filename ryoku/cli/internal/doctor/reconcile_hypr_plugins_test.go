package doctor

import (
	"errors"
	"strings"
	"testing"
)

func TestPlanHyprPlugins(t *testing.T) {
	noRepair := func() (map[string]string, error) { t.Fatal("repair must not run"); return nil, nil }
	stale := hyprPluginState{hubPresent: true, listed: true, enabled: 2, stale: []string{"dynamic-cursors"}, toolchain: true}

	t.Run("nothing enabled passes", func(t *testing.T) {
		r := planHyprPlugins(hyprPluginState{hubPresent: true, listed: true, toolchain: true}, true, noRepair)
		if r.status != recOK {
			t.Fatalf("status = %v, want ok", r.status)
		}
	})

	t.Run("enabled and current passes", func(t *testing.T) {
		r := planHyprPlugins(hyprPluginState{hubPresent: true, listed: true, enabled: 3, toolchain: true}, true, noRepair)
		if r.status != recOK {
			t.Fatalf("status = %v, want ok", r.status)
		}
	})

	t.Run("a disabled stale plugin is not the doctor's business", func(t *testing.T) {
		r := planHyprPlugins(hyprPluginState{hubPresent: true, listed: true, enabled: 1, toolchain: true}, false, noRepair)
		if r.status != recOK {
			t.Fatalf("status = %v, want ok", r.status)
		}
	})

	t.Run("stale reports in check mode", func(t *testing.T) {
		r := planHyprPlugins(stale, true, noRepair)
		if r.status != recWouldFix || !strings.Contains(r.detail, "dynamic-cursors") {
			t.Fatalf("result = %v %q", r.status, r.detail)
		}
	})

	t.Run("stale rebuilds in apply mode", func(t *testing.T) {
		ran := false
		r := planHyprPlugins(stale, false, func() (map[string]string, error) { ran = true; return nil, nil })
		if !ran || r.status != recFixed {
			t.Fatalf("ran=%v status=%v", ran, r.status)
		}
	})

	t.Run("a plugin the builder could not rebuild is named", func(t *testing.T) {
		r := planHyprPlugins(stale, false, func() (map[string]string, error) {
			return map[string]string{"dynamic-cursors": "build step failed: make all"}, nil
		})
		if r.status != recFailed || !strings.Contains(r.detail, "make all") {
			t.Fatalf("result = %v %q", r.status, r.detail)
		}
	})

	t.Run("a builder that cannot run fails", func(t *testing.T) {
		r := planHyprPlugins(stale, false, func() (map[string]string, error) { return nil, errors.New("no git") })
		if r.status != recFailed {
			t.Fatalf("status = %v, want failed", r.status)
		}
	})

	t.Run("no toolchain warns with what to install", func(t *testing.T) {
		s := stale
		s.toolchain, s.missing = false, []string{"cmake", "hyprland headers"}
		r := planHyprPlugins(s, false, noRepair)
		if r.status != recWarn || !strings.Contains(r.detail, "cmake") || !strings.Contains(r.remedy, "base-devel") {
			t.Fatalf("result = %v %q fix=%q", r.status, r.detail, r.remedy)
		}
	})

	t.Run("missing hub warns", func(t *testing.T) {
		r := planHyprPlugins(hyprPluginState{}, false, noRepair)
		if r.status != recWarn {
			t.Fatalf("status = %v, want warn", r.status)
		}
	})

	t.Run("unanswered backend is a note", func(t *testing.T) {
		r := planHyprPlugins(hyprPluginState{hubPresent: true}, false, noRepair)
		if r.status != recNote {
			t.Fatalf("status = %v, want note", r.status)
		}
	})
}
