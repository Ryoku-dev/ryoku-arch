package doctor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	i18n "ryoku-i18n"
)

// Recordings land in one directory. Three writers used to disagree about which:
// ryoku-cmd-screenrecord resolved it properly, the deck's list hardcoded
// $HOME/Videos/Recordings, and Ryoku Motion wrote into its own Electron
// userData dir, so a user ended up with clips scattered across
// ~/Videos/Recordings, ~/.config/ryomotion/recordings and a stray ~/Videos
// export. The shell and the Hub now both resolve the Hub's `directory` setting;
// this keeps the parts that are not config in step with it.
//
// Ryoku Motion hardcodes path.join(app.getPath("userData"), "recordings") with
// no env var or setting to redirect it, so its directory is made a symlink into
// the real one instead. Its recursive mkdir follows the link, so it keeps
// working and its clips land where everything else looks.

// recordingsDir resolves the one directory, in the same order as
// ryoku-cmd-screenrecord's recordings_dir() and Ryoku.Ui.Singletons.Paths.
func recordingsDir() string {
	if v := strings.TrimSpace(os.Getenv("RYOKU_SHELL_RECORDINGS_DIR")); v != "" {
		return v
	}
	if v := configuredRecordingsDir(); v != "" {
		return v
	}
	return filepath.Join(videosDir(), "Recordings")
}

func configuredRecordingsDir() string {
	b, err := os.ReadFile(filepath.Join(configHome(), "ryoku", "recording.json"))
	if err != nil {
		return ""
	}
	var doc struct {
		Directory string `json:"directory"`
	}
	if json.Unmarshal(b, &doc) != nil {
		return ""
	}
	d := strings.TrimSpace(doc.Directory)
	if strings.HasPrefix(d, "~/") {
		d = filepath.Join(homeDir(), d[2:])
	}
	return d
}

func videosDir() string {
	if v := strings.TrimSpace(os.Getenv("XDG_VIDEOS_DIR")); v != "" {
		return v
	}
	return filepath.Join(homeDir(), "Videos")
}

func homeDir() string { return os.Getenv("HOME") }

func configHome() string {
	if v := os.Getenv("XDG_CONFIG_HOME"); v != "" {
		return v
	}
	return filepath.Join(homeDir(), ".config")
}

// reconcileRecordingsDir keeps the one directory real and folds Ryoku Motion's
// own sink into it. Ryoku's legacy sinks are migrated; a directory that is not
// ours is only reported, since a user may be running that recorder deliberately.
func reconcileRecordingsDir(checkOnly bool) recResult {
	home := homeDir()
	if home == "" {
		return okRes(i18n.T("no HOME; nothing to reconcile"))
	}
	dir := recordingsDir()
	motion := filepath.Join(configHome(), "ryomotion", "recordings")

	var did []string

	// The target has to exist before anything can be pointed at it.
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		if checkOnly {
			return wouldRes(i18n.T("recordings directory %s is missing"), tildeOf(dir))
		}
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return failRes(i18n.T("could not create %s: %v"), tildeOf(dir), err)
		}
		did = append(did, i18n.Tf("created %s", tildeOf(dir)))
	}

	// Ryoku Motion: move anything it already recorded, then leave a symlink so
	// everything it records from now on lands in the one directory.
	if !sameDir(motion, dir) {
		fi, err := os.Lstat(motion)
		switch {
		case err == nil && fi.Mode()&os.ModeSymlink != 0:
			// already pointed somewhere; only correct it if it points elsewhere.
			if target, _ := os.Readlink(motion); !sameDir(target, dir) {
				if checkOnly {
					return wouldRes(i18n.T("Ryoku Motion records into %s, not %s"), tildeOf(target), tildeOf(dir))
				}
				_ = os.Remove(motion)
				if err := os.Symlink(dir, motion); err != nil {
					return failRes(i18n.T("could not point Ryoku Motion at %s: %v"), tildeOf(dir), err)
				}
				did = append(did, i18n.T("repointed Ryoku Motion"))
			}
		case err == nil && fi.IsDir():
			if checkOnly {
				return wouldRes(i18n.T("Ryoku Motion records into %s instead of %s"), tildeOf(motion), tildeOf(dir))
			}
			moved, err := moveContents(motion, dir)
			if err != nil {
				return failRes(i18n.T("could not move Ryoku Motion's recordings: %v"), err)
			}
			if err := os.Remove(motion); err != nil {
				return warnRes(i18n.T("moved %d file(s) out of %s but could not replace it with a link: %v"),
					moved, tildeOf(motion), err).
					withFix(i18n.T("remove %s once it is empty, then rerun ryoku doctor"), tildeOf(motion))
			}
			if err := os.Symlink(dir, motion); err != nil {
				return failRes(i18n.T("could not point Ryoku Motion at %s: %v"), tildeOf(dir), err)
			}
			did = append(did, fmt.Sprintf(i18n.T("folded Ryoku Motion in (%d file(s))"), moved))
		}
	}

	// The empty sink an older build left behind.
	legacy := filepath.Join(videosDir(), "Ryoku Motion")
	if entries, err := os.ReadDir(legacy); err == nil && len(entries) == 0 {
		if checkOnly {
			return wouldRes(i18n.T("empty legacy directory %s"), tildeOf(legacy))
		}
		if os.Remove(legacy) == nil {
			did = append(did, i18n.Tf("removed the empty %s", tildeOf(legacy)))
		}
	}

	// Someone else's directory. On the dev box this is the reference shell's
	// convention, which Ryoku explicitly refused (see MenuCapture.qml), but on a
	// user's machine it could be any recorder they run on purpose. Reported with
	// the command to merge it, never migrated: moving files Ryoku did not write
	// is the user's call.
	stray := filepath.Join(videosDir(), "ScreenRecordings")
	if entries, err := os.ReadDir(stray); err == nil && len(entries) > 0 {
		return noteRes(i18n.T("%d recording(s) from another recorder sit in %s, outside %s"),
			len(entries), tildeOf(stray), tildeOf(dir)).
			withFix("mv " + tildeOf(stray) + "/* " + tildeOf(dir) + "/ && rmdir " + tildeOf(stray))
	}

	if len(did) > 0 {
		return fixedRes("%s", strings.Join(did, "; "))
	}
	return okRes(i18n.T("everything records into %s"), tildeOf(dir))
}

// moveContents moves every entry of src into dst without overwriting: a name
// already taken gets a numeric suffix, so nothing a user recorded is lost.
func moveContents(src, dst string) (int, error) {
	entries, err := os.ReadDir(src)
	if err != nil {
		return 0, err
	}
	moved := 0
	for _, e := range entries {
		from := filepath.Join(src, e.Name())
		to := filepath.Join(dst, e.Name())
		for i := 1; ; i++ {
			if _, err := os.Lstat(to); os.IsNotExist(err) {
				break
			}
			ext := filepath.Ext(e.Name())
			base := strings.TrimSuffix(e.Name(), ext)
			to = filepath.Join(dst, fmt.Sprintf("%s-%d%s", base, i, ext))
		}
		if err := os.Rename(from, to); err != nil {
			return moved, err
		}
		moved++
	}
	return moved, nil
}

// sameDir compares two paths after resolving them, so a symlink already
// pointing at the target is not "moved" onto itself.
func sameDir(a, b string) bool {
	if a == "" || b == "" {
		return false
	}
	ra, err1 := filepath.EvalSymlinks(a)
	rb, err2 := filepath.EvalSymlinks(b)
	if err1 == nil && err2 == nil {
		return ra == rb
	}
	return filepath.Clean(a) == filepath.Clean(b)
}

// tildeOf shortens a path under HOME for the report.
func tildeOf(p string) string {
	if h := homeDir(); h != "" && strings.HasPrefix(p, h+"/") {
		return "~" + p[len(h):]
	}
	return p
}
