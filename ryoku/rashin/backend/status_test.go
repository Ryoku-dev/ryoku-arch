package main

import (
	"path/filepath"
	"testing"
)

// needleReady gates the needle's first-run setup prompt: an onboarded local
// agent, or a resolvable direct provider, counts as ready; nothing configured
// is not. A regression here would either nag a working box or leave a fresh
// user staring at a dead chat with no guidance.
func TestNeedleReady(t *testing.T) {
	// Isolate HOME/config so resolveQuickTarget cannot read a real hermes.
	h := t.TempDir()
	t.Setenv("HOME", h)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(h, "cfg"))

	// A configured local agent is ready regardless of any quick provider.
	if !needleReady(HermesInfo{Installed: true, Configured: true}, defaultConfig()) {
		t.Fatal("configured hermes should be ready")
	}
	// Installed but not onboarded, and no provider: not ready (show setup).
	if needleReady(HermesInfo{Installed: true, Configured: false}, defaultConfig()) {
		t.Fatal("un-onboarded hermes with no provider should not be ready")
	}
	// Nothing at all: not ready.
	if needleReady(HermesInfo{}, defaultConfig()) {
		t.Fatal("no agent and no provider should not be ready")
	}
	// No agent, but a direct provider resolves (keyless local): ready.
	cfg := defaultConfig()
	cfg.Quick.Provider = "local"
	cfg.Quick.Model = "some-model"
	if !needleReady(HermesInfo{Installed: true, Configured: false}, cfg) {
		t.Fatal("a resolvable quick provider should make the needle ready")
	}
}
