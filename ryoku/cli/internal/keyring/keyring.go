// Package keyring owns the GNOME keyring unlock policy: how the login/default
// secret store is unlocked so browsers and apps stop prompting on every launch.
// It is one concern split into halves. The user half (status, set) reads and
// converges the per-user keyring files under $XDG_DATA_HOME/keyrings and the
// config at ~/.config/ryoku/keyring.json, talking to gnome-keyring-daemon over
// the session bus. The privileged half (apply-pam) edits /etc/pam.d/sddm, so it
// runs as root via pkexec -- mirroring the Hub's escalateSelf pattern.
//
// Three modes, from silent-and-encrypted to always-ask:
//
//	unlock-on-login  PAM unlocks (or creates) the login keyring with the login
//	                 password at sign-in; the store is encrypted at rest and the
//	                 desktop never prompts. The default keyring points at login.
//	never-ask        the default keyring is blank (stored in plaintext), so it
//	                 is already unlocked; the only silent option under SDDM
//	                 autologin, where there is no password for PAM to reuse.
//	ask              status quo: the store stays locked until an app asks, and
//	                 gnome-keyring prompts for the password then.
package keyring

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

const (
	ModeUnlockOnLogin = "unlock-on-login"
	ModeNeverAsk      = "never-ask"
	ModeAsk           = "ask"
)

func validMode(m string) bool {
	return m == ModeUnlockOnLogin || m == ModeNeverAsk || m == ModeAsk
}

// configPath is ~/.config/ryoku/keyring.json, the one place the chosen mode is
// recorded so it survives reboots and updates (materialize never touches it).
func configPath() string {
	return filepath.Join(sys.ConfigHome(), "ryoku", "keyring.json")
}

type config struct {
	Mode string `json:"mode"`
}

// readConfig returns the recorded mode and whether keyring.json exists. A
// missing or unparseable file reports ("", false) so the caller infers instead.
func readConfig() (string, bool) {
	raw, err := os.ReadFile(configPath())
	if err != nil {
		return "", false
	}
	var c config
	if json.Unmarshal(raw, &c) != nil || !validMode(c.Mode) {
		return "", false
	}
	return c.Mode, true
}

func writeConfig(mode string) error {
	p := configPath()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	raw, err := json.Marshal(config{Mode: mode})
	if err != nil {
		return err
	}
	tmp := p + ".ryoku-tmp"
	if err := os.WriteFile(tmp, append(raw, '\n'), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

// Run is the `ryoku keyring` entry point, dispatched from main.
func Run(args []string) error {
	if len(args) == 0 {
		return usageErr()
	}
	switch args[0] {
	case "status":
		return runStatus(args[1:])
	case "set":
		return runSet(args[1:])
	case "init":
		return runInit(args[1:])
	case "apply-pam":
		return runApplyPAM(args[1:])
	case "-h", "--help", "help":
		fmt.Print(usageText())
		return nil
	default:
		return fmt.Errorf(i18n.T("unknown keyring command %q\n\n%s"), args[0], usageText())
	}
}

func usageText() string {
	return i18n.T("Usage: ryoku keyring <command>\n\n  status [--json]              show the configured mode and keyring state\n  init                         first-login default: record the mode and seed the\n                               blank keyring never-ask needs (no-op once set)\n  set <mode> [flags]           switch mode (unlock-on-login | never-ask | ask)\n      --convert                convert an encrypted keyring (reads passwords on stdin)\n      --reset                  back up the keyring files and start fresh\n      --password-stdin         read password(s) from stdin, one per line\n  apply-pam <mode>             privileged: wire /etc/pam.d/sddm for the mode\n")
}

func usageErr() error { return fmt.Errorf("%s", usageText()) }
