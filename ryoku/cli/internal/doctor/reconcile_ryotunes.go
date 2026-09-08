package doctor

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"ryoku-cli/internal/ryotunesrelease"
	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ryotunesSocketUnit is the user unit systemd listens on for the native
// client. `ryotunes` defers to the daemon only when its socket exists; without
// the unit enabled a fresh package install keeps opening the Tauri app.
const ryotunesSocketUnit = "ryotunesd.socket"

// Keeps an updated box off the retired Chromium YouTube Music window: a wrapper
// or locally built copy in ~/.local/bin shadows /usr/bin/ryotunes on PATH, and
// the socket unit needs enabling for `ryotunes` to reach the daemon.
//
// Installing the package belongs to reconcile_shipped_apps.go, which honours a
// removal, so a missing package is silence here.
func reconcileRyotunes(checkOnly bool) recResult {
	if !sys.PkgInstalled("ryotunes") {
		if stale := staleUserRyotunes(filepath.Join(sys.Home(), ".local", "bin", "ryotunes")); stale == "" {
			return okRes(i18n.T("the ryotunes package is not installed; nothing to reconcile"))
		}
	}
	var problems, fixes []string

	bin := filepath.Join(sys.Home(), ".local", "bin", "ryotunes")
	stale := staleUserRyotunes(bin)
	if stale != "" {
		problems = append(problems, i18n.Tf("%s in ~/.local/bin shadows the packaged app", stale))
		fixes = append(fixes, "rm -f ~/.local/bin/ryotunes ~/.local/share/applications/ryotunes.desktop")
	}
	socketMissing := sys.PkgInstalled("ryotunes") && !ryotunesSocketEnabled()
	if socketMissing {
		problems = append(problems, i18n.T("the ryotunesd socket is not enabled, so `ryotunes` opens the old Tauri app"))
		fixes = append(fixes, "systemctl --user enable --now ryotunesd.socket")
	}
	if len(problems) == 0 {
		if _, err := sys.RunOut("pacman", "-Qoq", "/usr/bin/ryotunes"); err != nil && sys.Exists("/usr/bin/ryotunes") {
			return warnRes(i18n.T("/usr/bin/ryotunes is not owned by the ryotunes package")).
				withFix("sudo pacman -S --overwrite /usr/bin/ryotunes ryotunes")
		}
		if note, ok := ryotunesUpdateNote(); ok {
			return note
		}
		return okRes(i18n.T("ryotunes is the packaged app"))
	}
	if checkOnly {
		return wouldRes("%s", strings.Join(problems, "; ")).withFix(strings.Join(fixes, " && "))
	}
	if stale != "" {
		appshare := sys.Xdg("XDG_DATA_HOME", ".local/share")
		for _, p := range []string{
			bin,
			filepath.Join(appshare, "applications", "ryotunes.desktop"),
			filepath.Join(appshare, "ryoku", "ryotunes.commit"),
			filepath.Join(appshare, "icons", "hicolor", "scalable", "apps", "ryotunes.svg"),
		} {
			_ = os.Remove(p)
		}
		icons, _ := filepath.Glob(filepath.Join(appshare, "icons", "hicolor", "*", "apps", "ryotunes.png"))
		for _, p := range icons {
			_ = os.Remove(p)
		}
	}
	if socketMissing {
		// daemon-reload so a unit the package just delivered is known, then
		// enable --now: the socket binds in this session without a relogin.
		_ = exec.Command("systemctl", "--user", "daemon-reload").Run()
		if err := exec.Command("systemctl", "--user", "enable", "--now", ryotunesSocketUnit).Run(); err != nil {
			return failRes(i18n.T("could not enable %s: %v"), ryotunesSocketUnit, err).
				withFix("systemctl --user enable --now ryotunesd.socket")
		}
	}
	return fixedRes(i18n.T("ryotunes opens the packaged app (%s)"), strings.Join(problems, "; "))
}

// Release availability is advisory: doctor checks but never installs. A lookup
// failure remains visible in check/report modes without failing desktop health.
func ryotunesUpdateNote() (recResult, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	st, err := ryotunesrelease.Check(ctx)
	if err != nil {
		return noteRes(i18n.T("could not check Ryotunes releases: %v"), err), true
	}
	if !st.Available {
		return recResult{}, false
	}
	return noteRes(i18n.T("a newer Ryotunes (%s) is available; `ryoku update` installs it"), st.Latest).
		withFix("ryoku update"), true
}

func ryotunesSocketEnabled() bool {
	out, _ := exec.Command("systemctl", "--user", "is-enabled", ryotunesSocketUnit).Output()
	return strings.TrimSpace(string(out)) == "enabled"
}

// staleUserRyotunes names what ~/.local/bin/ryotunes is when it is not the
// user's own program: the Chromium wrapper (a script that opens
// music.youtube.com) or a build the dev deploy recorded a commit for.
func staleUserRyotunes(bin string) string {
	st, err := os.Stat(bin)
	if err != nil || st.IsDir() {
		return ""
	}
	head := make([]byte, 4096)
	if f, err := os.Open(bin); err == nil {
		n, _ := f.Read(head)
		f.Close()
		head = head[:n]
	}
	if strings.HasPrefix(string(head), "#!") && strings.Contains(string(head), "music.youtube.com") {
		return "the Chromium YouTube Music wrapper"
	}
	if sys.Exists(filepath.Join(sys.Xdg("XDG_DATA_HOME", ".local/share"), "ryoku", "ryotunes.commit")) {
		return "a locally built ryotunes"
	}
	return ""
}
