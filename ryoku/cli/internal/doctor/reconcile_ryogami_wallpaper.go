package doctor

import (
	"os/exec"
	"strings"

	"ryoku-cli/internal/sys"
)

// ---- reconciler: cut existing boxes over from the old awww daemon to Ryogami -
//
// The wallpaper backend moved from awww (a swww fork the shell drove by name) to
// Ryogami, the in-repo daemon the shell now drives over ryogami.sock. `ryoku
// update` pulls the ryogami package (a ryoku-desktop depend) and drops the awww
// depend, but pacman alone leaves an existing box in a broken middle: the ryogami
// user unit is delivered but not enabled, so hyprland-session.target never owns
// it, and a stale awww-daemon from the old session keeps a surface mapped on the
// background layer that stacks over Ryogami's and swallows every static set. This
// daemon-reloads so systemd sees the delivered unit, enables it, clears it when
// wedged failed, and stops any leftover awww-daemon. Idempotent; retired once
// every box has cut over.

const ryogamiUserUnit = "ryogami.service"

// ryogamiWallpaperState is the subset of session state the reconciler decides
// on, split out so the decision is unit-testable without a live user manager.
type ryogamiWallpaperState struct {
	enabled     bool
	failed      bool
	awwwRunning bool
}

// ryogamiWallpaperActions decides what a box needs to finish the cutover: enable
// the delivered unit when it is not, clear a wedged failed state, and stop a
// leftover awww-daemon so it stops stacking over Ryogami's surface.
func ryogamiWallpaperActions(s ryogamiWallpaperState) (enable, clearFailed, stopAwww bool) {
	return !s.enabled, s.failed, s.awwwRunning
}

func ryogamiUnitEnabled() bool {
	out, _ := exec.Command("systemctl", "--user", "is-enabled", ryogamiUserUnit).Output()
	return strings.TrimSpace(string(out)) == "enabled"
}

func ryogamiUnitFailed() bool {
	out, _ := exec.Command("systemctl", "--user", "is-failed", ryogamiUserUnit).Output()
	return strings.TrimSpace(string(out)) == "failed"
}

func awwwDaemonRunning() bool {
	return exec.Command("pgrep", "-x", "awww-daemon").Run() == nil
}

func reconcileRyogamiWallpaper(checkOnly bool) recResult {
	if !sys.Has("ryogami") {
		return okRes("ryogami not installed yet (arrives with the ryoku-desktop update)")
	}
	state := ryogamiWallpaperState{
		enabled:     ryogamiUnitEnabled(),
		failed:      ryogamiUnitFailed(),
		awwwRunning: awwwDaemonRunning(),
	}
	enable, clearFailed, stopAwww := ryogamiWallpaperActions(state)
	if !enable && !clearFailed && !stopAwww {
		return okRes("ryogami wallpaper daemon enabled; no awww left to retire")
	}
	if checkOnly {
		switch {
		case stopAwww:
			return wouldRes("the retired awww wallpaper daemon is still running and stacks over Ryogami").
				withFix("ryoku doctor stops awww-daemon and enables the ryogami unit")
		case clearFailed:
			return wouldRes("the ryogami wallpaper daemon is wedged off (failed); the wallpaper is down").
				withFix("ryoku doctor reloads and restarts the ryogami unit")
		default:
			return wouldRes("the ryogami wallpaper daemon is delivered but not enabled").
				withFix("ryoku doctor enables the ryogami unit so the session starts it")
		}
	}
	// daemon-reload so systemd runs the just-delivered unit file.
	_ = exec.Command("systemctl", "--user", "daemon-reload").Run()
	var did []string
	if enable {
		_ = exec.Command("systemctl", "--user", "enable", ryogamiUserUnit).Run()
		did = append(did, "enabled the ryogami unit")
	}
	if clearFailed {
		_ = exec.Command("systemctl", "--user", "reset-failed", ryogamiUserUnit).Run()
		did = append(did, "cleared the wedged failed state")
	}
	if stopAwww {
		_ = exec.Command("pkill", "-x", "awww-daemon").Run()
		did = append(did, "stopped the retired awww-daemon")
	}
	// Refresh a daemon still running the pre-cutover binary so the delivered one
	// takes over and paints -- it restores the recorded wallpaper, or a shipped
	// default when none is recorded, instead of leaving the empty grey frame --
	// then start one that is down. Best-effort: a no-op outside a graphical
	// session (the unit gates on ConditionEnvironment=WAYLAND_DISPLAY), where
	// autostart starts it at login.
	_ = exec.Command("systemctl", "--user", "try-restart", ryogamiUserUnit).Run()
	_ = exec.Command("systemctl", "--user", "start", ryogamiUserUnit).Run()
	return fixedRes("cut the wallpaper over to Ryogami: " + strings.Join(did, ", "))
}
