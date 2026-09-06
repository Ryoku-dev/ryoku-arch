package doctor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ryoku-cli/internal/sys"
)

// A config that is exactly the old generated palette (the pre-split render matugen
// laid straight into ghostty/config) is a wrapper waiting to happen: no user
// bytes to lose, so the reconciler moves the colours to ryoku-colors and rewrites
// the config as the include wrapper.
const ghosttyRender = `background = #101216
foreground = #e2e2e6
cursor-color = #a4caf7
cursor-text = #003257
selection-background = #3a4858
selection-foreground = #d3e1f6
palette = 0=#282a2d
palette = 1=#ffb4ab
palette = 2=#a4caf7
palette = 3=#efbf76
palette = 4=#bac8db
palette = 5=#d0e4ff
palette = 6=#d5e4f8
palette = 7=#c2c7cf
palette = 8=#8c9199
palette = 9=#ffb4ab
palette = 10=#d0e4ff
palette = 11=#ffddaf
palette = 12=#d5e4f8
palette = 13=#a4caf7
palette = 14=#8c9199
palette = 15=#e2e2e6
`

func TestReconcileGhosttyConvertsGeneratedPalette(t *testing.T) {
	ueSetup(t)
	cfg := sys.ConfigHome()
	gcfg := filepath.Join(cfg, "ghostty/config")
	colors := filepath.Join(cfg, "ghostty/ryoku-colors")
	ueWrite(t, gcfg, ghosttyRender)

	if r := reconcileGhostty(true); r.status != recWouldFix {
		t.Fatalf("check: status=%s detail=%q, want todo", r.status.label(), r.detail)
	}
	if r := reconcileGhostty(false); r.status != recFixed {
		t.Fatalf("fix: status=%s detail=%q, want fixed", r.status.label(), r.detail)
	}
	ueWantFile(t, gcfg, ghosttyConfigWrapper)
	if !ghosttyHasInclude(mustRead(t, gcfg), "ryoku-colors") {
		t.Fatal("wrapper lost its ryoku-colors include")
	}
	if got := mustRead(t, colors); !strings.Contains(got, "palette = 0=#282a2d") {
		t.Fatalf("ryoku-colors did not keep the palette: %q", got)
	}
	if r := reconcileGhostty(false); r.status != recOK {
		t.Fatalf("idempotent: status=%s, want ok", r.status.label())
	}
}

// A config the user actually edited keeps every byte; only the include is added,
// and ryoku-colors is seeded from the colours already in the file.
func TestReconcileGhosttyPreservesHandEditedConfig(t *testing.T) {
	ueSetup(t)
	cfg := sys.ConfigHome()
	gcfg := filepath.Join(cfg, "ghostty/config")
	colors := filepath.Join(cfg, "ghostty/ryoku-colors")
	body := "font-size = 13\nkeybind = ctrl+shift+t=new_tab\nbackground = #123456\n"
	ueWrite(t, gcfg, body)

	if r := reconcileGhostty(false); r.status != recFixed {
		t.Fatalf("fix: status=%s detail=%q, want fixed", r.status.label(), r.detail)
	}
	got := mustRead(t, gcfg)
	for _, want := range []string{"font-size = 13", "keybind = ctrl+shift+t=new_tab", "background = #123456"} {
		if !strings.Contains(got, want) {
			t.Fatalf("user line %q was dropped; config is now %q", want, got)
		}
	}
	if !ghosttyHasInclude(got, "ryoku-colors") {
		t.Fatalf("include not added; config is %q", got)
	}
	if c := mustRead(t, colors); !strings.Contains(c, "background = #123456") {
		t.Fatalf("ryoku-colors not seeded from the config's colours: %q", c)
	}
	if r := reconcileGhostty(false); r.status != recOK {
		t.Fatalf("idempotent: status=%s, want ok", r.status.label())
	}
}

func TestReconcileGhosttyLeavesWrappedConfigAlone(t *testing.T) {
	ueSetup(t)
	gcfg := filepath.Join(sys.ConfigHome(), "ghostty/config")
	ueWrite(t, gcfg, ghosttyConfigWrapper)

	if r := reconcileGhostty(false); r.status != recOK {
		t.Fatalf("status=%s, want ok", r.status.label())
	}
	ueWantFile(t, gcfg, ghosttyConfigWrapper)
}

// A wrapped config with the ryoku-colors line removed (user.conf still included)
// is a deliberate opt-out; the reconciler must not force theming back on.
func TestReconcileGhosttyRespectsThemeOptOut(t *testing.T) {
	ueSetup(t)
	gcfg := filepath.Join(sys.ConfigHome(), "ghostty/config")
	body := "config-file = ?user.conf\nfont-size = 12\n"
	ueWrite(t, gcfg, body)

	if r := reconcileGhostty(false); r.status != recOK {
		t.Fatalf("status=%s, want ok", r.status.label())
	}
	ueWantFile(t, gcfg, body)
}

func TestReconcileGhosttyAbsentConfigIsNoOp(t *testing.T) {
	ueSetup(t)
	gcfg := filepath.Join(sys.ConfigHome(), "ghostty/config")

	if r := reconcileGhostty(false); r.status != recOK {
		t.Fatalf("status=%s, want ok", r.status.label())
	}
	if sys.Exists(gcfg) {
		t.Fatal("doctor created a ghostty config that the user never had")
	}
}

// Once the migration has run, a config with the include stripped out is the
// user's own decision: the doctor must not put the palette back.
func TestReconcileGhosttyNeverReAddsIncludeAfterMigration(t *testing.T) {
	ueSetup(t)
	gcfg := filepath.Join(sys.ConfigHome(), "ghostty/config")
	ueWrite(t, gcfg, ghosttyRender)
	if r := reconcileGhostty(false); r.status != recFixed {
		t.Fatalf("migration status=%s, want fixed", r.status.label())
	}

	own := "font-size = 12\n"
	ueWrite(t, gcfg, own)
	if r := reconcileGhostty(false); r.status != recOK {
		t.Fatalf("status=%s, want ok", r.status.label())
	}
	ueWantFile(t, gcfg, own)
}

func mustRead(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(b)
}
