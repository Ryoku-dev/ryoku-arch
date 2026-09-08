package main

import (
	"fmt"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
	"ryoku-cli/internal/updater"
	i18n "ryoku-i18n"
	"strings"
)

// where the track script lives, for boxes with no local checkout that ask to
// build from source (`--source`). Always the main copy: the stable script moves
// a box in either direction, so a packaged box can still reach it.
const trackURL = "https://raw.githubusercontent.com/ryoku-dev/ryoku-arch/main/bin/ryoku-track"

// sourceChannels are the git branches `ryoku track ... --source` builds from.
var sourceChannels = map[string]bool{"main": true, "unstable-dev": true}

// cmdTrack points the box at an update channel. By default a track selects a
// package channel and hands off to updater.Track (which rewrites the [ryoku]
// Server and runs an update): the branch aliases a tester knows map to their
// channels -- `unstable-dev` == `testing`, `main` == `stable` -- and stable,
// testing, and a release tag pass through. `--source` (either order) instead
// builds the box from a git checkout via bin/ryoku-track, the developer path.
func cmdTrack(args []string) error {
	channel, source, err := parseTrackArgs(args)
	if err != nil {
		return err
	}
	if source {
		if !sourceChannels[channel] {
			return fmt.Errorf(i18n.T("`--source` builds from a checkout and takes main or unstable-dev, not %q"), channel)
		}
		return trackFromSource(channel)
	}
	pkg := packageChannelFor(channel)
	if pkg == "" {
		return fmt.Errorf(i18n.T("unknown channel %q\n"+
			"  packaged: stable, testing, unstable-dev, main, or a release tag (v0.55.7-beta.19)\n"+
			"  source:   main or unstable-dev, with --source"), channel)
	}
	return updater.Track(pkg)
}

// parseTrackArgs pulls the one channel and the optional --source flag (either
// order) out of the track arguments.
func parseTrackArgs(args []string) (channel string, source bool, err error) {
	for _, a := range args {
		switch {
		case a == "--source":
			source = true
		case strings.HasPrefix(a, "-"):
			return "", false, fmt.Errorf(i18n.T("unknown flag %q (only --source is accepted)"), a)
		case channel != "":
			return "", false, fmt.Errorf(i18n.T("track takes one channel, got %q and %q"), channel, a)
		default:
			channel = a
		}
	}
	if channel == "" {
		return "", false, fmt.Errorf(i18n.T("usage: ryoku track <stable|testing|unstable-dev|main|v<release>>\n" +
			"       ryoku track <main|unstable-dev> --source   (build from a git checkout)"))
	}
	return channel, source, nil
}

// packageChannelFor maps a track argument to the package channel it selects:
// unstable-dev is testing (rebuilt on every push), main is stable (named
// releases); stable, testing, and a release tag pass through. "" for anything
// that names no package channel.
func packageChannelFor(name string) string {
	switch name {
	case "unstable-dev":
		return sys.ChannelTesting
	case "main":
		return sys.ChannelStable
	}
	if sys.ChannelServer(name) != "" {
		return name
	}
	return ""
}

// trackFromSource hands off to bin/ryoku-track, which builds and deploys the box
// from a git checkout of the branch. It prefers a local checkout's copy and
// otherwise fetches the canonical one, so `--source` works from a packaged
// install with no checkout. The script does the real work and does not lean on
// this binary.
func trackFromSource(channel string) error {
	if repo := sys.ResolveRepo(); repo != "" {
		if script := filepath.Join(repo, "bin", "ryoku-track"); sys.Exists(script) {
			return sys.Run("bash", script, channel)
		}
	}
	if !sys.Has("curl") {
		return fmt.Errorf(i18n.T("no local track script and curl is missing; run it by hand:\n  curl -fsSL %s | bash -s -- %s"), trackURL, channel)
	}
	tmp, err := os.CreateTemp("", "ryoku-track-*.sh")
	if err != nil {
		return err
	}
	tmp.Close()
	defer os.Remove(tmp.Name())
	if err := sys.Run("curl", "-fsSL", trackURL, "-o", tmp.Name()); err != nil {
		return fmt.Errorf(i18n.T("fetch track script from %s: %w"), trackURL, err)
	}
	return sys.Run("bash", tmp.Name(), channel)
}
