package doctor

import (
	"path/filepath"
	"strings"
	"testing"

	"ryoku-cli/internal/sys"
)

// A rail persisted before the Parallax panel existed gains the tab, so the
// panel is reachable after an update instead of only on a fresh install.
func TestReconcileParallaxModuleAddsTabToPersistedRail(t *testing.T) {
	ueSetup(t)
	store := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	ueWrite(t, store, `{"frameBars":{"menus":{"quick-settings":{"anchor":"left","modules":["home","notifications","weather","capture","depth"]}}}}`)

	if r := reconcileParallaxModule(false); r.status != recFixed {
		t.Fatalf("status=%s, detail=%s", r.status.label(), r.detail)
	}
	got := mustRead(t, store)
	if !strings.Contains(got, `"parallax"`) || !strings.Contains(got, `"anchor": "left"`) {
		t.Fatalf("rail did not gain parallax while keeping its other keys:\n%s", got)
	}
	if r := reconcileParallaxModule(false); r.status != recOK {
		t.Fatalf("second run = %s (must be idempotent)", r.status.label())
	}
}
