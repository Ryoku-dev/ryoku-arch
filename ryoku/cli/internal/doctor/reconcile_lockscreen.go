package doctor

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: the in-session lockscreen -----------------------------------
//
// `ryoku-shell lock` execs ~/.local/share/quickshell-lockscreen/lock.sh, and
// only the ISO installer ever laid that down. A box that predates the step, or
// where it failed, has a dead lock button and, worse, suspends without locking:
// hypridle's before_sleep runs the same command. The bundle now ships in
// ryoku-desktop (and lives in a checkout), so this can heal it anywhere.
//
// It also converges an INSTALLED bundle onto the shipped one. The copy under
// ~/.local/share is outside materialize's tree, so before this a lock fix (a
// reveal, a cursor default, a shim change) reached only fresh installs; every
// existing box kept the lock it was installed with. Only the shipped default
// skin (clockwork/orbital) is ever refreshed; a skin the user picked from the
// Store is never touched.

const defaultLockSkin = "clockwork/orbital"

// lockBundle finds the shipped qylock bundle: the package payload first, the
// checkout on a dev box.
func lockBundle() string {
	if p := "/usr/share/ryoku/lockscreen/qylock"; sys.Exists(p) {
		return p
	}
	if repo := sys.ResolveRepo(); repo != "" {
		if p := filepath.Join(repo, "ryoku", "lockscreen", "qylock"); sys.Exists(p) {
			return p
		}
	}
	return ""
}

// treeDiffers reports whether any regular file under src is missing at, or
// differs from, the same relative path under dst. Extra files under dst (the
// themes_link symlink, a user's additions) do not count.
func treeDiffers(src, dst string) bool {
	differs := false
	_ = filepath.WalkDir(src, func(p string, d os.DirEntry, err error) error {
		if err != nil || differs || !d.Type().IsRegular() {
			return nil
		}
		rel, _ := filepath.Rel(src, p)
		want, err := os.ReadFile(p)
		if err != nil {
			return nil
		}
		got, err := os.ReadFile(filepath.Join(dst, rel))
		if err != nil || !bytes.Equal(want, got) {
			differs = true
		}
		return nil
	})
	return differs
}

// lockscreenStale: the installed in-session lock (its runner and the default
// skin) no longer matches what the package ships.
func lockscreenStale(bundle string) bool {
	home := os.Getenv("HOME")
	return treeDiffers(filepath.Join(bundle, "quickshell-lockscreen"), filepath.Join(home, ".local", "share", "quickshell-lockscreen")) ||
		treeDiffers(filepath.Join(bundle, "themes", defaultLockSkin), filepath.Join(home, ".local", "share", "qylock", "themes", defaultLockSkin))
}

// greeterStale: the SDDM greeter is the shipped default skin (the preference
// names it, or was never written) and its installed copy drifted from the
// bundle. A picked skin is the user's; leave it.
func greeterStale(bundle string) bool {
	pref := strings.TrimSpace(readFileSafe(filepath.Join(sys.ConfigHome(), "qylock", "theme")))
	if pref != "" && pref != defaultLockSkin {
		return false
	}
	if !sys.Exists(filepath.Join(greeterThemeDir, "Main.qml")) {
		return false
	}
	return treeDiffers(filepath.Join(bundle, "themes", defaultLockSkin), greeterThemeDir)
}

// refreshGreeter re-lays the shipped default skin as the SDDM greeter, with the
// ownership and modes the sddm user needs (see reconcileGreeterTheme).
func refreshGreeter(bundle string) error {
	src := filepath.Join(bundle, "themes", defaultLockSkin)
	tmp := greeterThemeDir + ".new"
	if err := sys.Run("sudo", "rm", "-rf", tmp); err != nil {
		return err
	}
	if err := sys.Run("sudo", "cp", "-a", src, tmp); err != nil {
		return err
	}
	if err := sys.Run("sudo", "chown", "-R", "root:root", tmp); err != nil {
		return err
	}
	if err := sys.Run("sudo", "chmod", "-R", "a+rX", tmp); err != nil {
		return err
	}
	if err := sys.Run("sudo", "rm", "-rf", greeterThemeDir); err != nil {
		return err
	}
	return sys.Run("sudo", "mv", tmp, greeterThemeDir)
}

func lockerPath() string {
	return filepath.Join(os.Getenv("HOME"), ".local", "share", "quickshell-lockscreen", "lock.sh")
}

func legacyTapePath() string {
	return filepath.Join(os.Getenv("HOME"), ".local", "share", "qylock", "themes", "clockwork", "tape", "Main.qml")
}

func needsLockscreenInstaller(lockerPresent, legacyTape bool) bool {
	return !lockerPresent || legacyTape
}

// lockscreenInstaller finds the shipped installer: the package payload first,
// the checkout on a dev box.
func lockscreenInstaller() string {
	if p := "/usr/share/ryoku/lockscreen/install-qylock"; sys.Exists(p) {
		return p
	}
	if repo := sys.ResolveRepo(); repo != "" {
		if p := filepath.Join(repo, "ryoku", "lockscreen", "install-qylock"); sys.Exists(p) {
			return p
		}
	}
	return ""
}

func reconcileLockscreen(checkOnly bool) recResult {
	lockerPresent := sys.Exists(lockerPath())
	legacyTape := sys.Exists(legacyTapePath())
	if !needsLockscreenInstaller(lockerPresent, legacyTape) {
		return reconcileLockscreenDrift(checkOnly)
	}
	installer := lockscreenInstaller()
	if installer == "" {
		if legacyTape {
			return warnRes(i18n.T("the legacy Tape lockscreen needs migration and no lockscreen bundle is available")).
				withFix(i18n.T("ryoku update (ships the lockscreen bundle), then ryoku doctor"))
		}
		return warnRes(i18n.T("the in-session lockscreen is missing and no bundle is available to install it; the lock button and lock-on-sleep do nothing")).
			withFix(i18n.T("ryoku update (ships the lockscreen bundle), then ryoku doctor"))
	}
	if checkOnly {
		if legacyTape {
			return wouldRes(i18n.T("the legacy Tape lockscreen needs one-time Store migration")).
				withFix("ryoku doctor")
		}
		return wouldRes(i18n.T("the in-session lockscreen is missing; the lock button and lock-on-sleep do nothing")).
			withFix("ryoku doctor")
	}
	// RYOKU_QYLOCK_USER_ONLY skips the SDDM greeter half: it needs root, the
	// installer already did it at install time, and a user-session doctor run
	// must not hang on a sudo prompt.
	cmd := exec.Command(installer)
	cmd.Env = append(os.Environ(), "RYOKU_QYLOCK_USER_ONLY=1")
	if out, err := cmd.CombinedOutput(); err != nil {
		return failRes(i18n.T("lockscreen install failed: %v (%s)"), err, firstLine(string(out))).
			withFix(i18n.T("run %s by hand to see why"), installer)
	}
	if !sys.Exists(lockerPath()) {
		return failRes(i18n.T("lockscreen installer ran but %s did not appear"), lockerPath())
	}
	if legacyTape && !sys.Exists(legacyTapePath()) {
		return fixedRes(i18n.T("migrated the legacy Tape lockscreen into Store ownership"))
	}
	if lockerPresent {
		return okRes(i18n.T("in-session lockscreen installed; custom legacy Tape retained"))
	}
	return fixedRes(i18n.T("installed the in-session lockscreen; the lock button and lock-on-sleep work again"))
}

// reconcileLockscreenDrift refreshes an installed lock onto the shipped bundle
// (see the header). The user half re-runs the installer without the greeter
// step; the greeter half copies the skin as root, only when it is the shipped
// default and only when a sudo is available without a prompt (an update has
// one cached; a plain doctor run may not, and reports instead).
func reconcileLockscreenDrift(checkOnly bool) recResult {
	bundle := lockBundle()
	if bundle == "" {
		return okRes(i18n.T("in-session lockscreen installed"))
	}
	lockStale := lockscreenStale(bundle)
	greeter := greeterStale(bundle)
	if !lockStale && !greeter {
		return okRes(i18n.T("in-session lockscreen installed and current"))
	}
	if checkOnly {
		return wouldRes(i18n.T("the installed lockscreen predates the shipped one; lock fixes have not reached this box")).
			withFix("ryoku doctor")
	}
	var did []string
	if lockStale {
		installer := lockscreenInstaller()
		if installer == "" {
			return warnRes(i18n.T("the installed lockscreen predates the shipped one and no installer is available")).
				withFix("ryoku update")
		}
		cmd := exec.Command(installer)
		cmd.Env = append(os.Environ(), "RYOKU_QYLOCK_USER_ONLY=1")
		if out, err := cmd.CombinedOutput(); err != nil {
			return failRes(i18n.T("lockscreen refresh failed: %v (%s)"), err, firstLine(string(out))).
				withFix(i18n.T("run %s by hand to see why"), installer)
		}
		did = append(did, i18n.T("in-session lock"))
	}
	if greeter {
		if exec.Command("sudo", "-n", "true").Run() != nil {
			return noteRes(i18n.T("the SDDM greeter predates the shipped skin; refreshing it needs sudo")).
				withFix(i18n.T("sudo ryoku doctor (or the next ryoku update)"))
		}
		if err := refreshGreeter(bundle); err != nil {
			return failRes(i18n.T("could not refresh the SDDM greeter skin: %v"), err).
				withFix("sudo " + lockscreenInstaller())
		}
		did = append(did, i18n.T("SDDM greeter"))
	}
	return fixedRes(i18n.T("refreshed the %s to the shipped lockscreen bundle"), strings.Join(did, " and "))
}
