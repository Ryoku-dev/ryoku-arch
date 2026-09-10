package main

import (
	"fmt"
	"os/exec"
)

// chatbackend.go lets the Super+S chat run an agent other than Hermes for its
// interactive ACP session. Hermes is first-class and the recommended default;
// any other agent needs its own Agent Client Protocol adapter on PATH. A coding
// CLI with no ACP adapter is not a chat backend -- it is wired for terminal use
// instead (see agents.go), which is the path most agents take.

// chatBackend is an agent that can drive the chat's ACP session.
type chatBackend struct {
	ID          string
	Name        string
	Argv        []string // the ACP command to spawn
	Recommended bool
}

// chatBackends lists the agents Rashin can run as the chat's ACP session, in
// preference order (Hermes leads). omp and opencode speak ACP natively; claude
// and gemini need their adapter on PATH. An agent absent here is still wired for
// the terminal, it just cannot render inside the needle.
func chatBackends() []chatBackend {
	return []chatBackend{
		{ID: "hermes", Name: "Hermes", Argv: hermesACPArgv(), Recommended: true},
		{ID: "omp", Name: "Oh My Pi", Argv: []string{"omp", "acp"}},
		{ID: "opencode", Name: "opencode", Argv: []string{"opencode", "acp"}},
		{ID: "claude", Name: "Claude Code", Argv: []string{"claude-code-acp"}},
		{ID: "gemini", Name: "Gemini", Argv: []string{"gemini", "--experimental-acp"}},
	}
}

func hermesACPArgv() []string {
	if bin, ok := FindHermes(); ok {
		return []string{bin, "acp"}
	}
	return []string{"hermes", "acp"}
}

// chatBackendAvailable reports whether a backend's ACP command is runnable now.
func chatBackendAvailable(b chatBackend) bool {
	if len(b.Argv) == 0 {
		return false
	}
	if b.ID == "hermes" {
		_, ok := FindHermes()
		return ok
	}
	_, err := exec.LookPath(b.Argv[0])
	return err == nil
}

// resolveChatBackend picks the ACP command to spawn for the given config.
func resolveChatBackend(cfg Config) (chatBackend, bool) {
	return pickBackend(cfg.ChatAgent, chatBackends(), chatBackendAvailable)
}

// pickBackend is the pure selection core: the wanted agent when available, else
// the first available (Hermes leads), else none. Availability is injected so it
// is unit-testable without real adapters on PATH.
func pickBackend(want string, backs []chatBackend, avail func(chatBackend) bool) (chatBackend, bool) {
	if want != "" {
		for _, b := range backs {
			if b.ID == want && avail(b) {
				return b, true
			}
		}
	}
	for _, b := range backs {
		if avail(b) {
			return b, true
		}
	}
	return chatBackend{}, false
}

// lookupChatBackend finds a backend by id.
func lookupChatBackend(id string) (chatBackend, bool) {
	for _, b := range chatBackends() {
		if b.ID == id {
			return b, true
		}
	}
	return chatBackend{}, false
}

// setChatAgent persists the chat backend choice. "" or "auto" clears it back to
// the recommended default (hermes). A named agent must be a known backend.
func setChatAgent(id string) error {
	if id == "auto" {
		id = ""
	}
	if id != "" {
		if _, ok := lookupChatBackend(id); !ok {
			return fmt.Errorf("unknown chat agent %q", id)
		}
	}
	cfg := LoadConfig()
	cfg.ChatAgent = id
	return SaveConfig(cfg)
}
