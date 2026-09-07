package doctor

import "testing"

func TestRyogamiWallpaperActions(t *testing.T) {
	cases := []struct {
		name                                        string
		state                                       ryogamiWallpaperState
		wantEnable, wantFailed, wantStart, wantAwww bool
	}{
		{"fresh cutover: not enabled, awww still up",
			ryogamiWallpaperState{enabled: false, active: false, awwwRunning: true, inSession: true},
			true, false, true, true},
		{"enabled and running does nothing",
			ryogamiWallpaperState{enabled: true, active: true, inSession: true},
			false, false, false, false},
		{"enabled but wedged clears failed and starts",
			ryogamiWallpaperState{enabled: true, active: false, failed: true, inSession: true},
			false, true, true, false},
		{"enabled with stray awww stops it",
			ryogamiWallpaperState{enabled: true, active: true, awwwRunning: true, inSession: true},
			false, false, false, true},
		// The case an enabled-only check cannot see: systemd skipped the unit on
		// its ConditionEnvironment, so it is enabled, inactive and not failed,
		// and the desktop has no wallpaper while nothing looks wrong.
		{"enabled but skipped by its condition is started",
			ryogamiWallpaperState{enabled: true, active: false, failed: false, inSession: true},
			false, false, true, false},
		// Outside the session the condition would refuse a start and inactive is
		// the correct state, so it must not be reported as a fault.
		{"inactive outside the graphical session is fine",
			ryogamiWallpaperState{enabled: true, active: false, failed: false, inSession: false},
			false, false, false, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			gotEnable, gotFailed, gotStart, gotAwww := ryogamiWallpaperActions(c.state)
			if gotEnable != c.wantEnable || gotFailed != c.wantFailed || gotStart != c.wantStart || gotAwww != c.wantAwww {
				t.Fatalf("ryogamiWallpaperActions(%+v) = (enable=%v, failed=%v, start=%v, stopAwww=%v), want (%v, %v, %v, %v)",
					c.state, gotEnable, gotFailed, gotStart, gotAwww,
					c.wantEnable, c.wantFailed, c.wantStart, c.wantAwww)
			}
		})
	}
}
