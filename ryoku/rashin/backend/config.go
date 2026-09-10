package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type Config struct {
	Enabled bool `json:"enabled"`
	// OptedOut: the user turned rashin off on purpose (`disable`), so the
	// default-on convergence leaves it off. Cleared by `enable`.
	OptedOut bool `json:"optedOut,omitempty"`
	Port     int  `json:"port"`
	// Quick overrides the launcher fast lane's model connection. Empty means
	// derive it from hermes's own provider config. Provider names one of the
	// built-in openai-compatible providers (see quickProviders); BaseURL/KeyEnv
	// override it for anything else.
	Quick struct {
		Provider string `json:"provider,omitempty"`
		Model    string `json:"model,omitempty"`
		BaseURL  string `json:"baseUrl,omitempty"`
		KeyEnv   string `json:"keyEnv,omitempty"`
	} `json:"quick,omitzero"`
	// Habits gates the vault's user-habits mining. History defaults on;
	// nil means enabled so an absent key keeps the feature.
	Habits struct {
		History *bool `json:"history,omitempty"`
	} `json:"habits,omitzero"`
}

// HabitsHistoryEnabled: fish-history mining is opt-out.
func (c Config) HabitsHistoryEnabled() bool {
	return c.Habits.History == nil || *c.Habits.History
}

// defaultConfig: rashin is on by default (opt-out via `disable`, which records
// OptedOut). LoadConfig starts here, so a box with no config reads as enabled.
func defaultConfig() Config {
	return Config{Enabled: true, Port: 3600}
}

func LoadConfig() Config {
	c := defaultConfig()
	b, err := os.ReadFile(ConfigPath())
	if err != nil {
		return c
	}
	if json.Unmarshal(b, &c) != nil {
		return defaultConfig()
	}
	if c.Port <= 0 || c.Port > 65535 {
		c.Port = 3600
	}
	return c
}

func SaveConfig(c Config) error {
	p := ConfigPath()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, append(b, '\n'), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}
