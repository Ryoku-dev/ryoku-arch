package doctor

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	i18n "ryoku-i18n"
)

// ---- reconciler: a portal frontend left over from a previous session ----------
//
// xdg-desktop-portal is only PartOf=graphical-session.target and nothing ever
// stops that target, so logging out and back in leaves the old session's
// frontend running. A ScreenCast request then times out inside it instead of
// reaching the hyprland backend: no source picker, and the app is handed
// nothing with no error anywhere the user looks. A frontend older than the
// Hyprland it serves cannot belong to this session, and restarting it is
// enough; the backend re-registers on demand.

// parseStartTicks reads field 22 of /proc/<pid>/stat, in clock ticks since boot.
// The comm field may itself hold spaces and parentheses, so the count starts at
// the LAST ')' instead of splitting the whole line.
func parseStartTicks(stat string) (uint64, bool) {
	paren := strings.LastIndexByte(stat, ')')
	if paren < 0 {
		return 0, false
	}
	// state (field 3) is the first field after comm, so starttime (22) is the
	// 20th of what remains.
	f := strings.Fields(stat[paren+1:])
	if len(f) < 20 {
		return 0, false
	}
	ticks, err := strconv.ParseUint(f[19], 10, 64)
	if err != nil {
		return 0, false
	}
	return ticks, true
}

func procStartTicks(pid int) (uint64, bool) {
	b, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "stat"))
	if err != nil {
		return 0, false
	}
	return parseStartTicks(string(b))
}

// compositorStartTicks is the start time of the session's Hyprland, walked out
// of /proc rather than asked of hyprctl: the point is to compare against the
// LIVE compositor even when the caller's HYPRLAND_INSTANCE_SIGNATURE names a
// dead one. Oldest match wins, so a nested Hyprland cannot make a healthy
// frontend look stale and get it restarted out from under a live share.
func compositorStartTicks() (uint64, bool) {
	ents, err := os.ReadDir("/proc")
	if err != nil {
		return 0, false
	}
	oldest, found := uint64(0), false
	for _, e := range ents {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		comm, err := os.ReadFile(filepath.Join("/proc", e.Name(), "comm"))
		if err != nil || strings.TrimSpace(string(comm)) != "Hyprland" {
			continue
		}
		if ticks, ok := procStartTicks(pid); ok && (!found || ticks < oldest) {
			oldest, found = ticks, true
		}
	}
	return oldest, found
}

// userUnitMainPID is the MainPID of a --user unit, or 0 when it is not running.
func userUnitMainPID(unit string) int {
	out, err := exec.Command("systemctl", "--user", "show", "-p", "MainPID", "--value", unit).Output()
	if err != nil {
		return 0
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(out)))
	if err != nil {
		return 0
	}
	return pid
}

func reconcilePortalSession(checkOnly bool) recResult {
	hyprStart, ok := compositorStartTicks()
	if !ok {
		return okRes(i18n.T("no running compositor to compare against"))
	}
	fePID := userUnitMainPID("xdg-desktop-portal.service")
	if fePID == 0 {
		return okRes(i18n.T("portal frontend not running; it activates fresh on first use"))
	}
	feStart, ok := procStartTicks(fePID)
	if !ok {
		return okRes(i18n.T("could not read the portal frontend's start time"))
	}
	if feStart >= hyprStart {
		return okRes(i18n.T("portal frontend belongs to this session"))
	}
	if checkOnly {
		return wouldRes(i18n.T("the portal frontend predates this Hyprland session; screen share opens no source picker and silently shares nothing")).
			withFix(i18n.T("ryoku doctor restarts xdg-desktop-portal"))
	}
	if err := exec.Command("systemctl", "--user", "restart", "xdg-desktop-portal.service").Run(); err != nil {
		return failRes(i18n.T("could not restart the portal frontend: %v"), err).
			withFix("systemctl --user restart xdg-desktop-portal.service")
	}
	return fixedRes(i18n.T("restarted the portal frontend against this session; screen share picks a source again"))
}
