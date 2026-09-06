package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestParseTrackArgs(t *testing.T) {
	cases := []struct {
		args    []string
		channel string
		source  bool
		wantErr bool
	}{
		{[]string{"testing"}, "testing", false, false},
		{[]string{"unstable-dev"}, "unstable-dev", false, false},
		{[]string{"main", "--source"}, "main", true, false},
		{[]string{"--source", "main"}, "main", true, false},
		{[]string{"v0.55.7-beta.19"}, "v0.55.7-beta.19", false, false},
		{[]string{}, "", false, true},
		{[]string{"main", "extra"}, "", false, true},
		{[]string{"--bogus", "main"}, "", false, true},
	}
	for _, c := range cases {
		ch, src, err := parseTrackArgs(c.args)
		if (err != nil) != c.wantErr {
			t.Errorf("%v: err = %v, wantErr %v", c.args, err, c.wantErr)
			continue
		}
		if err != nil {
			continue
		}
		if ch != c.channel || src != c.source {
			t.Errorf("%v: got (%q, %v), want (%q, %v)", c.args, ch, src, c.channel, c.source)
		}
	}
}

func TestPackageChannelForAliases(t *testing.T) {
	cases := map[string]string{
		"unstable-dev":    "testing",
		"main":            "stable",
		"testing":         "testing",
		"stable":          "stable",
		"v0.55.7-beta.19": "v0.55.7-beta.19",
		"bogus":           "",
		"":                "",
	}
	for in, want := range cases {
		if got := packageChannelFor(in); got != want {
			t.Errorf("packageChannelFor(%q) = %q, want %q", in, got, want)
		}
	}
}

// `ryoku track <branch> --source` (either order) hands off to the local
// bin/ryoku-track with just the branch.
func TestTrackSourceRunsLocalScript(t *testing.T) {
	repo := t.TempDir()
	initGit := exec.Command("git", "-C", repo, "init")
	initGit.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null")
	if out, err := initGit.CombinedOutput(); err != nil {
		t.Fatalf("git init: %v\n%s", err, out)
	}
	marker := filepath.Join(repo, "ran")
	script := filepath.Join(repo, "bin", "ryoku-track")
	if err := os.MkdirAll(filepath.Dir(script), 0o755); err != nil {
		t.Fatal(err)
	}
	body := "#!/bin/sh\nprintf '%s' \"$1\" > " + shellQuote(marker) + "\n"
	if err := os.WriteFile(script, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_REPO", repo)

	if err := cmdTrack([]string{"--source", "unstable-dev"}); err != nil {
		t.Fatalf("cmdTrack --source: %v", err)
	}
	got, err := os.ReadFile(marker)
	if err != nil {
		t.Fatalf("local track script did not run: %v", err)
	}
	if string(got) != "unstable-dev" {
		t.Errorf("script received %q, want unstable-dev (channel not passed through)", got)
	}
}
