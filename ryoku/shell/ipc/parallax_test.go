package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestProgressLabel(t *testing.T) {
	cases := []struct {
		stage string
		want  string
	}{
		{"reading", "reading wallpaper"},
		{"subject", "cutting subject"},
		{"inpaint", "inpainting background"},
		{"writing", "writing layer"},
		{"done", "done"},
		{"cancelled", "cancelled"},
	}
	for _, tc := range cases {
		rec := map[string]any{"stage": tc.stage}
		got := progressLabel(rec)
		if got != tc.want {
			t.Errorf("progressLabel(%q) = %q, want %q", tc.stage, got, tc.want)
		}
	}
}

func TestProgressPercentMidpoints(t *testing.T) {
	for stage, want := range map[string]int{
		"subject": 45,
		"inpaint": 80,
		"done":    100,
		"writing": 92,
	} {
		if got := progressPercent(map[string]any{"stage": stage}); got != want {
			t.Errorf("progressPercent(%q) = %d, want %d", stage, got, want)
		}
	}
}

func TestReadLastParallaxProgress(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("XDG_STATE_HOME", filepath.Join(dir, ".local", "state"))

	path := parallaxProgressPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, r := range []map[string]any{
		{"stage": "starting"},
		{"stage": "subject", "model": "u2netp"},
		{"stage": "inpaint"},
		{"stage": "done", "subject": "wp-subject.png"},
	} {
		b, _ := json.Marshal(r)
		f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := f.Write(append(b, '\n')); err != nil {
			t.Fatal(err)
		}
		if err := f.Close(); err != nil {
			t.Fatal(err)
		}
	}
	rec, label, percent := readLastParallaxProgress()
	if rec == nil {
		t.Fatal("readLastParallaxProgress returned nil")
	}
	if got := rec["stage"]; got != "done" {
		t.Fatalf("rec[stage] = %v, want done", got)
	}
	if label != "done" || percent != 100 {
		t.Fatalf("label/percent = %q/%d, want done/100", label, percent)
	}
}

func TestParallaxStatusJSONFields(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("XDG_STATE_HOME", filepath.Join(dir, ".local", "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, ".config"))
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("PATH", t.TempDir()) // no ryoku-parallax-engine: engine reads as absent.

	wall := filepath.Join(dir, "wp.png")
	writeFile(t, wall, "png")
	parallaxDir := filepath.Join(dir, "Pictures", "Parallax")
	if err := os.MkdirAll(parallaxDir, 0o755); err != nil {
		t.Fatal(err)
	}
	l1 := filepath.Join(parallaxDir, "wp-l1.png")
	l2 := filepath.Join(parallaxDir, "wp-l2.png")
	writeFile(t, l1, "a")
	writeFile(t, l2, "b")

	reg := parallaxWalls{Walls: map[string]parallaxWall{}, Layers: map[string][]parallaxLayerRef{}}
	reg.Walls[wall] = parallaxWall{Enabled: true, Mode: parallaxModeManual}
	reg.Layers[wall] = []parallaxLayerRef{
		{Out: l1, Rev: fileModTime(l1)},
		{Out: l2, Rev: fileModTime(l2)},
	}
	saveParallaxWalls(reg)

	progressFile := parallaxProgressPath()
	if err := os.MkdirAll(filepath.Dir(progressFile), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, progressFile, `{"stage":"subject"}`+"\n")

	d := &daemon{}
	d.ryoWallMu.Lock()
	d.ryoWall = ryogamiFrame{Default: ryogamiFrameEntry{Path: wall}}
	d.ryoWallMu.Unlock()
	d.parallaxBusy.Store(true)

	body := d.parallaxStatusJSON()
	var got map[string]any
	if err := json.Unmarshal([]byte(body), &got); err != nil {
		t.Fatalf("status JSON: %v", err)
	}
	for _, k := range []string{"busy", "current", "layers", "mode", "stage", "percent"} {
		if _, ok := got[k]; !ok {
			t.Errorf("status JSON missing %q; body=%s", k, body)
		}
	}
	if got["busy"] != true || got["current"] != true {
		t.Errorf("busy/current = %v/%v, want true/true", got["busy"], got["current"])
	}
	if got["layers"].(float64) != 2 {
		t.Errorf("layers = %v, want 2", got["layers"])
	}
	if got["mode"] != "manual" {
		t.Errorf("mode = %v, want manual", got["mode"])
	}
	if got["stage"] != "cutting subject" {
		t.Errorf("stage = %v, want cutting subject", got["stage"])
	}
}

func TestParallaxDispatchArgs(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("XDG_STATE_HOME", filepath.Join(dir, ".local", "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, ".config"))
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())

	wall := filepath.Join(dir, "wp.png")
	writeFile(t, wall, "png")

	d := &daemon{}
	d.ryoWallMu.Lock()
	d.ryoWall = ryogamiFrame{Default: ryogamiFrameEntry{Path: wall}}
	d.ryoWallMu.Unlock()

	if got := d.dispatch("parallax set-mode bogus"); !strings.HasPrefix(got, "err parallax set-mode") {
		t.Fatalf("set-mode bogus = %q, want err", got)
	}
	if got := d.dispatch("parallax set-mode manual"); got != "ok" {
		t.Fatalf("set-mode manual = %q, want ok", got)
	}

	// A source path with a space must survive the command split intact.
	src := filepath.Join(dir, "my layer.png")
	writeFile(t, src, "layer")
	got := d.dispatch("parallax add-layer " + src)
	if !strings.HasPrefix(got, "ok ") {
		t.Fatalf("add-layer = %q, want ok <path>", got)
	}
	if _, err := os.Stat(strings.TrimPrefix(got, "ok ")); err != nil {
		t.Fatalf("add-layer dst missing: %v", err)
	}
}

func TestParallaxRefreshGuard(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("XDG_STATE_HOME", filepath.Join(dir, ".local", "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, ".config"))
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("PATH", t.TempDir())

	wall := filepath.Join(dir, "wp.png")
	writeFile(t, wall, "png")
	reg := parallaxWalls{Walls: map[string]parallaxWall{}, Layers: map[string][]parallaxLayerRef{}}
	reg.Walls[wall] = parallaxWall{Enabled: true, Mode: parallaxModeAuto}
	saveParallaxWalls(reg)

	parallaxCutPID.Store(98765)
	defer parallaxCutPID.Store(0)
	parallaxLastFinish.Store(0)

	d := &daemon{}
	d.ryoWallMu.Lock()
	d.ryoWall = ryogamiFrame{Default: ryogamiFrameEntry{Path: wall}}
	d.ryoWallMu.Unlock()

	d.reconcileParallax(false)
	if got := len(loadParallaxWalls().Layers[wall]); got != 0 {
		t.Fatalf("reconcile ran with PID live; layers = %d", got)
	}
}

func TestParallaxRefreshSettle(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("XDG_STATE_HOME", filepath.Join(dir, ".local", "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, ".config"))
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("PATH", t.TempDir())

	wall := filepath.Join(dir, "wp.png")
	writeFile(t, wall, "png")
	reg := parallaxWalls{Walls: map[string]parallaxWall{}, Layers: map[string][]parallaxLayerRef{}}
	reg.Walls[wall] = parallaxWall{Enabled: true, Mode: parallaxModeAuto}
	saveParallaxWalls(reg)

	parallaxCutPID.Store(0)
	parallaxLastFinish.Store(time.Now().Unix() - 5)
	d := &daemon{}
	d.ryoWallMu.Lock()
	d.ryoWall = ryogamiFrame{Default: ryogamiFrameEntry{Path: wall}}
	d.ryoWallMu.Unlock()
	d.reconcileParallax(false)
	if len(loadParallaxWalls().Layers[wall]) != 0 {
		t.Fatal("reconcile started a new cut within the settle window")
	}
}

func TestParallaxConfigFromDefault(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))

	if got := parallaxConfigFromFile(); got.mode != parallaxModeAuto ||
		got.model != "u2netp" || got.alphaMatting {
		t.Fatalf("default config = %+v", got)
	}
	dir := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "parallax.json"), []byte(
		`{"mode":"manual","model":"birefnet-general-lite","alphaMatting":true}`), 0o644); err != nil {
		t.Fatal(err)
	}
	got := parallaxConfigFromFile()
	if got.mode != parallaxModeManual || got.model != "birefnet-general-lite" || !got.alphaMatting {
		t.Errorf("override config = %+v", got)
	}
}

func TestListManualLayers(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	wall := filepath.Join(home, "wp.png")
	writeFile(t, wall, "png")
	dir := parallaxManualDir(wall)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"layer-03.png", "layer-01.png", "layer-02.png", "notes.txt", "layer-2.png"} {
		writeFile(t, filepath.Join(dir, name), name)
	}
	layers := listManualLayers(wall)
	if len(layers) != 3 {
		t.Fatalf("layers = %d, want 3", len(layers))
	}
	want := []string{"Layer 1", "Layer 2", "Layer 3"}
	wantSuffix := []string{"layer-01.png", "layer-02.png", "layer-03.png"}
	for i, l := range layers {
		if l.Label != want[i] {
			t.Errorf("layer[%d].label = %q, want %q", i, l.Label, want[i])
		}
		if !strings.HasSuffix(l.Out, wantSuffix[i]) {
			t.Errorf("layer[%d].out = %q, want suffix %q", i, l.Out, wantSuffix[i])
		}
	}
}

func TestListManualLayersMissingFolder(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	wall := filepath.Join(home, "wp.png")
	writeFile(t, wall, "png")
	layers := listManualLayers(wall)
	if layers == nil || len(layers) != 0 {
		t.Fatalf("layers = %#v, want a non-nil empty slice", layers)
	}
}

func TestParallaxAddManualLayer(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("XDG_STATE_HOME", filepath.Join(dir, ".local", "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, ".config"))
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("PATH", t.TempDir())

	wall := filepath.Join(dir, "Pictures", "wp.png")
	if err := os.MkdirAll(filepath.Dir(wall), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, wall, "png")
	existing := filepath.Join(parallaxManualDir(wall), "layer-01.png")
	if err := os.MkdirAll(filepath.Dir(existing), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, existing, "a")

	src := filepath.Join(dir, "candidate.png")
	writeFile(t, src, "PNG")

	d := &daemon{}
	d.ryoWallMu.Lock()
	d.ryoWall = ryogamiFrame{Default: ryogamiFrameEntry{Path: wall}}
	d.ryoWallMu.Unlock()

	got, err := d.parallaxAddManualLayer(src)
	if err != nil {
		t.Fatalf("add: %v", err)
	}
	want := filepath.Join(parallaxManualDir(wall), "layer-02.png")
	if got != want {
		t.Fatalf("add returned %q, want %q", got, want)
	}
}

func TestParallaxRemoveManualLayerRejectsPathTraversal(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("XDG_STATE_HOME", filepath.Join(dir, ".local", "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, ".config"))
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("PATH", t.TempDir())

	wall := filepath.Join(dir, "wp.png")
	writeFile(t, wall, "png")
	outside := filepath.Join(dir, "evil.png")
	writeFile(t, outside, "bad")

	d := &daemon{}
	d.ryoWallMu.Lock()
	d.ryoWall = ryogamiFrame{Default: ryogamiFrameEntry{Path: wall}}
	d.ryoWallMu.Unlock()

	if err := d.parallaxRemoveManualLayer(outside); err == nil {
		t.Fatal("removing outside the folder must fail")
	}
	if _, err := os.Stat(outside); err != nil {
		t.Fatalf("outside file must survive: %v", err)
	}
}

func TestParallaxManualFolderLayout(t *testing.T) {
	cases := map[string]bool{
		"layer-01.png":       true,
		"layer-100.png":      true,
		"layer-1.png":        false,
		"Layer-01.png":       false,
		"layer-01.jpg":       false,
		"layer-01.png.bak":   false,
		"layer-01-thumb.png": false,
	}
	for name, want := range cases {
		if got := manualLayerRe.MatchString(name); got != want {
			t.Errorf("%s -> %v, want %v", name, got, want)
		}
	}
}

func TestParallaxEngineBin(t *testing.T) {
	t.Setenv("RYOKU_SHELL_DIR", "/dev/null")
	if got := parallaxEngineBin(); got != "ryoku-parallax-engine" {
		t.Fatalf("engine bin with bad RYOKU_SHELL_DIR = %q", got)
	}
}

func TestParallaxSubjectOut(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	want := filepath.Join(home, "Pictures", "Parallax", "sunset", "layer-01.png")
	if got := parallaxSubjectOut("/walls/sunset.jpg"); got != want {
		t.Fatalf("subject out = %q, want %q", got, want)
	}
}

func TestParallaxInpaintedOut(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	want := filepath.Join(home, "Pictures", "Parallax", "sunset", "background.png")
	if got := parallaxInpaintedOut("/walls/sunset.jpg"); got != want {
		t.Fatalf("inpainted out = %q, want %q", got, want)
	}
}
