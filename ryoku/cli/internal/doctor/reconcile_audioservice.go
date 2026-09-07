package doctor

import (
	"context"
	"os"
	"os/exec"
	"strconv"
	"time"

	i18n "ryoku-i18n"
)

// ---- reconciler: a wedged PipeWire stack ------------------------------------
//
// A pipewire upgrade can leave stale user daemons behind, and a hung USB audio
// device can park wireplumber in kernel I/O -- either way sound stops and the
// graph never recovers on its own. ryoku-restart-audio is the recovery: restart
// the three user units, and if that does not take, reset a stuck USB audio
// device. It shipped as a manual command; this wires it into `ryoku doctor` so
// an update (or a hand-run doctor) heals a dead audio stack automatically.
//
// Fires ONLY when pipewire is actually running yet wpctl cannot talk to it --
// the unambiguous "wedged" signal. No session, or a healthy graph, is left
// alone, so a routine doctor pass never restarts working audio.

// wpctlResponds reports whether `wpctl status` answers within the timeout. A
// live PipeWire replies in milliseconds; a wedged one hangs until killed.
func wpctlResponds() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "wpctl", "status").Run() == nil
}

// pipewireRunning reports whether this user has a pipewire process, so a
// headless or logged-out doctor pass (no session) is not mistaken for a wedge.
func pipewireRunning() bool {
	return exec.Command("pgrep", "-u", strconv.Itoa(os.Getuid()), "-x", "pipewire").Run() == nil
}

func reconcileAudioService(checkOnly bool) recResult {
	if _, err := exec.LookPath("wpctl"); err != nil {
		return okRes(i18n.T("wpctl absent, nothing to check"))
	}
	if wpctlResponds() {
		return okRes(i18n.T("PipeWire is responding"))
	}
	if !pipewireRunning() {
		return okRes(i18n.T("no PipeWire session to recover"))
	}
	// pipewire is up but unreachable -> wedged.
	if checkOnly {
		return wouldRes(i18n.T("PipeWire is running but not responding")).withFix("ryoku-restart-audio")
	}
	if _, err := exec.LookPath("ryoku-restart-audio"); err != nil {
		return warnRes(i18n.T("PipeWire is wedged and ryoku-restart-audio is not installed")).withFix("ryoku-restart-audio")
	}
	_ = exec.Command("ryoku-restart-audio").Run()
	if wpctlResponds() {
		return fixedRes(i18n.T("restarted the audio stack; PipeWire is responding again"))
	}
	return warnRes(i18n.T("restarted the audio services but PipeWire still is not responding")).withFix("ryoku-restart-audio")
}
