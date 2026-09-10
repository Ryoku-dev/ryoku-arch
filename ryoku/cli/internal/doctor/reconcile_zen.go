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
// Linux): the Wayland / hardware-decode / privacy pref defaults, set as defaults
// the user can still override. It ships no extensions of its own; the
// palette-follow Ryoku theme extension is added on top only when its signed xpi
// is present, see zenPolicyBytes. The policy is merged into whatever the Zen
// package already ships in policies.json, so the packager's own keys survive.
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

// reconcileZen merges the Ryoku Zen policy into every Zen install it finds. It
// is a no-op when Zen is absent, so an update never installs Zen or touches the
// browser for a user who does not have it; Zen ships only on the ISO and the
// install script. When Zen is present the policy converges idempotently. It
// merges its keys onto whatever policies.json already holds rather than
// replacing the file, so the Zen packager's own policies are kept. It never sets
// the default browser and never edits a user profile, so a Zen user's own
// choices stand.
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
		cur, _ := os.ReadFile(dst)
		merged, err := mergeZenPolicy(cur, want)
		if err != nil {
			return failRes(i18n.T("could not merge the Zen policy at %s: %v"), dst, err).
				withFix("sudo ryoku doctor")
		}
		if bytes.Equal(bytes.TrimSpace(cur), bytes.TrimSpace(merged)) {
			continue
		}
		if checkOnly {
			pending = append(pending, root)
			continue
		}
		if err := writeZenPolicy(dst, append(merged, '\n')); err != nil {
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

// mergeZenPolicy folds the Ryoku policy (want) onto whatever policies.json the
// Zen package already ships (existing), so keys the packager set survive instead
// of being discarded. Nested objects (policies, Preferences, ExtensionSettings)
// are merged key by key; a scalar Ryoku sets wins for the keys it names, and
// every other key the file already had is kept. An empty or unparseable
// existing file starts from an empty base, so the result is just the Ryoku
// policy. Output is stable (indented, sorted keys) so a second run is a no-op.
func mergeZenPolicy(existing, want []byte) ([]byte, error) {
	base := map[string]any{}
	if trimmed := bytes.TrimSpace(existing); len(trimmed) > 0 {
		var cur map[string]any
		if err := json.Unmarshal(trimmed, &cur); err == nil && cur != nil {
			base = cur
		}
	}
	var overlay map[string]any
	if err := json.Unmarshal(bytes.TrimSpace(want), &overlay); err != nil {
		return nil, err
	}
	deepMerge(base, overlay)
	return json.MarshalIndent(base, "", "  ")
}

// deepMerge writes every key of src into dst, recursing where both sides hold a
// JSON object so sibling keys are preserved, and overwriting otherwise.
func deepMerge(dst, src map[string]any) {
	for k, sv := range src {
		if sm, ok := sv.(map[string]any); ok {
			if dm, ok := dst[k].(map[string]any); ok {
				deepMerge(dm, sm)
				continue
			}
		}
		dst[k] = sv
	}
}
