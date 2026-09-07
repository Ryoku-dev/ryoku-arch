package doctor

import (
	"context"
	"os/exec"
	"strings"
	"time"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: the flatpak app channel ------------------------------------
//
// Ryoku ships the `flatpak` package in base.packages, which means it is in the
// ISO's offline closure and installs with no network. What it does NOT ship is a
// configured remote: until this reconciler, the only thing that ever added
// flathub was stash-install.sh, per-user, and only while installing a .flatpak
// bundle someone had already downloaded. So a fresh box had the client and no
// catalogue: `flatpak install <app>` failed with nothing to search, and the
// portable app channel the package set advertises did not exist.
//
// Adding the remote needs the network, and an offline install must stay quiet
// rather than warn about a thing it cannot do, so this is deliberately a no-op
// when flatpak is absent or the machine cannot reach flathub. The remote then
// appears on the first online `ryoku update`, which is the moment it becomes
// useful. That ordering is the whole design: ship the client offline, wire the
// catalogue when there is a network to wire it to.
//
// System scope, not --user: the desktop's own installs (the stash file drop) and
// anything the user installs by hand then share one catalogue and one runtime
// set, instead of duplicating several hundred megabytes of runtime per user.
const flathubRepo = "https://flathub.org/repo/flathub.flatpakrepo"

// Seams, so the reconciler's decision table is testable without a flatpak
// binary, a network, or a real remote.
var flatpakPresent = func() bool { return sys.Has("flatpak") }

func reconcileFlatpakRemote(checkOnly bool) recResult {
	if !flatpakPresent() {
		return okRes(i18n.T("no flatpak installed; the app channel is not needed"))
	}
	if flathubConfigured() {
		return okRes(i18n.T("the flathub remote is configured"))
	}
	// Offline is the expected state of a fresh offline install, so it is a note
	// rather than a warning: nothing is broken, the catalogue simply has not had
	// a network yet.
	if !flathubReachable() {
		return noteRes(i18n.T("no flathub remote yet, and flathub is not reachable to add one")).
			withFix(i18n.T("connect to a network and run `ryoku update`; it adds the remote"))
	}
	if checkOnly {
		return noteRes(i18n.T("the flathub remote is missing")).
			withFix(i18n.T("ryoku doctor (adds the flathub remote)"))
	}
	if err := addFlathub(); err != nil {
		return warnRes(i18n.T("could not add the flathub remote: %v"), err).
			withFix(i18n.T("add it by hand: sudo flatpak remote-add --if-not-exists flathub ") + flathubRepo)
	}
	return fixedRes(i18n.T("added the flathub remote, so flatpak apps can be installed and updated"))
}

// flathubConfigured reports whether any flathub remote is already known, in
// either scope. A user-scope remote (what stash-install.sh adds) is enough to
// resolve runtimes, so this must not fight it by adding a second one.
var flathubConfigured = func() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "flatpak", "remotes", "--columns=name").Output()
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(out), "\n") {
		if strings.EqualFold(strings.TrimSpace(line), "flathub") {
			return true
		}
	}
	return false
}

// flathubReachable is a cheap liveness probe, not a download: it asks flatpak
// itself to read the repo description. Bounded, because a captive portal will
// accept the connection and then never answer.
var flathubReachable = func() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "flatpak", "remote-info", "--log", "flathub", "org.freedesktop.Platform").Run() == nil ||
		exec.CommandContext(ctx, "curl", "-fsS", "--max-time", "6", "-o", "/dev/null", flathubRepo).Run() == nil
}

// A system-scope remote is a root write, so it goes through sudo the way every
// other privileged doctor step does. Bounded by flatpak's own behaviour rather
// than a context, matching sys.Run's shape.
var addFlathub = func() error {
	return sys.Sudo("flatpak", "remote-add", "--if-not-exists", "flathub", flathubRepo)
}
