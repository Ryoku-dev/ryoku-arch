package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// restoreDaemon builds a daemon whose cache/config/state all point at temp
// dirs, so restoreOutputs runs against a controlled outputs.json without
// touching the real home.
func restoreDaemon(t *testing.T) (*daemon, string) {
	t.Helper()
	root := t.TempDir()
	cache := filepath.Join(root, "cache")
	if err := os.MkdirAll(cache, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(root, "state"))
	d := &daemon{surface: newWallSurface()}
	d.cfg.Paths.Cache = cache
	return d, cache
}

// A stored static choice whose file is not present yet must be reported as
// unapplied (the login-race signal the startup retry keys on) and must never
// publish a bogus frame; once the file lands the same choice applies and the
// frame carries it. This is the regression: restoreOutputs used to give up on
// the missing file with no way for the caller to know it had to retry, leaving
// the desktop on the empty grey frame until a manual wallpaper set.
func TestRestoreRetriesUntilFilePresent(t *testing.T) {
	d, cache := restoreDaemon(t)
	pic := filepath.Join(t.TempDir(), "wall.png")
	if err := os.WriteFile(filepath.Join(cache, "outputs.json"),
		[]byte(`{"*":{"type":"static","path":"`+pic+`"}}`), 0o644); err != nil {
		t.Fatal(err)
	}

	if want, applied := d.restoreOutputs(); want != 1 || applied != 0 {
		t.Fatalf("missing file: want/applied = %d/%d, expected 1/0", want, applied)
	}
	if got := d.surface.snapshot().Default.Path; got != "" {
		t.Fatalf("a missing file must not publish a frame, got %q", got)
	}

	writeE2EPNG(t, pic)
	if want, applied := d.restoreOutputs(); want != 1 || applied != 1 {
		t.Fatalf("present file: want/applied = %d/%d, expected 1/1", want, applied)
	}
	if got := d.surface.snapshot().Default.Path; got != pic {
		t.Fatalf("restored frame path = %q, want %q", got, pic)
	}
}

// No stored choice is not a failure: want is zero, so the caller neither
// retries nor treats the empty frame as a login race (first run, restore off).
func TestRestoreNoChoiceIsNotPending(t *testing.T) {
	d, _ := restoreDaemon(t)
	if want, applied := d.restoreOutputs(); want != 0 || applied != 0 {
		t.Fatalf("no outputs.json: want/applied = %d/%d, expected 0/0", want, applied)
	}
}

// A box upgraded across the Ryogami split has the pre-split state file but an
// empty outputs.json; the daemon seeds outputs.json from it once so the
// wallpaper survives the upgrade, and never overwrites a choice already set
// through Ryogami.
func TestMigrateLegacyOutputs(t *testing.T) {
	d, cache := restoreDaemon(t)
	pic := filepath.Join(t.TempDir(), "old.png")
	writeE2EPNG(t, pic)
	state := filepath.Join(os.Getenv("XDG_STATE_HOME"))
	if err := os.MkdirAll(state, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(state, "ryoku-wallpaper.json"),
		[]byte(`{"default":"`+pic+`","outputs":{}}`), 0o644); err != nil {
		t.Fatal(err)
	}

	d.migrateLegacyOutputs()
	if want, applied := d.restoreOutputs(); want != 1 || applied != 1 {
		t.Fatalf("after migration: want/applied = %d/%d, expected 1/1", want, applied)
	}
	if got := d.surface.snapshot().Default.Path; got != pic {
		t.Fatalf("migrated wallpaper path = %q, want %q", got, pic)
	}

	// A real Ryogami choice already present is never clobbered by the seed.
	newer := filepath.Join(t.TempDir(), "new.png")
	writeE2EPNG(t, newer)
	if err := os.WriteFile(filepath.Join(cache, "outputs.json"),
		[]byte(`{"*":{"type":"static","path":"`+newer+`"}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	d.migrateLegacyOutputs()
	if want, applied := d.restoreOutputs(); want != 1 || applied != 1 {
		t.Fatalf("post-clobber-guard: want/applied = %d/%d, expected 1/1", want, applied)
	}
	if got := d.surface.snapshot().Default.Path; got != newer {
		t.Fatalf("migration overwrote a live choice: path = %q, want %q", got, newer)
	}
}

// defaultWallpaper is the startup fallback for a box with no recorded choice: it
// returns the first static image in the wallpaper dir by name, skipping
// subdirs, dotfiles, videos, and animated formats (a .gif is typeOf "video"),
// so the fallback never lands on the live player. An empty or missing dir
// yields "" (nothing to paint) rather than an error.
func TestDefaultWallpaperPicksFirstStatic(t *testing.T) {
	d, _ := restoreDaemon(t)
	wallDir := filepath.Join(t.TempDir(), "Wallpapers")
	d.cfg.Paths.Wallpaper = wallDir

	if got := d.defaultWallpaper(); got != "" {
		t.Fatalf("missing wallpaper dir must yield \"\", got %q", got)
	}
	if err := os.MkdirAll(filepath.Join(wallDir, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	if got := d.defaultWallpaper(); got != "" {
		t.Fatalf("dir with no images must yield \"\", got %q", got)
	}

	// Names that sort before the first real image, but must all be skipped: a
	// subdir, a dotfile, a clip, and an animated gif.
	for _, name := range []string{"0-clip.mp4", "1-anim.gif", ".hidden.png", "aardvark.jpg", "zebra.png"} {
		if err := os.WriteFile(filepath.Join(wallDir, name), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(wallDir, "sub", "0-nested.png"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got, want := d.defaultWallpaper(), filepath.Join(wallDir, "aardvark.jpg"); got != want {
		t.Fatalf("defaultWallpaper() = %q, want the first static image %q", got, want)
	}
}

// A box that never recorded a wallpaper (a fresh install, or one cut over from
// awww) must land on the shipped default instead of the empty grey frame:
// applyDefaultWallpaper paints the frame AND persists the choice to
// outputs.json, so the next login's restore reproduces it. This is the #149
// regression: the desktop went black because ryogami painted nothing when no
// choice was stored.
func TestApplyDefaultWallpaperPaintsAndPersists(t *testing.T) {
	root := t.TempDir()
	cache := filepath.Join(root, "cache")
	if err := os.MkdirAll(cache, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(root, "state"))
	wallDir := filepath.Join(root, "Wallpapers")
	pic := filepath.Join(wallDir, "default.png")
	writeE2EPNG(t, pic)

	d := &daemon{surface: newWallSurface(), store: openStore(cache), events: newEventHub(), video: newVideoPlayer(), lastTransition: -1}
	d.cfg.Paths.Cache = cache
	d.cfg.Paths.Wallpaper = wallDir

	d.applyDefaultWallpaper()

	if got := d.surface.snapshot().Default.Path; got != pic {
		t.Fatalf("default wallpaper frame path = %q, want %q", got, pic)
	}
	// Persisted, so a plain restore (no fallback) reproduces the choice next login.
	if want, applied := d.restoreOutputs(); want != 1 || applied != 1 {
		t.Fatalf("after default apply: restore want/applied = %d/%d, expected 1/1", want, applied)
	}
}

// hyprEventSocket returns the newest instance's .socket2.sock and "" when no
// compositor socket has landed, so the watcher targets the live session and
// backs off cleanly during a login-time race.
func TestHyprEventSocketPicksNewest(t *testing.T) {
	rt := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", rt)

	if got := hyprEventSocket(); strings.HasPrefix(got, rt) {
		t.Fatalf("no instance under the runtime dir yet, but got %q", got)
	}

	older := filepath.Join(rt, "hypr", "sig-old")
	newer := filepath.Join(rt, "hypr", "sig-new")
	for _, d := range []string{older, newer} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(d, ".socket2.sock"), nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// Push both far into the future so a real /tmp/hypr socket on the host can
	// never outrank them, and make sig-new the newest.
	future := time.Now().Add(48 * time.Hour)
	if err := os.Chtimes(filepath.Join(older, ".socket2.sock"), future, future); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(filepath.Join(newer, ".socket2.sock"), future.Add(time.Hour), future.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if got, want := hyprEventSocket(), filepath.Join(newer, ".socket2.sock"); got != want {
		t.Fatalf("hyprEventSocket() = %q, want the newest %q", got, want)
	}
}
