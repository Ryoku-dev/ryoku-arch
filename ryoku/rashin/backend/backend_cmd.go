package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// quickInfoJSON is the fast-lane backend state for the CLI and the needle's
// picker: the resolved provider/model/endpoint, the list to choose from, and
// whether asks currently fall back to the full hermes session.
type quickInfoJSON struct {
	Provider    string   `json:"provider"`
	Model       string   `json:"model"`
	Endpoint    string   `json:"endpoint"`
	Label       string   `json:"label"`
	Available   []string `json:"available"`
	Ready       []string `json:"ready"`
	SessionLane bool     `json:"sessionLane"`
	Reason      string   `json:"reason,omitempty"`
}

// quickInfo resolves the fast-lane target for the given config, never erroring:
// an unresolved target reports the session-lane fallback and why.
func quickInfo(cfg Config) quickInfoJSON {
	info := quickInfoJSON{Available: providerIDs(), Ready: readyProviders(), Provider: cfg.Quick.Provider}
	t, err := resolveQuickTarget(cfg)
	if err != nil {
		info.SessionLane = true
		info.Reason = err.Error()
		info.Model = t.Model
		return info
	}
	info.Label = t.Label
	info.Endpoint = t.BaseURL
	info.Model = t.Model
	if i := strings.IndexByte(t.Label, ':'); i >= 0 {
		info.Provider = t.Label[:i]
	}
	return info
}

// cmdBackend views or sets the fast-lane assistant backend. No args prints the
// resolved state; `<provider>[:model]` selects one of the known providers;
// `auto` clears the override so the fast lane follows hermes's own provider.
func cmdBackend(args []string) error {
	cfg := LoadConfig()
	if len(args) == 1 && (args[0] == "--json" || args[0] == "-j") {
		return json.NewEncoder(os.Stdout).Encode(quickInfo(cfg))
	}
	if len(args) == 0 {
		printBackend(cfg)
		return nil
	}
	switch args[0] {
	case "auto", "clear", "--clear":
		cfg.Quick.Provider, cfg.Quick.Model, cfg.Quick.BaseURL, cfg.Quick.KeyEnv = "", "", "", ""
		if err := SaveConfig(cfg); err != nil {
			return err
		}
		fmt.Println("backend cleared; the fast lane follows hermes's provider")
		printBackend(LoadConfig())
		return nil
	}
	provider, model, _ := strings.Cut(args[0], ":")
	if _, ok := quickProviders[provider]; !ok {
		return fmt.Errorf("unknown provider %q; known: %s", provider, strings.Join(providerIDs(), ", "))
	}
	cfg.Quick.Provider = provider
	if model != "" {
		cfg.Quick.Model = model
	}
	if err := SaveConfig(cfg); err != nil {
		return err
	}
	fmt.Printf("backend set to %s\n", args[0])
	printBackend(LoadConfig())
	return nil
}

// printBackend renders the fast-lane state for the terminal.
func printBackend(cfg Config) {
	info := quickInfo(cfg)
	if info.SessionLane {
		fmt.Printf("fast lane: unavailable (%s)\n", info.Reason)
		fmt.Println("           quick asks use the full hermes session")
	} else {
		fmt.Printf("fast lane: %s\n", info.Label)
		fmt.Printf("  endpoint: %s\n", info.Endpoint)
	}
	fmt.Printf("providers: %s\n", strings.Join(info.Available, ", "))
	fmt.Println("keys:      ~/.config/ryoku/rashin.env (or the environment)")
	fmt.Println("set with:  ryoku-rashin backend <provider>[:model]   (`backend auto` to follow hermes)")
}
