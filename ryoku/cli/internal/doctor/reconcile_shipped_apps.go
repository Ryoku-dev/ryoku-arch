package doctor

import (
	"context"
	"fmt"
	"os/exec"
	"sort"
	"strings"
	"time"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: the apps Ryoku ships, and the user's right to delete them --
//
// The user-facing applications left ryoku-desktop's depends: pacman re-satisfies
// a dependency list on every upgrade of that package, so a hard depend put back
// apps people had deleted on purpose. They arrive here instead -- installed once
// per box, ledgered, and never pushed back after a removal. The ISO still
// pacstraps them from system/packages/base.packages.
//
// Present apps are also marked explicitly installed: outside depends they are
// orphan candidates, and one `pacman -Qtdq | pacman -Rns -` would take them.

type shippedApp struct {
	pkg  string
	what string
}

// Membership rule: a standalone application whose absence costs only itself.
// Tools the shell calls by name (grim, playerctl, matugen, cava, mpv for the
// launcher's radio, the pill's OCR/capture backends) stay hard depends, because
// losing them breaks a Ryoku surface the user never touched.
// Ryotunes has its own official-release install/reconciliation path.
func shippedApps() []shippedApp {
	return []shippedApp{
		{"kitty", "the default terminal (Settings > App Overrides repoints the terminal role)"},
		{"fish", "the optional interactive shell"},
		{"blesh", "Bash line editor"},
		{"starship", "the shell prompt"},
		{"fastfetch", "system summary (launcher, RyoStore covers)"},
		{"yazi", "terminal file manager"},
		{"neovim", "the shipped editor"},
		{"nautilus", "the graphical file manager"},
		{"nautilus-python", "the Ryoku stash actions in Nautilus' right-click menu"},
		{"ryomotion", "the screen-demo recorder and editor"},
		{"waifu2x-ncnn-vulkan", "AI upscale behind ryoshot Beautify HD and ryowalls Enhance"},
		{"pavucontrol", "the GUI mixer the bar's Open audio button launches"},
		{"songrec", "Recognize Music in the launcher"},
		{"openrgb", "keyboard and mouse lighting (Settings > Appearance > Lighting)"},
		{"gamescope", "the nested gaming micro-compositor"},
		{"gamemode", "the gaming performance governor Steam invokes"},
		{"mangohud", "the in-game FPS and frametime overlay"},
	}
}

type appPlan struct {
	install  []string // never seen here and absent: deliver once
	removed  []string // ledgered and gone: the user's call, honoured
	adopt    []string // present but unrecorded: ledger it
	explicit []string // present and installed-as-dependency: re-mark explicit
}

// planShippedApps is the three-way rule, pure so it is tested without pacman.
func planShippedApps(apps []shippedApp, installed, asDep, seen map[string]bool) appPlan {
	var p appPlan
	for _, a := range apps {
		switch {
		case installed[a.pkg]:
			if !seen[a.pkg] {
				p.adopt = append(p.adopt, a.pkg)
			}
			if asDep[a.pkg] {
				p.explicit = append(p.explicit, a.pkg)
			}
		case seen[a.pkg]:
			p.removed = append(p.removed, a.pkg)
		default:
			p.install = append(p.install, a.pkg)
		}
	}
	return p
}

// Seams: the live box's answers, replaced in tests.
var (
	appInstalled = func(pkg string) bool { return sys.PkgInstalled(pkg) }
	// `pacman -Qdq <pkg>` succeeds only for a package installed as a dependency.
	appInstalledAsDep = func(pkg string) bool {
		return exec.Command("pacman", "-Qdq", pkg).Run() == nil
	}
	// One transaction for the whole missing set, bounded, and best-effort: a box
	// with no network must not fail `ryoku update` over an app.
	installShippedApps = func(pkgs []string) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		defer cancel()
		args := append([]string{"pacman", "-S", "--needed", "--noconfirm"}, pkgs...)
		_ = exec.CommandContext(ctx, "sudo", args...).Run()
	}
	markAppsExplicit = func(pkgs []string) {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		args := append([]string{"pacman", "-D", "--asexplicit", "--quiet"}, pkgs...)
		_ = exec.CommandContext(ctx, "sudo", args...).Run()
	}
	hasPacman = func() bool { return sys.Has("pacman") }
)

func reconcileShippedApps(checkOnly bool) recResult {
	if !hasPacman() {
		return okRes(i18n.T("not a pacman box; shipped apps are the installer's business"))
	}
	apps := shippedApps()
	installed, asDep := map[string]bool{}, map[string]bool{}
	for _, a := range apps {
		if appInstalled(a.pkg) {
			installed[a.pkg] = true
			asDep[a.pkg] = appInstalledAsDep(a.pkg)
		}
	}
	plan := planShippedApps(apps, installed, asDep, provisioned())

	if len(plan.install) == 0 && len(plan.adopt) == 0 && len(plan.explicit) == 0 {
		if len(plan.removed) > 0 {
			return noteRes(i18n.T("%s stay removed (you deleted them; Ryoku does not put them back)"),
				strings.Join(plan.removed, ", "))
		}
		return okRes(i18n.T("every shipped app is present and owned by you"))
	}
	if checkOnly {
		var parts []string
		if len(plan.install) > 0 {
			parts = append(parts, i18n.Tf("would install %s", strings.Join(plan.install, ", ")))
		}
		if len(plan.explicit) > 0 || len(plan.adopt) > 0 {
			parts = append(parts, fmt.Sprintf(i18n.T("would take ownership of %d present app(s)"),
				len(union(plan.adopt, plan.explicit))))
		}
		return wouldRes("%s", strings.Join(parts, "; ")).
			withFix(i18n.T("run `ryoku doctor` (or `ryoku update`) to apply"))
	}

	// Ownership first: it cannot fail the run, and it protects what is already
	// here even if the install half finds no mirror.
	if len(plan.explicit) > 0 {
		markAppsExplicit(plan.explicit)
	}
	for _, pkg := range plan.adopt {
		recordProvisioned(pkg)
	}

	var landed, missed []string
	if len(plan.install) > 0 {
		installShippedApps(plan.install)
		for _, pkg := range plan.install {
			if appInstalled(pkg) {
				recordProvisioned(pkg)
				landed = append(landed, pkg)
			} else {
				missed = append(missed, pkg)
			}
		}
		if len(landed) > 0 {
			markAppsExplicit(landed)
		}
	}

	switch {
	case len(missed) > 0 && len(landed) > 0:
		return warnRes(i18n.T("installed %s; %s did not land"), strings.Join(landed, ", "), strings.Join(missed, ", ")).
			withFix("sudo pacman -S %s", strings.Join(missed, " "))
	case len(missed) > 0:
		return warnRes(i18n.T("%s could not be installed"), strings.Join(missed, ", ")).
			withFix("sudo pacman -Sy && sudo pacman -S %s", strings.Join(missed, " "))
	case len(landed) > 0:
		return fixedRes(i18n.T("installed %s (delete any of them and Ryoku will not reinstall it)"),
			strings.Join(landed, ", "))
	}
	return fixedRes(i18n.T("took ownership of %d shipped app(s) so an orphan sweep cannot remove them"),
		len(union(plan.adopt, plan.explicit)))
}

func union(a, b []string) []string {
	seen := map[string]bool{}
	for _, s := range append(append([]string{}, a...), b...) {
		seen[s] = true
	}
	out := make([]string, 0, len(seen))
	for s := range seen {
		out = append(out, s)
	}
	sort.Strings(out)
	return out
}
