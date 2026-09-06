package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// The depth-cutout policy lives here in the Go daemon (per-wall registry,
// engine runs, the depth IPC verbs), but the wallpaper surface itself lives in
// ryogami, the Rust wallpaper daemon. This bridge keeps the two honest: the
// daemon mirrors ryogami's published wallpaper frame to know what is on screen,
// and hands finished cutouts back over `depth set` / `depth clear`, which
// ryogami folds into the frame the shell's QML renders.

// ryogamiFrameEntry is the slice of ryogami's wallpaper frame the depth worker
// needs: the source path and whether a live player owns the slot.
type ryogamiFrameEntry struct {
	Path  string `json:"path"`
	Live  bool   `json:"live"`
	Video bool   `json:"video"`
	Depth string `json:"depth"`
}

// ryogamiFrame mirrors ryogami's `{default, outputs}` wallpaper topic frame.
type ryogamiFrame struct {
	Default ryogamiFrameEntry            `json:"default"`
	Outputs map[string]ryogamiFrameEntry `json:"outputs"`
}

func ryogamiSock() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = "/tmp"
	}
	return filepath.Join(dir, "ryogami.sock")
}

// ryogamiCmd sends one command line to ryogami and returns its single reply
// line. Timeouts are short: ryogami answers surface commands from memory, and a
// hung daemon must never wedge the depth worker.
func ryogamiCmd(line string) (string, error) {
	conn, err := net.DialTimeout("unix", ryogamiSock(), 2*time.Second)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.WriteString(conn, line+"\n"); err != nil {
		return "", err
	}
	reply, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil && reply == "" {
		return "", err
	}
	reply = strings.TrimSpace(reply)
	if strings.HasPrefix(reply, "err") {
		return "", fmt.Errorf("ryogami: %s", reply)
	}
	return reply, nil
}

// currentWall is the wallpaper the depth registry keys off: the default
// (broadcast) wallpaper of the last frame ryogami published.
func (d *daemon) currentWall() string {
	d.ryoWallMu.Lock()
	defer d.ryoWallMu.Unlock()
	return d.ryoWall.Default.Path
}

// currentWallVideo reports whether that default frame is a video's still:
// ryogami paints a clip's extracted frame with a `video` marker, and depth
// must treat it like the video it stands for, not as an image.
func (d *daemon) currentWallVideo() bool {
	d.ryoWallMu.Lock()
	defer d.ryoWallMu.Unlock()
	return d.ryoWall.Default.Video
}

// wallFrame returns a copy of the last frame seen from ryogami.
func (d *daemon) wallFrame() ryogamiFrame {
	d.ryoWallMu.Lock()
	defer d.ryoWallMu.Unlock()
	f := d.ryoWall
	f.Outputs = make(map[string]ryogamiFrameEntry, len(d.ryoWall.Outputs))
	for k, v := range d.ryoWall.Outputs {
		f.Outputs[k] = v
	}
	return f
}

// depthPublish hands a finished cutout to ryogami. Ryogami validates the source
// is still the one on screen (a switch mid-generation drops the stale cut) and
// republishes the wallpaper frame with the depth fields set. The revision is
// the cutout's mtime, so a regenerated file at the same path still busts the
// image cache.
func (d *daemon) depthPublish(slot, source, out string) {
	req, _ := json.Marshal(struct {
		Screen string `json:"screen"`
		Source string `json:"source"`
		Out    string `json:"out"`
		Rev    int64  `json:"rev"`
	}{slot, source, out, fileModTime(out)})
	if _, err := ryogamiCmd("depth set " + string(req)); err != nil {
		fmt.Fprintf(os.Stderr, "depthPublish: %v\n", err)
	}
}

// depthClear drops every slot's cutout from ryogami's frame.
func (d *daemon) depthClear() {
	if _, err := ryogamiCmd("depth clear"); err != nil {
		fmt.Fprintf(os.Stderr, "depthClear: %v\n", err)
	}
}

// sameWallSources reports whether two frames show the same wallpapers, ignoring
// revisions and depth: those change on our own publishes and must not wake the
// worker again.
func sameWallSources(a, b ryogamiFrame) bool {
	if a.Default.Path != b.Default.Path || a.Default.Live != b.Default.Live {
		return false
	}
	if len(a.Outputs) != len(b.Outputs) {
		return false
	}
	for name, ae := range a.Outputs {
		be, ok := b.Outputs[name]
		if !ok || ae.Path != be.Path || ae.Live != be.Live {
			return false
		}
	}
	return true
}

// missingDepth reports whether some still slot shows a wallpaper without a
// cutout. A re-set of the same path clears the frame's depth fields, so this is
// what re-arms the worker when the sources alone look unchanged.
func missingDepth(f ryogamiFrame) bool {
	if f.Default.Path != "" && !f.Default.Live && f.Default.Depth == "" {
		return true
	}
	for _, e := range f.Outputs {
		if e.Path != "" && !e.Live && e.Depth == "" {
			return true
		}
	}
	return false
}

// consumeRyogamiFrames mirrors ryogami's wallpaper topic into d.ryoWall and
// wakes the workers: a changed picture reschedules the depth cutout AND the
// palette pass (the dynamic matugen pipeline follows the wallpaper), while a
// frame that merely lost its cutout re-arms depth alone. The depth worker only
// reuses or clears on such a wake (it never auto-recuts), so a spurious wake
// settles immediately: an unchanged publish is suppressed by ryogami's topic
// and the chain goes quiet.
func (d *daemon) consumeRyogamiFrames(r io.Reader) {
	sc := bufio.NewScanner(r)
	for sc.Scan() {
		var f ryogamiFrame
		if err := json.Unmarshal(sc.Bytes(), &f); err != nil {
			continue
		}
		d.ryoWallMu.Lock()
		srcChanged := !sameWallSources(d.ryoWall, f)
		wakeDepth := srcChanged || missingDepth(f)
		d.ryoWall = f
		d.ryoWallMu.Unlock()
		if wakeDepth {
			d.scheduleDepth()
		}
		if srcChanged {
			d.scheduleTheme()
			d.scheduleParallax()
		}
	}
}

// watchRyogami subscribes to ryogami's wallpaper topic for the daemon's life,
// reconnecting with a small backoff (ryogami restarts independently). The
// retained frame arrives on every connect, so the cache reseeds itself and the
// worker re-publishes cutouts a restarted ryogami lost.
func (d *daemon) watchRyogami() {
	const minBackoff = 150 * time.Millisecond
	const maxBackoff = 5 * time.Second
	backoff := minBackoff
	for {
		select {
		case <-d.quit:
			return
		default:
		}

		conn, err := net.Dial("unix", ryogamiSock())
		if err != nil {
			select {
			case <-d.quit:
				return
			case <-time.After(backoff):
			}
			backoff = capDur(backoff*2, maxBackoff)
			continue
		}
		if _, err := io.WriteString(conn, "subscribe wallpaper\n"); err != nil {
			conn.Close()
			continue
		}

		backoff = minBackoff
		done := make(chan struct{})
		go func() {
			select {
			case <-d.quit:
				conn.Close()
			case <-done:
			}
		}()
		d.consumeRyogamiFrames(conn)
		close(done)
		conn.Close()
	}
}
