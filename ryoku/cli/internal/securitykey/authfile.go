package securitykey

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	i18n "ryoku-i18n"
)

type authFile struct {
	other []string
	creds []string
}

func currentUser() string {
	if u := strings.TrimSpace(os.Getenv("USER")); u != "" {
		return u
	}
	if u := strings.TrimSpace(os.Getenv("USERNAME")); u != "" {
		return u
	}
	return "traveler"
}

func parseUserLine(line string) (string, []string, bool) {
	line = strings.TrimSpace(line)
	if line == "" || strings.HasPrefix(line, "#") {
		return "", nil, false
	}
	parts := strings.Split(line, ":")
	if len(parts) < 2 || strings.TrimSpace(parts[0]) == "" {
		return "", nil, false
	}
	var creds []string
	for _, p := range parts[1:] {
		p = strings.TrimSpace(p)
		if p != "" {
			creds = append(creds, p)
		}
	}
	return strings.TrimSpace(parts[0]), creds, true
}

func loadAuthFile() (authFile, error) {
	raw, err := os.ReadFile(authFilePath())
	if err != nil {
		if os.IsNotExist(err) {
			return authFile{}, nil
		}
		return authFile{}, err
	}
	user := currentUser()
	var out authFile
	for _, line := range strings.Split(strings.ReplaceAll(string(raw), "\r\n", "\n"), "\n") {
		u, creds, ok := parseUserLine(line)
		if !ok {
			if strings.TrimSpace(line) != "" {
				out.other = append(out.other, strings.TrimSpace(line))
			}
			continue
		}
		if u != user {
			out.other = append(out.other, strings.TrimSpace(line))
			continue
		}
		for _, cred := range creds {
			if !containsCred(out.creds, cred) {
				out.creds = append(out.creds, cred)
			}
		}
	}
	return out, nil
}

func writeAuthFile(a authFile) error {
	path := authFilePath()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	lines := append([]string{}, a.other...)
	if len(a.creds) > 0 {
		lines = append(lines, currentUser()+":"+strings.Join(a.creds, ":"))
	}
	content := strings.Join(lines, "\n")
	if content != "" {
		content += "\n"
	}
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, []byte(content), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func containsCred(creds []string, want string) bool {
	for _, cred := range creds {
		if cred == want {
			return true
		}
	}
	return false
}

func removeCredential(id string) (int, error) {
	a, err := loadAuthFile()
	if err != nil {
		return 0, err
	}
	if len(a.creds) == 0 {
		return 0, fmt.Errorf(i18n.T("no enrolled security keys for %s"), currentUser())
	}
	if id == "all" {
		a.creds = nil
		return 0, writeAuthFile(a)
	}
	n, err := strconv.Atoi(id)
	if err != nil || n < 1 || n > len(a.creds) {
		return 0, fmt.Errorf(i18n.T("credential id must be 1..%d or 'all'"), len(a.creds))
	}
	a.creds = append(append([]string{}, a.creds[:n-1]...), a.creds[n:]...)
	return len(a.creds), writeAuthFile(a)
}
