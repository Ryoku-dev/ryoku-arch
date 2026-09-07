package i18n

import (
	"os"
	"path/filepath"
	"testing"
)

// A catalog on disk translates; a string it does not carry stays English.
func TestUseTranslatesAndFallsBack(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "pl.json"), `{"Power limit":"Limit mocy"}`)
	t.Setenv("RYOKU_I18N_DIR", dir)
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	if got := Use("pl"); got != "pl" {
		t.Fatalf("Use(pl) = %q", got)
	}
	if got := T("Power limit"); got != "Limit mocy" {
		t.Errorf("T(Power limit) = %q, want Limit mocy", got)
	}
	if got := T("Not in catalog"); got != "Not in catalog" {
		t.Errorf("missing key = %q, want the English source", got)
	}
}

// The user overlay beats the shipped catalog, so a hand fix survives an update.
func TestOverlayWins(t *testing.T) {
	shipped, cfg := t.TempDir(), t.TempDir()
	write(t, filepath.Join(shipped, "pl.json"), `{"Bar":"Pasek"}`)
	if err := os.MkdirAll(filepath.Join(cfg, "ryoku", "i18n"), 0o755); err != nil {
		t.Fatal(err)
	}
	write(t, filepath.Join(cfg, "ryoku", "i18n", "pl.json"), `{"Bar":"Belka"}`)
	t.Setenv("RYOKU_I18N_DIR", shipped)
	t.Setenv("XDG_CONFIG_HOME", cfg)

	Use("pl")
	if got := T("Bar"); got != "Belka" {
		t.Errorf("T(Bar) = %q, want the overlay's Belka", got)
	}
}

// Tf fills the translated format, so an argument lands wherever the target
// language puts it rather than where English did.
func TestTfUsesTranslatedOrder(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "pl.json"), `{"formatting %s as %s":"%[2]s na %[1]s"}`)
	t.Setenv("RYOKU_I18N_DIR", dir)
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	Use("pl")
	if got := Tf("formatting %s as %s", "/dev/sda1", "btrfs"); got != "btrfs na /dev/sda1" {
		t.Errorf("Tf = %q", got)
	}
}

// Resolution order: an explicit code, then RYOKU_LANG, then shell.json, then
// the POSIX locale, and a regional tag with no catalog falls back to its base.
func TestResolve(t *testing.T) {
	cfg := t.TempDir()
	if err := os.MkdirAll(filepath.Join(cfg, "ryoku"), 0o755); err != nil {
		t.Fatal(err)
	}
	write(t, filepath.Join(cfg, "ryoku", "shell.json"), `{"language":"Polski"}`)
	t.Setenv("XDG_CONFIG_HOME", cfg)
	t.Setenv("RYOKU_LANG", "")
	t.Setenv("LC_ALL", "")
	t.Setenv("LC_MESSAGES", "")
	t.Setenv("LANG", "de_AT.UTF-8")

	if got := Resolve("Deutsch"); got != "de" {
		t.Errorf("explicit native name -> %q, want de", got)
	}
	if got := Resolve("auto"); got != "pl" {
		t.Errorf("auto -> %q, want pl from shell.json", got)
	}
	write(t, filepath.Join(cfg, "ryoku", "shell.json"), `{"language":"Auto"}`)
	if got := Resolve(""); got != "de" {
		t.Errorf("locale de_AT -> %q, want the de catalog", got)
	}
	t.Setenv("LANG", "C")
	if got := Resolve(""); got != "en" {
		t.Errorf("locale C -> %q, want en", got)
	}
}

func TestRTL(t *testing.T) {
	if !IsRTL("ar") {
		t.Error("Arabic should be right to left")
	}
	if IsRTL("pl") {
		t.Error("Polish should not be right to left")
	}
	if _, ok := Find("zh_CN"); !ok {
		t.Error("zh_CN missing from the language table")
	}
}

func write(t *testing.T, path, body string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
