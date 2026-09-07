package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// reconcileObsidianSnippet links the Ryoku palette snippet into every Obsidian
// vault and enables it, so notes track the wallpaper scheme the way the rest of
// the app suite does. matugen renders the snippet to one file
// (~/.config/matugen/generated/obsidian.css); Obsidian only loads snippets that
// live under <vault>/.obsidian/snippets, so each vault gets a symlink to that one
// file plus "ryoku" in its enabled list. A dangling link until matugen first
// renders is harmless. No-op when Obsidian is absent; idempotent, and it never
// drops a user's other snippets.
func reconcileObsidianSnippet(checkOnly bool) recResult {
	cfg := filepath.Join(configHome(), "obsidian", "obsidian.json")
	if !sys.Has("obsidian") && !sys.Exists(cfg) {
		return okRes(i18n.T("Obsidian not installed"))
	}
	vaults, err := obsidianVaultPaths(cfg)
	if err != nil || len(vaults) == 0 {
		return okRes(i18n.T("no Obsidian vaults registered yet"))
	}
	generated := filepath.Join(configHome(), "matugen", "generated", "obsidian.css")

	var did, pending []string
	for _, vault := range vaults {
		if !sys.Exists(vault) {
			continue // stale entry: the vault was moved or deleted.
		}
		dot := filepath.Join(vault, ".obsidian")
		link := filepath.Join(dot, "snippets", "ryoku.css")

		if !symlinkPointsAt(link, generated) {
			if checkOnly {
				pending = append(pending, i18n.Tf("link palette snippet into %s", tildeOf(vault)))
			} else {
				if err := os.MkdirAll(filepath.Dir(link), 0o755); err != nil {
					return failRes(i18n.T("could not create %s: %v"), tildeOf(filepath.Dir(link)), err)
				}
				_ = os.Remove(link)
				if err := os.Symlink(generated, link); err != nil {
					return failRes(i18n.T("could not link the palette snippet in %s: %v"), tildeOf(vault), err)
				}
				did = append(did, i18n.Tf("linked %s", tildeOf(vault)))
			}
		}

		appearance := filepath.Join(dot, "appearance.json")
		changed, err := enableObsidianSnippet(appearance, !checkOnly)
		if err != nil {
			return failRes(i18n.T("could not enable the snippet in %s: %v"), tildeOf(vault), err)
		}
		if changed {
			if checkOnly {
				pending = append(pending, i18n.Tf("enable the snippet in %s", tildeOf(vault)))
			} else {
				did = append(did, i18n.Tf("enabled in %s", tildeOf(vault)))
			}
		}
	}

	switch {
	case checkOnly && len(pending) > 0:
		return wouldRes("%s", strings.Join(pending, "; "))
	case len(did) > 0:
		return fixedRes("%s", strings.Join(did, "; "))
	default:
		return okRes(i18n.T("palette snippet is linked and enabled in every vault"))
	}
}

// obsidianVaultPaths reads the absolute vault paths from Obsidian's registry
// (~/.config/obsidian/obsidian.json: {"vaults":{"<id>":{"path":"/abs"}}}).
func obsidianVaultPaths(cfgPath string) ([]string, error) {
	b, err := os.ReadFile(cfgPath)
	if err != nil {
		return nil, err
	}
	var doc struct {
		Vaults map[string]struct {
			Path string `json:"path"`
		} `json:"vaults"`
	}
	if err := json.Unmarshal(b, &doc); err != nil {
		return nil, err
	}
	var out []string
	for _, v := range doc.Vaults {
		if p := strings.TrimSpace(v.Path); p != "" {
			out = append(out, p)
		}
	}
	return out, nil
}

// symlinkPointsAt reports whether path is already a symlink to target.
func symlinkPointsAt(path, target string) bool {
	fi, err := os.Lstat(path)
	if err != nil || fi.Mode()&os.ModeSymlink == 0 {
		return false
	}
	dst, err := os.Readlink(path)
	return err == nil && dst == target
}

// enableObsidianSnippet adds "ryoku" to a vault's enabledCssSnippets, creating
// appearance.json when absent and preserving every other snippet and setting.
// It reports whether a change was needed; the change is written only when apply
// is true, so the check-only pass can report without touching the file. An
// unparseable appearance.json is left untouched rather than clobbered.
func enableObsidianSnippet(path string, apply bool) (bool, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		if !apply {
			return true, nil
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return false, err
		}
		return true, os.WriteFile(path, []byte(`{"enabledCssSnippets":["ryoku"]}`+"\n"), 0o644)
	}
	if err != nil {
		return false, err
	}
	var doc map[string]any
	if json.Unmarshal(b, &doc) != nil {
		return false, nil
	}
	list, _ := doc["enabledCssSnippets"].([]any)
	for _, s := range list {
		if v, ok := s.(string); ok && v == "ryoku" {
			return false, nil
		}
	}
	if !apply {
		return true, nil
	}
	doc["enabledCssSnippets"] = append(list, "ryoku")
	out, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return false, err
	}
	return true, os.WriteFile(path, append(out, '\n'), 0o644)
}
