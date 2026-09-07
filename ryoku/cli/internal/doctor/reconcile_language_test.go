package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// An existing box stores the old human-readable language name the six-entry
// picker wrote. The reconciler must rewrite it as the catalog code the picker
// writes today, leave every other key alone, and leave an already-migrated or
// Auto value untouched.
func TestReconcileShellLanguage(t *testing.T) {
	for _, c := range []struct {
		name   string
		stored string
		want   string // "" = the file must not change
		fixed  bool
	}{
		{"old native name", `"Español"`, "es", true},
		{"old regional name", `"Português (BR)"`, "pt_BR", true},
		{"english name", `"English"`, "en", true},
		{"already a code", `"pl"`, "", false},
		{"auto", `"Auto"`, "", false},
	} {
		t.Run(c.name, func(t *testing.T) {
			home := t.TempDir()
			t.Setenv("XDG_CONFIG_HOME", home)
			dir := filepath.Join(home, "ryoku")
			if err := os.MkdirAll(dir, 0o755); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "shell.json")
			body := `{"language":` + c.stored + `,"barStyle":"sumi"}`
			if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
				t.Fatal(err)
			}

			if got := reconcileShellLanguage(true); (got.status == recWouldFix) != c.fixed {
				t.Errorf("checkOnly status = %v, want a pending fix = %v", got.status, c.fixed)
			}
			// check-only must never write.
			if b, _ := os.ReadFile(path); string(b) != body {
				t.Fatalf("checkOnly rewrote the file: %s", b)
			}

			res := reconcileShellLanguage(false)
			var store map[string]any
			b, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(b, &store); err != nil {
				t.Fatalf("shell.json no longer parses: %v", err)
			}
			if store["barStyle"] != "sumi" {
				t.Errorf("an unrelated key was lost: %v", store)
			}
			if c.want == "" {
				if string(b) != body {
					t.Errorf("file changed but should not have: %s", b)
				}
				return
			}
			if (res.status == recFixed) != c.fixed {
				t.Errorf("status = %v, want fixed", res.status)
			}
			if store["language"] != c.want {
				t.Errorf("language = %v, want %q", store["language"], c.want)
			}
		})
	}
}
