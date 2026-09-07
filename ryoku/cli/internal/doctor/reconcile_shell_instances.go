package doctor

// One desktop, not two. Quickshell runs a second instance of the same config
// without complaint, so a surface orphaned by a killed daemon (the unit is
// KillMode=process) keeps drawing beside the live one for the rest of the
// session. The instance whose parent is the supervising daemon is the desktop;
// the rest are leftovers and go.

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	i18n "ryoku-i18n"
)

// shellInstance is one live Quickshell process that renders a Ryoku config.
type shellInstance struct {
	pid    int
	ppid   int
	config string // the config it renders: "shell" for the desktop
}

// shellUnit is the systemd user unit that owns the desktop.
const shellUnit = "ryoku-shell.service"

func reconcileShellInstances(checkOnly bool) recResult {
	found := liveShellInstances()
	if len(found) < 2 {
		return okRes(i18n.T("one desktop instance is running"))
	}

	keep, strays := pickLiveShell(found, userUnitMainPID(shellUnit), daemonPids())
	if len(strays) == 0 {
		return okRes(i18n.T("one desktop instance is running"))
	}
	if checkOnly {
		return wouldRes(i18n.T("%d duplicate desktop instance(s) are running beside the live one (pid %d)"), len(strays), keep).
			withFix(i18n.T("ryoku doctor stops the duplicates; the desktop you are using stays up"))
	}

	pids := make([]int, 0, len(strays))
	for _, s := range strays {
		pids = append(pids, s.pid)
	}
	killShellInstances(pids)
	if left := livePids(pids); len(left) > 0 {
		return failRes(i18n.T("could not stop duplicate desktop instance(s) %v"), left).
			withFix(i18n.T("log out and back in; a wedged Quickshell cannot be signalled away"))
	}
	return fixedRes(i18n.T("stopped %d duplicate desktop instance(s); pid %d keeps the desktop"), len(pids), keep)
}

// liveShellInstances lists the running Quickshell processes that render a Ryoku
// config, with the parent that started each one.
func liveShellInstances() []shellInstance {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil
	}
	var out []shellInstance
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		raw, err := os.ReadFile(filepath.Join("/proc", e.Name(), "cmdline"))
		if err != nil {
			continue
		}
		argv := strings.Split(strings.TrimRight(string(raw), "\x00"), "\x00")
		config, ok := quickshellConfig(argv)
		if !ok || config != "shell" {
			continue
		}
		out = append(out, shellInstance{pid: pid, ppid: procPPID(pid), config: config})
	}
	return out
}

// quickshellConfig names the config an argv runs, and reports false for anything
// that is not a Quickshell instance.
//
// Both selector forms name the same desktop: a packaged install runs `qs -c
// shell` and a checkout runs `qs -p <repo>/ryoku/shell/quickshell/shell`, and a
// box that has been both ways is exactly where duplicates hid. A selector
// followed by a subcommand (`qs -c shell ipc call ...`) is a client talking to an
// instance, not an instance.
func quickshellConfig(argv []string) (string, bool) {
	if len(argv) < 3 {
		return "", false
	}
	switch filepath.Base(argv[0]) {
	case "qs", "quickshell":
	default:
		return "", false
	}
	for i := 1; i < len(argv)-1; i++ {
		switch argv[i] {
		case "-c", "--config", "-p", "--path":
			if i+2 != len(argv) {
				return "", false
			}
			return filepath.Base(argv[i+1]), true
		}
	}
	return "", false
}

// pickLiveShell decides which instance is the desktop and which are leftovers.
// The keeper is the one started by the supervising daemon: the systemd unit's
// MainPID first, then any live `ryoku-shell daemon` (a dev checkout runs it
// outside systemd), and failing both the oldest instance, which is the one the
// session came up with.
func pickLiveShell(found []shellInstance, unitPID int, daemons map[int]bool) (int, []shellInstance) {
	if len(found) == 0 {
		return 0, nil
	}
	keeper := -1
	for i, s := range found {
		if unitPID > 0 && s.ppid == unitPID {
			keeper = i
			break
		}
	}
	if keeper < 0 {
		for i, s := range found {
			if daemons[s.ppid] {
				keeper = i
				break
			}
		}
	}
	if keeper < 0 {
		// No daemon owns any of them (every one was orphaned): keep the instance
		// that has been up longest, which is the desktop the session has been
		// using, and clear the newcomers drawn on top of it.
		keeper = 0
		best, ok := procStartTicks(found[0].pid)
		for i := 1; i < len(found); i++ {
			ticks, got := procStartTicks(found[i].pid)
			if got && (!ok || ticks < best) {
				keeper, best, ok = i, ticks, true
			}
		}
	}
	var strays []shellInstance
	for i, s := range found {
		if i != keeper {
			strays = append(strays, s)
		}
	}
	return found[keeper].pid, strays
}

// daemonPids: every live `ryoku-shell daemon`, so an instance supervised outside
// systemd (a dev checkout) is still recognised as the live one.
func daemonPids() map[int]bool {
	out := map[int]bool{}
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return out
	}
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		raw, err := os.ReadFile(filepath.Join("/proc", e.Name(), "cmdline"))
		if err != nil {
			continue
		}
		argv := strings.Split(strings.TrimRight(string(raw), "\x00"), "\x00")
		if len(argv) >= 2 && filepath.Base(argv[0]) == "ryoku-shell" && argv[1] == "daemon" {
			out[pid] = true
		}
	}
	return out
}

// procPPID reads a process's parent from /proc, 0 when it cannot be read. The
// status file is used rather than stat: a process name can contain spaces and
// parentheses, which makes field counting in stat fragile.
func procPPID(pid int) int {
	b, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "status"))
	if err != nil {
		return 0
	}
	for _, line := range strings.Split(string(b), "\n") {
		if rest, ok := strings.CutPrefix(line, "PPid:"); ok {
			if v, err := strconv.Atoi(strings.TrimSpace(rest)); err == nil {
				return v
			}
			return 0
		}
	}
	return 0
}

// killShellInstances asks the duplicates to quit, then insists. A Quickshell that
// is wedged (the state that produced the duplicate in the first place) would
// ignore a polite signal and keep drawing.
func killShellInstances(pids []int) {
	signalPids(pids, syscall.SIGTERM)
	deadline := time.Now().Add(3 * time.Second)
	for len(livePids(pids)) > 0 && time.Now().Before(deadline) {
		time.Sleep(100 * time.Millisecond)
	}
	if left := livePids(pids); len(left) > 0 {
		signalPids(left, syscall.SIGKILL)
		deadline = time.Now().Add(time.Second)
		for len(livePids(left)) > 0 && time.Now().Before(deadline) {
			time.Sleep(100 * time.Millisecond)
		}
	}
}

func signalPids(pids []int, sig syscall.Signal) {
	for _, pid := range pids {
		if p, err := os.FindProcess(pid); err == nil {
			_ = p.Signal(sig)
		}
	}
}

// livePids filters to the pids that are still running. A zombie is finished, so
// it does not count as a live desktop.
func livePids(pids []int) []int {
	var out []int
	for _, pid := range pids {
		b, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "stat"))
		if err != nil {
			continue
		}
		s := string(b)
		i := strings.LastIndexByte(s, ')')
		if i < 0 {
			continue
		}
		fields := strings.Fields(s[i+1:])
		if len(fields) > 0 && fields[0] == "Z" {
			continue
		}
		out = append(out, pid)
	}
	return out
}
