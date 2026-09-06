package doctor

import (
	"strings"
	"testing"
)

func TestPlanShippedApps(t *testing.T) {
	apps := []shippedApp{
		{"kitty", "terminal"},
		{"neovim", "editor"},
		{"ryotunes", "music"},
		{"mangohud", "overlay"},
	}
	// kitty: present as a dependency; neovim: present and ledgered;
	// ryotunes: ledgered and gone; mangohud: never seen.
	plan := planShippedApps(apps,
		map[string]bool{"kitty": true, "neovim": true},
		map[string]bool{"kitty": true},
		map[string]bool{"neovim": true, "ryotunes": true},
	)
	if got := strings.Join(plan.install, ","); got != "mangohud" {
		t.Errorf("install = %q, want mangohud", got)
	}
	if got := strings.Join(plan.removed, ","); got != "ryotunes" {
		t.Errorf("removed = %q, want ryotunes", got)
	}
	if got := strings.Join(plan.adopt, ","); got != "kitty" {
		t.Errorf("adopt = %q, want kitty", got)
	}
	if got := strings.Join(plan.explicit, ","); got != "kitty" {
		t.Errorf("explicit = %q, want kitty", got)
	}
}

func TestReconcileShippedAppsLeavesRemovedAppsRemoved(t *testing.T) {
	// everything present except the two the user deleted after Ryoku installed them
	present := map[string]bool{}
	for _, a := range shippedApps() {
		present[a.pkg] = true
	}
	delete(present, "kitty")
	delete(present, "ryotunes")
	withShippedAppTestState(t, present)
	recordProvisioned("kitty")
	recordProvisioned("ryotunes")
	for pkg := range present {
		recordProvisioned(pkg)
	}
	var installs [][]string
	installShippedApps = func(pkgs []string) { installs = append(installs, pkgs) }

	got := reconcileShippedApps(false)
	if len(installs) != 0 {
		t.Fatalf("installed %v; a removed app must stay removed", installs)
	}
	if got.status != recNote || !strings.Contains(got.detail, "kitty") {
		t.Fatalf("result = %+v, want a note naming kitty", got)
	}
}

func TestReconcileShippedAppsDeliversOnce(t *testing.T) {
	present := map[string]bool{}
	withShippedAppTestState(t, present)

	var runs int
	installShippedApps = func(pkgs []string) {
		runs++
		for _, p := range pkgs {
			present[p] = true
		}
	}

	if got := reconcileShippedApps(false); got.status != recFixed {
		t.Fatalf("first run = %+v, want fixed", got)
	}
	if runs != 1 {
		t.Fatalf("pacman runs = %d, want one transaction for the whole set", runs)
	}
	for _, a := range shippedApps() {
		if !provisioned()[a.pkg] {
			t.Fatalf("%s installed but not ledgered; a later removal would be undone", a.pkg)
		}
	}
	if got := reconcileShippedApps(false); got.status != recOK || runs != 1 {
		t.Fatalf("second run = %+v (runs=%d), want ok with no further install", got, runs)
	}
}

func TestReconcileShippedAppsCheckOnly(t *testing.T) {
	withShippedAppTestState(t, nil)
	installShippedApps = func(pkgs []string) { t.Fatalf("check mode installed %v", pkgs) }
	markAppsExplicit = func(pkgs []string) { t.Fatalf("check mode changed ownership of %v", pkgs) }

	if got := reconcileShippedApps(true); got.status != recWouldFix {
		t.Fatalf("result = %+v, want todo", got)
	}
}

func TestReconcileShippedAppsClaimsDependencyInstalls(t *testing.T) {
	all := map[string]bool{}
	for _, a := range shippedApps() {
		all[a.pkg] = true
	}
	withShippedAppTestState(t, all)
	appInstalledAsDep = func(pkg string) bool { return pkg == "kitty" }

	var claimed []string
	markAppsExplicit = func(pkgs []string) { claimed = append(claimed, pkgs...) }

	got := reconcileShippedApps(false)
	if got.status != recFixed || strings.Join(claimed, ",") != "kitty" {
		t.Fatalf("result = %+v, claimed = %v", got, claimed)
	}
}

// withShippedAppTestState isolates the ledger and stubs every pacman seam;
// present lists the installed packages (nil = none).
func withShippedAppTestState(t *testing.T, present map[string]bool) {
	t.Helper()
	isolateProvisioned(t)
	oldInstalled, oldDep := appInstalled, appInstalledAsDep
	oldInstall, oldExplicit := installShippedApps, markAppsExplicit
	oldHas := hasPacman
	appInstalled = func(pkg string) bool { return present[pkg] }
	appInstalledAsDep = func(string) bool { return false }
	installShippedApps = func([]string) {}
	markAppsExplicit = func([]string) {}
	hasPacman = func() bool { return true } // the CI runner has no pacman
	t.Cleanup(func() {
		appInstalled, appInstalledAsDep = oldInstalled, oldDep
		installShippedApps, markAppsExplicit = oldInstall, oldExplicit
		hasPacman = oldHas
	})
}
