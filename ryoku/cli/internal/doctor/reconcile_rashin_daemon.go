package doctor

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: deliver the hardened rashin daemon to boxes that enabled it -
//
// The rashin agent daemon is opt-in. Boxes that turned it on before the
// hardening shipped are stuck two ways `pacman -Syu` alone cannot fix: the
// pre-hardening unit could trip systemd's default start-limit and park itself
// in `failed` for good (the daemon that "turns off and stays off"), and the
// one-click setup only ever enabled it for login-start, so a headless boot
// leaves the dashboard down (the daemon that "does not turn on"). The package
// lays the new unit file, but only a daemon-reload makes systemd run it on a
// live box, only enable-linger starts it at boot, and only reset-failed clears
// a unit already wedged off. This converges all three. Idempotent, and it never
// turns the daemon on for a user who left it off; retired once every enabled
// box has run it once.

const rashinUserUnit = "ryoku-rashin.service"

// rashinUnitState is the subset of systemd state the reconciler decides on,
// split out so the decision is unit-testable without a live user manager.
type rashinUnitState struct {
	enabled bool
	linger  bool
	failed  bool
}

// rashinDaemonActions decides what an enabled box needs to converge: bring
// boot-start on when lingering is off, and clear a unit wedged into `failed`.
// A disabled unit needs nothing (the daemon is opt-in).
func rashinDaemonActions(s rashinUnitState) (enableLinger, clearFailed bool) {
	if !s.enabled {
		return false, false
	}
	return !s.linger, s.failed
}

func rashinUnitEnabled() bool {
	out, _ := exec.Command("systemctl", "--user", "is-enabled", rashinUserUnit).Output()
	return strings.TrimSpace(string(out)) == "enabled"
}

func rashinUnitFailed() bool {
	out, _ := exec.Command("systemctl", "--user", "is-failed", rashinUserUnit).Output()
	return strings.TrimSpace(string(out)) == "failed"
}

// rashinLingerOn reads the marker systemd-logind maintains for a lingering user,
// which is readable the same whether doctor runs as the user or under sudo.
func rashinLingerOn(user string) bool {
	if user == "" {
		return false
	}
	_, err := os.Stat("/var/lib/systemd/linger/" + user)
	return err == nil
}

func doctorUser() string {
	if u := os.Getenv("USER"); u != "" {
		return u
	}
	return os.Getenv("LOGNAME")
}

func reconcileRashinDaemon(checkOnly bool) recResult {
	if !sys.Has("ryoku-rashin") {
		return okRes(i18n.T("ryoku-rashin not installed"))
	}
	if !rashinUnitEnabled() {
		return okRes(i18n.T("rashin daemon is opt-in and not enabled"))
	}
	user := doctorUser()
	state := rashinUnitState{enabled: true, linger: rashinLingerOn(user), failed: rashinUnitFailed()}
	enableLinger, clearFailed := rashinDaemonActions(state)
	wireSkill := rashinSkillLinksMissing()
	if !enableLinger && !clearFailed && !wireSkill {
		return okRes(i18n.T("rashin daemon enabled with boot-start; the ryoku skill is wired"))
	}
	if checkOnly {
		switch {
		case clearFailed:
			return wouldRes(i18n.T("the rashin daemon is enabled but wedged off (failed); the dashboard is down")).
				withFix(i18n.T("ryoku doctor reloads the hardened unit and restarts it"))
		case enableLinger:
			return wouldRes(i18n.T("rashin is enabled but only starts at login; a headless boot leaves the dashboard down")).
				withFix(i18n.T("ryoku doctor enables lingering so it starts at boot"))
		default:
			return wouldRes(i18n.T("rashin is enabled but the ryoku agent skill is not wired into every agent")).
				withFix(i18n.T("ryoku doctor runs `ryoku-rashin wire`"))
		}
	}
	var did []string
	if enableLinger || clearFailed {
		// daemon-reload so the just-delivered hardened unit is the one systemd runs.
		_ = exec.Command("systemctl", "--user", "daemon-reload").Run()
	}
	if enableLinger {
		if user == "" {
			return failRes(i18n.T("cannot enable rashin boot-start: no login user in the environment")).
				withFix("sudo loginctl enable-linger <you>")
		}
		if err := sys.Sudo("loginctl", "enable-linger", user); err != nil {
			return failRes(i18n.T("could not enable lingering for the rashin daemon: %v"), err).
				withFix("sudo loginctl enable-linger " + user)
		}
		did = append(did, i18n.T("enabled boot-start (lingering)"))
	}
	if clearFailed {
		_ = exec.Command("systemctl", "--user", "reset-failed", rashinUserUnit).Run()
		did = append(did, i18n.T("cleared the wedged failed state"))
	}
	if enableLinger || clearFailed {
		_ = exec.Command("systemctl", "--user", "start", rashinUserUnit).Run()
		did = append(did, i18n.T("reloaded the hardened unit"))
	}
	if wireSkill {
		// wire is idempotent and cheap: it drops the ryoku skill symlink into
		// every agent's skills dir and refreshes the vault pointers.
		_ = exec.Command("ryoku-rashin", "wire").Run()
		did = append(did, i18n.T("wired the ryoku agent skill"))
	}
	return fixedRes(i18n.T("converged the rashin daemon: ") + strings.Join(did, " and "))
}

// reconcileProwlAgent surfaces a rashin box that lost its prowl-agent binary.
// ryoku-rashin now depends on prowl-agent (its `index` builds the vault code map
// and its `wire` installs Prowl's agent skills), so a box that enabled rashin
// before that dependency shipped can run without it. `pacman -Syu` delivers it
// going forward; this reports the gap for a box still stuck without it. Reported,
// never auto-run: installing a package is the user's call.
func reconcileProwlAgent(checkOnly bool) recResult {
	enabled := rashinUnitEnabled()
	present := sys.Has("prowl-agent")
	if !prowlAgentNeeded(enabled, present) {
		if !enabled {
			return okRes(i18n.T("rashin daemon is opt-in and not enabled"))
		}
		return okRes(i18n.T("prowl-agent is present for the rashin agent index"))
	}
	return warnRes(i18n.T("rashin is enabled but prowl-agent is missing; the vault code index and agent skills will not refresh")).
		withFix("sudo pacman -S prowl-agent")
}

// prowlAgentNeeded reports whether a box should be told to install prowl-agent:
// rashin is enabled but the binary is absent. Split out so the decision is
// unit-testable without a live systemd or PATH.
func prowlAgentNeeded(rashinEnabled, prowlPresent bool) bool {
	return rashinEnabled && !prowlPresent
}

// rashinSkillSource resolves the shipped `ryoku` skill dir the same way
// ryoku-rashin wire does: an override, the packaged tree, then a dev checkout.
// Returns "" when the skill is not installed, so a box without it stays quiet.
func rashinSkillSource() string {
	var roots []string
	if v := strings.TrimSpace(os.Getenv("RYOKU_RASHIN_SKILLS")); v != "" {
		roots = append(roots, v)
	}
	roots = append(roots, "/usr/share/ryoku/skills")
	if repo := sys.ResolveRepo(); repo != "" {
		roots = append(roots, filepath.Join(repo, "ryoku", "rashin", "skills"))
	}
	for _, r := range roots {
		if sys.Exists(filepath.Join(r, "ryoku", "SKILL.md")) {
			return filepath.Join(r, "ryoku")
		}
	}
	return ""
}

// rashinSkillLinksMissing reports whether the skill is installed but an
// always-created link (~/.agents, ~/.hermes) is absent or points elsewhere.
// Cheap: a couple of Lstat calls.
func rashinSkillLinksMissing() bool {
	src := rashinSkillSource()
	if src == "" {
		return false // skill not installed; nothing to wire
	}
	for _, link := range []string{
		filepath.Join(sys.Home(), ".agents", "skills", "ryoku"),
		filepath.Join(sys.Home(), ".hermes", "skills", "ryoku"),
	} {
		if !symlinkPointsAt(link, src) {
			return true
		}
	}
	return false
}
