package main

import (
	"log"
	"time"
)

// autoprofile switches the power profile to Power Saver while the machine runs on
// battery and restores the prior profile on AC, when the user opts in via
// performance.json's autoPowerSaverOnBattery. It rides the same sysfs power state
// powersounds reads and the same power-profiles-daemon connection the profile
// topic uses, so QML sees the switch on its normal PowerProfiles stream (and the
// shell's Perf policy then lightens the desktop). The decision is a pure step over
// the AC state and the saved profile, unit-tested without a bus, sysfs, or clock.

const ppSaver = "power-saver"

// autoProfile tracks one on-battery episode: the profile to restore on AC, and
// whether we already switched this episode, so a manual change while on battery is
// left alone until the next unplug.
type autoProfile struct {
	saved  string // profile to restore when back on AC; "" = nothing to restore
	active bool   // we switched to Power Saver for the current on-battery episode
}

// step folds one power reading into the tracker and returns the profile to set, or
// "" for no change. It switches once when a battery episode begins, restores on AC
// (or when the feature is turned off) only while the profile is still the saver we
// set, and otherwise keeps out of the way.
func (a *autoProfile) step(enabled, onBattery bool, current string, avail []string) string {
	hasSaver := false
	for _, p := range avail {
		if p == ppSaver {
			hasSaver = true
			break
		}
	}
	if enabled && hasSaver && onBattery {
		if a.active {
			return "" // already switched this episode; do not fight a manual change
		}
		a.active = true
		if current != ppSaver {
			a.saved = current
			return ppSaver
		}
		a.saved = "" // already on saver; nothing to restore to
		return ""
	}
	if a.active {
		a.active = false
		restore := a.saved
		a.saved = ""
		if restore != "" && current == ppSaver {
			return restore
		}
	}
	return ""
}

// watchAutoPowerSaver applies the auto-profile policy on the same 2 s cadence as
// the power cues. It no-ops without a power-profiles-daemon connection (d.pp nil)
// or on a machine with no battery.
func (d *daemon) watchAutoPowerSaver() {
	var a autoProfile
	prevAC, first := true, true
	for {
		if d.pp != nil {
			st := readPowerState()
			onBattery := st.present && st.discharging
			onAC := !onBattery
			active := d.pp.activeProfile()
			if !first && onAC != prevAC {
				d.pp.noteACFlip()
			}
			to := a.step(perfFlag("autoPowerSaverOnBattery"), onBattery, active, d.pp.profiles())
			// On the plug edge, if autoprofile has nothing to restore, re-assert
			// the saved profile so a firmware/ppd switch to performance on AC
			// cannot strand the desktop on a profile the user never picked.
			if to == "" && !first && onAC && !prevAC {
				if saved := readPersistedProfile(); saved != "" && saved != active {
					to = saved
				}
			}
			// Game mode owns the profile; don't fight its switch.
			if gameModeActive() {
				to = ""
			}
			if to != "" {
				if err := d.pp.setProfile(to); err != nil {
					log.Printf("ryoku-shell: auto power profile: set %q failed: %v", to, err)
				}
			}
			prevAC, first = onAC, false
		}
		select {
		case <-d.quit:
			return
		case <-time.After(powerPoll):
		}
	}
}
