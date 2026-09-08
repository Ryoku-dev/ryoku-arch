package updater

import (
	"context"
	"time"

	"ryoku-cli/internal/ryotunesrelease"
)

// externalReleasePkgs are packages tracked on their own GitHub release channel
// (Upgrade/Check here), not through the [ryoku] pacman repo. pendingUpdates
// filters them out of the distribution lane so `ryoku status` reports Ryotunes
// once, in the Ryoku lane the update button runs (addRyotunesUpdate), never
// twice.
var externalReleasePkgs = map[string]bool{"ryotunes": true}

// upgradeRyotunes moves Ryotunes to its latest published GitHub release as part
// of `ryoku update`. Ryotunes is released on its own cadence as a prebuilt Arch
// package (ryoku-dev/ryotunes releases), not through the [ryoku] pacman repo, so
// it updates on its own channel: internal/ryotunesrelease re-reads the release
// fresh, verifies the download by sha256 and by its own pacman metadata (name,
// version, x86_64), installs it with pacman -U, and only ever moves the version
// forward. It runs on every `ryoku update` channel (git checkout and packaged)
// and outside the [ryoku] package set, so a box with no Ryoku changes still
// picks up a new Ryotunes.
//
// Best-effort, like the AUR and Flatpak lanes: a failure is reported and never
// fails the whole update, and an offline or failed check is never rendered as
// "up to date". Not installed -> nothing to do: Upgrade does no network and
// installs nothing, so a Ryotunes the user removed is not resurrected.
func upgradeRyotunes() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	st, err := ryotunesrelease.Upgrade(ctx)
	switch {
	case err != nil:
		progress.logf("Could not update Ryotunes: %v", err)
	case st.Installed == "":
		// Ryotunes is not installed; nothing to update (a removal stays removed).
	case st.Updated:
		progress.logf("Ryotunes updated to %s", st.Latest)
	default:
		progress.logf("Ryotunes is current (%s)", st.Installed)
	}
}

// addRyotunesUpdate folds a pending Ryotunes release into the Ryoku-lane report
// so `ryoku status --json` (the Updates page and the island) reflects it the
// same as a Ryoku package bump: `ryoku update` installs it, so it belongs in the
// lane the update button runs, not the distribution lane. Bounded and read-only
// -- Check never installs and does no network when Ryotunes is absent. An error
// or an up-to-date box adds nothing and never clears the rest of the report, so
// an offline poll is never rendered as a spurious update nor as a false
// "current".
func addRyotunesUpdate(r *statusReport) {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	st, err := ryotunesrelease.Check(ctx)
	if err != nil || !st.Available {
		return
	}
	r.Updates = append(r.Updates, updateItem{Name: "ryotunes", Old: st.Installed, New: st.Latest})
	r.Behind++
	r.Available = true
}
