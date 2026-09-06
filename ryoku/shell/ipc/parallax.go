package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

// Parallax: cuts or lists the wallpaper's layers per wall (docs/parallax.md).
// Auto shells ryoku-parallax-engine (subject + recoloured background); manual
// lists ~/Pictures/Parallax/<stem>/layer-NN.png. The QML watches layers.pz.

type parallaxMode string

const (
	parallaxModeAuto   parallaxMode = "auto"
	parallaxModeManual parallaxMode = "manual"
)

type parallaxWall struct {
	Enabled bool         `json:"enabled"`
	Mode    parallaxMode `json:"mode"`
	Scene   []string     `json:"scene,omitempty"`
}

type parallaxLayerRef struct {
	Out   string  `json:"out"`
	Rev   int64   `json:"rev"`
	Label string  `json:"label,omitempty"`
	Depth float32 `json:"depth,omitempty"`
	Area  float32 `json:"area,omitempty"`
}

type parallaxWalls struct {
	Walls  map[string]parallaxWall       `json:"walls"`
	Layers map[string][]parallaxLayerRef `json:"layers"`
}

func parallaxWallsPath() string { return filepath.Join(parallaxDir(), "layers.pz") }

func loadParallaxWalls() parallaxWalls {
	var w parallaxWalls
	if raw, err := os.ReadFile(parallaxWallsPath()); err == nil {
		_ = json.Unmarshal(raw, &w)
	}
	// Normalize after any read or decode failure so callers can assign into
	// the maps without a nil-map panic.
	if w.Walls == nil {
		w.Walls = map[string]parallaxWall{}
	}
	if w.Layers == nil {
		w.Layers = map[string][]parallaxLayerRef{}
	}
	return w
}

func saveParallaxWalls(w parallaxWalls) error {
	if w.Walls == nil {
		w.Walls = map[string]parallaxWall{}
	}
	if w.Layers == nil {
		w.Layers = map[string][]parallaxLayerRef{}
	}
	path := parallaxWallsPath()
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("parallax walls mkdir: %w", err)
	}
	b, err := json.MarshalIndent(w, "", "  ")
	if err != nil {
		return fmt.Errorf("parallax walls marshal: %w", err)
	}
	// Write to a temp file in the same directory and rename so a crash never
	// leaves a half-written registry.
	tmp, err := os.CreateTemp(dir, ".layers-*.pz")
	if err != nil {
		return fmt.Errorf("parallax walls temp: %w", err)
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return fmt.Errorf("parallax walls write: %w", err)
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return fmt.Errorf("parallax walls close: %w", err)
	}
	if err := os.Chmod(tmpName, 0o644); err != nil {
		os.Remove(tmpName)
		return fmt.Errorf("parallax walls chmod: %w", err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		os.Remove(tmpName)
		return fmt.Errorf("parallax walls rename: %w", err)
	}
	return nil
}

type parallaxConfig struct {
	mode         parallaxMode
	model        string
	alphaMatting bool
}

func parallaxConfigFromFile() parallaxConfig {
	def := parallaxConfig{mode: parallaxModeAuto, model: "u2netp", alphaMatting: false}
	dir := ryokuConfigDir()
	if dir == "" {
		return def
	}
	b, err := os.ReadFile(filepath.Join(dir, "parallax.json"))
	if err != nil {
		return def
	}
	var m struct {
		Mode         string `json:"mode"`
		Model        string `json:"model"`
		AlphaMatting bool   `json:"alphaMatting"`
	}
	if json.Unmarshal(b, &m) != nil {
		return def
	}
	out := def
	switch parallaxMode(m.Mode) {
	case parallaxModeAuto, parallaxModeManual:
		out.mode = parallaxMode(m.Mode)
	}
	if m.Model != "" {
		out.model = m.Model
	}
	if m.AlphaMatting {
		out.alphaMatting = true
	}
	return out
}

func parallaxDir() string { return filepath.Join(os.Getenv("HOME"), "Pictures", "Parallax") }

// layer-01.png in the per-wallpaper folder.
func parallaxSubjectOut(source string) string {
	return filepath.Join(parallaxManualDir(source), "layer-01.png")
}

// background.png in the per-wallpaper folder.
func parallaxInpaintedOut(source string) string {
	return filepath.Join(parallaxManualDir(source), "background.png")
}

func parallaxManualDir(source string) string {
	stem := strings.TrimSuffix(filepath.Base(source), filepath.Ext(filepath.Base(source)))
	return filepath.Join(parallaxDir(), stem)
}

var manualLayerRe = regexp.MustCompile(`^layer-(\d{2,})\.png$`)

func parallaxProgressPath() string {
	return filepath.Join(stateDir(), "ryoku", "parallax", "progress")
}

func writeParallaxProgress(record map[string]any) {
	path := parallaxProgressPath()
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	b, err := json.Marshal(record)
	if err != nil {
		return
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.Write(append(b, '\n'))
}

// resetParallaxProgress truncates the progress log so each cut starts fresh
// and the append-only file cannot grow without bound.
func resetParallaxProgress() {
	path := parallaxProgressPath()
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	_ = os.WriteFile(path, nil, 0o644)
}

func progressPercent(rec map[string]any) int {
	stage, _ := rec["stage"].(string)
	switch stage {
	case "starting", "reading":
		return 5
	case "subject":
		return 45
	case "inpaint":
		return 80
	case "writing":
		return 92
	case "done":
		return 100
	case "cancelled":
		return 100
	default:
		return 0
	}
}

func progressLabel(rec map[string]any) string {
	stage, _ := rec["stage"].(string)
	switch stage {
	case "starting":
		return "starting"
	case "reading":
		return "reading wallpaper"
	case "subject":
		return "cutting subject"
	case "inpaint":
		return "inpainting background"
	case "writing":
		return "writing layer"
	case "done":
		return "done"
	case "cancelled":
		return "cancelled"
	case "error":
		return "error"
	default:
		return stage
	}
}

func readLastParallaxProgress() (map[string]any, string, int) {
	b, err := os.ReadFile(parallaxProgressPath())
	if err != nil {
		return nil, "", 0
	}
	var record map[string]any
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || !strings.HasPrefix(line, "{") {
			continue
		}
		var rec map[string]any
		if json.Unmarshal([]byte(line), &rec) != nil {
			continue
		}
		record = rec
	}
	if record == nil {
		return nil, "", 0
	}
	return record, progressLabel(record), progressPercent(record)
}

func (d *daemon) parallaxStatusJSON() string {
	reg := loadParallaxWalls()
	wall := d.currentWall()
	entry, hasWall := reg.Walls[wall]
	layers := len(reg.Layers[wall])
	_, label, percent := readLastParallaxProgress()
	mode := entry.Mode
	if mode == "" {
		mode = parallaxModeAuto
	}
	b, _ := json.Marshal(struct {
		Busy    bool         `json:"busy"`
		Current bool         `json:"current"`
		Layers  int          `json:"layers"`
		Mode    parallaxMode `json:"mode"`
		Stage   string       `json:"stage"`
		Percent int          `json:"percent"`
	}{
		Busy:    d.parallaxBusy.Load(),
		Current: hasWall && entry.Enabled,
		Layers:  layers,
		Mode:    mode,
		Stage:   label,
		Percent: percent,
	})
	return string(b)
}

func runParallaxAuto(source string, subjectModel string, alphaMatting bool) error {
	subjectOut := parallaxSubjectOut(source)
	inpaintedOut := parallaxInpaintedOut(source)
	if err := os.MkdirAll(filepath.Dir(subjectOut), 0o755); err != nil {
		return fmt.Errorf("parallax mkdir: %w", err)
	}
	resetParallaxProgress()

	cutoutArgs := []string{"cutout", source, subjectOut, "--model", subjectModel}
	if alphaMatting {
		cutoutArgs = append(cutoutArgs, "--alpha-matting")
	}

	// parallaxCutPID holds the running child's real PID (not the daemon's) so
	// `parallax cancel` can signal its process group; reset to 0 once it exits.
	writeParallaxProgress(map[string]any{"stage": "subject", "model": subjectModel})
	cmd := exec.Command(parallaxEngineBin(), cutoutArgs...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("parallax cutout stderr: %w", err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = io.Copy(io.Discard, stderr)
	}()
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("parallax cutout start: %w", err)
	}
	parallaxCutPID.Store(int32(cmd.Process.Pid))
	werr := cmd.Wait()
	parallaxCutPID.Store(0)
	<-done
	if werr != nil {
		writeParallaxProgress(map[string]any{"stage": "error", "error": werr.Error()})
		return werr
	}
	if _, err := os.Stat(subjectOut); err != nil {
		writeParallaxProgress(map[string]any{"stage": "error", "error": "subject png missing"})
		return err
	}

	writeParallaxProgress(map[string]any{"stage": "inpaint"})
	inpaintCmd := exec.Command(parallaxEngineBin(), "inpaint", source, subjectOut, inpaintedOut)
	inpaintCmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	inStderr, err := inpaintCmd.StderrPipe()
	if err != nil {
		writeParallaxProgress(map[string]any{"stage": "error", "error": err.Error()})
		return fmt.Errorf("parallax inpaint stderr: %w", err)
	}
	done2 := make(chan struct{})
	go func() {
		defer close(done2)
		_, _ = io.Copy(io.Discard, inStderr)
	}()
	if err := inpaintCmd.Start(); err != nil {
		writeParallaxProgress(map[string]any{"stage": "error", "error": err.Error()})
		return fmt.Errorf("parallax inpaint start: %w", err)
	}
	parallaxCutPID.Store(int32(inpaintCmd.Process.Pid))
	werr = inpaintCmd.Wait()
	parallaxCutPID.Store(0)
	<-done2
	if werr != nil {
		// Inpainting failing is non-fatal: the user can still see the
		// subject drifting over the original wallpaper (which still has
		// the subject drawn in it). The daemon logs and the surface
		// falls back to the original.
		writeParallaxProgress(map[string]any{"stage": "error", "error": werr.Error(), "warning": "inpaint failed"})
		return nil
	}

	writeParallaxProgress(map[string]any{"stage": "done", "subject": filepath.Base(subjectOut), "inpainted": filepath.Base(inpaintedOut)})
	// Sweep mktemp leftovers from cancelled cuts.
	for _, base := range []string{subjectOut, inpaintedOut} {
		dir := filepath.Dir(base)
		prefix := filepath.Base(base) + "."
		if entries, err := os.ReadDir(dir); err == nil {
			for _, e := range entries {
				if !e.IsDir() && strings.HasPrefix(e.Name(), prefix) {
					os.Remove(filepath.Join(dir, e.Name()))
				}
			}
		}
	}
	parallaxLastFinish.Store(time.Now().Unix())
	return nil
}

var parallaxCutPID atomic.Int32
var parallaxLastFinish atomic.Int64

func parallaxCancel() {
	pid := int(parallaxCutPID.Load())
	if pid <= 0 {
		return
	}
	_ = syscall.Kill(-pid, syscall.SIGKILL)
}

func parallaxEngineBin() string {
	if dir := os.Getenv("RYOKU_SHELL_DIR"); dir != "" {
		p := filepath.Join(dir, "scripts", "ryoku-parallax-engine")
		if isFile(p) {
			return p
		}
	}
	return "ryoku-parallax-engine"
}

func parallaxEngineAvailable() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, parallaxEngineBin(), "check").Run() == nil
}

func (d *daemon) scheduleParallax() {
	select {
	case d.parallaxSig <- struct{}{}:
	default:
	}
}

func (d *daemon) parallaxWorker() {
	for range d.parallaxSig {
		d.reconcileParallax(d.parallaxForce.Swap(false))
	}
}

type parallaxTarget struct {
	slot   string
	source string
}

func (d *daemon) parallaxTargets() []parallaxTarget {
	f := d.wallFrame()
	var out []parallaxTarget
	if p := f.Default.Path; p != "" && !f.Default.Live && !f.Default.Video && !isVideo(p) && isFile(p) {
		out = append(out, parallaxTarget{"", p})
	}
	for name, e := range f.Outputs {
		if e.Path != "" && !e.Live && !e.Video && !isVideo(e.Path) && isFile(e.Path) {
			out = append(out, parallaxTarget{name, e.Path})
		}
	}
	return out
}

func (d *daemon) reconcileParallax(force bool) {
	cfg := parallaxConfigFromFile()
	reg := loadParallaxWalls()
	targets := d.parallaxTargets()

	if len(targets) == 0 {
		d.parallaxBusy.Store(false)
		return
	}
	_ = os.MkdirAll(parallaxDir(), 0o755)
	changed := false
	defer func() { d.parallaxBusy.Store(false) }()

	for _, t := range targets {
		wall, ok := reg.Walls[t.source]
		if !ok || !wall.Enabled {
			if _, had := reg.Layers[t.source]; had {
				delete(reg.Layers, t.source)
				changed = true
			}
			continue
		}
		mode := wall.Mode
		if mode == "" {
			mode = cfg.mode
		}
		layers := d.refreshWallLayers(t.source, mode, force)
		if layers == nil {
			continue
		}
		reg.Layers[t.source] = layers
		entry := reg.Walls[t.source]
		entry.Mode = mode
		reg.Walls[t.source] = entry
		changed = true
	}

	if changed {
		if err := saveParallaxWalls(reg); err != nil {
			fmt.Fprintf(os.Stderr, "parallax: save walls: %v\n", err)
		}
	}
}

func (d *daemon) refreshWallLayers(source string, mode parallaxMode, force bool) []parallaxLayerRef {
	switch mode {
	case parallaxModeManual:
		return listManualLayers(source)
	case parallaxModeAuto:
		return d.refreshAutoLayers(source, force)
	default:
		return d.refreshAutoLayers(source, force)
	}
}

func listManualLayers(source string) []parallaxLayerRef {
	dir := parallaxManualDir(source)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return []parallaxLayerRef{}
	}
	type found struct {
		idx int
		ref parallaxLayerRef
	}
	var files []found
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		match := manualLayerRe.FindStringSubmatch(e.Name())
		if match == nil {
			continue
		}
		var idx int
		_, _ = fmt.Sscanf(match[1], "%d", &idx)
		path := filepath.Join(dir, e.Name())
		files = append(files, found{
			idx: idx,
			ref: parallaxLayerRef{
				Out:   path,
				Rev:   fileModTime(path),
				Label: fmt.Sprintf("Layer %d", idx),
			},
		})
	}
	sort.Slice(files, func(i, j int) bool { return files[i].idx < files[j].idx })
	layers := make([]parallaxLayerRef, 0, len(files))
	for _, f := range files {
		layers = append(layers, f.ref)
	}
	return layers
}

func (d *daemon) refreshAutoLayers(source string, force bool) []parallaxLayerRef {
	if !parallaxEngineAvailable() {
		return nil
	}
	subjectOut := parallaxSubjectOut(source)
	inpaintedOut := parallaxInpaintedOut(source)

	stem := strings.TrimSuffix(filepath.Base(source), filepath.Ext(filepath.Base(source)))
	for _, legacy := range []string{
		filepath.Join(parallaxDir(), stem+"-subject.png"),
		filepath.Join(parallaxDir(), stem+"-inpainted.png"),
	} {
		if isFile(legacy) {
			os.Remove(legacy)
		}
	}

	if !force {
		srcMod := fileModTime(source)
		if st, err := os.Stat(subjectOut); err == nil && st.ModTime().Unix() >= srcMod {
			return []parallaxLayerRef{{Out: subjectOut, Rev: st.ModTime().Unix(), Label: "subject"}}
		}
	}
	if parallaxCutPID.Load() > 0 {
		return nil
	}
	if !force {
		const settleCutoff = int64(10)
		last := parallaxLastFinish.Load()
		if last > 0 && time.Now().Unix()-last < settleCutoff {
			return nil
		}
	}
	cfg := parallaxConfigFromFile()
	d.parallaxBusy.Store(true)
	if err := runParallaxAuto(source, cfg.model, cfg.alphaMatting); err != nil {
		fmt.Fprintf(os.Stderr, "parallaxWorker: %v\n", err)
		return nil
	}
	st, err := os.Stat(subjectOut)
	if err != nil {
		return nil
	}
	_ = inpaintedOut
	return []parallaxLayerRef{{Out: subjectOut, Rev: st.ModTime().Unix(), Label: "subject"}}
}

func (d *daemon) parallaxSetEnabled(on bool) {
	d.parallaxSetEnabledMode(on, "")
}

func (d *daemon) parallaxSetMode(mode parallaxMode) {
	wall := d.currentWall()
	if wall == "" {
		return
	}
	d.parallaxSetEnabledMode(true, mode)
}

func (d *daemon) parallaxSetEnabledMode(on bool, mode parallaxMode) {
	wall := d.currentWall()
	if wall == "" {
		return
	}
	reg := loadParallaxWalls()
	prevEnabled := reg.Walls[wall].Enabled
	prevLayers := len(reg.Layers[wall])
	prevMode := reg.Walls[wall].Mode
	if on {
		entry := reg.Walls[wall]
		entry.Enabled = true
		if mode != "" {
			entry.Mode = mode
		} else if entry.Mode == "" {
			entry.Mode = parallaxConfigFromFile().mode
		}
		reg.Walls[wall] = entry
	} else {
		delete(reg.Walls, wall)
		delete(reg.Layers, wall)
	}
	dirty := reg.Walls[wall].Enabled != prevEnabled ||
		len(reg.Layers[wall]) != prevLayers ||
		reg.Walls[wall].Mode != prevMode
	if dirty {
		if err := saveParallaxWalls(reg); err != nil {
			fmt.Fprintf(os.Stderr, "parallax: save walls: %v\n", err)
		}
	}
	d.parallaxForce.Store(true)
	d.scheduleParallax()
}

func (d *daemon) parallaxSetScene(body string) {
	wall := d.currentWall()
	if wall == "" {
		return
	}
	var scene []string
	if err := json.Unmarshal([]byte(body), &scene); err != nil {
		return
	}
	reg := loadParallaxWalls()
	entry := reg.Walls[wall]
	entry.Enabled = entry.Enabled || len(scene) > 0
	entry.Scene = scene
	reg.Walls[wall] = entry
	if err := saveParallaxWalls(reg); err != nil {
		fmt.Fprintf(os.Stderr, "parallax: save walls: %v\n", err)
	}
}

func (d *daemon) parallaxAddManualLayer(src string) (string, error) {
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
	dir := parallaxManualDir(wall)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	next := 1
	entries, err := os.ReadDir(dir)
	if err == nil {
		for _, e := range entries {
			match := manualLayerRe.FindStringSubmatch(e.Name())
			if match == nil {
				continue
			}
			var idx int
			_, _ = fmt.Sscanf(match[1], "%d", &idx)
			if idx >= next {
				next = idx + 1
			}
		}
	}
	name := fmt.Sprintf("layer-%02d.png", next)
	dst := filepath.Join(dir, name)
	if err := copyFile(src, dst); err != nil {
		return "", err
	}
	d.parallaxForce.Store(true)
	d.scheduleParallax()
	return dst, nil
}

func (d *daemon) parallaxRemoveManualLayer(path string) error {
	wall := d.currentWall()
	if wall == "" {
		return fmt.Errorf("no active wallpaper")
	}
	if path == "" {
		return fmt.Errorf("empty path")
	}
	dir := parallaxManualDir(wall)
	clean := filepath.Clean(path)
	if !strings.HasPrefix(clean, dir+string(filepath.Separator)) {
		return fmt.Errorf("not in wallpaper folder: %s", path)
	}
	if err := os.Remove(clean); err != nil {
		return err
	}
	d.parallaxForce.Store(true)
	d.scheduleParallax()
	return nil
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
