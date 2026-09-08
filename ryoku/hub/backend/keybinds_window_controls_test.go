package main

import (
	"os"
	"strings"
	"testing"
)

// The shipped Lua is the System catalogue, not a parallel Custom inventory.
func TestShippedWindowControlsCatalogue(t *testing.T) {
	src, err := os.ReadFile("../../hyprland/modules/binds.lua")
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"ALT + Tab":                  "Cycle to next window",
		"ALT + SHIFT + Tab":          "Cycle to previous window",
		"SUPER + ALT + F":            "Toggle full column width (scrolling layout)",
		"SUPER + A":                  "Float at 1000x660, centred (press again to restore tiling)",
		"SUPER + SHIFT + mouse_up":   "Focus column left (scrolling layout)",
		"SUPER + SHIFT + mouse_down": "Focus column right (scrolling layout)",
		"SUPER + CTRL + Left":        "Resize window narrower",
		"SUPER + CTRL + Right":       "Resize window wider",
	}
	counts := map[string]int{}
	for _, cat := range parseBinds(string(src)).Categories {
		for _, b := range cat.Binds {
			desc, ok := want[b.Combo]
			if !ok {
				continue
			}
			counts[b.Combo]++
			if b.Desc != desc {
				t.Errorf("%s: description = %q, want %q", b.Combo, b.Desc, desc)
			}
			if b.Rebindable != !strings.Contains(b.Combo, "mouse") {
				t.Errorf("%s: System rebinding policy changed", b.Combo)
			}
			if cat.Name != "Windows" && cat.Name != "Focus and move windows" {
				t.Errorf("%s: unexpected category %q", b.Combo, cat.Name)
			}
		}
	}
	for combo := range want {
		if counts[combo] != 1 {
			t.Errorf("%s: got %d catalogue entries, want one", combo, counts[combo])
		}
	}
}
