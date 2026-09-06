package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

// profileNames extracts the ordered profile names from the raw Profiles
// property (aa{sv}), skipping malformed rows and preserving service order.
func TestProfileNames(t *testing.T) {
	raw := []map[string]dbus.Variant{
		{"Profile": dbus.MakeVariant("power-saver"), "Driver": dbus.MakeVariant("amd_pstate")},
		{"Profile": dbus.MakeVariant("balanced")},
		{"Driver": dbus.MakeVariant("only")}, // no Profile key, skipped
		{"Profile": dbus.MakeVariant("performance")},
	}
	got := profileNames(raw)
	want := []string{"power-saver", "balanced", "performance"}
	if len(got) != len(want) {
		t.Fatalf("profileNames = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("profileNames[%d] = %q, want %q (order must be preserved)", i, got[i], want[i])
		}
	}

	if profileNames("not the right type") != nil {
		t.Error("profileNames on a wrong-typed value should be nil")
	}
}

// TestLivePowerProfilesFrame exercises the real publish path against the running
// power-profiles daemon and prints the frame, as evidence the topic renders live
// data. Gated so the default `go test` stays deterministic and bus-free.
func TestLivePowerProfilesFrame(t *testing.T) {
	if os.Getenv("RYOKU_LIVE_DBUS") == "" {
		t.Skip("set RYOKU_LIVE_DBUS=1 to run the live power-profiles integration")
	}
	conn, err := dbus.ConnectSystemBus()
	if err != nil {
		t.Skipf("no system bus: %v", err)
	}
	defer conn.Close()
	p := &powerProfilesState{
		conn:  conn,
		obj:   conn.Object(ppBusName, dbus.ObjectPath(ppPath)),
		topic: newStateTopic(),
	}
	sub := p.topic.subscribe()
	defer p.topic.unsubscribe(sub)
	p.publish()
	select {
	case frame := <-sub.frames:
		t.Logf("powerprofiles frame: %s", frame)
		var m struct {
			Active   string   `json:"active_profile"`
			Profiles []string `json:"profiles"`
		}
		if err := json.Unmarshal(frame, &m); err != nil {
			t.Fatalf("frame is not valid JSON: %v", err)
		}
		if len(m.Profiles) == 0 {
			t.Error("no profiles from the running daemon")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("no powerprofiles frame published")
	}
}

func TestShouldApplyProfile(t *testing.T) {
	cases := []struct {
		name, cfg, active, want string
	}{
		{"no profiles block", `{"chargeLimit":80}`, "balanced", ""},
		{"profile not defined", `{"profiles":{"performance":{"epp":"performance"}}}`, "balanced", ""},
		{"empty active", `{"profiles":{"balanced":{}}}`, "", ""},
		{"malformed", `not json`, "balanced", ""},
		{"defined", `{"profiles":{"balanced":{"governor":"powersave"}}}`, "balanced", "balanced"},
	}
	for _, c := range cases {
		if got := shouldApplyProfile([]byte(c.cfg), c.active); got != c.want {
			t.Errorf("%s: shouldApplyProfile = %q, want %q", c.name, got, c.want)
		}
	}
}

// TestApplyActiveProfileNoConfig proves the load-bearing safety rule: with a
// power.json that has no "profiles" block, the applier is never invoked, so an
// unconfigured user triggers no ryoku-power exec (and thus no pkexec prompt).
func TestApplyActiveProfileNoConfig(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	cfgDir := filepath.Join(dir, "ryoku")
	if err := os.MkdirAll(cfgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(cfgDir, "power.json")
	if err := os.WriteFile(path, []byte(`{"chargeLimit":80}`), 0o644); err != nil {
		t.Fatal(err)
	}

	var calls []string
	orig := applyProfileCmd
	applyProfileCmd = func(profile string) error { calls = append(calls, profile); return nil }
	defer func() { applyProfileCmd = orig }()

	p := &powerProfilesState{}
	p.applyActiveProfile("balanced")
	if len(calls) != 0 {
		t.Fatalf("applier invoked %v with no profiles block; must stay hands-off", calls)
	}

	// Positive control: once the profile is defined, the applier runs exactly once.
	if err := os.WriteFile(path, []byte(`{"profiles":{"balanced":{"governor":"powersave"}}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	p.applyActiveProfile("balanced")
	if len(calls) != 1 || calls[0] != "balanced" {
		t.Fatalf("applier calls = %v, want one apply of balanced", calls)
	}
}

func TestApplyDelay(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	cfgDir := filepath.Join(dir, "ryoku")
	if err := os.MkdirAll(cfgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(cfgDir, "power.json")

	if got := applyDelay(); got != 400*time.Millisecond {
		t.Errorf("applyDelay with no file = %v, want 400ms", got)
	}
	os.WriteFile(path, []byte(`{"applyDelayMs":1000}`), 0o644)
	if got := applyDelay(); got != time.Second {
		t.Errorf("applyDelay = %v, want 1s", got)
	}
	os.WriteFile(path, []byte(`{"applyDelayMs":0}`), 0o644)
	if got := applyDelay(); got != 400*time.Millisecond {
		t.Errorf("applyDelay with 0 = %v, want 400ms default", got)
	}
}

func TestDecideProfileChange(t *testing.T) {
	const long = time.Hour
	const near = 2 * time.Second // inside autoSwitchWindow and restoreReassertWindow
	cases := []struct {
		name                                       string
		active, saved                              string
		restoreDone, onBat, saverFeature, gameMode bool
		sinceFlip, sinceRestore                    time.Duration
		want                                       profileAction
	}{
		// boot noise and Ryoku-caused changes are never a pick.
		{"empty profile", "", "balanced", true, false, false, false, long, long, profileNone},
		{"before restore is boot noise", "performance", "balanced", false, false, false, false, long, long, profileNone},
		{"game mode owns the profile", "performance", "balanced", true, false, false, true, long, long, profileNone},
		{"game mode wins even inside the restore window", "performance", "balanced", true, false, false, true, long, near, profileNone},
		{"battery saver is not a choice", "power-saver", "balanced", true, true, true, false, long, long, profileNone},
		{"switch right after an AC flip is automatic", "performance", "balanced", true, false, false, false, near, long, profileNone},
		// a late ppd boot default is put back, not banked.
		{"ppd default drift inside the restore window is re-asserted", "performance", "balanced", true, false, false, false, long, near, profileReassert},
		{"no saved pick means nothing to re-assert", "performance", "", true, false, false, false, long, near, profilePersist},
		{"drift equal to the saved pick is not re-asserted", "balanced", "balanced", true, false, false, false, long, near, profilePersist},
		// genuine picks on either write path persist.
		{"saver on AC is a real pick", "power-saver", "balanced", true, false, true, false, long, long, profilePersist},
		{"performance after the restore window is a pick", "performance", "balanced", true, false, false, false, long, long, profilePersist},
		{"settled balanced is a pick", "balanced", "balanced", true, false, false, false, long, long, profilePersist},
	}
	for _, c := range cases {
		got := decideProfileChange(c.active, c.saved, c.restoreDone, c.onBat, c.saverFeature, c.gameMode, c.sinceFlip, c.sinceRestore)
		if got != c.want {
			t.Errorf("%s: decideProfileChange = %v, want %v", c.name, got, c.want)
		}
	}
}
