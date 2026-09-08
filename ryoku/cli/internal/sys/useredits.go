package sys

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// UserEditFiles lists the layable files in the overlay: regular files under
// UserEditsDir, slash-relative and sorted, skipping symlinks, .md notes (the
// guide and anything a user keeps beside their edits), and the overlay's own
// nested path. The overlay lays these over ~/.config; doctor reads the same set
// to spot forks; reset walks it to clear everything. Absent overlay -> no files.
func UserEditFiles() ([]string, error) {
	root := UserEditsDir()
	if _, err := os.Stat(root); err != nil {
		return nil, nil
	}
	var rels []string
	err := filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || d.Type()&os.ModeSymlink != 0 || strings.HasSuffix(d.Name(), ".md") {
			return nil
		}
		rel, err := filepath.Rel(root, p)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		if strings.HasPrefix(rel, "ryoku/user_edits/") {
			return nil // never mirror the overlay tree into itself
		}
		rels = append(rels, rel)
		return nil
	})
	sort.Strings(rels)
	return rels, err
}

// LiveOwnedConfig are the files edited at their normal ~/.config path and
// loaded there directly. Two kinds qualify: the tool's own user-include files
// (hyprland.lua's optional("user") and optional("monitors_user"); kitty.conf
// includes user.conf), and the update seeds the runtime or the Hub edits in
// place (materialize's generatedSeed set: the Hub's Fastfetch editor and the
// store's readout styles rewrite fastfetch/config.jsonc, ryoku-gpu owns
// gpu.lua, the display flow owns monitors.lua and keyboard.lua, matugen owns
// kitty/current-theme.conf and ghostty/ryoku-colors). They must NEVER live in the overlay:
// overlayUserEdits would re-lay a frozen copy over the live file on every
// update and silently wipe edits made afterward. The user.lua report was the
// first sighting; "updates keep resetting my fastfetch" was the same bug
// through the seed set. The overlay is for forking a whole Ryoku file, not
// these.
var LiveOwnedConfig = []string{
	"hypr/user.lua",
	"hypr/monitors_user.lua",
	"kitty/user.conf",
	"fastfetch/config.jsonc",
	"hypr/monitors.lua",
	"hypr/gpu.lua",
	"hypr/keyboard.lua",
	"kitty/current-theme.conf",
	"ghostty/ryoku-colors",
}

// IsLiveOwnedConfig reports whether rel (a slash path relative to ~/.config) is
// one of the live-owned user files the overlay must never lay. The nvim tree
// counts too: it seeds once (updater.isSeed) and is then the user's, so a frozen
// overlay copy must never be re-laid over their live LazyVim config.
func IsLiveOwnedConfig(rel string) bool {
	if strings.HasPrefix(rel, "nvim/") {
		return true
	}
	for _, r := range LiveOwnedConfig {
		if r == rel {
			return true
		}
	}
	return false
}
