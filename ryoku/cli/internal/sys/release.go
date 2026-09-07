package sys

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	i18n "ryoku-i18n"
)

// Package channels. A packaged box takes its Ryoku set from one [ryoku] repo
// directory, and which directory is the channel:
//
//	stable    x86_64/                  the pointer every installed box has; a
//	                                   byte copy of the newest frozen release
//	testing   channels/testing/x86_64/ rebuilt on every push to unstable-dev
//	v<tag>    releases/<tag>/x86_64/   one frozen release, never rewritten
//
// All of them live under RepoBase, the one bucket mount the repo domain
// serves (repo.ryoku.dev/stable/<key> is bucket object <key>; the "stable"
// segment is the mount, not the channel). publish-repo.yml writes them. The
// channel a box is on is nothing but the Server line of its [ryoku] stanza,
// so there is no second state to drift from it.
const RepoBase = "https://repo.ryoku.dev/stable"

const (
	ChannelStable  = "stable"
	ChannelTesting = "testing"
)

// PacmanConf is where the [ryoku] stanza lives; a var so tests point it at a
// fixture.
var PacmanConf = "/etc/pacman.conf"

// ReleaseFile is the pacman-owned marker ryoku-desktop ships naming the
// release a box runs; a var for tests.
var ReleaseFile = "/etc/ryoku-release"

// the shape stable-release.yml tags (bin/ryoku-release-bump): a core version
// with an optional alpha/beta/rc counter. a testing build's name
// (v0.56.0-beta.19.dev.363+g4d1cf63) is deliberately not one: nothing frozen
// stands behind it, so it can be neither tracked nor gone back to.
var releaseTagRe = regexp.MustCompile(`^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$`)

// IsReleaseTag reports whether s names a frozen release (v0.55.7-beta.19,
// v1.0.0), the shape stable-release.yml tags.
func IsReleaseTag(s string) bool { return releaseTagRe.MatchString(s) }

// ChannelServer is the [ryoku] Server line for a channel or release tag, or ""
// for a name that is neither.
func ChannelServer(channel string) string {
	switch {
	case channel == ChannelStable:
		return RepoBase + "/$arch"
	case channel == ChannelTesting:
		return RepoBase + "/channels/testing/$arch"
	case IsReleaseTag(channel):
		return RepoBase + "/releases/" + channel + "/$arch"
	}
	return ""
}

// ChannelOfServer maps a Server line back to its channel name: stable,
// testing, a release tag, or "" for a mirror Ryoku does not publish (a local
// build-repo.sh out/ tree, a private mirror), which is left alone everywhere.
func ChannelOfServer(server string) string {
	s := strings.TrimSpace(server)
	s = strings.TrimSuffix(strings.TrimSuffix(s, "/"), "$arch")
	s = strings.TrimSuffix(strings.TrimSuffix(s, "/"), "x86_64")
	s = strings.TrimSuffix(s, "/")
	if !strings.HasPrefix(s, RepoBase) {
		return ""
	}
	rest := strings.Trim(strings.TrimPrefix(s, RepoBase), "/")
	switch {
	case rest == "":
		return ChannelStable
	case rest == "channels/testing":
		return ChannelTesting
	case strings.HasPrefix(rest, "releases/"):
		if tag := strings.TrimPrefix(rest, "releases/"); IsReleaseTag(tag) {
			return tag
		}
	}
	return ""
}

// ChannelURL is the browsable base of a channel's x86_64 directory (Server with
// $arch resolved), used to read release.json.
func ChannelURL(channel string) string {
	return strings.Replace(ChannelServer(channel), "$arch", "x86_64", 1)
}

// RyokuServer returns the Server line of the [ryoku] stanza in pacman.conf, or
// "" when the stanza is absent.
func RyokuServer() string {
	b, err := os.ReadFile(PacmanConf)
	if err != nil {
		return ""
	}
	in := false
	sc := bufio.NewScanner(strings.NewReader(string(b)))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(line, "[") {
			in = line == "[ryoku]"
			continue
		}
		if in && strings.HasPrefix(line, "Server") {
			if i := strings.Index(line, "="); i >= 0 {
				return strings.TrimSpace(line[i+1:])
			}
		}
	}
	return ""
}

// PackagedChannel is the channel a packaged box follows: the channel its
// [ryoku] Server names, "" when there is no stanza or it points at a mirror
// Ryoku does not publish.
func PackagedChannel() string { return ChannelOfServer(RyokuServer()) }

// SetPackagedChannel rewrites the [ryoku] Server line to channel (stable,
// testing, or a release tag). It needs a stanza to rewrite; the doctor adds a
// missing one. Written through sudo install, so the file is replaced whole.
func SetPackagedChannel(channel string) error {
	server := ChannelServer(channel)
	if server == "" {
		return fmt.Errorf(i18n.T("unknown channel %q (stable, testing, or a release tag like v0.55.7-beta.19)"), channel)
	}
	b, err := os.ReadFile(PacmanConf)
	if err != nil {
		return err
	}
	lines := strings.Split(string(b), "\n")
	in, done := false, false
	for i, raw := range lines {
		line := strings.TrimSpace(raw)
		if strings.HasPrefix(line, "[") {
			in = line == "[ryoku]"
			continue
		}
		if in && strings.HasPrefix(line, "Server") && strings.Contains(line, "=") {
			lines[i] = "Server = " + server
			done = true
		}
	}
	if !done {
		return fmt.Errorf(i18n.T("no [ryoku] repo in %s; run `ryoku doctor` to add it"), PacmanConf)
	}
	if err := WriteRootFile(PacmanConf, strings.Join(lines, "\n"), "0644"); err != nil {
		return err
	}
	// the cached sync db describes the server the box just left; pacman only
	// refetches a db it thinks is newer, so a stale copy against a frozen
	// (older) release fails its signature check until it is gone.
	return DropRyokuSyncDB()
}

// DropRyokuSyncDB removes the cached [ryoku] sync db, its signature, and the
// files db. pacman refetches a db only when it thinks the server's is newer, so
// a cached db whose bytes no longer match its ryoku.db.sig wedges every
// transaction on "invalid or corrupted database (PGP signature)"; dropping it
// lets the next -Sy pull a matched pair. Callers refresh afterwards.
func DropRyokuSyncDB() error {
	names := []string{"ryoku.db", "ryoku.db.sig", "ryoku.files", "ryoku.files.sig"}
	paths := make([]string, len(names))
	for i, n := range names {
		paths[i] = filepath.Join(PacmanSyncDir, n)
	}
	// Remove directly when we own the sync dir (a test fixture under a temp dir);
	// the real root-owned /var/lib/pacman/sync falls back to sudo.
	if writableDir(PacmanSyncDir) {
		for _, p := range paths {
			if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
				return err
			}
		}
		return nil
	}
	return Sudo(append([]string{"rm", "-f"}, paths...)...)
}

// PacmanSyncDir holds pacman's cached sync dbs; a var so tests point it at a
// fixture and DropRyokuSyncDB never removes the real one.
var PacmanSyncDir = "/var/lib/pacman/sync"

// WriteRootFile replaces path whole with contents at the given mode. A target
// whose directory we can write (a user-owned file, a test fixture under a temp
// dir) is written in place; only a root-owned path like /etc falls back to
// sudo install. The in-place path keeps writers hermetic under a temp
// PacmanConf and never shells out to sudo in a unit test.
func WriteRootFile(path, contents, mode string) error {
	if writableDir(filepath.Dir(path)) {
		return writeFileAtomic(path, contents, fileMode(mode))
	}
	tmp, err := os.CreateTemp("", "ryoku-root-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(contents); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return Run("sudo", "install", "-D", "-m", mode, "-o", "root", "-g", "root", tmp.Name(), path)
}

// writableDir reports whether the current process can create a file in dir (a
// user-owned config dir or a test temp dir); a root-owned dir like /etc returns
// false so the caller escalates.
func writableDir(dir string) bool {
	f, err := os.CreateTemp(dir, ".ryoku-probe-*")
	if err != nil {
		return false
	}
	name := f.Name()
	f.Close()
	_ = os.Remove(name)
	return true
}

// writeFileAtomic writes contents to path via a temp file in the same directory
// and an atomic rename, so a reader never sees a half-written file.
func writeFileAtomic(path, contents string, mode os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".ryoku-tmp-*")
	if err != nil {
		return err
	}
	name := tmp.Name()
	if _, err := tmp.WriteString(contents); err != nil {
		tmp.Close()
		_ = os.Remove(name)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(name)
		return err
	}
	if err := os.Chmod(name, mode); err != nil {
		_ = os.Remove(name)
		return err
	}
	if err := os.Rename(name, path); err != nil {
		_ = os.Remove(name)
		return err
	}
	return nil
}

// fileMode parses an octal mode string ("0644") for the in-place writer,
// defaulting to 0644 for anything unparseable.
func fileMode(mode string) os.FileMode {
	if m, err := strconv.ParseUint(mode, 8, 32); err == nil {
		return os.FileMode(m)
	}
	return 0o644
}

// Release is /etc/ryoku-release: the named state a packaged box runs, written
// by the ryoku-desktop package from what build-repo.sh was told at publish.
type Release struct {
	Release string // v0.55.7-beta.19 on stable, v0.55.9.dev.412+gabc1234 on testing, local-* for a hand build
	Name    string // the line's name (CODENAME at the build, see release/names.md)
	Channel string // stable, testing, local
	Version string // the pacman pkgver
	Commit  string
	Date    string
}

// ReadRelease parses ReleaseFile; every field is "" when the file is absent
// (a box installed before releases were named; the next update carries it).
func ReadRelease() Release {
	var r Release
	b, err := os.ReadFile(ReleaseFile)
	if err != nil {
		return r
	}
	for _, line := range strings.Split(string(b), "\n") {
		k, v, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok {
			continue
		}
		v = strings.Trim(strings.TrimSpace(v), `"`)
		switch strings.TrimSpace(k) {
		case "RELEASE":
			r.Release = v
		case "NAME":
			r.Name = v
		case "CHANNEL":
			r.Channel = v
		case "VERSION":
			r.Version = v
		case "COMMIT":
			r.Commit = v
		case "DATE":
			r.Date = v
		}
	}
	return r
}
