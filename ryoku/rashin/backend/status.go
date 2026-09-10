package main

import "time"

// Status is the full daemon report for `status --json`, the Hub page, and
// /api/status.
type Status struct {
	Enabled bool        `json:"enabled"`
	Running bool        `json:"running"`
	Port    int         `json:"port"`
	// Ready is true when the needle can actually answer: the local agent is
	// configured, or a direct quick-ask provider resolves. Drives the first-run
	// setup prompt in the needle.
	Ready  bool        `json:"ready"`
	Vault  VaultStatus `json:"vault"`
	Hermes HermesInfo  `json:"hermes"`
	Agents []Agent     `json:"agents"`
}

// VaultStatus is the vault summary embedded in Status.
type VaultStatus struct {
	Path        string    `json:"path"`
	Exists      bool      `json:"exists"`
	Files       int       `json:"files"`
	LastIndexed time.Time `json:"lastIndexed"`
}

// BuildStatus assembles the report. Running is probed over the loopback API
// (pingDaemon, in server.go) so the answer reflects a live daemon, not just the
// enabled gate.
func BuildStatus(cfg Config) Status {
	files, last, exists := VaultStats()
	h := HermesStatus()
	ready := needleReady(h, cfg)
	return Status{
		Enabled: cfg.Enabled,
		Running: pingDaemon(cfg.Port),
		Port:    cfg.Port,
		Ready:   ready,
		Vault: VaultStatus{
			Path:        VaultDir(),
			Exists:      exists,
			Files:       files,
			LastIndexed: last,
		},
		Hermes: h,
		Agents: DetectAgents(),
	}
}

// needleReady reports whether the needle can actually answer: the local agent
// is installed and onboarded, or a direct quick-ask provider resolves. Pure
// over its inputs so the first-run gate is unit-testable.
func needleReady(h HermesInfo, cfg Config) bool {
	if h.Installed && h.Configured {
		return true
	}
	_, err := resolveQuickTarget(cfg)
	return err == nil
}
