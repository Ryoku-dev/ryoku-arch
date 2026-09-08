// Package ryotunesrelease is the update client for Ryotunes, an app Ryoku ships
// but does not build: it is released on its own cadence as a prebuilt Arch
// package on the ryoku-dev/ryotunes GitHub releases, and a Ryoku box tracks it by
// polling those releases directly rather than through the [ryoku] pacman repo.
//
// The package exposes exactly two operations, both context-bounded:
//
//	Check(ctx)   reports what is installed and what the latest published build
//	             is, without ever touching a package. It is what `ryoku doctor`
//	             calls, so it is cheap (a cached, bounded release lookup) and
//	             never mutates anything.
//	Upgrade(ctx) installs the latest build when it is strictly newer than what is
//	             installed. It is what `ryoku update` calls. It re-reads the
//	             release fresh (never a stale cache), verifies the downloaded
//	             package by sha256 and by its own pacman metadata (name, version,
//	             architecture) before it runs pacman, and only ever moves the
//	             version forward.
//
// Both refuse to invent good news: an offline box or a failed lookup returns an
// error, never a false "up to date", so the doctor and the updater can report
// "could not check" instead of silently claiming the box is current. Neither
// touches the network, and Upgrade never installs, when Ryotunes is not already
// installed: Ryoku tracks an app it has, it does not resurrect one the user
// removed.
package ryotunesrelease

import (
	"context"
	"time"
)

// Status is the outcome of a Check or an Upgrade.
//
//	Installed is the pacman version (pkgver-pkgrel, epoch included) currently
//	          installed, or "" when Ryotunes is not installed. After a successful
//	          Upgrade it is the version just installed.
//	Latest    is the newest published version discovered, or "" when Ryotunes is
//	          not installed (no lookup runs) or discovery was skipped.
//	Available reports that a strictly newer build exists than what is installed.
//	          Only Check sets it; a successful Upgrade clears it (nothing newer
//	          remains).
//	Updated   reports that Upgrade installed a newer build during this call.
type Status struct {
	Installed string
	Latest    string
	Available bool
	Updated   bool
}

// pkgName is the pacman package (and the GitHub asset prefix) this client tracks.
const pkgName = "ryotunes"

// wantArch is the only architecture Ryoku publishes and installs Ryotunes for.
// A package file that reports any other architecture is refused before pacman
// ever sees it.
const wantArch = "x86_64"

// checkCacheTTL bounds how often Check re-reads the GitHub release. `ryoku
// doctor` (and anything else polling availability) can run repeatedly; a cache
// this side of an hour keeps that off the network and well under GitHub's
// unauthenticated rate limit while staying fresh enough to notice a new release
// the same day. Upgrade ignores it and always fetches fresh.
const checkCacheTTL = time.Hour

// Check reports the installed and latest Ryotunes versions without mutating any
// package. It performs a bounded, cached release lookup; when Ryotunes is not
// installed it returns a zero Status and does no network at all. A lookup that
// fails with nothing cached returns an error rather than a false "up to date".
func Check(ctx context.Context) (Status, error) { return defaultClient().Check(ctx) }

// Upgrade installs the latest published Ryotunes when it is strictly newer than
// the installed build, and does nothing otherwise. It is a no-op (Updated false,
// no network, no install) when Ryotunes is not installed, so it never resurrects
// a removed app and never downgrades. The candidate package is verified by
// sha256 and by its own pacman metadata before it is installed through pacman.
func Upgrade(ctx context.Context) (Status, error) { return defaultClient().Upgrade(ctx) }

// Check is the Client-scoped implementation behind the package-level Check.
func (c *Client) Check(ctx context.Context) (Status, error) {
	installed := c.installedVersion(pkgName)
	if installed == "" {
		// Not installed: Ryoku only tracks an app the box already has, so there
		// is nothing to compare and no reason to touch the network.
		return Status{}, nil
	}

	rel, err := c.latestRelease(ctx, false)
	if err != nil {
		// Offline or a failed lookup: report what we know (the installed
		// version) and surface the error. Never claim "up to date".
		return Status{Installed: installed}, err
	}

	newer, err := c.isNewer(rel.Version, installed)
	if err != nil {
		return Status{Installed: installed, Latest: rel.Version}, err
	}
	return Status{Installed: installed, Latest: rel.Version, Available: newer}, nil
}

// Upgrade is the Client-scoped implementation behind the package-level Upgrade.
func (c *Client) Upgrade(ctx context.Context) (Status, error) {
	installed := c.installedVersion(pkgName)
	if installed == "" {
		// Not installed: do not install, do not fetch. Upgrading an app the box
		// does not have would be installing it, which is not this path's job.
		return Status{}, nil
	}

	// Fresh, never a stale cache: an install decision must be made against what
	// GitHub serves right now, not a lookup Check left behind minutes ago.
	rel, err := c.latestRelease(ctx, true)
	if err != nil {
		return Status{Installed: installed}, err
	}

	newer, err := c.isNewer(rel.Version, installed)
	if err != nil {
		return Status{Installed: installed, Latest: rel.Version}, err
	}
	if !newer {
		// Already current or ahead: nothing to install. Never downgrade.
		return Status{Installed: installed, Latest: rel.Version}, nil
	}

	if err := c.installRelease(ctx, rel); err != nil {
		return Status{Installed: installed, Latest: rel.Version, Available: true}, err
	}
	// Installed the new build: it is now what is installed, and nothing newer
	// remains to offer.
	return Status{Installed: rel.Version, Latest: rel.Version, Updated: true}, nil
}

// isNewer reports whether latest is strictly greater than installed under
// pacman's own version ordering (epoch, pkgver, pkgrel), so an epoch bump or a
// pkgrel-only rebuild is compared the same way pacman would.
func (c *Client) isNewer(latest, installed string) (bool, error) {
	cmp, err := c.vercmp(latest, installed)
	if err != nil {
		return false, err
	}
	return cmp > 0, nil
}
