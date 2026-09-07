package doctor

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// The WebExtension native-messaging host name and the extension ids that may
// talk to it. The Chromium id is fixed by the "key" in manifest.chromium.json.
const (
	browserHostName   = "ryoku_theme"
	browserFirefoxExt = "ryoku-theme@ryoku.arch"
	browserChromiumID = "mcmfbdeecgccbnlekdmalihgmpbplcij"
)

// reconcileBrowserTheme installs the native-messaging host so the Ryoku browser
// extension can reach the palette daemon. It writes a small launcher (execs
// ryoku-shell browser-host) and a host manifest into every browser profile root
// that exists. No-op when no supported browser is present; idempotent, and it
// never touches a browser's own settings.
func reconcileBrowserTheme(checkOnly bool) recResult {
	home := homeDir()
	if home == "" {
		return okRes(i18n.T("no HOME"))
	}
	launcher := filepath.Join(browserDataHome(), "ryoku", "ryoku-browser-host")

	// Firefox family keys on allowed_extensions; Chromium on allowed_origins.
	ffManifest := map[string]any{
		"name": browserHostName, "description": "Ryoku palette host",
		"path": launcher, "type": "stdio",
		"allowed_extensions": []string{browserFirefoxExt},
	}
	crManifest := map[string]any{
		"name": browserHostName, "description": "Ryoku palette host",
		"path": launcher, "type": "stdio",
		"allowed_origins": []string{"chrome-extension://" + browserChromiumID + "/"},
	}

	// A browser family is present when its probe dir exists; the host manifest
	// then goes into each of its native-messaging dirs. Zen keeps its profiles
	// under XDG ~/.config/zen, but resolves native-messaging manifests from the
	// classic ~/.mozilla dir (verified against the shipped Zen), so probe the
	// XDG dir and install into ~/.mozilla.
	type target struct {
		probe    string
		dirs     []string
		manifest map[string]any
	}
	targets := []target{
		{".mozilla", []string{".mozilla/native-messaging-hosts"}, ffManifest},
		{".librewolf", []string{".librewolf/native-messaging-hosts"}, ffManifest},
		{".config/zen", []string{".mozilla/native-messaging-hosts"}, ffManifest},
		{".config/chromium", []string{".config/chromium/NativeMessagingHosts"}, crManifest},
		{".config/google-chrome", []string{".config/google-chrome/NativeMessagingHosts"}, crManifest},
		{".config/BraveSoftware/Brave-Browser", []string{".config/BraveSoftware/Brave-Browser/NativeMessagingHosts"}, crManifest},
		{".config/microsoft-edge", []string{".config/microsoft-edge/NativeMessagingHosts"}, crManifest},
		{".config/vivaldi", []string{".config/vivaldi/NativeMessagingHosts"}, crManifest},
	}

	var pending, did []string
	present := false
	seen := map[string]bool{}
	launcherOK := launcherCurrent(launcher)
	for _, t := range targets {
		if !sys.Exists(filepath.Join(home, t.probe)) {
			continue
		}
		present = true
		for _, d := range t.dirs {
			manifestPath := filepath.Join(home, d, browserHostName+".json")
			if seen[manifestPath] {
				continue
			}
			seen[manifestPath] = true
			if launcherOK && manifestCurrent(manifestPath, t.manifest, launcher) {
				continue
			}
			if checkOnly {
				pending = append(pending, d)
				continue
			}
			if err := writeLauncher(launcher); err != nil {
				return failRes(i18n.T("could not write the browser host launcher: %v"), err)
			}
			launcherOK = true
			if err := writeManifestJSON(manifestPath, t.manifest); err != nil {
				return failRes(i18n.T("could not install the host manifest for %s: %v"), d, err)
			}
			did = append(did, d)
		}
	}

	switch {
	case !present:
		return okRes(i18n.T("no supported browser present"))
	case checkOnly && len(pending) > 0:
		return wouldRes(i18n.T("install the Ryoku browser host for: %s"), strings.Join(pending, ", "))
	case len(did) > 0:
		return fixedRes(i18n.T("installed the browser host for: %s"), strings.Join(did, ", "))
	default:
		return okRes(i18n.T("browser host installed"))
	}
}

func browserDataHome() string {
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		return d
	}
	return filepath.Join(homeDir(), ".local", "share")
}

// manifestCurrent reports whether the host manifest already exists pointing at
// our launcher, so a run that changes nothing stays a no-op.
func manifestCurrent(path string, want map[string]any, launcher string) bool {
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	var got map[string]any
	if json.Unmarshal(b, &got) != nil {
		return false
	}
	return got["path"] == launcher && got["name"] == want["name"]
}

// launcherCurrent reports whether the launcher exists and still execs the host,
// so a deleted or stale one is repaired rather than silently left broken.
func launcherCurrent(path string) bool {
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return strings.Contains(string(b), "browser-host")
}

// writeLauncher writes the tiny exec shim the browser runs. It bakes ryoku-shell's
// absolute path (a browser spawns the host directly, not through a login shell,
// so PATH is not guaranteed), falling back to a bare name if it is not on PATH yet.
func writeLauncher(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	bin := "ryoku-shell"
	if abs, err := exec.LookPath("ryoku-shell"); err == nil {
		bin = abs
	}
	body := "#!/bin/sh\nexec " + bin + " browser-host \"$@\"\n"
	return os.WriteFile(path, []byte(body), 0o755)
}

func writeManifestJSON(path string, v map[string]any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o644)
}
