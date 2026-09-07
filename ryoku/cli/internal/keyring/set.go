package keyring

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	i18n "ryoku-i18n"
)

// setOpts is one `ryoku keyring set` invocation: the target mode and the two
// escape hatches for an encrypted keyring -- convert (rekey it with a known
// password) or reset (back it up and start fresh).
type setOpts struct {
	mode    string
	convert bool
	reset   bool
	stdin   bool
}

func runSet(args []string) error {
	var o setOpts
	for _, a := range args {
		switch a {
		case "--convert":
			o.convert = true
		case "--reset":
			o.reset = true
		case "--password-stdin":
			o.stdin = true
		default:
			if strings.HasPrefix(a, "-") || o.mode != "" || !validMode(a) {
				return fmt.Errorf(i18n.T("usage: ryoku keyring set <unlock-on-login|never-ask|ask> [--convert|--reset] [--password-stdin]"))
			}
			o.mode = a
		}
	}
	if o.mode == "" {
		return fmt.Errorf(i18n.T("usage: ryoku keyring set <unlock-on-login|never-ask|ask> [--convert|--reset] [--password-stdin]"))
	}
	if o.convert && o.reset {
		return fmt.Errorf(i18n.T("--convert and --reset are mutually exclusive"))
	}
	switch o.mode {
	case ModeUnlockOnLogin:
		if err := setUnlockOnLogin(o); err != nil {
			return err
		}
	case ModeNeverAsk:
		if err := setNeverAsk(o); err != nil {
			return err
		}
	case ModeAsk:
		// config-only; no keyring file changes.
	}
	if err := writeConfig(o.mode); err != nil {
		return fmt.Errorf(i18n.T("record mode: %w"), err)
	}
	if err := applyPAMHalf(o.mode); err != nil {
		return fmt.Errorf(i18n.T("wire PAM: %w"), err)
	}
	fmt.Printf(i18n.T("keyring mode set to %s\n"), o.mode)
	return nil
}

func setUnlockOnLogin(o setOpts) error {
	prev, changed, err := pointDefaultAt("login")
	if err != nil {
		return fmt.Errorf(i18n.T("point default keyring at login: %w"), err)
	}
	if changed {
		fmt.Printf(i18n.T("backup: previous default pointer was %q (saved to keyrings/default.ryoku-bak)\n"), strings.TrimSpace(prev))
	}
	f := probeFormat(keyringFile("login"))
	switch f {
	case fmtAbsent:
		fmt.Println(i18n.T("login keyring absent; PAM will create it at your next login"))
	case fmtPlaintext:
		fmt.Println(i18n.T("login keyring is blank; it is already unlocked"))
	case fmtEncrypted:
		switch {
		case o.reset:
			return resetKeyrings("login")
		case o.convert:
			old, newPw, err := readTwoPasswords()
			if err != nil {
				return err
			}
			if err := ops.changePassword("login", old, newPw); err != nil {
				return fmt.Errorf(i18n.T("convert login keyring: %w"), err)
			}
			fmt.Println(i18n.T("login keyring re-keyed to the supplied password"))
		default:
			fmt.Println(i18n.T("login keyring is password-protected; it will unlock silently at next login only if that password is your login password (re-run with --convert to change it, or --reset to start fresh)"))
		}
	}
	return nil
}

func setNeverAsk(o setOpts) error {
	name := defaultKeyringName()
	f := probeFormat(keyringFile(name))
	switch f {
	case fmtAbsent:
		if err := ops.createBlank(name); err != nil {
			return fmt.Errorf(i18n.T("create blank %q keyring: %w"), name, err)
		}
		fmt.Printf(i18n.T("created a blank %q keyring (no password, never prompts)\n"), name)
	case fmtPlaintext:
		fmt.Printf(i18n.T("%q keyring is already blank\n"), name)
	case fmtEncrypted:
		switch {
		case o.reset:
			if err := resetKeyrings(name); err != nil {
				return err
			}
			if err := ops.createBlank(name); err != nil {
				return fmt.Errorf(i18n.T("create blank %q keyring: %w"), name, err)
			}
			if _, _, err := pointDefaultAt(name); err != nil {
				return fmt.Errorf(i18n.T("point default keyring at %q: %w"), name, err)
			}
			fmt.Printf(i18n.T("started fresh: blank %q keyring, old one backed up\n"), name)
		case o.convert:
			old, err := readOnePassword()
			if err != nil {
				return err
			}
			if err := ops.changePassword(name, old, ""); err != nil {
				return fmt.Errorf(i18n.T("convert %q keyring to blank: %w"), name, err)
			}
			fmt.Printf(i18n.T("%q keyring converted to blank\n"), name)
		default:
			return fmt.Errorf(i18n.T("the %q keyring is password-protected; never-ask needs it blank -- re-run with --convert (supply its current password) or --reset (backs it up and starts fresh)"), name)
		}
	}
	return nil
}

// secretOps is the daemon-facing half of the state machine, behind an interface
// so the mode logic is unit-testable with a fake in place of a live daemon.
type secretOps interface {
	createBlank(name string) error
	changePassword(name, old, newPw string) error
}

// ops is the live implementation; tests swap it out.
var ops secretOps = liveSecretOps{}

type liveSecretOps struct{}

func (liveSecretOps) createBlank(name string) error {
	return withDaemon(func(c *secretsClient) error { return c.createBlank(name) })
}

func (liveSecretOps) changePassword(name, old, newPw string) error {
	return withDaemon(func(c *secretsClient) error { return c.changePassword(name, old, newPw) })
}

// withDaemon runs fn against a live secrets session, giving a clear error when
// the daemon is not reachable.
func withDaemon(fn func(*secretsClient) error) error {
	c, err := dial()
	if err != nil {
		return fmt.Errorf(i18n.T("%w (is gnome-keyring-daemon running?)"), err)
	}
	defer c.close()
	return fn(c)
}

// pointDefaultAt writes keyrings/default = name, backing up any previous pointer
// to default.ryoku-bak. Returns the previous content and whether it changed.
func pointDefaultAt(name string) (prev string, changed bool, err error) {
	dir := keyringsDir()
	p := filepath.Join(dir, "default")
	old, _ := os.ReadFile(p)
	if strings.TrimSpace(string(old)) == name {
		return string(old), false, nil
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", false, err
	}
	if len(old) > 0 {
		if err := os.WriteFile(p+".ryoku-bak", old, 0o600); err != nil {
			return "", false, err
		}
	}
	if err := os.WriteFile(p, []byte(name+"\n"), 0o600); err != nil {
		return "", false, err
	}
	return string(old), true, nil
}

// resetKeyrings moves the named keyring files into keyrings/backup-<ts>/ so the
// daemon (or a fresh create) starts clean. Never deletes: the backup is the
// user's only copy of whatever was in there.
func resetKeyrings(names ...string) error {
	dir := keyringsDir()
	bak := filepath.Join(dir, "backup-"+time.Now().Format("20060102-150405"))
	if err := os.MkdirAll(bak, 0o700); err != nil {
		return err
	}
	for _, n := range names {
		src := keyringFile(n)
		if !fileExists(src) {
			continue
		}
		if err := os.Rename(src, filepath.Join(bak, n+".keyring")); err != nil {
			return fmt.Errorf(i18n.T("back up %q keyring: %w"), n, err)
		}
	}
	fmt.Printf(i18n.T("backup: moved keyring files to %s\n"), bak)
	return nil
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// applyPAMHalf converges the SDDM PAM stack for mode. It skips silently when the
// stack already matches, applies in place on the test path (RYOKU_PAM_FILE set
// and writable), and otherwise re-runs the privileged half under pkexec.
func applyPAMHalf(mode string) error {
	path := pamFilePath()
	want := mode == ModeUnlockOnLogin
	if raw, err := os.ReadFile(path); err == nil {
		if out, missing := applyPAMText(string(raw), want); len(missing) == 0 && out == string(raw) {
			return nil
		}
	}
	if os.Getenv("RYOKU_PAM_FILE") != "" && pamWritable(path) {
		return applyPAMFile(path, mode)
	}
	return escalateApplyPAM(mode)
}

// escalateApplyPAM re-runs this binary's privileged half as root via pkexec,
// preserving the invoking user's id -- the Hub's escalateSelf pattern.
func escalateApplyPAM(mode string) error {
	exe := selfExe()
	uid := strconv.Itoa(os.Getuid())
	cmd := exec.Command("pkexec", "env", "PKEXEC_UID="+uid, exe, "keyring", "apply-pam", mode)
	cmd.Stdout, cmd.Stderr, cmd.Stdin = os.Stdout, os.Stderr, os.Stdin
	return cmd.Run()
}

func selfExe() string {
	if e, err := os.Executable(); err == nil {
		return e
	}
	return "ryoku"
}

// readOnePassword reads a single password line from stdin (the current keyring
// password), never from argv.
func readOnePassword() (string, error) {
	sc := bufio.NewScanner(os.Stdin)
	if !sc.Scan() {
		return "", fmt.Errorf(i18n.T("expected the current keyring password on stdin"))
	}
	return sc.Text(), nil
}

// readTwoPasswords reads the current password then the new one, each on its own
// stdin line.
func readTwoPasswords() (old, newPw string, err error) {
	sc := bufio.NewScanner(os.Stdin)
	if !sc.Scan() {
		return "", "", fmt.Errorf(i18n.T("expected the current keyring password on stdin (line 1)"))
	}
	old = sc.Text()
	if !sc.Scan() {
		return "", "", fmt.Errorf(i18n.T("expected the new keyring password on stdin (line 2)"))
	}
	return old, sc.Text(), nil
}
