package securitykey

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

func runEnroll(args []string) error {
	if len(args) != 0 {
		return fmt.Errorf(i18n.T("usage: ryoku security-key enroll"))
	}
	var cred string
	if fakeFIDO() {
		cred = fakeEnrollment()
	} else {
		if !sys.Has("pamu2fcfg") {
			return fmt.Errorf(i18n.T("pamu2fcfg is not installed; install pam-u2f first"))
		}
		origin := defaultOrigin()
		_, _, caps := probeDevice()
		cmd := exec.Command("pamu2fcfg", enrollmentArgs(origin, caps)...)
		cmd.Stdin, cmd.Stdout, cmd.Stderr = nil, nil, nil
		out, err := cmd.CombinedOutput()
		if err != nil {
			msg := strings.TrimSpace(string(out))
			if msg == "" {
				msg = err.Error()
			}
			return fmt.Errorf(i18n.T("pamu2fcfg failed: %s"), msg)
		}
		adoptPolicyFor(caps)
		var err2 error
		cred, err2 = parseEnrollment(string(out))
		if err2 != nil {
			return err2
		}
	}
	a, err := loadAuthFile()
	if err != nil {
		return err
	}
	if containsCred(a.creds, cred) {
		fmt.Println(i18n.T("that security key is already enrolled"))
		return nil
	}
	a.creds = append(a.creds, cred)
	if err := writeAuthFile(a); err != nil {
		return err
	}
	fmt.Printf(i18n.T("enrolled security key %d for %s\n"), len(a.creds), currentUser())
	return nil
}

func enrollmentArgs(origin string, caps Capabilities) []string {
	args := []string{"-o", origin, "-i", origin}
	p := readPolicy()
	if caps.AlwaysUV || caps.ClientPIN || p.PinVerification {
		args = append(args, "-N")
	}
	if p.UserVerification {
		args = append(args, "-V")
	}
	return args
}

func adoptPolicyFor(caps Capabilities) {
	if !caps.AlwaysUV && !caps.ClientPIN {
		return
	}
	p := readPolicy()
	p.PinVerification = true
	p.TouchRequired = true
	if err := writePolicy(p); err != nil {
		fmt.Printf(i18n.T("warning: couldn't record security-key policy: %v\n"), err)
	}
}

func fakeEnrollment() string {
	return fmt.Sprintf("fake-key-handle-%d,es256,+presence", time.Now().UnixNano())
}

func parseEnrollment(out string) (string, error) {
	for _, line := range strings.Split(strings.ReplaceAll(out, "\r\n", "\n"), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || !strings.Contains(line, ":") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 || strings.TrimSpace(parts[1]) == "" {
			continue
		}
		return strings.TrimSpace(parts[1]), nil
	}
	return "", fmt.Errorf(i18n.T("pamu2fcfg returned no credential line"))
}

func runRemove(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf(i18n.T("usage: ryoku security-key remove <id|all>"))
	}
	left, err := removeCredential(args[0])
	if err != nil {
		return err
	}
	if args[0] == "all" {
		fmt.Println(i18n.T("removed all enrolled security keys"))
		return nil
	}
	fmt.Printf(i18n.T("removed security key %s (%d remaining)\n"), args[0], left)
	return nil
}
