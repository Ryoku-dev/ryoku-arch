package securitykey

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	i18n "ryoku-i18n"
)

func pamRoot() string {
	if p := os.Getenv("RYOKU_SECURITY_KEY_PAM_ROOT"); p != "" {
		return p
	}
	return "/etc/pam.d"
}

func targetName(target string) (string, error) {
	switch target {
	case TargetSudo:
		return "sudo", nil
	case TargetPolkit, "polkit-1":
		return "polkit-1", nil
	case TargetLogin, "sddm":
		return "sddm", nil
	default:
		return "", fmt.Errorf(i18n.T("unknown target %q"), target)
	}
}

func pamPath(target string) (string, error) {
	name, err := targetName(target)
	if err != nil {
		return "", err
	}
	return filepath.Join(pamRoot(), name), nil
}

func pamLine() string {
	origin := defaultOrigin()
	p := readPolicy()
	control := "sufficient"
	if p.Mode == ModeMFA {
		control = "required"
	}
	parts := []string{
		"auth",
		control,
		"pam_u2f.so",
		"openasuser",
		"cue",
		"origin=" + origin,
		"appid=" + origin,
	}
	if p.TouchRequired {
		parts = append(parts, "userpresence=1")
	} else {
		parts = append(parts, "userpresence=0")
	}
	if p.PinVerification {
		parts = append(parts, "pinverification=1")
	}
	if p.UserVerification {
		parts = append(parts, "userverification=1")
	} else {
		parts = append(parts, "userverification=0")
	}
	return strings.Join(parts, " ")
}

func defaultOrigin() string {
	host, err := os.Hostname()
	if err != nil || strings.TrimSpace(host) == "" {
		host = "localhost"
	}
	return "pam://" + strings.TrimSpace(host)
}

func pamEnabled(target string) bool {
	path, err := pamPath(target)
	if err != nil {
		return false
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return strings.Contains(string(raw), "pam_u2f.so")
}

func applyPAMText(content string, on bool) string {
	var out []string
	for _, line := range strings.Split(content, "\n") {
		if strings.Contains(line, "pam_u2f.so") {
			continue
		}
		out = append(out, line)
	}
	text := strings.Join(out, "\n")
	if !on {
		return text
	}
	if text == "" {
		return pamLine() + "\n"
	}
	return pamLine() + "\n" + text
}

func applyPAMFile(path string, on bool) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf(i18n.T("read %s: %w"), path, err)
	}
	out := applyPAMText(string(raw), on)
	if out == string(raw) {
		return nil
	}
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".ryoku-u2f-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if err := tmp.Chmod(info.Mode().Perm()); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.WriteString(out); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

func pamWritable(path string) bool {
	f, err := os.OpenFile(path, os.O_WRONLY, 0)
	if err != nil {
		return false
	}
	f.Close()
	return true
}

func enabledTargets() []string {
	var out []string
	for _, target := range []string{TargetSudo, TargetPolkit, TargetLogin} {
		if pamEnabled(target) {
			out = append(out, target)
		}
	}
	return out
}

func rewriteEnabledTargets() error {
	var errs []string
	for _, target := range enabledTargets() {
		path, err := pamPath(target)
		if err != nil {
			errs = append(errs, err.Error())
			continue
		}
		if err := applyPAMFile(path, true); err != nil {
			errs = append(errs, err.Error())
		}
	}
	if len(errs) > 0 {
		return fmt.Errorf(strings.Join(errs, "; "))
	}
	return nil
}

func applyPAMHalf(target string, on bool) error {
	path, err := pamPath(target)
	if err != nil {
		return err
	}
	if raw, err := os.ReadFile(path); err == nil {
		if out := applyPAMText(string(raw), on); out == string(raw) {
			return nil
		}
	}
	if os.Getenv("RYOKU_SECURITY_KEY_PAM_ROOT") != "" && pamWritable(path) {
		return applyPAMFile(path, on)
	}
	return escalateApplyPAM(target, on)
}

func escalateApplyPAM(target string, on bool) error {
	exe := selfExe()
	uid := strconv.Itoa(os.Getuid())
	state := "off"
	if on {
		state = "on"
	}
	cmd := exec.Command("pkexec", "env", "PKEXEC_UID="+uid, exe, "security-key", "apply-pam", target, state)
	cmd.Stdout, cmd.Stderr, cmd.Stdin = os.Stdout, os.Stderr, os.Stdin
	return cmd.Run()
}

func selfExe() string {
	if e, err := os.Executable(); err == nil {
		return e
	}
	return "ryoku"
}

func runApplyPAM(args []string) error {
	if len(args) != 2 {
		return fmt.Errorf(i18n.T("usage: ryoku security-key apply-pam <sudo|polkit|login> <on|off>"))
	}
	on, err := parseOnOff(args[1])
	if err != nil {
		return err
	}
	path, err := pamPath(args[0])
	if err != nil {
		return err
	}
	if !pamWritable(path) {
		return fmt.Errorf(i18n.T("%s is not writable (run via pkexec/root)"), path)
	}
	return applyPAMFile(path, on)
}
