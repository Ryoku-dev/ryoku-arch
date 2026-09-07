package main

import (
	"os"
	"path/filepath"
	"testing"
)

// touch creates an empty file, making its parent dirs.
func touch(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatal(err)
	}
}

// writeIndexTheme writes a theme's index.theme with an Inherits= line.
func writeIndexTheme(t *testing.T, root, theme, inherits string) {
	t.Helper()
	dir := filepath.Join(root, theme)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	body := "[Icon Theme]\nName=" + theme + "\n"
	if inherits != "" {
		body += "Inherits=" + inherits + "\n"
	}
	if err := os.WriteFile(filepath.Join(dir, "index.theme"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// parseSizeDir reads the leading integer, doubling for @2x.
func TestParseSizeDir(t *testing.T) {
	cases := map[string]int{
		"48":       48,
		"48x48":    48,
		"256x256":  256,
		"512x512":  512,
		"48x48@2x": 96,
		"32@2x":    64,
		"scalable": 0,
		"symbolic": 0,
		"apps":     0,
		"":         0,
	}
	for in, want := range cases {
		if got := parseSizeDir(in); got != want {
			t.Errorf("parseSizeDir(%q) = %d, want %d", in, got, want)
		}
	}
}

// parseInherits pulls the Inherits list out of the [Icon Theme] section only.
func TestParseInherits(t *testing.T) {
	data := []byte("[Icon Theme]\nName=X\nInherits=a,b, c\n\n[48x48/apps]\nSize=48\nInherits=ignored\n")
	got := parseInherits(data)
	want := []string{"a", "b", "c"}
	if len(got) != len(want) {
		t.Fatalf("parseInherits = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("parseInherits = %v, want %v", got, want)
		}
	}
}

// The chain is the theme, its Inherits parents depth-first and deduped, then
// hicolor last -- and hicolor is never duplicated when a theme names it.
func TestIconThemeChain(t *testing.T) {
	root := t.TempDir()
	writeIndexTheme(t, root, "themeA", "themeB,themeC")
	writeIndexTheme(t, root, "themeB", "themeC")
	writeIndexTheme(t, root, "themeC", "hicolor")
	got := iconThemeChain("themeA", []string{root})
	want := []string{"themeA", "themeB", "themeC", "hicolor"}
	if len(got) != len(want) {
		t.Fatalf("chain = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("chain = %v, want %v", got, want)
		}
	}
}

// Within one theme a scalable SVG beats the largest sized raster, which beats a
// symbolic variant; among sized dirs the largest wins and @2x counts double.
func TestSizePreferenceWithinTheme(t *testing.T) {
	root := t.TempDir()
	writeIndexTheme(t, root, "theme", "")
	base := filepath.Join(root, "theme")

	// `pref` has scalable + sized + symbolic: the scalable svg must win.
	touch(t, filepath.Join(base, "16x16", "apps", "pref.png"))
	touch(t, filepath.Join(base, "48x48", "apps", "pref.png"))
	touch(t, filepath.Join(base, "scalable", "apps", "pref.svg"))
	touch(t, filepath.Join(base, "symbolic", "apps", "pref.svg"))

	// `raster` has only sized dirs: the largest wins, and @2x doubles.
	touch(t, filepath.Join(base, "64x64", "apps", "raster.png"))
	touch(t, filepath.Join(base, "48x48@2x", "apps", "raster.png")) // 96 -> wins

	idx := buildIndex("theme", []string{root}, "")
	if got := idx.Icons["pref"]; got != filepath.Join(base, "scalable", "apps", "pref.svg") {
		t.Errorf("pref resolved to %q, want the scalable svg", got)
	}
	if got := idx.Icons["raster"]; got != filepath.Join(base, "48x48@2x", "apps", "raster.png") {
		t.Errorf("raster resolved to %q, want the 48x48@2x png (96)", got)
	}
}

// The first theme in the chain that has a name keeps it, even when a later theme
// has a nominally better candidate.
func TestFirstThemeWins(t *testing.T) {
	root := t.TempDir()
	writeIndexTheme(t, root, "themeA", "themeB")
	writeIndexTheme(t, root, "themeB", "")
	// themeA has only a small raster; themeB has a scalable svg. themeA wins.
	touch(t, filepath.Join(root, "themeA", "16x16", "apps", "dup.png"))
	touch(t, filepath.Join(root, "themeB", "scalable", "apps", "dup.svg"))

	idx := buildIndex("themeA", []string{root}, "")
	if got := idx.Icons["dup"]; got != filepath.Join(root, "themeA", "16x16", "apps", "dup.png") {
		t.Errorf("dup resolved to %q, want themeA's raster (first theme wins)", got)
	}
}

// Earlier roots win ties for the same theme, so a user override beats the system
// copy at the same score.
func TestEarlierRootWins(t *testing.T) {
	userRoot := t.TempDir()
	sysRoot := t.TempDir()
	writeIndexTheme(t, userRoot, "theme", "")
	writeIndexTheme(t, sysRoot, "theme", "")
	touch(t, filepath.Join(userRoot, "theme", "scalable", "apps", "app.svg"))
	touch(t, filepath.Join(sysRoot, "theme", "scalable", "apps", "app.svg"))

	idx := buildIndex("theme", []string{userRoot, sysRoot}, "")
	if got := idx.Icons["app"]; got != filepath.Join(userRoot, "theme", "scalable", "apps", "app.svg") {
		t.Errorf("app resolved to %q, want the user root copy", got)
	}
}

// A name found nowhere in the theme chain falls back to /usr/share/pixmaps,
// preferring svg over png over xpm; a themed name is never overridden by pixmaps.
func TestPixmapsFallback(t *testing.T) {
	root := t.TempDir()
	pix := t.TempDir()
	writeIndexTheme(t, root, "theme", "")
	touch(t, filepath.Join(root, "theme", "scalable", "apps", "themed.svg"))
	touch(t, filepath.Join(pix, "themed.png")) // must NOT override the themed svg
	touch(t, filepath.Join(pix, "only.png"))
	touch(t, filepath.Join(pix, "only.svg")) // svg preferred over png
	touch(t, filepath.Join(pix, "only.xpm"))

	idx := buildIndex("theme", []string{root}, pix)
	if got := idx.Icons["themed"]; got != filepath.Join(root, "theme", "scalable", "apps", "themed.svg") {
		t.Errorf("themed resolved to %q, want the themed svg (pixmaps must not override)", got)
	}
	if got := idx.Icons["only"]; got != filepath.Join(pix, "only.svg") {
		t.Errorf("only resolved to %q, want the pixmaps svg", got)
	}
}

// A symbolic variant is indexed under its own -symbolic stem, and loses to a
// non-symbolic icon of the same base name.
func TestSymbolicNaming(t *testing.T) {
	root := t.TempDir()
	writeIndexTheme(t, root, "theme", "")
	base := filepath.Join(root, "theme")
	touch(t, filepath.Join(base, "scalable", "apps", "go-home.svg"))
	touch(t, filepath.Join(base, "scalable", "apps", "go-home-symbolic.svg"))

	idx := buildIndex("theme", []string{root}, "")
	if got := idx.Icons["go-home"]; got != filepath.Join(base, "scalable", "apps", "go-home.svg") {
		t.Errorf("go-home resolved to %q, want the plain svg", got)
	}
	if _, ok := idx.Icons["go-home-symbolic"]; !ok {
		t.Errorf("go-home-symbolic was not indexed under its own stem")
	}
}

// resolveIconName passes an existing absolute path through, drops a missing one,
// and otherwise looks the name up in the index.
func TestResolveIconName(t *testing.T) {
	dir := t.TempDir()
	real := filepath.Join(dir, "real.svg")
	touch(t, real)
	idx := iconIndex{Icons: map[string]string{"kitty": "/usr/share/icons/hicolor/scalable/apps/kitty.svg"}}

	if got := resolveIconName(real, idx); got != real {
		t.Errorf("absolute existing path = %q, want %q", got, real)
	}
	if got := resolveIconName("/no/such/icon.svg", idx); got != "" {
		t.Errorf("absolute missing path = %q, want \"\"", got)
	}
	if got := resolveIconName("kitty", idx); got != "/usr/share/icons/hicolor/scalable/apps/kitty.svg" {
		t.Errorf("kitty = %q, want the indexed path", got)
	}
	if got := resolveIconName("nope", idx); got != "" {
		t.Errorf("unknown name = %q, want \"\"", got)
	}
	if got := resolveIconName("", idx); got != "" {
		t.Errorf("empty name = %q, want \"\"", got)
	}
}
