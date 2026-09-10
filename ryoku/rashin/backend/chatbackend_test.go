package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// pickBackend is the chat-agent selection core. A wrong choice would either
// silently ignore the user's pick or drive the chat with an adapter that is not
// installed. Availability is injected so the test needs no real adapters.
func TestPickBackend(t *testing.T) {
	backs := []chatBackend{
		{ID: "hermes", Name: "Hermes", Recommended: true},
		{ID: "claude", Name: "Claude Code"},
		{ID: "gemini", Name: "Gemini"},
	}
	only := func(ids ...string) func(chatBackend) bool {
		set := map[string]bool{}
		for _, id := range ids {
			set[id] = true
		}
		return func(b chatBackend) bool { return set[b.ID] }
	}
	cases := []struct {
		name   string
		want   string
		avail  func(chatBackend) bool
		expect string
		ok     bool
	}{
		{"default falls to hermes", "", only("hermes", "claude"), "hermes", true},
		{"explicit available pick wins", "claude", only("hermes", "claude"), "claude", true},
		{"unavailable pick falls back to hermes", "claude", only("hermes"), "hermes", true},
		{"gemini when only gemini is present", "gemini", only("gemini"), "gemini", true},
		{"nothing available", "claude", only(), "", false},
		{"default with only a non-hermes agent", "", only("claude"), "claude", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			b, ok := pickBackend(c.want, backs, c.avail)
			if ok != c.ok || b.ID != c.expect {
				t.Fatalf("pickBackend(%q) = (%q,%v), want (%q,%v)", c.want, b.ID, ok, c.expect, c.ok)
			}
		})
	}
}

// setChatAgent must reject an unknown agent (so the chat never tries to spawn a
// backend that does not exist) and persist a valid one; "auto" clears it.
func TestSetChatAgent(t *testing.T) {
	cfg := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", cfg)

	if err := setChatAgent("bogus"); err == nil {
		t.Fatal("unknown chat agent must error")
	}
	if err := setChatAgent("claude"); err != nil {
		t.Fatalf("valid agent: %v", err)
	}
	if got := LoadConfig().ChatAgent; got != "claude" {
		t.Fatalf("chatAgent = %q, want claude", got)
	}
	if err := setChatAgent("auto"); err != nil {
		t.Fatalf("auto: %v", err)
	}
	if got := LoadConfig().ChatAgent; got != "" {
		t.Fatalf("auto should clear chatAgent, got %q", got)
	}
}

// The paste snippet is the whole point of "point any agent at Ryoku": it must
// name the vault, prowl-agent, and the skill so an unsupported agent gets the
// same power. A regression that drops one silently weakens every such agent.
func TestManifestSnippet(t *testing.T) {
	h := t.TempDir()
	t.Setenv("XDG_DATA_HOME", filepath.Join(h, "data"))
	skill := filepath.Join(h, "skills", "ryoku")
	snip := manifestSnippet(skill)
	for _, want := range []string{"prowl-agent", "AGENTS.md", filepath.Join(skill, "SKILL.md"), "ryoku-rashin"} {
		if !strings.Contains(snip, want) {
			t.Fatalf("snippet missing %q:\n%s", want, snip)
		}
	}
}

// vaultManifest lists the read-order docs; the index (AGENTS.md) must lead so an
// agent reads the map before anything else.
func TestVaultManifestOrder(t *testing.T) {
	items := vaultManifest()
	if len(items) == 0 || items[0].Label != "AGENTS.md" {
		t.Fatalf("vault manifest must lead with AGENTS.md, got %+v", items)
	}
	var haveDesktop bool
	for _, it := range items {
		if it.Label == "desktop.md" {
			haveDesktop = true
		}
	}
	if !haveDesktop {
		t.Fatal("vault manifest missing desktop.md")
	}
}
