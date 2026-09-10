package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

// `chat` is the sidebar's multi-turn client: it drives the daemon's shared
// hermes session over /ws/chat and relays each frame as one line of JSON
// (working|delta|perm|done|error) so streamed chunks keep their newlines.
// Flags: --image <path> (repeatable), --cancel, --new, --perm <id> <option>.

func chatWSURL() string {
	return fmt.Sprintf("ws://127.0.0.1:%d/ws/chat", LoadConfig().Port)
}

func emitChat(frame map[string]any) {
	if b, err := json.Marshal(frame); err == nil {
		fmt.Println(string(b))
	}
}

func chatImageMime(p string) string {
	switch strings.ToLower(filepath.Ext(p)) {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".webp":
		return "image/webp"
	case ".gif":
		return "image/gif"
	default:
		return "image/png"
	}
}

func loadPromptImages(paths []string) []PromptImage {
	var out []PromptImage
	for _, p := range paths {
		data, mime := encodeImage(p)
		if data == "" {
			continue
		}
		out = append(out, PromptImage{Data: data, MimeType: mime})
	}
	return out
}

// encodeImage base64-encodes an image for the model, downscaling through
// ImageMagick to a sane edge (as the dashboard does) so a big screenshot or
// photo is small on the wire. If magick is missing or fails, the original
// bytes are sent.
func encodeImage(p string) (data, mime string) {
	if _, err := exec.LookPath("magick"); err == nil {
		out, err := exec.Command("magick", p, "-resize", "1568x1568>", "-strip", "-quality", "85", "jpeg:-").Output()
		if err == nil && len(out) > 0 {
			return base64.StdEncoding.EncodeToString(out), "image/jpeg"
		}
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return "", ""
	}
	return base64.StdEncoding.EncodeToString(b), chatImageMime(p)
}

func emitModelsFrame(m wsOut) {
	arr := make([]map[string]any, 0, len(m.Models))
	for _, mi := range m.Models {
		arr = append(arr, map[string]any{"id": mi.ID, "name": mi.Name})
	}
	emitChat(map[string]any{"type": "models", "models": arr, "current": m.Current, "agent": m.Agent})
}

func emitCommandsFrame(m wsOut) {
	arr := make([]map[string]any, 0, len(m.Commands))
	for _, c := range m.Commands {
		arr = append(arr, map[string]any{"name": c.Name, "description": c.Description, "hint": c.Hint})
	}
	emitChat(map[string]any{"type": "commands", "commands": arr})
}

func emitSessionsFrame(m wsOut) {
	arr := make([]map[string]any, 0, len(m.Sessions))
	for _, s := range m.Sessions {
		arr = append(arr, map[string]any{"id": s.ID, "title": s.Title, "updatedAt": s.UpdatedAt})
	}
	emitChat(map[string]any{"type": "sessions", "sessions": arr})
}

func skillMeta(path string) (name, desc string) {
	f, err := os.Open(path)
	if err != nil {
		return "", ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	fences := 0
	for sc.Scan() {
		t := strings.TrimSpace(sc.Text())
		if t == "---" {
			fences++
			if fences >= 2 {
				break
			}
			continue
		}
		if fences != 1 {
			continue
		}
		switch {
		case strings.HasPrefix(t, "name:"):
			name = strings.Trim(strings.TrimSpace(strings.TrimPrefix(t, "name:")), "\"'")
		case strings.HasPrefix(t, "description:"):
			desc = strings.Trim(strings.TrimSpace(strings.TrimPrefix(t, "description:")), "\"'")
		}
	}
	return name, desc
}

// emitSkillsFrame lists the installed hermes skills (each usable as a slash
// command) by walking ~/.hermes/skills for SKILL.md files.
func emitSkillsFrame() {
	home := os.Getenv("HERMES_HOME")
	if home == "" {
		if h, err := os.UserHomeDir(); err == nil {
			home = filepath.Join(h, ".hermes")
		}
	}
	type skill struct{ name, desc string }
	var found []skill
	seen := map[string]bool{}
	addSkill := func(p string) {
		name, desc := skillMeta(p)
		if name == "" {
			name = filepath.Base(filepath.Dir(p))
		}
		if name == "" || seen[name] {
			return
		}
		seen[name] = true
		found = append(found, skill{name, desc})
	}
	// A skill is <skills>/<name>/SKILL.md, or one of a bundle at
	// <skills>/<bundle>/skills/<name>/SKILL.md. Symlinked dirs are read through:
	// wire links the shipped ryoku skill in, and WalkDir would skip it.
	_ = filepath.WalkDir(filepath.Join(home, "skills"), func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.Type()&fs.ModeSymlink != 0 {
			if info, statErr := os.Stat(p); statErr == nil && info.IsDir() {
				if _, e := os.Stat(filepath.Join(p, "SKILL.md")); e == nil {
					addSkill(filepath.Join(p, "SKILL.md"))
				}
				bundled, _ := filepath.Glob(filepath.Join(p, "skills", "*", "SKILL.md"))
				for _, cand := range bundled {
					addSkill(cand)
				}
			}
			return nil
		}
		if d.IsDir() || d.Name() != "SKILL.md" {
			return nil
		}
		addSkill(p)
		return nil
	})
	sort.Slice(found, func(i, j int) bool { return found[i].name < found[j].name })
	arr := make([]map[string]any, 0, len(found))
	for _, s := range found {
		arr = append(arr, map[string]any{"name": s.name, "description": s.desc})
	}
	emitChat(map[string]any{"type": "skills", "skills": arr})
}

// emitHistory replays the daemon's current session transcript into a single
// history frame so a freshly loaded sidebar (after a shell reload) shows the
// conversation the persistent session still holds. Text only; the live turns
// that follow carry full activity.
func emitHistory(ctx context.Context, c *websocket.Conn) {
	msgs := []map[string]any{}
	inReplay := false
	var agent strings.Builder
	flush := func() {
		if agent.Len() > 0 {
			msgs = append(msgs, map[string]any{"who": "agent", "body": agent.String()})
			agent.Reset()
		}
	}
	for {
		var m wsOut
		if wsjson.Read(ctx, c, &m) != nil {
			break
		}
		if m.Type == "replay_start" {
			inReplay = true
			continue
		}
		if m.Type == "replay_end" {
			break
		}
		if !inReplay {
			continue
		}
		switch m.Type {
		case "user_text":
			flush()
			msgs = append(msgs, map[string]any{"who": "user", "body": m.Text})
		case "agent_text":
			agent.WriteString(m.Text)
		case "turn_end":
			flush()
		}
	}
	flush()
	emitChat(map[string]any{"type": "history", "messages": msgs})
}

func cmdChat(args []string) error {
	var images, words []string
	var modelID, sessionID, permID, permOption string
	mode := "ask"
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--cancel":
			mode = "cancel"
		case "--new":
			mode = "new"
		case "--models":
			mode = "models"
		case "--commands":
			mode = "commands"
		case "--skills":
			mode = "skills"
		case "--history":
			mode = "history"
		case "--sessions":
			mode = "sessions"
		case "--load":
			mode = "load"
			if i+1 < len(args) {
				i++
				sessionID = args[i]
			}
		case "--set-model":
			mode = "setmodel"
			if i+1 < len(args) {
				i++
				modelID = args[i]
			}
		case "--perm":
			mode = "perm"
			if i+2 < len(args) {
				permID, permOption = args[i+1], args[i+2]
				i += 2
			}
		case "--image":
			if i+1 < len(args) {
				i++
				images = append(images, args[i])
			}
		default:
			words = append(words, args[i])
		}
	}
	q := strings.TrimSpace(strings.Join(words, " "))
	if mode == "skills" {
		emitSkillsFrame()
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	c, _, err := websocket.Dial(ctx, chatWSURL(), nil)
	if err != nil {
		emitChat(map[string]any{"type": "error", "message": "daemon not reachable"})
		return nil
	}
	defer c.Close(websocket.StatusNormalClosure, "")
	c.SetReadLimit(4 << 20)

	switch mode {
	case "cancel":
		_ = wsjson.Write(ctx, c, wsIn{Type: "cancel"})
		time.Sleep(150 * time.Millisecond)
		return nil
	case "new":
		_ = wsjson.Write(ctx, c, wsIn{Type: "new"})
		time.Sleep(200 * time.Millisecond)
		return nil
	case "perm":
		_ = wsjson.Write(ctx, c, wsIn{Type: "permission", RequestID: permID, OptionID: permOption})
		time.Sleep(150 * time.Millisecond)
		return nil
	case "history":
		hctx, hcancel := context.WithTimeout(ctx, 3*time.Second)
		defer hcancel()
		emitHistory(hctx, c)
		return nil
	case "sessions":
		sctx, scancel := context.WithTimeout(ctx, 4*time.Second)
		defer scancel()
		_ = wsjson.Write(sctx, c, wsIn{Type: "history"})
		for {
			var m wsOut
			if wsjson.Read(sctx, c, &m) != nil {
				emitChat(map[string]any{"type": "sessions", "sessions": []any{}})
				return nil
			}
			if m.Type == "history" {
				emitSessionsFrame(m)
				return nil
			}
		}
	case "load":
		if sessionID == "" {
			return nil
		}
		_ = wsjson.Write(ctx, c, wsIn{Type: "load", SessionID: sessionID})
		lctx, lcancel := context.WithTimeout(ctx, 10*time.Second)
		defer lcancel()
		sawBusy := false
		for {
			var m wsOut
			if wsjson.Read(lctx, c, &m) != nil {
				return nil
			}
			if m.Type == "state" && m.State == "busy" {
				sawBusy = true
			}
			if m.Type == "state" && m.State == "ready" && sawBusy {
				return nil
			}
		}
	case "setmodel":
		if modelID != "" {
			_ = wsjson.Write(ctx, c, wsIn{Type: "set_model", ModelID: modelID})
			time.Sleep(200 * time.Millisecond)
		}
		return nil
	case "models":
		mctx, mcancel := context.WithTimeout(ctx, 4*time.Second)
		defer mcancel()
		for {
			var m wsOut
			if wsjson.Read(mctx, c, &m) != nil {
				emitChat(map[string]any{"type": "models", "models": []any{}, "current": ""})
				return nil
			}
			if m.Type == "models" {
				emitModelsFrame(m)
				return nil
			}
		}
	case "commands":
		cctx, ccancel := context.WithTimeout(ctx, 4*time.Second)
		defer ccancel()
		for {
			var m wsOut
			if wsjson.Read(cctx, c, &m) != nil {
				emitChat(map[string]any{"type": "commands", "commands": []any{}})
				return nil
			}
			if m.Type == "commands" {
				emitCommandsFrame(m)
				return nil
			}
		}
	}

	if q == "" && len(images) == 0 {
		return nil
	}
	if err := wsjson.Write(ctx, c, wsIn{Type: "user", Text: q, Images: loadPromptImages(images)}); err != nil {
		emitChat(map[string]any{"type": "error", "message": "send failed"})
		return nil
	}

	// Skip the join greeting and the transcript replay; only the frames of the
	// turn we just started should reach the sidebar. `busy` guards against a
	// stale state:dead from before our turn (sending user revives the session).
	inReplay := false
	busy := false
	var full strings.Builder
	for {
		var m wsOut
		if err := wsjson.Read(ctx, c, &m); err != nil {
			emitChat(map[string]any{"type": "error", "message": "connection closed"})
			return nil
		}
		switch m.Type {
		case "replay_start":
			inReplay = true
			continue
		case "replay_end":
			inReplay = false
			continue
		}
		if inReplay {
			continue
		}
		switch m.Type {
		case "state":
			switch m.State {
			case "busy":
				busy = true
				emitChat(map[string]any{"type": "working", "label": "thinking"})
			case "dead":
				if busy {
					msg := m.Error
					if msg == "" {
						msg = "the agent stopped"
					}
					emitChat(map[string]any{"type": "error", "message": msg})
					return nil
				}
			}
		case "agent_thought":
			if m.Text != "" {
				emitChat(map[string]any{"type": "thought", "text": m.Text})
			}
		case "tool":
			emitChat(map[string]any{"type": "tool", "id": m.ID, "title": m.Title, "kind": m.Kind, "status": m.Status})
		case "agent_text":
			busy = true
			full.WriteString(m.Text)
			emitChat(map[string]any{"type": "delta", "text": m.Text})
		case "permission":
			emitChat(map[string]any{"type": "perm", "title": m.Title, "requestId": m.RequestID, "options": m.Options})
		case "models":
			emitModelsFrame(m)
		case "turn_end":
			imgs := extractImages(full.String())
			if imgs == nil {
				imgs = []string{}
			}
			emitChat(map[string]any{"type": "done", "images": imgs})
			return nil
		}
	}
}
