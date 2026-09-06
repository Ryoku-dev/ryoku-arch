package main

import (
	"bufio"
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// writeStageStub installs a fake ryostage engine (via RYOKU_STAGE_ENGINE) that
// records every invocation and, for cut/inpaint, writes the requested output.
// Behaviour is steered per-test through STAGE_STUB_* env vars the daemon
// inherits when it spawns the child. Returns the call-log path.
func writeStageStub(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	logf := filepath.Join(dir, "calls.log")
	bin := filepath.Join(dir, "ryostage-stub")
	const script = `#!/usr/bin/env bash
echo "$*" >> "$STAGE_STUB_LOG"
cmd="${1:-}"; shift || true
case "$cmd" in
  check)
    if [[ -n "${STAGE_STUB_MISSING:-}" ]]; then echo missing; exit 1; fi
    echo available; exit 0 ;;
  models)
    echo '[{"id":"u2netp","tier":"draft","label":"Draft","installed":true}]'; exit 0 ;;
  cut)
    out="$2"
    if [[ -n "${STAGE_STUB_SLEEP:-}" ]]; then sleep "$STAGE_STUB_SLEEP"; fi
    if [[ -n "${STAGE_STUB_CUT_FAIL:-}" ]]; then echo "cut failed" >&2; exit 1; fi
    mkdir -p "$(dirname "$out")"; printf 'SUBJECTPNG' > "$out"; echo "$out"; exit 0 ;;
  inpaint)
    out="$3"
    if [[ -n "${STAGE_STUB_INPAINT_FAIL:-}" ]]; then echo "inpaint failed" >&2; exit 1; fi
    mkdir -p "$(dirname "$out")"; printf 'BGPNG' > "$out"; echo "$out"; exit 0 ;;
esac
exit 0
`
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RYOKU_STAGE_ENGINE", bin)
	t.Setenv("STAGE_STUB_LOG", logf)
	return logf
}

// countCalls returns how many logged engine invocations began with verb.
func countCalls(logf, verb string) int {
	b, err := os.ReadFile(logf)
	if err != nil {
		return 0
	}
	n := 0
	for _, line := range strings.Split(string(b), "\n") {
		if fields := strings.Fields(line); len(fields) > 0 && fields[0] == verb {
			n++
		}
	}
	return n
}

// stageHome wires a hermetic HOME + XDG tree and returns it.
func stageHome(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_STATE_HOME", filepath.Join(home, ".local", "state"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(home, ".cache"))
	// An empty runtime dir: no ryogami socket, so depthClear/publish fail fast
	// and harmlessly instead of reaching the live daemon.
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	return home
}

func (d *daemon) showWall(pic string) {
	d.ryoWallMu.Lock()
	d.ryoWall = ryogamiFrame{Default: ryogamiFrameEntry{Path: pic}}
	d.ryoWallMu.Unlock()
}

// TestStageWallsRoundTrip pins the registry contract: a saved registry loads
// back identically (effect, mode, scene, per-layer knobs), and a missing or
// corrupt file loads with a non-nil map so callers never panic assigning in.
func TestStageWallsRoundTrip(t *testing.T) {
	home := stageHome(t)
	wall := filepath.Join(home, "w.png")

	reg := stageWalls{Current: wall, Walls: map[string]stageWall{}}
	reg.Walls[wall] = stageWall{
		Effect: stageEffectParallax,
		Mode:   stageModeManual,
		Scene:  []string{"wallpaper", "layer:1", "widget:clock"},
		Layers: []stageLayer{
			{"out": "/a/subject.png", "rev": float64(11), "label": "Subject", "opacity": 0.8, "feather": nil},
		},
	}
	if err := saveStageWalls(reg); err != nil {
		t.Fatal(err)
	}
	got := loadStageWalls()
	if got.Current != wall {
		t.Fatalf("current = %q, want %q", got.Current, wall)
	}
	w := got.Walls[wall]
	if w.Effect != stageEffectParallax || w.Mode != stageModeManual {
		t.Fatalf("effect/mode = %v/%v", w.Effect, w.Mode)
	}
	if len(w.Scene) != 3 || w.Scene[2] != "widget:clock" {
		t.Fatalf("scene = %v", w.Scene)
	}
	if len(w.Layers) != 1 || w.Layers[0]["label"] != "Subject" || w.Layers[0]["opacity"] != 0.8 {
		t.Fatalf("layers = %v", w.Layers)
	}
	if v, ok := w.Layers[0]["feather"]; !ok || v != nil {
		t.Fatalf("feather knob (null=inherit) not preserved: %v ok=%v", v, ok)
	}

	// Normalisation after a decode failure: a garbage file still yields a
	// non-nil map.
	if err := os.WriteFile(stageWallsPath(), []byte("{not json"), 0o644); err != nil {
		t.Fatal(err)
	}
	if norm := loadStageWalls(); norm.Walls == nil {
		t.Fatal("corrupt registry did not normalise to a non-nil Walls map")
	}
}

// TestStageSwitchReusesWithoutGenerating pins the core rule: a wallpaper switch
// (a plain reconcile, neither force nor gen) reuses an existing cut instantly
// and never runs the engine -- not even the availability probe.
func TestStageSwitchReusesWithoutGenerating(t *testing.T) {
	home := stageHome(t)
	logf := writeStageStub(t)

	wall := filepath.Join(home, "w.png")
	writeFile(t, wall, "wp")
	subj := stageSubjectOut(wall)
	if err := os.MkdirAll(filepath.Dir(subj), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, subj, "SUBJECT")
	newer := time.Now().Add(time.Hour)
	if err := os.Chtimes(subj, newer, newer); err != nil {
		t.Fatal(err)
	}
	reg := stageWalls{Walls: map[string]stageWall{wall: {Effect: stageEffectSubject}}}
	if err := saveStageWalls(reg); err != nil {
		t.Fatal(err)
	}

	d := &daemon{}
	d.showWall(wall)
	d.reconcileStage(false, false)

	if got := countCalls(logf, "cut") + countCalls(logf, "inpaint") + countCalls(logf, "check"); got != 0 {
		t.Fatalf("a switch made %d engine calls, want 0", got)
	}
	frame := d.buildStageFrame()
	if frame.Walls[wall].Subject != subj {
		t.Fatalf("reused subject not in frame: %+v", frame.Walls[wall])
	}
}

// TestStageSetEffectSubject pins the enable path: turning the subject effect on
// for an uncut wallpaper runs exactly one cut, publishes the subject in the
// topic frame, and folds it to ryogami over the unchanged `depth set` wire.
func TestStageSetEffectSubject(t *testing.T) {
	home := stageHome(t)
	logf := writeStageStub(t)

	// A fake ryogami to capture the pixel-lock fold.
	rt := os.Getenv("XDG_RUNTIME_DIR")
	ln, err := net.Listen("unix", filepath.Join(rt, "ryogami.sock"))
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	lines := make(chan string, 4)
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				l, _ := bufio.NewReader(c).ReadString('\n')
				lines <- strings.TrimSpace(l)
				_, _ = io.WriteString(c, "ok\n")
			}(conn)
		}
	}()

	wall := filepath.Join(home, "w.png")
	writeFile(t, wall, "wp")
	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.showWall(wall)

	d.stageSetEffect(stageEffectSubject)
	d.reconcileStage(d.stageForce.Swap(false), d.stageGen.Swap(false))

	if n := countCalls(logf, "cut"); n != 1 {
		t.Fatalf("cut called %d times, want exactly 1", n)
	}
	subj := stageSubjectOut(wall)
	if !isFile(subj) {
		t.Fatalf("subject.png not produced at %s", subj)
	}
	frame := d.buildStageFrame()
	if frame.Walls[wall].Effect != stageEffectSubject || frame.Walls[wall].Subject != subj {
		t.Fatalf("frame did not publish subject: %+v", frame.Walls[wall])
	}
	select {
	case got := <-lines:
		body, ok := strings.CutPrefix(got, "depth set ")
		if !ok || !strings.Contains(body, subj) {
			t.Fatalf("ryogami fold = %q, want `depth set` carrying %s", got, subj)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("subject was never folded to ryogami")
	}
}

// TestStageSetEffectParallax pins the parallax enable: it runs a cut then an
// inpaint and publishes both the subject and the recoloured background.
func TestStageSetEffectParallax(t *testing.T) {
	home := stageHome(t)
	logf := writeStageStub(t)

	wall := filepath.Join(home, "w.png")
	writeFile(t, wall, "wp")
	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.showWall(wall)

	d.stageSetEffect(stageEffectParallax)
	d.reconcileStage(d.stageForce.Swap(false), d.stageGen.Swap(false))

	if n := countCalls(logf, "cut"); n != 1 {
		t.Fatalf("cut called %d times, want 1", n)
	}
	if n := countCalls(logf, "inpaint"); n != 1 {
		t.Fatalf("inpaint called %d times, want 1", n)
	}
	subj := stageSubjectOut(wall)
	bg := stageBackgroundOut(wall)
	if !isFile(subj) || !isFile(bg) {
		t.Fatalf("subject=%v background=%v, want both", isFile(subj), isFile(bg))
	}
	w := d.buildStageFrame().Walls[wall]
	if w.Effect != stageEffectParallax || w.Subject != subj || w.Background != bg {
		t.Fatalf("frame did not publish parallax artifacts: %+v", w)
	}
}

// TestStageCancelSignalsChild pins cancellation: a cut in flight is killed at
// its real child PID, so the reconcile returns and no subject is written.
func TestStageCancelSignalsChild(t *testing.T) {
	home := stageHome(t)
	writeStageStub(t)
	t.Setenv("STAGE_STUB_SLEEP", "5")

	wall := filepath.Join(home, "w.png")
	writeFile(t, wall, "wp")
	reg := stageWalls{Walls: map[string]stageWall{wall: {Effect: stageEffectSubject}}}
	if err := saveStageWalls(reg); err != nil {
		t.Fatal(err)
	}

	d := &daemon{stageSig: make(chan struct{}, 1)}
	d.showWall(wall)

	done := make(chan struct{})
	go func() {
		defer close(done)
		d.reconcileStage(false, true) // gen: runs the (sleeping) cut
	}()

	// Wait for the child to come up, then cancel it.
	deadline := time.Now().Add(4 * time.Second)
	for stageCutPID.Load() == 0 {
		if time.Now().After(deadline) {
			t.Fatal("cut child never started")
		}
		time.Sleep(10 * time.Millisecond)
	}
	stageCancel()

	select {
	case <-done:
	case <-time.After(4 * time.Second):
		t.Fatal("reconcile did not return after cancel")
	}
	if stageCutPID.Load() != 0 {
		t.Fatalf("cut PID not cleared after cancel: %d", stageCutPID.Load())
	}
	if isFile(stageSubjectOut(wall)) {
		t.Fatal("a cancelled cut still produced a subject")
	}
}

// TestStageQualityTiers pins the tier -> model+matting contract the engine
// calls depend on.
func TestStageQualityTiers(t *testing.T) {
	cases := []struct {
		tier    string
		model   string
		matting bool
	}{
		{"draft", "u2netp", false},
		{"standard", "u2netp", true},
		{"fine", "birefnet-general-lite", true},
		{"", "u2netp", false}, // unknown falls back to draft
	}
	for _, tc := range cases {
		got := stageQualityFor(tc.tier)
		if got.model != tc.model || got.matting != tc.matting {
			t.Errorf("stageQualityFor(%q) = %+v, want {%s %v}", tc.tier, got, tc.model, tc.matting)
		}
	}
}

// TestStageEngineBinSeam pins the resolution order: the RYOKU_STAGE_ENGINE seam
// wins, and a bad RYOKU_SHELL_DIR falls back to the PATH name.
func TestStageEngineBinSeam(t *testing.T) {
	t.Setenv("RYOKU_STAGE_ENGINE", "/opt/ryostage")
	if got := stageEngineBin(); got != "/opt/ryostage" {
		t.Fatalf("engine bin = %q, want the RYOKU_STAGE_ENGINE seam", got)
	}
	t.Setenv("RYOKU_STAGE_ENGINE", "")
	t.Setenv("RYOKU_SHELL_DIR", "/dev/null")
	if got := stageEngineBin(); got != "ryostage" {
		t.Fatalf("engine bin with bad RYOKU_SHELL_DIR = %q, want ryostage", got)
	}
}

// TestStageManualLayers pins the manual-layer naming and ordering contract.
func TestStageManualLayers(t *testing.T) {
	home := stageHome(t)
	wall := filepath.Join(home, "w.png")
	dir := stageWallDir(wall)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"layer-03.png", "layer-01.png", "layer-02.png", "subject.png", "notes.txt", "layer-1.png"} {
		writeFile(t, filepath.Join(dir, name), name)
	}
	layers := manualLayers(wall)
	if len(layers) != 3 {
		t.Fatalf("manual layers = %d, want 3 (subject.png and single-digit excluded)", len(layers))
	}
	wantLabel := []string{"Layer 1", "Layer 2", "Layer 3"}
	wantSuffix := []string{"layer-01.png", "layer-02.png", "layer-03.png"}
	for i, l := range layers {
		if l["label"] != wantLabel[i] {
			t.Errorf("layer[%d] label = %v, want %q", i, l["label"], wantLabel[i])
		}
		if out, _ := l["out"].(string); !strings.HasSuffix(out, wantSuffix[i]) {
			t.Errorf("layer[%d] out = %v, want suffix %q", i, l["out"], wantSuffix[i])
		}
	}
}

// TestStageMigration pins the one-time fold: old depth-walls + Pictures/Depth +
// parallax layers.pz + Pictures/Parallax + depth.json + parallax.json land as
// the new registry, artifact tree and stage.json with the user's values intact
// and the marker written; a second start is a no-op.
func TestStageMigration(t *testing.T) {
	home := stageHome(t)
	if err := os.MkdirAll(filepath.Join(stateDir(), "ryoku"), 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(cfg, 0o755); err != nil {
		t.Fatal(err)
	}

	wpA := filepath.Join(home, "walls", "a.png") // depth-only
	wpB := filepath.Join(home, "walls", "b.png") // parallax auto
	if err := os.MkdirAll(filepath.Dir(wpA), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, wpA, "A")
	writeFile(t, wpB, "B")

	// Old depth-walls.json (per-wall opt-in) + its cutout.
	writeFile(t, legacyDepthWallsPath(), `{"current":true,"walls":{"`+wpA+`":true}}`)
	depthPNG := filepath.Join(legacyDepthDir(), "a-depth.png")
	if err := os.MkdirAll(filepath.Dir(depthPNG), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, depthPNG, "OLDCUT")

	// Old parallax layers.pz (per-wall scene/layers) + its folder.
	pbDir := filepath.Join(legacyParallaxDir(), "b")
	if err := os.MkdirAll(pbDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(pbDir, "layer-01.png"), "OLDSUBJECT")
	writeFile(t, filepath.Join(pbDir, "layer-02.png"), "OLDLAYER2")
	writeFile(t, filepath.Join(pbDir, "background.png"), "OLDBG")
	lp := legacyParallaxWalls{
		Walls: map[string]legacyParallaxWall{
			wpB: {Enabled: true, Mode: "auto", Scene: []string{"wallpaper", "layer:1"}},
		},
		Layers: map[string][]legacyParallaxLayer{
			wpB: {
				{Out: filepath.Join(pbDir, "layer-01.png"), Rev: 1, Label: "subject", Depth: 0.5},
				{Out: filepath.Join(pbDir, "layer-02.png"), Rev: 2, Label: "Layer 2"},
			},
		},
	}
	lpBytes, _ := json.Marshal(lp)
	writeFile(t, legacyLayersPath(), string(lpBytes))

	// Old settings: parallax's model+matting must win the derived quality, and a
	// user's `front` from depth.json must survive.
	writeFile(t, filepath.Join(cfg, "depth.json"), `{"model":"u2netp","alphaMatting":false,"front":["clock"]}`)
	writeFile(t, filepath.Join(cfg, "parallax.json"), `{"mode":"auto","model":"birefnet-general-lite","alphaMatting":true}`)

	migrateStage()

	// Registry.
	reg := loadStageWalls()
	if reg.Walls[wpA].Effect != stageEffectSubject {
		t.Fatalf("wpA effect = %v, want subject", reg.Walls[wpA].Effect)
	}
	b := reg.Walls[wpB]
	if b.Effect != stageEffectParallax || b.Mode != stageModeAuto {
		t.Fatalf("wpB effect/mode = %v/%v, want parallax/auto", b.Effect, b.Mode)
	}
	if len(b.Scene) != 2 || b.Scene[1] != "layer:1" {
		t.Fatalf("wpB scene = %v", b.Scene)
	}
	if len(b.Layers) != 2 {
		t.Fatalf("wpB layers = %d, want 2", len(b.Layers))
	}
	if out, _ := b.Layers[0]["out"].(string); !strings.HasSuffix(out, filepath.Join("Stage", "b", "subject.png")) {
		t.Fatalf("wpB layer[0] out = %v, want the rewritten subject.png", b.Layers[0]["out"])
	}
	if out, _ := b.Layers[1]["out"].(string); !strings.HasSuffix(out, filepath.Join("Stage", "b", "layer-02.png")) {
		t.Fatalf("wpB layer[1] out = %v", b.Layers[1]["out"])
	}

	// Artifact tree: renamed, sources gone.
	if !isFile(stageSubjectOut(wpA)) {
		t.Fatal("depth cutout did not become Stage/a/subject.png")
	}
	if isFile(depthPNG) {
		t.Fatal("old depth cutout was copied, not moved")
	}
	if !isFile(stageSubjectOut(wpB)) || !isFile(stageBackgroundOut(wpB)) ||
		!isFile(filepath.Join(stageWallDir(wpB), "layer-02.png")) {
		t.Fatal("parallax folder did not move whole into Stage/b/")
	}
	if isDir(pbDir) {
		t.Fatal("old parallax folder was copied, not moved")
	}

	// Settings fold: user's quality (fine) and front carried; defaults present.
	sb, err := os.ReadFile(filepath.Join(cfg, "stage.json"))
	if err != nil {
		t.Fatalf("stage.json not written: %v", err)
	}
	var settings map[string]any
	if err := json.Unmarshal(sb, &settings); err != nil {
		t.Fatal(err)
	}
	if settings["quality"] != "fine" {
		t.Fatalf("quality = %v, want fine (parallax birefnet+matting)", settings["quality"])
	}
	front, _ := settings["front"].([]any)
	if len(front) != 1 || front[0] != "clock" {
		t.Fatalf("front = %v, want [clock] carried from depth.json", settings["front"])
	}
	if _, ok := settings["feather"]; !ok {
		t.Fatal("stage.json missing a defaulted key (feather)")
	}

	// Marker written; a second start is a no-op.
	if !isFile(stageMigrationMarker()) {
		t.Fatal("migration marker not written")
	}
	before, _ := os.ReadFile(stageWallsPath())
	migrateStage()
	after, _ := os.ReadFile(stageWallsPath())
	if string(before) != string(after) {
		t.Fatal("second migration mutated the registry (not a no-op)")
	}
}

// TestStageRyogamiFrameWake pins the bridge trigger after the depth/parallax
// merge: a frame showing a new wallpaper, one that lost its subject fold, or a
// live claim wakes the unified stage worker, while the frame our own publish
// produces (same sources, subject folded) stays quiet, so the publish-subscribe
// loop settles.
func TestStageRyogamiFrameWake(t *testing.T) {
	d := &daemon{stageSig: make(chan struct{}, 1)}
	woke := func() bool {
		select {
		case <-d.stageSig:
			return true
		default:
			return false
		}
	}
	feed := func(js string) { d.consumeRyogamiFrames(strings.NewReader(js + "\n")) }

	feed(`{"default":{"path":"/w/a.png"},"outputs":{}}`)
	if !woke() {
		t.Fatal("a new wallpaper did not wake the stage worker")
	}
	feed(`{"default":{"path":"/w/a.png","depth":"/d/a-subject.png"},"outputs":{}}`)
	if woke() {
		t.Fatal("our own subject fold woke the worker again")
	}
	feed(`{"default":{"path":"/w/a.png"},"outputs":{}}`)
	if !woke() {
		t.Fatal("a re-set that dropped the subject fold did not wake the worker")
	}
	feed(`{"default":{"path":"/w/a.png","live":true},"outputs":{}}`)
	if !woke() {
		t.Fatal("a live claim did not wake the worker")
	}
}

// parallax.json keeps feather/lift/shadow per layer (arrays); depth.json keeps
// the scalars. The fold must take the scalar and the higher quality tier.
func TestStageMigrationSettingsKinds(t *testing.T) {
	home := stageHome(t)
	cfg := filepath.Join(home, ".config", "ryoku")
	if err := os.MkdirAll(cfg, 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(cfg, "parallax.json"), []byte(`{"feather":[0],"lift":[0],"shadow":[0],"shadowAngle":[331],"model":"u2netp"}`), 0o644)
	os.WriteFile(filepath.Join(cfg, "depth.json"), []byte(`{"feather":0.15,"lift":1,"shadow":0.85,"model":"birefnet-general-lite","alphaMatting":true}`), 0o644)
	migrateStageSettings()
	b, err := os.ReadFile(filepath.Join(cfg, "stage.json"))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	if got["shadow"] != 0.85 || got["feather"] != 0.15 || got["quality"] != "fine" {
		t.Fatalf("stage.json = %s", b)
	}
	if _, isList := got["shadowAngle"].([]any); isList {
		t.Fatalf("shadowAngle folded as a list: %s", b)
	}
}
