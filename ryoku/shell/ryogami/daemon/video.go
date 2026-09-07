package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// videoPlayer drives video wallpapers through ryogami-live, one process per
// live output (each in its own process group so the whole tree dies on Stop).
// Play is asynchronous: the one-time transcode runs off the hot path while the
// shell paints the clip's still, and a generation counter serializes rapid
// switches so a clip the user already moved past never paints. The player's
// READY line (its first committed frame) drives onLive: the shell painter
// yields only once real video is on screen, and un-yields if every player
// dies, so the desktop always shows a frame and never a hole.
type videoPlayer struct {
	mu        sync.Mutex
	gen       int64
	procs     []*exec.Cmd
	log       *os.File
	path      string
	outputs   []string
	announced bool
	onLive    func(bool)
	// Unexpected-exit bookkeeping for respawn's backoff.
	deaths  int
	deathAt time.Time
}

func newVideoPlayer() *videoPlayer { return &videoPlayer{} }

// liveSlots is the set of outputs a broadcast video spans: every connected
// output by name, or the NULL slot ("", the compositor's primary) when the
// list can't be read.
func liveSlots() []string {
	out, err := exec.Command("hyprctl", "monitors", "-j").Output()
	if err != nil {
		return []string{""}
	}
	var mons []struct {
		Name string `json:"name"`
	}
	if json.Unmarshal(out, &mons) != nil || len(mons) == 0 {
		return []string{""}
	}
	slots := make([]string, 0, len(mons))
	for _, m := range mons {
		slots = append(slots, m.Name)
	}
	return slots
}

// Play prepares path (probe + cached transcode) and launches one player per
// target output. An empty outputs slice or one containing "*" spans every
// connected output. onLive fires with true once the first player painted and
// with false if every player is gone; nil is allowed. The audio verbs remain
// accepted state upstream: the player is a silent renderer, wallpapers do not
// own the mixer.
func (p *videoPlayer) Play(outputs []string, path, fit, tier string, onLive func(bool)) {
	p.Stop()

	all := len(outputs) == 0
	for _, o := range outputs {
		if o == "*" {
			all = true
			break
		}
	}

	p.mu.Lock()
	gen := p.gen
	p.announced = false
	p.onLive = onLive
	if f, err := os.OpenFile(managedLogPath("video"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); err == nil {
		p.log = f
	}
	p.path = path
	if all {
		p.outputs = []string{"*"}
	} else {
		p.outputs = append([]string(nil), outputs...)
	}
	p.mu.Unlock()

	go func() {
		capW := liveCapWidth(tier)
		src := liveProbe(path)
		fps := liveFps(tier, src)
		file := livewallSource(path, src, capW, fps)
		if file == "" {
			fmt.Fprintf(os.Stderr, "ryogami: transcode failed for %s; keeping the still\n", path)
			return
		}
		targets := outputs
		if all {
			targets = liveSlots()
		}
		p.mu.Lock()
		defer p.mu.Unlock()
		if p.gen != gen {
			return // switched away while transcoding
		}
		for _, out := range targets {
			p.spawnLocked(gen, out, file, capW, fit)
		}
	}()
}

// spawnLocked launches one player bound to output ("" = compositor primary);
// caller holds the lock. Stdout is scanned for the READY handshake and teed to
// the managed log. A crash while the player still believes it should be
// running is logged to stderr, but there is deliberately no auto-restart loop:
// the shell keeps painting the clip's still underneath.
func (p *videoPlayer) spawnLocked(gen int64, output, file string, capW int, fit string) {
	args := []string{file, strconv.Itoa(capW), fit}
	if output != "" && output != "*" {
		args = append(args, output)
	}
	cmd := exec.Command(liveDaemon, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdin = nil
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		stdout = nil
	}
	if p.log != nil {
		if stdout == nil {
			cmd.Stdout = p.log
		}
		cmd.Stderr = p.log
	}
	if err := cmd.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "ryogami: launch %s: %v (build it with ryoku/shell/livewall/build.sh)\n", liveDaemon, err)
		return
	}
	p.procs = append(p.procs, cmd)
	if stdout != nil {
		go p.scanReady(gen, stdout)
	}
	go func() {
		err := cmd.Wait()
		p.mu.Lock()
		// Still tracked means Stop did not remove it: an unexpected exit.
		tracked := p.removeLocked(cmd)
		lastGone := tracked && len(p.procs) == 0 && p.gen == gen && p.announced
		cb := p.onLive
		p.mu.Unlock()
		if tracked {
			fmt.Fprintf(os.Stderr, "ryogami: %s on %q exited unexpectedly: %v\n", liveDaemon, output, err)
		}
		if lastGone && cb != nil {
			cb(false) // every player died: the still shows meanwhile
		}
		if tracked {
			p.respawn(gen, output, file, capW, fit)
		}
	}()
}

// respawn brings back a player that died under the daemon (a compositor
// output cycle, a suspend, a stray kill), so a video wallpaper never stays a
// still until the next login. Backoff steps 1s, 2s, 4s, 8s and gives up after
// the fifth death within a minute (a clip that cannot play at all would spin
// otherwise); Stop or a new Play (a generation change) cancels a pending one.
func (p *videoPlayer) respawn(gen int64, output, file string, capW int, fit string) {
	p.mu.Lock()
	now := time.Now()
	if now.Sub(p.deathAt) > time.Minute {
		p.deaths = 0
	}
	p.deaths++
	p.deathAt = now
	n := p.deaths
	p.mu.Unlock()
	if n > 5 {
		fmt.Fprintf(os.Stderr, "ryogami: %s on %q keeps dying; leaving the still\n", liveDaemon, output)
		return
	}
	delay := time.Second << (n - 1)
	if delay > 8*time.Second {
		delay = 8 * time.Second
	}
	time.Sleep(delay)
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.gen != gen {
		return
	}
	p.announced = false
	p.spawnLocked(gen, output, file, capW, fit)
}

// scanReady tees one player's stdout into the managed log and fires onLive(true)
// on the first READY of the current generation.
func (p *videoPlayer) scanReady(gen int64, r io.Reader) {
	sc := bufio.NewScanner(r)
	for sc.Scan() {
		line := sc.Text()
		p.mu.Lock()
		if p.log != nil {
			fmt.Fprintln(p.log, line)
		}
		var cb func(bool)
		if strings.TrimSpace(line) == "READY" && p.gen == gen && !p.announced {
			p.announced = true
			cb = p.onLive
		}
		p.mu.Unlock()
		if cb != nil {
			cb(true)
		}
	}
}

// removeLocked drops cmd from the tracked set, returning whether it was present.
func (p *videoPlayer) removeLocked(cmd *exec.Cmd) bool {
	for i, c := range p.procs {
		if c == cmd {
			p.procs = append(p.procs[:i], p.procs[i+1:]...)
			return true
		}
	}
	return false
}

// Stop invalidates any in-flight transcode, kills every spawned player (whole
// process group) and, mirroring how process.go clears stale wall-ui, pkills
// orphans: livewall from a crashed daemon, mpvpaper from releases that shipped
// it (an orphan's surface stacks above ours, hiding every later wallpaper).
func (p *videoPlayer) Stop() {
	p.mu.Lock()
	p.gen++
	procs := p.procs
	p.procs = nil
	log := p.log
	p.log = nil
	p.path = ""
	p.outputs = nil
	p.mu.Unlock()

	for _, cmd := range procs {
		if cmd.Process != nil {
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
	}
	if log != nil {
		_ = log.Close()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = exec.CommandContext(ctx, "pkill", "-x", liveDaemon).Run()
	_ = exec.CommandContext(ctx, "pkill", "-f", "mpvpaper").Run()
}

func (p *videoPlayer) Playing() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.procs) > 0
}

func (p *videoPlayer) Current() (path string, outputs []string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.path, append([]string(nil), p.outputs...)
}
