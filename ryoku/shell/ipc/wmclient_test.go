package main

import (
	"os/exec"
	"testing"

	wm "ryoku-wm"
)

// A focus frame warms the cache; a focus frame with an empty output clears it.
func TestFocusFrameUpdatesCache(t *testing.T) {
	d := &daemon{}
	d.onWMFrame(wm.Frame{Kind: wm.FrameFocus, FocusedOutput: "DP-1"})
	if got := d.activeMonitor(); got != "DP-1" {
		t.Fatalf("activeMonitor() = %q, want DP-1", got)
	}
	d.onWMFrame(wm.Frame{Kind: wm.FrameFocus})
	if got := d.activeMonitor(); got != "" {
		t.Fatalf("after empty focus frame, activeMonitor() = %q, want empty", got)
	}
}

// A cold cache resolves to "" without a fork; callers tolerate no focused output.
func TestActiveMonitorColdCacheEmpty(t *testing.T) {
	d := &daemon{}
	if got := d.activeMonitor(); got != "" {
		t.Fatalf("cold activeMonitor() = %q, want empty", got)
	}
}

// The watcher writes while keybinds read; run with -race to prove it is safe.
func TestMonitorConcurrent(t *testing.T) {
	d := &daemon{}
	done := make(chan struct{})
	go func() {
		for range 2000 {
			d.onWMFrame(wm.Frame{Kind: wm.FrameFocus, FocusedOutput: "DP-1"})
			d.onWMFrame(wm.Frame{Kind: wm.FrameFocus})
		}
		close(done)
	}()
	for range 2000 {
		_ = d.activeMonitor()
	}
	<-done
}

func BenchmarkActiveMonitorCached(b *testing.B) {
	d := &daemon{}
	d.onWMFrame(wm.Frame{Kind: wm.FrameFocus, FocusedOutput: "DP-1"})
	b.ReportAllocs()
	for b.Loop() {
		if d.activeMonitor() == "" {
			b.Fatal("empty monitor")
		}
	}
}

// BenchmarkMonitorSpawnProxy measures a bare fork+exec: the per-keybind floor the
// cache removes. A provider query is strictly more expensive than this.
func BenchmarkMonitorSpawnProxy(b *testing.B) {
	if _, err := exec.LookPath("true"); err != nil {
		b.Skip("true not on PATH")
	}
	b.ReportAllocs()
	for b.Loop() {
		_ = exec.Command("true").Run()
	}
}

func TestUnchangedWorkspaceFrameDoesNotWakeWidgets(t *testing.T) {
	d := &daemon{widgetSig: make(chan struct{}, 1)}
	f := wm.Frame{Kind: wm.FrameWorkspaces, Workspaces: []wm.Workspace{{ID: "1", Windows: 2}}}

	d.onWMFrame(f)
	<-d.widgetSig

	d.onWMFrame(f)
	select {
	case <-d.widgetSig:
		t.Fatal("unchanged frame woke widget gate")
	default:
	}

	d.onWMFrame(wm.Frame{
		Kind:       wm.FrameWorkspaces,
		Workspaces: []wm.Workspace{},
	})
	select {
	case <-d.widgetSig:
	default:
		t.Fatal("empty workspace transition lost")
	}
}
