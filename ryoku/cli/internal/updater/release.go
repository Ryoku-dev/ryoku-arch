package updater

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// channelRelease is release.json as build-repo.sh writes it beside a channel's
// db: which release that channel serves right now.
type channelRelease struct {
	Release string `json:"release"`
	Name    string `json:"name"`
	Channel string `json:"channel"`
	Version string `json:"version"`
	Commit  string `json:"commit"`
	Date    string `json:"date"`
}

// releaseLedger is releases/index.json, the list publish-repo.yml appends a
// stable release to; `ryoku rollback` offers its entries.
type releaseLedger struct {
	Latest   string          `json:"latest"`
	Releases []ledgerRelease `json:"releases"`
}

type ledgerRelease struct {
	Tag     string `json:"tag"`
	Name    string `json:"name"`
	Version string `json:"version"`
	Commit  string `json:"commit"`
	Date    string `json:"date"`
	Repo    string `json:"repo"`
}

// releaseFetchTTL bounds how often `ryoku status` (polled by the Hub and the
// update island) re-reads a channel's release.json.
const releaseFetchTTL = 10 * time.Minute

// RYOKU_RELEASE_BASE overrides RepoBase for tests and a local mirror.
func repoBase() string {
	if b := strings.TrimSpace(os.Getenv("RYOKU_RELEASE_BASE")); b != "" {
		return strings.TrimSuffix(b, "/")
	}
	return sys.RepoBase
}

// fetchCached GETs url into a state-dir cache keyed by name, re-fetching
// after ttl; offline or on error it serves the last cached body, or nil.
func fetchCached(name, url string, ttl time.Duration) []byte {
	dir := filepath.Join(sys.StateDir(), "release-cache")
	path := filepath.Join(dir, name)
	if st, err := os.Stat(path); err == nil && time.Since(st.ModTime()) < ttl {
		if b, err := os.ReadFile(path); err == nil {
			return b
		}
	}
	client := &http.Client{Timeout: 6 * time.Second}
	resp, err := client.Get(url)
	if err == nil {
		defer resp.Body.Close()
		if resp.StatusCode == http.StatusOK {
			if b, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20)); err == nil {
				_ = os.MkdirAll(dir, 0o755)
				_ = os.WriteFile(path, b, 0o644)
				return b
			}
		}
	}
	if b, err := os.ReadFile(path); err == nil {
		return b
	}
	return nil
}

// channelServes reads what a channel currently serves, or a zero value when
// the channel is unreachable and nothing is cached.
func channelServes(channel string) channelRelease {
	var r channelRelease
	url := strings.Replace(sys.ChannelServer(channel), sys.RepoBase, repoBase(), 1)
	url = strings.Replace(url, "$arch", "x86_64", 1)
	if url == "" {
		return r
	}
	if b := fetchCached("channel-"+sanitize(channel)+".json", url+"/release.json", releaseFetchTTL); b != nil {
		_ = json.Unmarshal(b, &r)
	}
	return r
}

// ledger reads the release ledger, newest first.
func ledger() releaseLedger {
	var l releaseLedger
	if b := fetchCached("releases-index.json", repoBase()+"/releases/index.json", releaseFetchTTL); b != nil {
		_ = json.Unmarshal(b, &l)
	}
	return l
}

func sanitize(s string) string {
	return strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '.' || r == '-' {
			return r
		}
		return '_'
	}, s)
}

// Track moves a box onto a package channel: stable (the pointer every install
// starts on), testing (rebuilt on every push to unstable-dev), or a release
// tag (pinned to that frozen release until tracked away). It rewrites the
// [ryoku] Server line and runs an update, which moves the Ryoku set to whatever
// the channel serves, down as well as up. A box whose updates currently come
// from a source checkout is migrated onto packages first: the checkout is
// retired as the update source (the ~/ryoku-arch clone stays on disk but no
// longer drives updates). Building from a checkout is `ryoku track ... --source`.
func Track(channel string) error {
	if sys.ChannelServer(channel) == "" {
		return fmt.Errorf(i18n.T("unknown channel %q: stable, testing, or a release tag (see `ryoku rollback` for the list)"), channel)
	}
	source := sys.SourceTracked()
	install := !sys.PkgInstalled("ryoku-desktop")
	// A pure source box with no ryoku-desktop and no [ryoku] repo to install it
	// from cannot be moved onto packages here; the doctor adds the repo first.
	if install && sys.RyokuServer() == "" {
		return fmt.Errorf(i18n.T("no ryoku-desktop package and no [ryoku] repo to install it from; run `ryoku doctor` to add the repo, then `ryoku track %s`"), channel)
	}
	// A deliberate private mirror (a Server Ryoku does not publish) is never
	// silently overwritten, unless we are migrating a source box off its checkout.
	if !source && sys.PackagedChannel() == "" && sys.RyokuServer() != "" {
		return fmt.Errorf(i18n.T("the [ryoku] repo points at %s, a mirror Ryoku does not publish; edit %s by hand"), sys.RyokuServer(), sys.PacmanConf)
	}
	// Already on the channel, package box, nothing to migrate: only move the set
	// if the channel now serves something newer than what is installed.
	if !source && !install && sys.PackagedChannel() == channel {
		if serves := channelServes(channel).Release; serves == "" || serves == sys.ReadRelease().Release {
			fmt.Printf(i18n.T("already on %s\n"), channel)
			return nil
		}
		fmt.Printf(i18n.T("==> Already tracking %s; moving the Ryoku set to what it serves\n"), channel)
		return runChannelUpdate()
	}

	migrated, err := switchToPackageChannel(channel)
	if err != nil {
		return err
	}
	if migrated {
		clearSessionChannelEnv()
		fmt.Println(i18n.T("==> Retired the source checkout as the update source; the ~/ryoku-arch clone stays on disk but no longer drives updates."))
	}
	switch {
	case channel == sys.ChannelTesting:
		fmt.Println(i18n.T("==> Now tracking testing packages: rebuilt on every push to unstable-dev. `ryoku track main` returns to stable releases."))
	case sys.IsReleaseTag(channel):
		fmt.Printf(i18n.T("==> Pinned to release %s. `ryoku update` keeps this release; `ryoku track main` follows releases again.\n"), channel)
	default:
		fmt.Println(i18n.T("==> Now tracking stable packages: named releases as they are published."))
	}
	if install {
		fmt.Println(i18n.T("==> ryoku-desktop is not installed here; the channel switch installs it from the selected channel."))
	}
	fmt.Println(i18n.T("==> Updates now come from packages: `ryoku update` runs pacman."))
	return runChannelUpdate()
}

// switchToPackageChannel performs the filesystem side of a packaged track:
// migrate a source-tracked box off its checkout (retire tracking, keep the
// clone) and rewrite the [ryoku] Server to channel. It touches no pacman and no
// network, so it is unit-testable; the caller runs the pacman side after.
func switchToPackageChannel(channel string) (migrated bool, err error) {
	if sys.SourceTracked() {
		if err := sys.RetireSourceTracking(); err != nil {
			return false, fmt.Errorf(i18n.T("could not retire the source checkout: %w"), err)
		}
		migrated = true
	}
	if err := sys.SetPackagedChannel(channel); err != nil {
		return migrated, err
	}
	return migrated, nil
}

// runChannelUpdate is the pacman side of a track (the forced -Syyu plus an
// explicit -S ryoku-desktop, which installs it when absent and moves the set in
// either direction). A var so a test exercises the switch without running pacman.
var runChannelUpdate = func() error { return Update([]string{"--channel-switch"}) }

// clearSessionChannelEnv drops RYOKU_CHANNEL from the running user manager and
// the D-Bus activation env (the reverse of bin/ryoku-track), so units and apps
// launched after a migration no longer carry the stale channel. Best-effort and
// a var so a test never touches the real session.
var clearSessionChannelEnv = func() {
	_ = exec.Command("systemctl", "--user", "unset-environment", "RYOKU_CHANNEL").Run()
	_ = exec.Command("dbus-update-activation-environment", "RYOKU_CHANNEL=").Run()
	os.Unsetenv("RYOKU_CHANNEL")
}
