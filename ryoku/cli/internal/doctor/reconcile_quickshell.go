package doctor

// Quickshell links Qt's private API, which breaks across Qt minor releases. The
// repo package is rebuilt with Qt; an AUR build (quickshell-git) is not, and it
// satisfies the dependency through provides, so the next Qt update turns every
// Ryoku surface into a black screen and makes `ryoku reload` look inert.

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

const qtCoreLib = "/usr/lib/libQt6Core.so.6"

func reconcileQuickshell(checkOnly bool) recResult {
	bin, err := exec.LookPath("qs")
	if err != nil {
		if _, err := exec.LookPath("quickshell"); err != nil {
			return warnRes(i18n.T("quickshell is not installed, so no Ryoku surface can render")).
				withFix("sudo pacman -S quickshell")
		}
		bin = "quickshell"
	}

	out, runErr := quickshellVersion(bin)
	owner := pkgOwning(bin)
	foreign := owner != "" && pkgIsForeign(owner)

	if runErr == nil {
		switch {
		case foreign && qtNewerThan(bin):
			return noteRes(i18n.T("quickshell comes from %s, built before the installed Qt; a Qt update can stop it loading"), owner).
				withFix(i18n.T("sudo pacman -S quickshell takes the repository build, which is rebuilt with Qt"))
		case foreign:
			return noteRes(i18n.T("quickshell comes from %s; an AUR build has to be rebuilt on every Qt update"), owner)
		}
		return okRes(i18n.T("quickshell runs"))
	}

	reason := loaderFailure(out)
	if reason == "" {
		return warnRes(i18n.T("quickshell will not start: %s"), firstLine(out)).
			withFix(i18n.T("run `qs --version` to see the error in full"))
	}

	// A QML module built locally (a plugin under development, Ryoku.Blobs on a
	// dev box) breaks the same way, and that one is ours to move.
	if mod := staleQmlModule(out); mod != "" {
		if checkOnly {
			return wouldRes(i18n.T("the QML module %s was built against another Qt and stops the desktop loading"), filepath.Base(mod)).
				withFix(i18n.T("ryoku doctor moves it aside; `ryoku deploy` rebuilds it against this Qt"))
		}
		if err := os.Rename(mod, mod+".stale"); err != nil {
			return failRes(i18n.T("could not move the stale QML module %s aside: %v"), mod, err).
				withFix(i18n.T("delete it by hand, then run `ryoku deploy`"))
		}
		return fixedRes(i18n.T("moved the stale QML module %s aside; `ryoku deploy` rebuilds it"), filepath.Base(mod))
	}

	if !foreign {
		return warnRes(i18n.T("quickshell will not start: %s"), reason).
			withFix(i18n.T("sudo pacman -Syu (the renderer and Qt are from different updates)"))
	}
	if checkOnly {
		return wouldRes(i18n.T("quickshell (%s) was built against another Qt and will not start: %s"), owner, reason).
			withFix(i18n.T("ryoku doctor installs the repository build, which is rebuilt with Qt"))
	}
	if err := sys.Sudo("pacman", "-S", "--needed", "--noconfirm", "quickshell"); err != nil {
		return failRes(i18n.T("could not replace %s with the repository quickshell: %v"), owner, err).
			withFix(i18n.T("sudo pacman -S quickshell, then restart the shell"))
	}
	if _, err := quickshellVersion(bin); err != nil {
		return failRes(i18n.T("quickshell still will not start after taking the repository build")).
			withFix(i18n.T("sudo pacman -Syu, then log out and back in"))
	}
	return fixedRes(i18n.T("replaced %s with the repository quickshell; restart the shell to get the desktop back"), owner)
}

// Running it is the only honest test: the break is a link failure, invisible to
// any version compare.
func quickshellVersion(bin string) (string, error) {
	cmd := exec.Command(bin, "--version")
	done := make(chan struct{})
	var out []byte
	var err error
	go func() {
		out, err = cmd.CombinedOutput()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(15 * time.Second):
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
		<-done
	}
	return string(out), err
}

func loaderFailure(out string) string {
	for _, line := range strings.Split(out, "\n") {
		l := strings.TrimSpace(line)
		if l == "" {
			continue
		}
		if strings.Contains(l, "symbol lookup error") ||
			strings.Contains(l, "undefined symbol") ||
			strings.Contains(l, "cannot open shared object") ||
			strings.Contains(l, "Qt_6_PRIVATE_API") {
			return l
		}
	}
	return ""
}

// Only modules under the user's own import path: a system one belongs to a
// package and is not ours to move.
func staleQmlModule(out string) string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	root := filepath.Join(home, ".local", "lib")
	for _, field := range strings.FieldsFunc(out, func(r rune) bool {
		return r == ' ' || r == '\n' || r == '\t' || r == ':' || r == '"' || r == '\''
	}) {
		if !strings.HasPrefix(field, root) || !strings.HasSuffix(field, ".so") {
			continue
		}
		if _, err := os.Stat(field); err == nil {
			return field
		}
	}
	return ""
}

func pkgOwning(bin string) string {
	path, err := exec.LookPath(bin)
	if err != nil {
		return ""
	}
	out, err := exec.Command("pacman", "-Qoq", path).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func pkgIsForeign(name string) bool {
	out, err := exec.Command("pacman", "-Qmq").Output()
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(out), "\n") {
		if strings.TrimSpace(line) == name {
			return true
		}
	}
	return false
}

// File times, not versions: an AUR package records no Qt it was compiled with.
func qtNewerThan(bin string) bool {
	path, err := exec.LookPath(bin)
	if err != nil {
		return false
	}
	binInfo, err := os.Stat(path)
	if err != nil {
		return false
	}
	qtInfo, err := os.Stat(qtCoreLib)
	if err != nil {
		return false
	}
	return qtInfo.ModTime().After(binInfo.ModTime())
}
