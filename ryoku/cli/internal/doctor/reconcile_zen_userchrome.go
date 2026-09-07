package doctor

import (
	"bytes"
	_ "embed"
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

//go:embed ryoku_animations.css
var zenAnimationsCSS []byte

const zenAnimSheetName = "ryoku-animations.css"

// reconcileZenUserChrome installs the Ryoku animation sheet into each Zen
// profile and @imports it from userChrome.css, preserving the user's own rules.
// The pref that loads userChrome.css is set by reconcileZen. No-op without Zen.
func reconcileZenUserChrome(checkOnly bool) recResult {
	home := homeDir()
	if home == "" {
		return okRes(i18n.T("no HOME"))
	}
	zenRoot := filepath.Join(home, ".config", "zen")
	if !sys.Exists(zenRoot) {
		return okRes(i18n.T("no Zen present"))
	}
	profiles := zenProfileDirs(zenRoot)
	if len(profiles) == 0 {
		return okRes(i18n.T("no Zen profile"))
	}

	var pending, did []string
	for _, prof := range profiles {
		name := filepath.Base(prof)
		chromeDir := filepath.Join(prof, "chrome")
		sheet := filepath.Join(chromeDir, zenAnimSheetName)
		userCSS := filepath.Join(chromeDir, "userChrome.css")

		if zenFileEqual(sheet, zenAnimationsCSS) && userChromeImportsAnim(userCSS) {
			continue
		}
		if checkOnly {
			pending = append(pending, name)
			continue
		}
		if err := os.MkdirAll(chromeDir, 0o755); err != nil {
			return failRes(i18n.T("could not create %s: %v"), chromeDir, err)
		}
		if err := os.WriteFile(sheet, zenAnimationsCSS, 0o644); err != nil {
			return failRes(i18n.T("could not write the Ryoku animation sheet: %v"), err)
		}
		if err := ensureUserChromeImport(userCSS); err != nil {
			return failRes(i18n.T("could not update userChrome.css for %s: %v"), name, err)
		}
		did = append(did, name)
	}

	switch {
	case checkOnly && len(pending) > 0:
		return wouldRes(i18n.T("install browser animations for Zen profile: %s"), strings.Join(pending, ", "))
	case len(did) > 0:
		return fixedRes(i18n.T("installed browser animations for Zen profile: %s"), strings.Join(did, ", "))
	default:
		return okRes(i18n.T("browser animations installed"))
	}
}

// zenProfileDirs returns profile dirs (those with a prefs.js), skipping
// container dirs like "Profile Groups".
func zenProfileDirs(root string) []string {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		p := filepath.Join(root, e.Name())
		if sys.Exists(filepath.Join(p, "prefs.js")) {
			out = append(out, p)
		}
	}
	return out
}

func zenFileEqual(path string, want []byte) bool {
	b, err := os.ReadFile(path)
	return err == nil && bytes.Equal(b, want)
}

func userChromeImportsAnim(path string) bool {
	b, err := os.ReadFile(path)
	return err == nil && bytes.Contains(b, []byte(zenAnimSheetName))
}

// ensureUserChromeImport prepends the @import (CSS needs it before other rules),
// keeping any existing content.
func ensureUserChromeImport(path string) error {
	existing, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if bytes.Contains(existing, []byte(zenAnimSheetName)) {
		return nil
	}
	var buf bytes.Buffer
	buf.WriteString(`@import "` + zenAnimSheetName + `";` + "\n")
	if len(existing) > 0 {
		buf.WriteByte('\n')
		buf.Write(existing)
	}
	return os.WriteFile(path, buf.Bytes(), 0o644)
}
