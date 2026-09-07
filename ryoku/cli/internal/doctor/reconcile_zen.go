package doctor

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// zenPolicies is the base Ryoku Zen policy, embedded in the ryoku binary. It is a
// Firefox enterprise policies.json (Zen is a Firefox fork and honours it on
// Linux): the shipped extensions (uBlock Origin, Privacy Badger, installed
// removable, not forced) and the Wayland / hardware-decode / privacy pref
// defaults, set as defaults the user can still override. The palette-follow
// Ryoku theme extension is added on top only when its signed xpi is present, see
// zenPolicyBytes.
//
//go:embed zen_policies.json
var zenPolicies []byte

// zenThemeXPI is where the AMO-signed Ryoku theme extension is shipped once a
// release signs it. Zen enforces extension signing (a branded release build), so
// an unsigned extension cannot load and this file only exists after a signing
// pass; until then the theme extension is simply omitted. Overridable in tests.
var zenThemeXPI = "/usr/share/ryoku/browser/ryoku-theme.xpi"

// zenPolicyBytes returns the policy to write. Without the signed theme xpi it is
// the embedded payload verbatim; when the xpi is present it also installs the
// Ryoku palette-follow extension from that local file, so signing the extension
// in a release lights the browser theme up with no further change here.
func zenPolicyBytes() []byte {
	base := bytes.TrimSpace(zenPolicies)
	if !sys.Exists(zenThemeXPI) {
		return base
	}
	var doc map[string]any
	if err := json.Unmarshal(base, &doc); err != nil {
		return base
	}
	pol, _ := doc["policies"].(map[string]any)
	if pol == nil {
		return base
	}
	ext, _ := pol["ExtensionSettings"].(map[string]any)
	if ext == nil {
		ext = map[string]any{}
		pol["ExtensionSettings"] = ext
	}
	ext["ryoku-theme@ryoku.arch"] = map[string]any{
		"installation_mode": "normal_installed",
		"install_url":       "file://" + zenThemeXPI,
	}
	out, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return base
	}
	return out
}

// zenInstallRoots lists the directories a Zen install may live under. The policy
// belongs in <root>/distribution/policies.json, where it applies to every
// profile without touching the user's own settings. The list covers the AUR
// package (zen-browser-bin), a plain /opt drop, a per-user tarball, and whatever
// dir a zen binary on PATH resolves into.
func zenInstallRoots() []string {
	roots := []string{
		"/usr/lib/zen-browser",
		"/usr/lib64/zen-browser",
		"/opt/zen-browser-bin",
		"/opt/zen",
	}
	if home := homeDir(); home != "" {
		roots = append(roots, filepath.Join(home, ".local", "opt", "zen"))
	}
	for _, name := range []string{"zen", "zen-browser", "zen-bin"} {
		if p, err := exec.LookPath(name); err == nil {
			if real, err := filepath.EvalSymlinks(p); err == nil {
				roots = append(roots, filepath.Dir(real))
			}
		}
	}
	return roots
}

// reconcileZen writes the Ryoku Zen policy into every Zen install it finds. It
// is a no-op when Zen is absent, so an update never installs Zen or touches the
// browser for a user who does not have it; Zen ships only on the ISO and the
// install script. When Zen is present the policy converges idempotently. It
// never sets the default browser and never edits a user profile, so a Zen user's
// own choices stand.
func reconcileZen(checkOnly bool) recResult {
	return reconcileZenInto(zenInstallRoots(), checkOnly)
}

func reconcileZenInto(roots []string, checkOnly bool) recResult {
	want := zenPolicyBytes()
	var present, pending, did []string
	seen := map[string]bool{}
	for _, root := range roots {
		if root == "" || seen[root] || !sys.Exists(filepath.Join(root, "application.ini")) {
			continue
		}
		seen[root] = true
		present = append(present, root)
		dst := filepath.Join(root, "distribution", "policies.json")
		if cur, err := os.ReadFile(dst); err == nil && bytes.Equal(bytes.TrimSpace(cur), want) {
			continue
		}
		if checkOnly {
			pending = append(pending, root)
			continue
		}
		if err := writeZenPolicy(dst, append(append([]byte{}, want...), '\n')); err != nil {
			return failRes(i18n.T("could not write the Zen policy at %s: %v"), dst, err).
				withFix("sudo ryoku doctor")
		}
		did = append(did, root)
	}
	switch {
	case len(present) == 0:
		return okRes(i18n.T("Zen not installed"))
	case checkOnly && len(pending) > 0:
		return wouldRes(i18n.T("apply the Ryoku Zen policy in: %s"), strings.Join(pending, ", "))
	case len(did) > 0:
		return fixedRes(i18n.T("applied the Ryoku Zen policy in: %s"), strings.Join(did, ", "))
	default:
		return okRes(i18n.T("Zen policy up to date"))
	}
}

// writeZenPolicy lands the policy as the user when the install dir is theirs
// (a tarball under ~/.local), and through sudo when it is a package's under
// /opt or /usr, which is the common case and used to fail with EACCES.
func writeZenPolicy(dst string, body []byte) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err == nil {
		if err := os.WriteFile(dst, body, 0o644); err == nil {
			return nil
		} else if !os.IsPermission(err) {
			return err
		}
	} else if !os.IsPermission(err) {
		return err
	}
	if err := sys.Sudo("install", "-d", "-m", "0755", filepath.Dir(dst)); err != nil {
		return err
	}
	return sys.WriteRootFile(dst, string(body), "0644")
}
