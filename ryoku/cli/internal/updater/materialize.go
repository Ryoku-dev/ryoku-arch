package updater

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
	"sort"
	"strings"
)

const wirePlumberPolicyRel = "wireplumber/wireplumber.conf.d/51-ryoku-bluetooth.conf"

// Ryoku's drop-ins share wireplumber.conf.d with the user's own, so only the
// NN-ryoku-*.conf ones are ours to converge.
const wpDropInDir = "wireplumber/wireplumber.conf.d"

var ryokuDropIn = regexp.MustCompile(`^[0-9]+-ryoku-[^/]*\.conf$`)

// generatedSeed: base files seeded once on a fresh install, then never
// clobbered or pruned by an update. The machine owns them after first boot.
// Two kinds qualify: per-machine files the runtime regenerates (monitors.lua,
// gpu.lua; kitty/current-theme.conf, which matugen rewrites from the wallpaper)
// and user-owned config the package only seeds a starting point for
// (keyboard.lua; hypr/user.lua, seeded with a header so a hand-edit sticks;
// fastfetch/config.jsonc, which has no include mechanism, so direct edits
// are the only way to customize the readout).
// Slash-separated paths, relative to the config base. Most are also in
// sys.LiveOwnedConfig so the overlay never re-lays a frozen copy over a file
// edited in place; ghostty/config is the exception -- it is a seed the user may
// instead fork through the overlay, so it stays overlay-able (not live-owned).
var generatedSeed = map[string]bool{
	"hypr/monitors.lua":        true,
	"hypr/gpu.lua":             true,
	"hypr/keyboard.lua":        true,
	"hypr/user.lua":            true,
	"fastfetch/config.jsonc":   true,
	"kitty/current-theme.conf": true,
	"ghostty/config":           true,
	"ghostty/ryoku-colors":     true,
}

// nvim is seeded like ghostty: Ryoku lays its LazyVim starting point once, then
// the config is the user's. Their edits, plugins and LazyVim's own state under
// ~/.config/nvim then survive every update instead of being reset each time.
// isSeed folds the per-path seeds and the whole nvim tree into one test.
func isSeed(rel string) bool {
	return generatedSeed[rel] || strings.HasPrefix(rel, "nvim/")
}

// Materialize lays the Ryoku-owned base configs into the user's ~/.config,
// declaratively: every file the package ships under baseConfigDir() is
// copied over (clobbering the previous Ryoku copy), files we shipped before
// but no longer ship are removed, anything the package never shipped (user
// files: hypr/monitors_user.lua, kitty/user.conf, ...) is left alone. Per-machine
// generated seeds (generatedSeed, e.g. hypr/monitors.lua) are the exception:
// seeded only when absent, never clobbered, so an update keeps the user's
// runtime-written display and GPU config.
//
// Production replacement for deploy.sh's per-user config copy. Base lives at
// /usr/share/ryoku/config on an installed system; on a dev checkout
// RYOKU_CONFIG_BASE points at ryoku/<...> via `ryoku deploy`.
//
// The set of Ryoku-owned paths is the manifest. Recorded in the state file so
// the next run can prune files dropped from a release without guessing.
func Materialize() error {
	base := sys.BaseConfigDir()
	dest := sys.ConfigHome()
	state := materializeStatePath()
	wirePlumberBefore, _ := os.ReadFile(filepath.Join(dest, wirePlumberPolicyRel))

	info, err := os.Stat(base)
	if err != nil || !info.IsDir() {
		if os.Getenv("RYOKU_CONFIG_BASE") != "" {
			return fmt.Errorf(i18n.T("base config dir not found: %s (RYOKU_CONFIG_BASE points at a missing dir)"), base)
		}
		return fmt.Errorf(i18n.T("base config dir not found: %s\n"+
			"  `ryoku materialize` applies a packaged install's config; on a dev checkout run `ryoku deploy` instead"), base)
	}

	// ~/.config/ryoku is where the shell's JSON stores live (shell.json,
	// launcher.json, hypr.json). The package ships no file under it, so the
	// walk below never creates it, and the shell's QML self-seed cannot make
	// parent directories: guarantee it here, at install and on every update.
	_ = os.MkdirAll(filepath.Join(dest, "ryoku"), 0o755)

	current, err := walkRel(base)
	if err != nil {
		return fmt.Errorf(i18n.T("scan %s: %w"), base, err)
	}

	// Lay down every shipped file, except seeds: those copy only when absent
	// (fresh install) and never get overwritten, so an update leaves the
	// user's display, GPU pin, and keyboard layout alone. Only clobbered
	// files enter the manifest, so a later prune can never remove a seed either.
	//
	// A shipped file whose live bytes match neither what the last update laid
	// nor what this one ships was edited by hand; it becomes a fork under the
	// overlay instead of being thrown away.
	laidHashes := readManifestHashes(state)
	overlaid := map[string]bool{}
	if rels, err := sys.UserEditFiles(); err == nil {
		for _, rel := range rels {
			overlaid[rel] = true
		}
	}
	managed := make([]string, 0, len(current))
	hashes := make(map[string]string, len(current))
	var kept []string
	for _, rel := range current {
		dst := filepath.Join(dest, rel)
		if isSeed(rel) {
			if !sys.Exists(dst) {
				if err := sys.CopyFile(filepath.Join(base, rel), dst); err != nil {
					return fmt.Errorf(i18n.T("seed %s: %w"), rel, err)
				}
			}
			continue
		}
		shipped, err := os.ReadFile(filepath.Join(base, rel))
		if err != nil {
			return fmt.Errorf(i18n.T("read %s: %w"), rel, err)
		}
		hashes[rel] = hashBytes(shipped)
		if forkable(rel) && !overlaid[rel] {
			if laid, ok := laidHashes[rel]; ok {
				if live, err := os.ReadFile(dst); err == nil {
					if h := hashBytes(live); h != laid && h != hashes[rel] {
						if err := sys.CopyFile(dst, filepath.Join(sys.UserEditsDir(), rel)); err != nil {
							return fmt.Errorf(i18n.T("keep your edit of %s: %w"), rel, err)
						}
						kept = append(kept, rel)
					}
				}
			}
		}
		if err := sys.CopyFile(filepath.Join(base, rel), dst); err != nil {
			return fmt.Errorf(i18n.T("copy %s: %w"), rel, err)
		}
		managed = append(managed, rel)
	}

	// Prune files this release no longer ships (in the previous manifest,
	// absent now). Never touches paths outside the manifest, i.e. user files.
	previous := readManifest(state)
	curSet := make(map[string]bool, len(current))
	for _, p := range current {
		curSet[p] = true
	}

	// ~/.config/quickshell is wholly Ryoku-owned (user plugins live under
	// ~/.local/share/ryoku), so converge it against the shipped tree directly:
	// stale QML from releases this box's manifest never recorded (a lost state
	// file, an old deploy.sh run) would otherwise load beside the new tree
	// forever. Everything else is mixed with user files and stays manifest-pruned.
	if local, err := walkRel(filepath.Join(dest, "quickshell")); err == nil {
		for _, rel := range local {
			full := "quickshell/" + rel
			if curSet[full] || generatedSeed[full] {
				continue
			}
			_ = os.Remove(filepath.Join(dest, full))
			pruneEmptyParents(dest, filepath.Dir(full))
		}
	}
	wpConfigPruned := false

	// Withdrawn policy goes even without a manifest entry: deploy.sh copies the
	// files but never writes the manifest, so a box configured that way would
	// keep a dropped override forever.
	if local, err := walkRel(filepath.Join(dest, wpDropInDir)); err == nil {
		for _, rel := range local {
			full := wpDropInDir + "/" + rel
			if curSet[full] || !ryokuDropIn.MatchString(rel) {
				continue
			}
			_ = os.Remove(filepath.Join(dest, full))
			wpConfigPruned = true
			pruneEmptyParents(dest, filepath.Dir(full))
		}
	}

	// retiredKeep: a path Ryoku used to lay into ~/.config and deliberately
	// stopped shipping. The manifest prune would delete the user's copy, which
	// for mimeapps.list means throwing away every default app they picked, the
	// exact damage that moving Ryoku's map to the vendor layer
	// (/usr/share/applications/mimeapps.list) exists to stop. `ryoku doctor`
	// strips the stale Ryoku lines out of it instead.
	retiredKeep := map[string]bool{"mimeapps.list": true}
	for _, rel := range previous {
		if curSet[rel] || retiredKeep[rel] {
			continue
		}
		if strings.HasPrefix(rel, "wireplumber/") {
			wpConfigPruned = true
		}
		_ = os.Remove(filepath.Join(dest, rel))
		pruneEmptyParents(dest, filepath.Dir(rel))
	}

	if err := overlayUserEdits(dest); err != nil {
		return err
	}
	for _, rel := range managed {
		if live, err := os.ReadFile(filepath.Join(dest, rel)); err == nil {
			hashes[rel] = hashBytes(live)
		}
	}
	if err := writeManifest(state, managed, hashes); err != nil {
		return fmt.Errorf(i18n.T("record manifest: %w"), err)
	}
	wirePlumberAfter, _ := os.ReadFile(filepath.Join(dest, wirePlumberPolicyRel))
	if wpConfigPruned || !bytes.Equal(wirePlumberBefore, wirePlumberAfter) {
		_ = exec.Command("systemctl", "--user", "try-restart", "wireplumber.service").Run()
	}
	fmt.Printf(i18n.T("materialized %d files -> %s\n"), len(managed), dest)
	if len(kept) > 0 {
		fmt.Printf(i18n.T("kept your edits to %d shipped file(s) as forks under %s (a fork wins over updates; delete it to take Ryoku's version again):\n"), len(kept), sys.UserEditsDir())
		for _, rel := range kept {
			fmt.Printf("  %s\n", rel)
		}
	}
	return nil
}

// The quickshell tree is the shell itself; a stale fork there breaks it.
func forkable(rel string) bool {
	return !strings.HasPrefix(rel, "quickshell/") && !sys.IsLiveOwnedConfig(rel)
}

func hashBytes(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

// walkRel: every regular file under root, as slash-separated paths relative
// to root, sorted.
func walkRel(root string) ([]string, error) {
	var rels []string
	err := filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.Type().IsRegular() {
			return nil
		}
		rel, err := filepath.Rel(root, p)
		if err != nil {
			return err
		}
		rels = append(rels, filepath.ToSlash(rel))
		return nil
	})
	sort.Strings(rels)
	return rels, err
}

func pruneEmptyParents(root, rel string) {
	for rel != "." && rel != "/" && rel != "" {
		dir := filepath.Join(root, rel)
		entries, err := os.ReadDir(dir)
		if err != nil || len(entries) > 0 {
			return
		}
		if err := os.Remove(dir); err != nil {
			return
		}
		rel = filepath.Dir(rel)
	}
}

// Manifest lines are "path<TAB>sha256"; an older line without a hash still
// prunes, it just cannot tell a hand edit apart.
func readManifest(path string) []string {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var out []string
	for _, line := range strings.Split(string(b), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			rel, _, _ := strings.Cut(line, "\t")
			out = append(out, rel)
		}
	}
	return out
}

func readManifestHashes(path string) map[string]string {
	out := map[string]string{}
	b, err := os.ReadFile(path)
	if err != nil {
		return out
	}
	for _, line := range strings.Split(string(b), "\n") {
		if rel, h, ok := strings.Cut(strings.TrimSpace(line), "\t"); ok && rel != "" && h != "" {
			out[rel] = h
		}
	}
	return out
}

func writeManifest(path string, rels []string, hashes map[string]string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	lines := make([]string, 0, len(rels))
	for _, rel := range rels {
		lines = append(lines, rel+"\t"+hashes[rel])
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}

// overlayUserEdits lays the user's override tree over the freshly materialized
// base: a regular file under ~/.config/ryoku/user_edits wins at the mirrored
// ~/.config path. Runs last, after the prune and the quickshell converge, so a
// fork is the final word and nothing sweeps it, while every base fix was still
// laid underneath first. An absent or empty overlay is a no-op.
func overlayUserEdits(dest string) error {
	rels, err := sys.UserEditFiles()
	if err != nil {
		return fmt.Errorf(i18n.T("scan overlay: %w"), err)
	}
	root := sys.UserEditsDir()
	for _, rel := range rels {
		// live-owned user files (hypr/user.lua, monitors_user.lua, kitty/user.conf)
		// are edited in place, never overlaid. A stale overlay copy from the retired
		// adopt step would otherwise re-lay a frozen snapshot over the live file
		// every update and wipe later hand edits; doctor migrates any such copy out.
		if sys.IsLiveOwnedConfig(rel) {
			continue
		}
		if err := sys.CopyFile(filepath.Join(root, rel), filepath.Join(dest, rel)); err != nil {
			return fmt.Errorf(i18n.T("overlay %s: %w"), rel, err)
		}
	}
	return nil
}
