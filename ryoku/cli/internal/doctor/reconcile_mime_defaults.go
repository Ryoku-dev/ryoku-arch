package doctor

// Unfreeze the default-app map. Ryoku used to materialize its own map into
// ~/.config/mimeapps.list, the file every "Set as default" writes, so each update
// overwrote the user's picks. The map ships to
// /usr/share/applications/mimeapps.list now, below the user's file in the XDG
// chain; this drops the entries left frozen in their file that are only copies of
// Ryoku's values, and keeps whatever they chose.

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

const mimeDefaultsSection = "Default Applications"

// vendorMimeLists: every mimeapps.list below the user's own file, nearest layer
// first, as the XDG spec orders them. Ryoku ships the last one; the others are
// read so a value the user set that matches any lower layer still counts as
// redundant rather than a choice worth freezing.
func vendorMimeLists() []string {
	var out []string
	dataHome := sys.Xdg("XDG_DATA_HOME", ".local/share")
	out = append(out, filepath.Join(dataHome, "applications", "mimeapps.list"))
	dirs := os.Getenv("XDG_DATA_DIRS")
	if dirs == "" {
		dirs = "/usr/local/share:/usr/share"
	}
	for _, d := range strings.Split(dirs, ":") {
		if d == "" {
			continue
		}
		out = append(out, filepath.Join(d, "applications", "mimeapps.list"))
	}
	return out
}

func userMimeList() string { return filepath.Join(sys.ConfigHome(), "mimeapps.list") }

// reconcileMimeDefaults drops the Ryoku-owned defaults from the user's
// mimeapps.list so their own picks are the only thing left in it.
func reconcileMimeDefaults(checkOnly bool) recResult {
	path := userMimeList()
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return okRes(i18n.T("no user mimeapps.list; default apps come from the shipped map"))
	}
	if err != nil {
		return warnRes(i18n.T("could not read %s: %v"), path, err).
			withFix(i18n.T("fix the file permissions, then run `ryoku doctor`"))
	}

	vendor := map[string]string{}
	for _, p := range vendorMimeLists() {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		for mime, app := range mimeDefaults(string(b)) {
			if _, seen := vendor[mime]; !seen {
				vendor[mime] = app
			}
		}
	}
	if len(vendor) == 0 {
		return okRes(i18n.T("no shipped default-app map is installed; the user's mimeapps.list is left alone"))
	}

	next, dropped := stripRedundantDefaults(string(raw), vendor)
	if dropped == 0 {
		return okRes(i18n.T("mimeapps.list holds only the defaults you chose"))
	}
	if checkOnly {
		return wouldRes(i18n.T("mimeapps.list still carries %d default(s) copied from Ryoku's map"), dropped).
			withFix(i18n.T("ryoku doctor drops them, so your own picks are what remains and Ryoku's defaults come from the shipped map"))
	}

	if strings.TrimSpace(stripComments(next)) == "" {
		if err := os.Remove(path); err != nil {
			return failRes(i18n.T("could not remove the stale %s: %v"), path, err)
		}
		return fixedRes(i18n.T("removed a mimeapps.list that only copied Ryoku's map; default apps now follow the shipped one"))
	}
	if err := replaceFileKeepingMode(path, []byte(next)); err != nil {
		return failRes(i18n.T("could not rewrite %s: %v"), path, err).
			withFix(i18n.T("fix the file permissions, then run `ryoku doctor`"))
	}
	return fixedRes(i18n.T("dropped %d default(s) copied from Ryoku's map; the apps you picked yourself are untouched"), dropped)
}

// mimeDefaults reads the [Default Applications] table out of a mimeapps.list.
func mimeDefaults(text string) map[string]string {
	out := map[string]string{}
	section := ""
	for _, line := range strings.Split(text, "\n") {
		t := strings.TrimSpace(line)
		if t == "" || strings.HasPrefix(t, "#") {
			continue
		}
		if strings.HasPrefix(t, "[") && strings.HasSuffix(t, "]") {
			section = strings.TrimSpace(t[1 : len(t)-1])
			continue
		}
		if section != mimeDefaultsSection {
			continue
		}
		mime, app, ok := splitEntry(t)
		if ok {
			out[mime] = app
		}
	}
	return out
}

// splitEntry parses `mime=app.desktop;` into its two halves. The value is a
// desktop-id list; the trailing separator the spec allows is not part of it.
func splitEntry(line string) (string, string, bool) {
	mime, app, ok := strings.Cut(line, "=")
	if !ok {
		return "", "", false
	}
	mime = strings.TrimSpace(mime)
	app = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(app), ";"))
	if mime == "" || app == "" {
		return "", "", false
	}
	return mime, app, true
}

// stripRedundantDefaults removes the [Default Applications] entries whose value
// a lower layer already provides, keeping the file's own order, comments and
// other sections. An emptied section header goes with them.
func stripRedundantDefaults(text string, vendor map[string]string) (string, int) {
	lines := strings.Split(text, "\n")
	kept := make([]string, 0, len(lines))
	dropped := 0
	section := ""

	// index of the [Default Applications] header in kept, and whether anything
	// survived under it, so a header left alone is dropped too.
	headerAt, sectionKept := -1, false
	closeSection := func() {
		if headerAt >= 0 && !sectionKept {
			kept = append(kept[:headerAt], kept[headerAt+1:]...)
		}
		headerAt, sectionKept = -1, false
	}

	for _, line := range lines {
		t := strings.TrimSpace(line)
		if strings.HasPrefix(t, "[") && strings.HasSuffix(t, "]") {
			closeSection()
			section = strings.TrimSpace(t[1 : len(t)-1])
			kept = append(kept, line)
			if section == mimeDefaultsSection {
				headerAt = len(kept) - 1
			}
			continue
		}
		if section == mimeDefaultsSection && t != "" && !strings.HasPrefix(t, "#") {
			if mime, app, ok := splitEntry(t); ok {
				if v, known := vendor[mime]; known && v == app {
					dropped++
					continue
				}
				sectionKept = true
			}
		}
		kept = append(kept, line)
	}
	closeSection()

	out := strings.Join(kept, "\n")
	// collapse the blank runs an emptied section leaves behind.
	for strings.Contains(out, "\n\n\n") {
		out = strings.ReplaceAll(out, "\n\n\n", "\n\n")
	}
	return out, dropped
}

// stripComments: what is left once comments and blank lines go, used only to ask
// whether a file still says anything.
func stripComments(text string) string {
	var b strings.Builder
	for _, line := range strings.Split(text, "\n") {
		t := strings.TrimSpace(line)
		if t == "" || strings.HasPrefix(t, "#") {
			continue
		}
		if strings.HasPrefix(t, "[") && strings.HasSuffix(t, "]") {
			continue
		}
		b.WriteString(t)
	}
	return b.String()
}

// replaceFileKeepingMode writes data over path atomically, keeping its mode.
func replaceFileKeepingMode(path string, data []byte) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".ryoku-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	if err := tmp.Chmod(info.Mode().Perm()); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return fmt.Errorf(i18n.T("replace %s: %w"), path, err)
	}
	return nil
}
