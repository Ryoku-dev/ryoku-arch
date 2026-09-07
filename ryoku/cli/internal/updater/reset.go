package updater

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
	"strings"
)

// Reset drops user overrides from ~/.config/ryoku/user_edits so a customization
// returns to the Ryoku-shipped default. With paths it resets exactly those
// (relative to ~/.config, e.g. hypr/modules/binds.lua); with none it clears the
// whole overlay after a confirm (-y skips it). It touches only overlay files, not
// the Hub's stores.
//
// On a packaged box the live copy is removed and the base re-laid, so a base file
// is re-copied, a seed re-seeds, and an additive overlay (no base default) simply
// stays gone. On a dev checkout there is no base tree to re-lay from, so the
// override is dropped and `ryoku deploy` re-composes live from the repo.
func Reset(args []string) error {
	yes := false
	var paths []string
	for _, a := range args {
		if a == "-y" || a == "--yes" {
			yes = true
			continue
		}
		paths = append(paths, a)
	}

	edits := sys.UserEditsDir()
	if _, err := os.Stat(edits); err != nil {
		fmt.Println(i18n.T("no user edits to reset"))
		return nil
	}

	var targets []string
	if len(paths) == 0 {
		if !yes && !confirmReset(fmt.Sprintf(i18n.T("Reset ALL user edits under %s to Ryoku defaults?"), edits)) {
			fmt.Println(i18n.T("cancelled"))
			return nil
		}
		rels, err := sys.UserEditFiles()
		if err != nil {
			return err
		}
		targets = rels
	} else {
		for _, p := range paths {
			targets = append(targets, filepath.ToSlash(strings.TrimPrefix(p, "./")))
		}
	}

	baseOK := false
	if info, err := os.Stat(sys.BaseConfigDir()); err == nil && info.IsDir() {
		baseOK = true
	}

	removed := 0
	for _, rel := range targets {
		p := filepath.Join(edits, rel)
		if !sys.Exists(p) {
			fmt.Printf(i18n.T("  not overridden: %s\n"), rel)
			continue
		}
		if err := os.Remove(p); err != nil {
			return fmt.Errorf(i18n.T("reset %s: %w"), rel, err)
		}
		pruneEmptyParents(edits, filepath.Dir(rel))
		// on a packaged box, clear the live copy so the re-materialize restores the
		// shipped default; on dev, leave it for `ryoku deploy` to re-lay.
		if baseOK {
			_ = os.Remove(filepath.Join(sys.ConfigHome(), rel))
		}
		removed++
		fmt.Printf(i18n.T("  reset %s\n"), rel)
	}
	if removed == 0 {
		return nil
	}

	if baseOK {
		if err := Materialize(); err != nil {
			return err
		}
		fmt.Println(i18n.T("reverted; run `ryoku reload` to apply it to the running session"))
		return nil
	}
	fmt.Println(i18n.T("run `ryoku deploy` (dev) or `ryoku materialize` to re-lay the base"))
	return nil
}

func confirmReset(prompt string) bool {
	fmt.Printf(i18n.T("%s [y/N] "), prompt)
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	line = strings.TrimSpace(strings.ToLower(line))
	return line == "y" || line == "yes"
}
