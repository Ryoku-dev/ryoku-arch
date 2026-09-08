package main

import (
	"fmt"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
	"ryoku-cli/internal/updater"
)

// where the track script lives, for boxes with no local checkout (a packaged
// install switching onto a dev channel). Always the main copy: the stable script
// moves a box in either direction, so a packaged main box can still reach it.
const trackURL = "https://raw.githubusercontent.com/ryoku-dev/ryoku-arch/main/bin/ryoku-track"

// the two git channels a checkout box can track: the stable branch everyone
// runs and the bleeding edge rebuilt from source. a packaged box tracks
// package channels instead (stable, testing, or a release tag), which
// updater.Track serves without a checkout.
var trackChannels = map[string]bool{"main": true, "unstable-dev": true}

// cmdTrack points the box at an update channel (main or unstable-dev) so
// `ryoku update` follows it. It hands off to bin/ryoku-track, preferring a local
// checkout's copy and otherwise fetching the canonical one. The script does the
// real work (build tools, checkout, channel, redeploy) and does not lean on this
// binary, so switching still works from a packaged install with no checkout.
func cmdTrack(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("usage: ryoku track <stable|testing|v<release>>   (packaged box)\n       ryoku track <main|unstable-dev>            (checkout box)")
	}
	ch := args[0]
	if sys.ChannelServer(ch) != "" {
		return updater.Track(ch)
	}
	if !trackChannels[ch] {
		return fmt.Errorf("unknown channel %q (packaged: stable, testing, or a release tag; checkout: main or unstable-dev)", ch)
	}
	if repo := sys.ResolveRepo(); repo != "" {
		if script := filepath.Join(repo, "bin", "ryoku-track"); sys.Exists(script) {
			return sys.Run("bash", append([]string{script}, args...)...)
		}
	}

	if !sys.Has("curl") {
		return fmt.Errorf("no local track script and curl is missing; run it by hand:\n  curl -fsSL %s | bash -s -- %s", trackURL, ch)
	}
	tmp, err := os.CreateTemp("", "ryoku-track-*.sh")
	if err != nil {
		return err
	}
	tmp.Close()
	defer os.Remove(tmp.Name())
	if err := sys.Run("curl", "-fsSL", trackURL, "-o", tmp.Name()); err != nil {
		return fmt.Errorf("fetch track script from %s: %w", trackURL, err)
	}
	return sys.Run("bash", append([]string{tmp.Name()}, args...)...)
}
