package doctor

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"ryoku-cli/internal/sys"
)

// Ghostty's palette used to render straight into ~/.config/ghostty/config, the
// file the user owns, so every retint wiped their settings. matugen now writes
// only the colours to a sibling ryoku-colors that the config pulls in with
// `config-file = ryoku-colors`. This reconciler migrates a box that predates the
// split: a config that is nothing but the old generated palette is replaced with
// the wrapper (its colours preserved into ryoku-colors); a config that carries
// the user's own settings is left intact and only gains the include if it is
// missing. A config that already opted out (the include removed) is left alone.

// ghosttyScalarKeys are the six non-palette keys the matugen template renders, in
// order; a config that is exactly these plus palette 0..15 is a pure render.
var ghosttyScalarKeys = []string{
	"background", "foreground", "cursor-color", "cursor-text",
	"selection-background", "selection-foreground",
}

const ghosttyColorsHeader = `# Ryoku palette -> ghostty. Rendered by matugen; do not edit. Your own settings
# live in ~/.config/ghostty/config, which includes this file for the colours.
`

// ghosttyConfigWrapper is byte-identical to the shipped ryoku/apps/ghostty/config
// seed, so a migrated box and a fresh install converge on the same file.
const ghosttyConfigWrapper = `# Your ghostty config. Ryoku seeds this once and never overwrites it, so
# anything you add here survives updates.
#
# ghostty applies config-file includes after this file's own keys, so the
# palette below lands on top of any colour set here; put colour overrides in
# user.conf, which loads last and wins.

# theme palette, written by matugen next to this file
config-file = ryoku-colors

# your overrides; never shipped, loads last. ? = optional, no error if absent
config-file = ?user.conf
`

const ghosttyIncludeAppend = "\n# theme palette, written by matugen next to this file\nconfig-file = ryoku-colors\n# your overrides; loads last so they win. ? = optional\nconfig-file = ?user.conf\n"

const ghosttyIncludeMigration = "ghostty-palette-include"

func ghosttyMigrationMarker() string {
	return filepath.Join(sys.StateDir(), "migrations", ghosttyIncludeMigration)
}

func reconcileGhostty(checkOnly bool) recResult {
	dir := filepath.Join(sys.ConfigHome(), "ghostty")
	cfgPath := filepath.Join(dir, "config")
	colorsPath := filepath.Join(dir, "ryoku-colors")

	body, err := os.ReadFile(cfgPath)
	if err != nil {
		// Absent config: the seed (materialize/deploy) lays a fresh wrapper, and a
		// config the user deleted stays deleted. Nothing to migrate either way.
		return okRes("no ghostty config to migrate")
	}
	content := string(body)

	if ghosttyHasInclude(content, "ryoku-colors") {
		if !sys.Exists(ghosttyMigrationMarker()) && !checkOnly {
			_ = markMigration(ghosttyMigrationMarker())
		}
		return okRes("ghostty config includes the Ryoku palette")
	}
	// The include is gone. Once the migration has run, that is the user's edit
	// (or an explicit opt-out kept alongside a user.conf include), so theming is
	// never forced back on.
	if sys.Exists(ghosttyMigrationMarker()) || ghosttyHasInclude(content, "user.conf") {
		return okRes("ghostty config opted out of the Ryoku palette; left as is")
	}

	render := ghosttyIsRender(content)
	if checkOnly {
		if render {
			return wouldRes("your ghostty config is a generated palette; an update overwrote it wholesale").
				withFix("ryoku doctor rewrites it as a wrapper that includes the palette, so your own settings survive")
		}
		return wouldRes("your ghostty config does not include the Ryoku palette").
			withFix("ryoku doctor adds `config-file = ryoku-colors`, leaving your settings untouched")
	}

	if err := os.MkdirAll(dir, 0o755); err != nil {
		return failRes("could not create %s: %v", dir, err)
	}

	if render {
		// The whole file is the old render, so it holds no user settings: seed
		// ryoku-colors from it (keeps the current colours until the next retint)
		// and replace the config with the wrapper.
		if !sys.Exists(colorsPath) {
			if err := os.WriteFile(colorsPath, []byte(ghosttyColorsHeader+"\n"+strings.TrimSpace(content)+"\n"), 0o644); err != nil {
				return failRes("could not write %s: %v", colorsPath, err)
			}
		}
		if err := os.WriteFile(cfgPath, []byte(ghosttyConfigWrapper), 0o644); err != nil {
			return failRes("could not rewrite %s: %v", cfgPath, err)
		}
		_ = markMigration(ghosttyMigrationMarker())
		return fixedRes("converted your generated ghostty config to a wrapper; the palette now lives in ryoku-colors and your future edits survive updates")
	}

	// A config with the user's own settings: leave every byte and only append the
	// include so the palette reaches ghostty. ryoku-colors must exist first, or
	// the (non-optional) include warns; seed it from any colour lines already in
	// the config so the current look is kept.
	if !sys.Exists(colorsPath) {
		if err := os.WriteFile(colorsPath, []byte(ghosttyColorsHeader+ghosttyColourLines(content)), 0o644); err != nil {
			return failRes("could not write %s: %v", colorsPath, err)
		}
	}
	appended := content
	if !strings.HasSuffix(appended, "\n") {
		appended += "\n"
	}
	appended += ghosttyIncludeAppend
	if err := os.WriteFile(cfgPath, []byte(appended), 0o644); err != nil {
		return failRes("could not update %s: %v", cfgPath, err)
	}
	_ = markMigration(ghosttyMigrationMarker())
	return fixedRes("added the Ryoku palette include to your ghostty config; your settings are untouched")
}

// ghosttyHasInclude reports whether content has a `config-file = <target>` line
// (the optional `?` prefix and surrounding space are ignored).
func ghosttyHasInclude(content, target string) bool {
	for _, ln := range strings.Split(content, "\n") {
		t := strings.TrimSpace(ln)
		if strings.HasPrefix(t, "#") {
			continue
		}
		key, val, ok := strings.Cut(t, "=")
		if !ok || strings.TrimSpace(key) != "config-file" {
			continue
		}
		v := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(val), "?"))
		if v == target {
			return true
		}
	}
	return false
}

// ghosttyIsRender reports whether content is exactly what the matugen template
// produces: the six scalar keys in order, then palette 0..15, and nothing else.
// The exact shape is the proof it is generated, not a user file that happens to
// set only colours.
func ghosttyIsRender(content string) bool {
	lines := ghosttyContentLines(content)
	if len(lines) != len(ghosttyScalarKeys)+16 {
		return false
	}
	for i, want := range ghosttyScalarKeys {
		key, _, ok := strings.Cut(lines[i], "=")
		if !ok || strings.TrimSpace(key) != want {
			return false
		}
	}
	for i := range 16 {
		key, val, ok := strings.Cut(lines[len(ghosttyScalarKeys)+i], "=")
		if !ok || strings.TrimSpace(key) != "palette" {
			return false
		}
		idx, _, ok := strings.Cut(strings.TrimSpace(val), "=")
		if !ok || strings.TrimSpace(idx) != strconv.Itoa(i) {
			return false
		}
	}
	return true
}

// ghosttyColourLines returns the theme-owned lines (the scalar keys and palette
// entries) from content, so a migration can seed ryoku-colors with the colours
// already in a user's config.
func ghosttyColourLines(content string) string {
	owned := map[string]bool{"palette": true}
	for _, k := range ghosttyScalarKeys {
		owned[k] = true
	}
	var out []string
	for _, ln := range ghosttyContentLines(content) {
		key, _, ok := strings.Cut(ln, "=")
		if ok && owned[strings.TrimSpace(key)] {
			out = append(out, ln)
		}
	}
	if len(out) == 0 {
		return ""
	}
	return strings.Join(out, "\n") + "\n"
}

// ghosttyContentLines are the non-blank, non-comment lines of content, trimmed.
func ghosttyContentLines(content string) []string {
	var out []string
	for _, ln := range strings.Split(content, "\n") {
		t := strings.TrimSpace(ln)
		if t == "" || strings.HasPrefix(t, "#") {
			continue
		}
		out = append(out, t)
	}
	return out
}
