package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

// Ryostage (docs/stage.md): the desktop as a stage. One worker, one registry,
// one topic, replacing the old depth and parallax workers. "Subject in front"
// is a stage with a single still layer above the widgets; "Parallax" is the
// same stage with the subject and layers drifting and a recoloured backdrop
// behind them. Both effects share the ryostage cut-out engine, the per-wall
// registry, and the artifact tree under ~/Pictures/Stage. Generation is slow,
// so it runs on a coalescing worker off the wallpaper hot path; the finished
// subject is folded into ryogami's wallpaper frame under the unchanged `depth`
// wire for pixel-lock, and the full editor state rides the `stage` topic QML
// renders from.

type stageEffect string

const (
	stageEffectOff      stageEffect = "off"
	stageEffectSubject  stageEffect = "subject"
	stageEffectParallax stageEffect = "parallax"
)

type stageMode string

const (
	stageModeAuto   stageMode = "auto"
	stageModeManual stageMode = "manual"
)

// stageLayer is one entry in a wall's layer list. The daemon owns only the
// identity keys (`out`, `rev`, `label`), refreshed from the filesystem on every
// reconcile; every other key is an opaque per-layer knob the QML renderer owns
// and the daemon round-trips verbatim (motion, idle animation, audio, offsets,
// null=inherit look overrides). A map keeps that passthrough honest without the
// daemon pinning a schema it does not define.
type stageLayer = map[string]any

// stageWall is a wallpaper's persisted scene: which effect is on, the parallax
// mode, the cast order (scene), and the layer list with its knobs. Per-wall,
// because a cut belongs to one image and a user's arrangement belongs to it.
type stageWall struct {
	Effect stageEffect  `json:"effect"`
	Mode   stageMode    `json:"mode,omitempty"`
	Scene  []string     `json:"scene,omitempty"`
	Layers []stageLayer `json:"layers,omitempty"`
}

// stageWalls is the daemon-owned registry at ~/.local/state/ryoku/stage-walls.json.
// `current` mirrors the wallpaper on screen now so the shell can key its lookup.
type stageWalls struct {
	Current string               `json:"current"`
	Walls   map[string]stageWall `json:"walls"`
}

// stageIndex records what produced a wall's subject.png, so a returning
// wallpaper reuses its cut instantly (mtime) while a quality change re-cuts.
type stageIndex struct {
	Source  string `json:"source"`
	Model   string `json:"model"`
	Matting bool   `json:"matting"`
}

// stageQuality is the model+matting pair a quality tier resolves to.
type stageQuality struct {
	model   string
	matting bool
}

type stageTarget struct {
	slot   string
	source string
}

// stageWallFrame and stageFrame are the `stage` topic shape QML binds to
// (per-wallpaper keyed so each monitor reads its own entry). busy/stage/percent
// are global to the single worker; everything else is per wall.
type stageWallFrame struct {
	Effect     stageEffect  `json:"effect"`
	Mode       stageMode    `json:"mode"`
	Subject    string       `json:"subject"`
	Background string       `json:"background"`
	Rev        int64        `json:"rev"`
	Scene      []string     `json:"scene"`
	Layers     []stageLayer `json:"layers"`
}

type stageFrame struct {
	Current string                    `json:"current"`
	Busy    bool                      `json:"busy"`
	Stage   string                    `json:"stage"`
	Percent int                       `json:"percent"`
	Walls   map[string]stageWallFrame `json:"walls"`
}

var manualLayerRe = regexp.MustCompile(`^layer-(\d{2,})\.png$`)

// stageCutPID holds the running engine child's real PID (not the daemon's) so
// `stage cancel` can signal its process group; reset to 0 once it exits.
var stageCutPID atomic.Int32

func logStage(what string, err error) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "stage: %s: %v\n", what, err)
		return
	}
	fmt.Fprintf(os.Stderr, "stage: %s\n", what)
}

// --- paths -----------------------------------------------------------------

func stageWallsPath() string { return filepath.Join(stateDir(), "ryoku", "stage-walls.json") }
func stageDir() string       { return filepath.Join(os.Getenv("HOME"), "Pictures", "Stage") }

func stageStem(source string) string {
	base := filepath.Base(source)
	return strings.TrimSuffix(base, filepath.Ext(base))
}

func stageWallDir(source string) string    { return filepath.Join(stageDir(), stageStem(source)) }
func stageSubjectOut(source string) string { return filepath.Join(stageWallDir(source), "subject.png") }
func stageBackgroundOut(source string) string {
	return filepath.Join(stageWallDir(source), "background.png")
}
func stageIndexPath(source string) string { return filepath.Join(stageWallDir(source), ".index.json") }
func stageProgressPath() string           { return filepath.Join(stateDir(), "ryoku", "stage", "progress") }

// --- shared fs helpers (previously in depth.go/parallax.go) ----------------

func fileModTime(p string) int64 {
	if st, err := os.Stat(p); err == nil {
		return st.ModTime().Unix()
	}
	return 0
}

func isDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

// writeJSONFileAtomic writes v as indented JSON via a temp file + rename in the
// same directory, so a crash never leaves a half-written registry or settings.
func writeJSONFileAtomic(path string, v any) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".stage-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Chmod(tmpName, 0o644); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		os.Remove(tmpName)
		return err
	}
	return nil
}

// --- registry --------------------------------------------------------------

func loadStageWalls() stageWalls {
	var w stageWalls
	if b, err := os.ReadFile(stageWallsPath()); err == nil {
		_ = json.Unmarshal(b, &w)
	}
	// Normalize after any read or decode failure so callers can assign into the
	// map without a nil-map panic.
	if w.Walls == nil {
		w.Walls = map[string]stageWall{}
	}
	return w
}

func saveStageWalls(w stageWalls) error {
	if w.Walls == nil {
		w.Walls = map[string]stageWall{}
	}
	return writeJSONFileAtomic(stageWallsPath(), w)
}

func loadStageIndex(source string) stageIndex {
	var idx stageIndex
	if b, err := os.ReadFile(stageIndexPath(source)); err == nil {
		_ = json.Unmarshal(b, &idx)
	}
	return idx
}

func saveStageIndex(source string, idx stageIndex) {
	if err := writeJSONFileAtomic(stageIndexPath(source), idx); err != nil {
		logStage("save index", err)
	}
}

// --- settings --------------------------------------------------------------

// stageConfig reads the shell-owned quality tier from stage.json and resolves it
// to the model + matting pair. Whether an effect is on for a wallpaper is the
// per-wall registry, not this file.
func stageConfig() stageQuality {
	def := stageQualityFor("draft")
	dir := ryokuConfigDir()
	if dir == "" {
		return def
	}
	b, err := os.ReadFile(filepath.Join(dir, "stage.json"))
	if err != nil {
		return def
	}
	var m struct {
		Quality string `json:"quality"`
	}
	if json.Unmarshal(b, &m) != nil {
		return def
	}
	return stageQualityFor(m.Quality)
}

// stageQualityFor maps a quality tier to the engine model + matting pair:
// draft -> u2netp, standard -> u2netp + matting, fine -> birefnet + matting.
func stageQualityFor(tier string) stageQuality {
	switch tier {
	case "standard":
		return stageQuality{model: "u2netp", matting: true}
	case "fine":
		return stageQuality{model: "birefnet-general-lite", matting: true}
	default:
		return stageQuality{model: "u2netp", matting: false}
	}
}

// --- engine ----------------------------------------------------------------

// stageEngineBin resolves the ryostage helper. RYOKU_STAGE_ENGINE is the test /
// out-of-tree seam; a dev run reaches it under RYOKU_SHELL_DIR; otherwise it is
// on PATH once packaged.
func stageEngineBin() string {
	if bin := os.Getenv("RYOKU_STAGE_ENGINE"); bin != "" {
		return bin
	}
	if dir := os.Getenv("RYOKU_SHELL_DIR"); dir != "" {
		p := filepath.Join(dir, "scripts", "ryostage")
		if isFile(p) {
			return p
		}
	}
	return "ryostage"
}

// stageEngineAvailable probes the runtime on a deadline: a hung helper must
// never wedge the worker.
func stageEngineAvailable() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, stageEngineBin(), "check").Run() == nil
}

// stageModelsJSON passes the curated catalogue through to the shell.
func stageModelsJSON() string {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, stageEngineBin(), "models", "--json").Output()
	if err != nil {
		return "err stage models: " + err.Error()
	}
	return strings.TrimSpace(string(out))
}

// runEngine runs one engine subcommand bounded and cancellable. The child is its
// own process group so `stage cancel` (and a deadline) can signal the whole
// tree (bash + python), not just the leader. stderr is drained so a chatty
// helper cannot block on a full pipe.
func (d *daemon) runEngine(timeout time.Duration, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, stageEngineBin(), args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return err
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = io.Copy(io.Discard, stderr)
	}()
	if err := cmd.Start(); err != nil {
		return err
	}
	stageCutPID.Store(int32(cmd.Process.Pid))
	werr := cmd.Wait()
	stageCutPID.Store(0)
	<-done
	return werr
}

// stageCancel kills the running engine child's process group.
func stageCancel() {
	pid := int(stageCutPID.Load())
	if pid <= 0 {
		return
	}
	_ = syscall.Kill(-pid, syscall.SIGKILL)
}

// --- progress --------------------------------------------------------------

func resetStageProgress() {
	p := stageProgressPath()
	_ = os.MkdirAll(filepath.Dir(p), 0o755)
	_ = os.WriteFile(p, nil, 0o644)
}

func writeStageProgress(rec map[string]any) {
	p := stageProgressPath()
	_ = os.MkdirAll(filepath.Dir(p), 0o755)
	b, err := json.Marshal(rec)
	if err != nil {
		return
	}
	f, err := os.OpenFile(p, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.Write(append(b, '\n'))
}

func readLastStagePhase() string {
	b, err := os.ReadFile(stageProgressPath())
	if err != nil {
		return ""
	}
	phase := ""
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || !strings.HasPrefix(line, "{") {
			continue
		}
		var rec map[string]any
		if json.Unmarshal([]byte(line), &rec) != nil {
			continue
		}
		if p, ok := rec["phase"].(string); ok {
			phase = p
		}
	}
	return phase
}

// --- reuse rules -----------------------------------------------------------

// subjectFresh reports whether a generated artifact is no older than its source,
// so a returning wallpaper reuses it but an edited image regenerates.
func subjectFresh(source, out string) bool {
	ot := fileModTime(out)
	return ot > 0 && ot >= fileModTime(source)
}

func backgroundFresh(source, out string) bool { return subjectFresh(source, out) }

// subjectMatches is the stricter generate-time check: fresh AND cut with the
// requested model+matting, so an enable skips a redundant re-cut.
func (d *daemon) subjectMatches(source, out string, q stageQuality) bool {
	if !subjectFresh(source, out) {
		return false
	}
	idx := loadStageIndex(source)
	return idx.Source == source && idx.Model == q.model && idx.Matting == q.matting
}

// --- layers ----------------------------------------------------------------

func newSubjectLayer(out string) stageLayer {
	return stageLayer{"out": out, "rev": fileModTime(out), "label": "Subject"}
}

// manualLayers lists the user-placed layer-NN.png in a wall's folder, ordered.
func manualLayers(source string) []stageLayer {
	dir := stageWallDir(source)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	type found struct {
		idx   int
		layer stageLayer
	}
	var fs []found
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		m := manualLayerRe.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		var idx int
		_, _ = fmt.Sscanf(m[1], "%d", &idx)
		out := filepath.Join(dir, e.Name())
		fs = append(fs, found{idx, stageLayer{"out": out, "rev": fileModTime(out), "label": fmt.Sprintf("Layer %d", idx)}})
	}
	sort.Slice(fs, func(i, j int) bool { return fs[i].idx < fs[j].idx })
	out := make([]stageLayer, 0, len(fs))
	for _, f := range fs {
		out = append(out, f.layer)
	}
	return out
}

// mergeLayerKnobs carries the user's per-layer knobs (everything but the
// identity keys) forward from the previous registry entry onto the freshly
// derived layer list, matched by output path, so a reconcile never drops a
// knob the user set.
func mergeLayerKnobs(prev, next []stageLayer) []stageLayer {
	byOut := map[string]stageLayer{}
	for _, p := range prev {
		if out, _ := p["out"].(string); out != "" {
			byOut[out] = p
		}
	}
	for _, n := range next {
		out, _ := n["out"].(string)
		p, ok := byOut[out]
		if !ok {
			continue
		}
		for k, v := range p {
			if k == "out" || k == "rev" || k == "label" {
				continue
			}
			n[k] = v
		}
	}
	return next
}

// --- worker ----------------------------------------------------------------

func (d *daemon) scheduleStage() {
	select {
	case d.stageSig <- struct{}{}:
	default:
	}
}

func (d *daemon) stageWorker() {
	for range d.stageSig {
		d.reconcileStage(d.stageForce.Swap(false), d.stageGen.Swap(false))
	}
}

// stageTargets are the still wallpapers on screen (default + per-output),
// skipping videos and live-claimed slots, each paired with its ryogami slot.
func (d *daemon) stageTargets() []stageTarget {
	f := d.wallFrame()
	var out []stageTarget
	if p := f.Default.Path; p != "" && !f.Default.Live && !f.Default.Video && !isVideo(p) && isFile(p) {
		out = append(out, stageTarget{"", p})
	}
	for name, e := range f.Outputs {
		if e.Path != "" && !e.Live && !e.Video && !isVideo(e.Path) && isFile(e.Path) {
			out = append(out, stageTarget{name, e.Path})
		}
	}
	return out
}

// reconcileStage resolves every on-screen wallpaper's stage from the registry.
// A plain wake (neither force nor gen) reuses artifacts and never runs the
// engine, so a switch reuses a stage instantly but never auto-generates; gen
// (an enable) reuses when present and only generates when missing; force (a
// quality change, refresh, or manual re-cut) regenerates. The finished subject
// is folded to ryogami under the `depth` wire for the subject effect only;
// parallax renders from the topic. A failure leaves the effect off with a
// logged reason and is never fatal.
func (d *daemon) reconcileStage(force, gen bool) {
	wall := d.currentWall()
	reg := loadStageWalls()
	if reg.Current != wall {
		reg.Current = wall
		if err := saveStageWalls(reg); err != nil {
			logStage("save current", err)
		}
	}
	// Only probe the engine when generation is actually possible, so a plain
	// switch makes zero engine calls.
	available := false
	if force || gen {
		available = stageEngineAvailable()
	}
	q := stageConfig()
	dirty := false
	subjectPublished := false
	for _, t := range d.stageTargets() {
		e := reg.Walls[t.source]
		effect := e.Effect
		if effect == "" || effect == stageEffectOff {
			continue
		}
		mode := e.Mode
		if mode == "" {
			mode = stageModeAuto
		}
		prevBytes, _ := json.Marshal(e)
		subjectExists, layers := d.ensureArtifacts(t.source, effect, mode, q, force, gen, available)
		e.Mode = mode
		e.Layers = mergeLayerKnobs(e.Layers, layers)
		reg.Walls[t.source] = e
		if newBytes, _ := json.Marshal(e); !bytes.Equal(prevBytes, newBytes) {
			dirty = true
		}
		if effect == stageEffectSubject && subjectExists {
			d.depthPublish(t.slot, t.source, stageSubjectOut(t.source))
			subjectPublished = true
		}
	}
	// No subject folded anywhere: clear the wallpaper-frame overlay (a switch to
	// a parallax/off wall must not leave a stale static subject behind).
	if !subjectPublished {
		d.depthClear()
	}
	if dirty {
		if err := saveStageWalls(reg); err != nil {
			logStage("save walls", err)
		}
	}
	d.stageBusy.Store(false)
	d.publishStage()
}

// ensureArtifacts brings one wall's artifacts in line with its effect and mode,
// running the engine only when a generation is warranted and the runtime is
// available, and returns whether a fresh subject exists plus the derived layer
// list. A cut failure returns no subject and is logged, never fatal.
func (d *daemon) ensureArtifacts(source string, effect stageEffect, mode stageMode, q stageQuality, force, gen, available bool) (bool, []stageLayer) {
	subj := stageSubjectOut(source)
	bg := stageBackgroundOut(source)
	layers := []stageLayer{}
	subjectExists := false
	didCut := false

	needSubject := effect == stageEffectSubject || (effect == stageEffectParallax && mode == stageModeAuto)
	if needSubject {
		if (force || (gen && !d.subjectMatches(source, subj, q))) && available {
			if err := d.runCut(source, subj, q); err != nil {
				logStage("cut "+stageStem(source), err)
				return false, layers
			}
			saveStageIndex(source, stageIndex{Source: source, Model: q.model, Matting: q.matting})
			subjectExists, didCut = true, true
		} else {
			subjectExists = subjectFresh(source, subj)
		}
	}

	switch effect {
	case stageEffectSubject:
		if subjectExists {
			layers = []stageLayer{newSubjectLayer(subj)}
		}
	case stageEffectParallax:
		if mode == stageModeManual {
			layers = manualLayers(source)
		} else {
			if subjectExists {
				if (didCut || force || (gen && !backgroundFresh(source, bg))) && available {
					if !didCut {
						resetStageProgress()
					}
					if err := d.runInpaint(source, subj, bg); err != nil {
						// Inpaint failing is non-fatal: the subject still
						// drifts over the original wallpaper; the daemon logs
						// and the surface falls back to no recoloured backdrop.
						logStage("inpaint "+stageStem(source), err)
					}
				}
				layers = append(layers, newSubjectLayer(subj))
			}
			layers = append(layers, manualLayers(source)...)
		}
	}

	if didCut {
		writeStageProgress(map[string]any{"phase": "done"})
	}
	if layers == nil {
		layers = []stageLayer{}
	}
	return subjectExists, layers
}

// runCut writes the wallpaper's subject as an alpha-matted PNG. The progress log
// is truncated per run; busy is set for the topic and cleared by reconcileStage.
func (d *daemon) runCut(source, out string, q stageQuality) error {
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	resetStageProgress()
	d.stageBusy.Store(true)
	writeStageProgress(map[string]any{"phase": "cut", "model": q.model})
	d.publishStage()
	args := []string{"cut", source, out, "--model", q.model}
	if q.matting {
		args = append(args, "--matting")
	}
	if err := d.runEngine(5*time.Minute, args...); err != nil {
		writeStageProgress(map[string]any{"phase": "error", "error": err.Error()})
		return err
	}
	if !isFile(out) {
		writeStageProgress(map[string]any{"phase": "error", "error": "subject png missing"})
		return fmt.Errorf("subject png missing")
	}
	return nil
}

// runInpaint fills the subject's hole with the surrounding colour (the parallax
// backdrop).
func (d *daemon) runInpaint(source, subj, bg string) error {
	d.stageBusy.Store(true)
	writeStageProgress(map[string]any{"phase": "inpaint"})
	d.publishStage()
	if err := d.runEngine(2*time.Minute, "inpaint", source, subj, bg); err != nil {
		writeStageProgress(map[string]any{"phase": "error", "error": err.Error(), "warning": "inpaint failed"})
		return err
	}
	return nil
}

// --- topic -----------------------------------------------------------------

// buildStageFrame assembles the `stage` topic frame: one entry per on-screen
// wallpaper (plus the current), keyed by path, so each monitor reads its own.
func (d *daemon) buildStageFrame() stageFrame {
	reg := loadStageWalls()
	cur := d.currentWall()
	busy := d.stageBusy.Load()
	stageStr, percent := "", 0
	if busy {
		switch readLastStagePhase() {
		case "cut":
			stageStr, percent = "cut", 40
		case "inpaint":
			stageStr, percent = "inpaint", 80
		default:
			stageStr, percent = "", 5
		}
	}
	paths := map[string]bool{}
	if cur != "" {
		paths[cur] = true
	}
	for _, t := range d.stageTargets() {
		paths[t.source] = true
	}
	walls := map[string]stageWallFrame{}
	for p := range paths {
		e := reg.Walls[p]
		effect := e.Effect
		if effect == "" {
			effect = stageEffectOff
		}
		mode := e.Mode
		if mode == "" {
			mode = stageModeAuto
		}
		wf := stageWallFrame{
			Effect: effect,
			Mode:   mode,
			Scene:  e.Scene,
			Layers: e.Layers,
		}
		if wf.Scene == nil {
			wf.Scene = []string{}
		}
		if wf.Layers == nil {
			wf.Layers = []stageLayer{}
		}
		if effect != stageEffectOff {
			if subj := stageSubjectOut(p); subjectFresh(p, subj) {
				wf.Subject = subj
				wf.Rev = fileModTime(subj)
			}
			if effect == stageEffectParallax {
				if bg := stageBackgroundOut(p); isFile(bg) {
					wf.Background = bg
					if r := fileModTime(bg); r > wf.Rev {
						wf.Rev = r
					}
				}
			}
		}
		walls[p] = wf
	}
	return stageFrame{Current: cur, Busy: busy, Stage: stageStr, Percent: percent, Walls: walls}
}

func (d *daemon) publishStage() {
	t := d.topic("stage")
	if t == nil {
		return
	}
	if b, err := json.Marshal(d.buildStageFrame()); err == nil {
		t.publish(b)
	}
}

func (d *daemon) stageStatusJSON() string {
	b, _ := json.Marshal(d.buildStageFrame())
	return string(b)
}

// --- verbs -----------------------------------------------------------------

// restField recovers a trailing argument that may contain spaces from the raw
// command line, splitting into exactly n fields (like the old parallax case).
func restField(line string, n int) string {
	parts := strings.SplitN(line, " ", n)
	if len(parts) == n {
		return parts[n-1]
	}
	return ""
}

// stageSetEffect records the three-way effect for the current wallpaper and
// schedules a reconcile. Enabling reuses a saved cut when one exists and only
// generates when missing, so turning an effect on is instant; off clears the
// overlay. The write is synchronous so the shell's control reflects at once.
func (d *daemon) stageSetEffect(eff stageEffect) {
	wall := d.currentWall()
	if wall == "" {
		return
	}
	reg := loadStageWalls()
	e := reg.Walls[wall]
	e.Effect = eff
	if eff == stageEffectParallax && e.Mode == "" {
		e.Mode = stageModeAuto
	}
	if eff == stageEffectOff {
		// Keep the wall's arrangement (scene, manual-layer files) for a later
		// re-enable; only the derived layer list drops.
		e.Layers = nil
	}
	reg.Walls[wall] = e
	reg.Current = wall
	if err := saveStageWalls(reg); err != nil {
		logStage("set-effect save", err)
	}
	if eff == stageEffectOff {
		d.depthClear()
		d.publishStage()
		return
	}
	d.stageGen.Store(true)
	d.scheduleStage()
	d.publishStage()
}

// stageSetMode switches the parallax mode (and turns parallax on, as the mode is
// meaningless otherwise), reusing or generating as an enable does.
func (d *daemon) stageSetMode(m stageMode) {
	wall := d.currentWall()
	if wall == "" {
		return
	}
	reg := loadStageWalls()
	e := reg.Walls[wall]
	e.Mode = m
	if e.Effect != stageEffectParallax {
		e.Effect = stageEffectParallax
	}
	reg.Walls[wall] = e
	reg.Current = wall
	if err := saveStageWalls(reg); err != nil {
		logStage("set-mode save", err)
	}
	d.stageGen.Store(true)
	d.scheduleStage()
	d.publishStage()
}

// stageSetScene stores the per-wall cast order (which widgets and the visualizer
// sit in front of or behind each layer). It is z-order metadata, so it never
// runs the engine.
func (d *daemon) stageSetScene(body string) {
	wall := d.currentWall()
	if wall == "" {
		return
	}
	var scene []string
	if err := json.Unmarshal([]byte(body), &scene); err != nil {
		logStage("set-scene decode", err)
		return
	}
	reg := loadStageWalls()
	e := reg.Walls[wall]
	e.Scene = scene
	reg.Walls[wall] = e
	reg.Current = wall
	if err := saveStageWalls(reg); err != nil {
		logStage("set-scene save", err)
	}
	d.publishStage()
}

// stageSetLayer merges a partial knob object into one layer (0-based). The
// daemon protects the identity keys out/rev and stores everything else verbatim.
func (d *daemon) stageSetLayer(indexArg, body string) error {
	wall := d.currentWall()
	if wall == "" {
		return fmt.Errorf("no active wallpaper")
	}
	index, err := strconv.Atoi(indexArg)
	if err != nil {
		return fmt.Errorf("bad index: %s", indexArg)
	}
	var knobs map[string]any
	if err := json.Unmarshal([]byte(body), &knobs); err != nil {
		return err
	}
	reg := loadStageWalls()
	e := reg.Walls[wall]
	if index < 0 || index >= len(e.Layers) {
		return fmt.Errorf("layer index out of range: %d", index)
	}
	layer := e.Layers[index]
	if layer == nil {
		layer = stageLayer{}
	}
	for k, v := range knobs {
		if k == "out" || k == "rev" {
			continue
		}
		layer[k] = v
	}
	e.Layers[index] = layer
	reg.Walls[wall] = e
	reg.Current = wall
	if err := saveStageWalls(reg); err != nil {
		return err
	}
	d.publishStage()
	return nil
}

// stageAddLayer copies a source image into the wall's folder as the next
// numbered manual layer and re-derives; no re-cut of the auto subject.
func (d *daemon) stageAddLayer(src string) (string, error) {
	wall := d.currentWall()
	if wall == "" {
		return "", fmt.Errorf("no active wallpaper")
	}
	if src == "" {
		return "", fmt.Errorf("empty source path")
	}
	st, err := os.Stat(src)
	if err != nil || st.IsDir() {
		return "", fmt.Errorf("source not a file: %s", src)
	}
	dir := stageWallDir(wall)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	next := 1
	if entries, err := os.ReadDir(dir); err == nil {
		for _, e := range entries {
			m := manualLayerRe.FindStringSubmatch(e.Name())
			if m == nil {
				continue
			}
			var idx int
			_, _ = fmt.Sscanf(m[1], "%d", &idx)
			if idx >= next {
				next = idx + 1
			}
		}
	}
	dst := filepath.Join(dir, fmt.Sprintf("layer-%02d.png", next))
	if err := copyFile(src, dst); err != nil {
		return "", err
	}
	d.scheduleStage()
	return dst, nil
}

// stageRemoveLayer deletes a manual layer, guarded to the wall's own folder.
func (d *daemon) stageRemoveLayer(path string) error {
	wall := d.currentWall()
	if wall == "" {
		return fmt.Errorf("no active wallpaper")
	}
	if path == "" {
		return fmt.Errorf("empty path")
	}
	dir := stageWallDir(wall)
	clean := filepath.Clean(path)
	if !strings.HasPrefix(clean, dir+string(filepath.Separator)) {
		return fmt.Errorf("not in wallpaper folder: %s", path)
	}
	if err := os.Remove(clean); err != nil {
		return err
	}
	d.scheduleStage()
	return nil
}

// stageClear removes the current wall's generated artifacts (subject, backdrop,
// index), keeping manual layers and the effect setting, then reconciles so the
// overlay clears and layers re-derive without regenerating.
func (d *daemon) stageClear() {
	if wall := d.currentWall(); wall != "" {
		dir := stageWallDir(wall)
		for _, n := range []string{"subject.png", "background.png", ".index.json"} {
			_ = os.Remove(filepath.Join(dir, n))
		}
	}
	d.scheduleStage()
}

// --- migration -------------------------------------------------------------

// Legacy on-disk formats read once at daemon start to fold Depth and Parallax
// into Ryostage. These mirror the retired depth.go / parallax.go structs.

type legacyDepthWalls struct {
	Walls map[string]bool `json:"walls"`
}

type legacyParallaxLayer struct {
	Out   string  `json:"out"`
	Rev   int64   `json:"rev"`
	Label string  `json:"label"`
	Depth float32 `json:"depth"`
	Area  float32 `json:"area"`
}

type legacyParallaxWall struct {
	Enabled bool     `json:"enabled"`
	Mode    string   `json:"mode"`
	Scene   []string `json:"scene"`
}

type legacyParallaxWalls struct {
	Walls  map[string]legacyParallaxWall    `json:"walls"`
	Layers map[string][]legacyParallaxLayer `json:"layers"`
}

func legacyDepthWallsPath() string { return filepath.Join(stateDir(), "ryoku", "depth-walls.json") }
func legacyDepthDir() string       { return filepath.Join(os.Getenv("HOME"), "Pictures", "Depth") }
func legacyParallaxDir() string    { return filepath.Join(os.Getenv("HOME"), "Pictures", "Parallax") }
func legacyLayersPath() string     { return filepath.Join(legacyParallaxDir(), "layers.pz") }
func stageMigrationMarker() string {
	return filepath.Join(stateDir(), "ryoku", "migrations", "ryostage")
}

// migrateStage folds the retired Depth and Parallax state into Ryostage once,
// gated by a marker. Registries fold into stage-walls.json, artifacts move (by
// rename, never copy) into ~/Pictures/Stage/<stem>/, and depth.json+parallax.json
// fold into stage.json. Every step leaves its source where it was and logs on
// failure; the marker is written only after the registry persists, so a failed
// run retries on the next start and a second start is a no-op.
func migrateStage() {
	marker := stageMigrationMarker()
	if isFile(marker) {
		return
	}
	reg := loadStageWalls()

	depthWalls := loadLegacyDepthWalls()
	for path, on := range depthWalls {
		if !on {
			continue
		}
		e := reg.Walls[path]
		if e.Effect == "" || e.Effect == stageEffectOff {
			e.Effect = stageEffectSubject
		}
		reg.Walls[path] = e
	}

	lp := loadLegacyParallaxWalls()
	for path, w := range lp.Walls {
		if !w.Enabled {
			continue
		}
		// Parallax is the richer effect; it wins for a wall enabled in both.
		e := reg.Walls[path]
		e.Effect = stageEffectParallax
		if w.Mode != "" {
			e.Mode = stageMode(w.Mode)
		}
		if len(w.Scene) > 0 {
			e.Scene = w.Scene
		}
		reg.Walls[path] = e
	}

	// Move the parallax folders whole first (they may create Stage/<stem>/),
	// then the depth PNGs into whatever folder now exists.
	for path, w := range lp.Walls {
		if !w.Enabled {
			continue
		}
		migrateParallaxFolder(path, w, lp.Layers[path], &reg)
	}
	for path, on := range depthWalls {
		if on {
			migrateDepthPNG(path)
		}
	}

	migrateStageSettings()

	if err := saveStageWalls(reg); err != nil {
		// Do not mark the migration done: the fold did not persist, so the next
		// start retries and the superseded sources stay where they are.
		logStage("migrate save walls", err)
		return
	}
	if err := os.MkdirAll(filepath.Dir(marker), 0o755); err != nil {
		logStage("migrate marker dir", err)
		return
	}
	if err := os.WriteFile(marker, []byte("ryostage migration complete\n"), 0o644); err != nil {
		logStage("migrate marker", err)
	}
}

func loadLegacyDepthWalls() map[string]bool {
	b, err := os.ReadFile(legacyDepthWallsPath())
	if err != nil {
		return nil
	}
	var dw legacyDepthWalls
	if json.Unmarshal(b, &dw) != nil {
		return nil
	}
	return dw.Walls
}

func loadLegacyParallaxWalls() legacyParallaxWalls {
	var lp legacyParallaxWalls
	if b, err := os.ReadFile(legacyLayersPath()); err == nil {
		_ = json.Unmarshal(b, &lp)
	}
	return lp
}

// migrateParallaxFolder moves ~/Pictures/Parallax/<stem>/ whole into the Stage
// tree, renames the auto subject (old layer-01.png) to subject.png, and rewrites
// the wall's layer refs onto the new folder. On any conflict or failure the
// source is left in place and logged.
func migrateParallaxFolder(path string, w legacyParallaxWall, layers []legacyParallaxLayer, reg *stageWalls) {
	stem := stageStem(path)
	src := filepath.Join(legacyParallaxDir(), stem)
	if !isDir(src) {
		return
	}
	dst := stageWallDir(path)
	if isDir(dst) {
		logStage("migrate parallax "+stem+": destination exists, left in place", nil)
		return
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		logStage("migrate parallax mkdir "+stem, err)
		return
	}
	if err := os.Rename(src, dst); err != nil {
		logStage("migrate move parallax "+stem, err)
		return
	}
	auto := w.Mode == "" || w.Mode == "auto"
	if auto {
		l1 := filepath.Join(dst, "layer-01.png")
		sp := filepath.Join(dst, "subject.png")
		if isFile(l1) && !isFile(sp) {
			if err := os.Rename(l1, sp); err != nil {
				logStage("migrate rename subject "+stem, err)
			}
		}
	}
	var newLayers []stageLayer
	for _, ol := range layers {
		base := filepath.Base(ol.Out)
		if auto && base == "layer-01.png" {
			base = "subject.png"
		}
		out := filepath.Join(dst, base)
		nl := stageLayer{"out": out, "rev": fileModTime(out), "label": ol.Label}
		if ol.Depth != 0 {
			nl["depth"] = ol.Depth
		}
		if ol.Area != 0 {
			nl["area"] = ol.Area
		}
		newLayers = append(newLayers, nl)
	}
	if len(newLayers) > 0 {
		e := reg.Walls[path]
		e.Layers = newLayers
		reg.Walls[path] = e
	}
}

// migrateDepthPNG renames ~/Pictures/Depth/<stem>-depth.png to the wall's
// subject.png, unless a subject is already present (a wall enabled in both
// effects keeps the parallax subject; the depth PNG is left for the doctor).
func migrateDepthPNG(path string) {
	stem := stageStem(path)
	src := filepath.Join(legacyDepthDir(), stem+"-depth.png")
	if !isFile(src) {
		return
	}
	dst := stageSubjectOut(path)
	if isFile(dst) {
		logStage("migrate depth "+stem+": subject already present, left in place", nil)
		return
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		logStage("migrate depth mkdir "+stem, err)
		return
	}
	if err := os.Rename(src, dst); err != nil {
		logStage("migrate move depth "+stem, err)
	}
}

var stageSettingKeys = []string{"quality", "feather", "lift", "shadow", "shadowAngle", "motion", "preset", "front"}

// defaultStageSettings is the spec's stage.json defaults, the base the fold
// overlays legacy and existing values onto.
func defaultStageSettings() map[string]any {
	return map[string]any{
		"quality":     "draft",
		"feather":     0.15,
		"lift":        1.0,
		"shadow":      0,
		"shadowAngle": 90,
		"motion":      map[string]any{"mouse": true, "sensitivity": 1, "range": 0.3, "wallpaper": 0.2},
		"preset":      "none",
		"front":       []any{},
	}
}

func qualityRank(t string) int {
	switch t {
	case "fine":
		return 2
	case "standard":
		return 1
	}
	return 0
}

// qualityTierForModel maps a legacy model + matting pair back to a quality tier.
func qualityTierForModel(model string, matting bool) string {
	switch {
	case model == "birefnet-general-lite":
		return "fine"
	case matting:
		return "standard"
	default:
		return "draft"
	}
}

// migrateStageSettings folds depth.json + parallax.json into stage.json: spec
// keys carry across verbatim, the legacy model+matting derive the quality tier,
// and an existing stage.json wins over everything. It only materializes
// stage.json when there is legacy state to fold (the file is otherwise
// GUI-owned and never created by the daemon).
func migrateStageSettings() {
	dir := ryokuConfigDir()
	if dir == "" {
		return
	}
	stagePath := filepath.Join(dir, "stage.json")
	result := defaultStageSettings()
	foundLegacy := false
	// parallax.json first, depth.json last: the global look is the subject's, and
	// parallax stores feather/lift/shadow per layer (arrays), which must not land
	// where a scalar is expected.
	for _, name := range []string{"parallax.json", "depth.json"} {
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			continue
		}
		var m map[string]any
		if json.Unmarshal(b, &m) != nil {
			continue
		}
		foundLegacy = true
		for _, k := range stageSettingKeys {
			if v, ok := m[k]; ok && sameJSONKind(v, result[k]) {
				result[k] = v
			}
		}
		// Two files may disagree on quality; the higher tier is what the user
		// paid the download for.
		model, _ := m["model"].(string)
		if matting, ok := m["alphaMatting"].(bool); ok || model != "" {
			if model == "" {
				model = "u2netp"
			}
			tier := qualityTierForModel(model, matting)
			if qualityRank(tier) > qualityRank(result["quality"].(string)) {
				result["quality"] = tier
			}
		}
	}
	if !foundLegacy {
		return
	}
	// The user's existing stage.json wins over defaults and legacy folds.
	if b, err := os.ReadFile(stagePath); err == nil {
		var ex map[string]any
		if json.Unmarshal(b, &ex) == nil {
			for k, v := range ex {
				result[k] = v
			}
		}
	}
	if err := writeJSONFileAtomic(stagePath, result); err != nil {
		logStage("migrate settings", err)
	}
}

// sameJSONKind reports whether a legacy value has the shape of the default it
// would replace (number, bool, string, list, object), so a per-layer array
// never lands in a scalar slot.
func sameJSONKind(v, def any) bool {
	switch def.(type) {
	case float64, int:
		_, ok := v.(float64)
		return ok
	case bool:
		_, ok := v.(bool)
		return ok
	case string:
		_, ok := v.(string)
		return ok
	case []any, []string:
		_, ok := v.([]any)
		return ok
	case map[string]any:
		_, ok := v.(map[string]any)
		return ok
	}
	return false
}

// startStage registers the topic, runs the one-time migration, publishes the
// first frame, and starts the coalescing worker.
func (d *daemon) startStage() {
	d.registerTopic("stage")
	migrateStage()
	d.publishStage()
	go d.stageWorker()
}
