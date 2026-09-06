package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSettingsSectionRoutesStoreCategories(t *testing.T) {
	cases := map[string]string{
		"rices":     "appearance",
		"plugins":   "addons",
		"bundles":   "addons",
		"barstyles": "bar-studio",
		"fastfetch": "fastfetch",
	}
	for category, want := range cases {
		got, ok := settingsSection(category)
		if !ok || got != want {
			t.Fatalf("settingsSection(%q) = %q, %v; want %q, true", category, got, ok, want)
		}
	}
	// Today has no Settings page; lockscreen and the app launcher are edit-only,
	// and the flat-image categories have no page, so none routes to Settings.
	for _, edit := range []string{"today", "lockscreens", "decors", "launcher-images", "ryotunes-skins"} {
		if _, ok := settingsSection(edit); ok {
			t.Fatalf("%q should have no Settings route", edit)
		}
	}
}

func TestStoreSectionIncludesShowroomRoutesAndEveryCategory(t *testing.T) {
	for _, section := range []string{"discover", "library", "rices", "lockscreens", "barstyles", "fastfetch", "plugins", "bundles", "ryotunes-skins"} {
		if !storeSection(section) {
			t.Fatalf("storeSection(%q) = false", section)
		}
	}
	for _, section := range []string{"today", "installed", "unknown"} {
		if storeSection(section) {
			t.Fatalf("storeSection(%q) = true", section)
		}
	}
}

func TestDispatchRoutesHandoffCommands(t *testing.T) {
	dir := t.TempDir()
	qs := filepath.Join(dir, "qs")
	if err := os.WriteFile(qs, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))

	for name, args := range map[string][]string{
		"open":     {"open", "library"},
		"settings": {"settings", "rices"},
	} {
		t.Run(name, func(t *testing.T) {
			if err := dispatch(args); err != nil {
				t.Fatalf("dispatch(%q): %v", args, err)
			}
		})
	}
}
