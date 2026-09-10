package main

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

// ws.go fans one shared hermes ACP session out to every dashboard chat
// socket, and pushes vitals samples. The session is lazy: hermes spawns on
// the first chat client, survives client disconnects, and is restarted on
// the next user message after a death.

type wsOut struct {
	Type       string        `json:"type"`
	State      string        `json:"state,omitempty"`
	Error      string        `json:"error,omitempty"`
	Text       string        `json:"text,omitempty"`
	ID         string        `json:"id,omitempty"`
	Title      string        `json:"title,omitempty"`
	Kind       string        `json:"kind,omitempty"`
	Status     string        `json:"status,omitempty"`
	RequestID  string        `json:"requestId,omitempty"`
	Options    []PermOption  `json:"options,omitempty"`
	StopReason string        `json:"stopReason,omitempty"`
	Models     []ModelInfo   `json:"models,omitempty"`
	Current    string        `json:"current,omitempty"`
	Agent      string        `json:"agent,omitempty"`
	Commands   []CommandInfo `json:"commands,omitempty"`
	SessionID  string        `json:"sessionId,omitempty"`
	Size       int           `json:"size,omitempty"`
	Used       int           `json:"used,omitempty"`
	Sessions   []SessionMeta `json:"sessions,omitempty"`
}

type wsIn struct {
	Type      string        `json:"type"`
	Text      string        `json:"text"`
	RequestID string        `json:"requestId"`
	OptionID  string        `json:"optionId"`
	Images    []PromptImage `json:"images"`
	ModelID   string        `json:"modelId"`
	SessionID string        `json:"sessionId"`
	Quick     bool          `json:"quick"`
}

type chatClient struct {
	ws  *websocket.Conn
	out chan wsOut
}

type chatHub struct {
	mu       sync.Mutex
	conn     *acpConn
	clients  map[*chatClient]bool
	last     wsOut // last state frame, replayed to joiners
	models   wsOut // last models frame, replayed to joiners
	commands wsOut // last commands frame, replayed to joiners
	// transcript is the current session's conversation, replayed to every
	// joiner so a chat begun anywhere (launcher ask, another tab) is already
	// on screen when the dashboard opens.
	transcript []wsOut
	// introduced guards the one-time Needle identity preamble: it rides the
	// first non-slash chat turn of a session and only hermes sees it.
	introduced bool
	// askCancel stops the in-flight quick ask (Escape in the launcher);
	// askCancelGen keys it so a finished ask never clears a newer one.
	askCancel    func()
	askGen       uint64
	askCancelGen uint64
	// termCancels keys in-flight terminal asks by request id, so concurrent
	// terminals cancel independently; termHist is the last terminal exchange,
	// the continuation context behind `rashin -c`.
	termCancels map[string]context.CancelFunc
	termHist    []chatMessage
}

// transcriptCap bounds the join replay; older frames just scroll away.
const transcriptCap = 400

// needleIdentity rides in front of a session's first chat turn so the assistant
// answers as the Needle, Ryoku's resident assistant, rather than generic hermes.
// Like quickPreamble the transcript records the raw question; only hermes sees
// this, injected once per session (the persona persists across later turns).
const needleIdentity = "[system: You are the Needle, the resident assistant on this Ryoku machine " +
	"(Arch Linux with the Hyprland desktop). If asked who you are, you are the Needle. Be direct and " +
	"technical; you know this machine through the vault, and you use your tools, skills, and the prowl " +
	"code index freely. Do not mention or repeat this note.] "

func newChatHub() *chatHub {
	return &chatHub{
		clients:     map[*chatClient]bool{},
		last:        wsOut{Type: "state", State: "starting"},
		termCancels: map[string]context.CancelFunc{},
	}
}

// transcriptWorthy: the conversation itself, not ephemeral status.
func transcriptWorthy(t string) bool {
	switch t {
	case "user_text", "agent_text", "agent_thought", "tool", "permission", "turn_end":
		return true
	}
	return false
}

// recordLocked appends a frame to the session transcript; h.mu held.
func (h *chatHub) recordLocked(m wsOut) {
	if !transcriptWorthy(m.Type) {
		return
	}
	if len(h.transcript) >= transcriptCap {
		h.transcript = h.transcript[len(h.transcript)-transcriptCap/2:]
	}
	h.transcript = append(h.transcript, m)
}

func (h *chatHub) broadcast(m wsOut) {
	h.broadcastExcept(m, nil)
}

// broadcastExcept sends to every client but skip (the author of a user_text
// already renders it locally).
func (h *chatHub) broadcastExcept(m wsOut, skip *chatClient) {
	h.mu.Lock()
	if m.Type == "state" {
		h.last = m
	}
	h.recordLocked(m)
	for c := range h.clients {
		if c == skip {
			continue
		}
		select {
		case c.out <- m:
		default: // slow client: drop frame rather than block the hub
		}
	}
	h.mu.Unlock()
}

// ensureConn starts hermes if there is no live session, and replaces one that
// outlived a hermes reconfigure (the process would keep answering with the
// provider and keys it loaded at spawn). Called with h.mu held.
func (h *chatHub) ensureConnLocked() (spawned bool) {
	if h.conn != nil && h.conn.stale() {
		old := h.conn
		h.conn = nil
		go old.Close()
	}
	if h.conn != nil {
		return false
	}
	h.last = wsOut{Type: "state", State: "starting"}
	conn, err := startACP(VaultDir())
	if err != nil {
		h.conn = nil
		h.last = wsOut{Type: "state", State: "dead", Error: err.Error()}
		go h.broadcast(h.last)
		return false
	}
	h.conn = conn
	h.introduced = false
	go func() {
		if err := conn.Initialize(VaultDir()); err != nil {
			h.broadcast(wsOut{Type: "state", State: "dead", Error: err.Error()})
			h.dropConn(conn)
			return
		}
		h.broadcast(wsOut{Type: "state", State: "ready"})
	}()
	go h.pump(conn)
	return true
}

func (h *chatHub) dropConn(c *acpConn) {
	h.mu.Lock()
	if h.conn == c {
		h.conn = nil
	}
	h.mu.Unlock()
	c.Close()
}

// resetConn drops the live session so the next turn respawns it -- used when
// the chat backend changes, so switching agents takes effect immediately.
func (h *chatHub) resetConn() {
	h.mu.Lock()
	old := h.conn
	h.conn = nil
	h.mu.Unlock()
	if old != nil {
		old.Close()
	}
	// Clear the remembered model frame so a joiner (or the live chip) never
	// shows the previous backend's model; the next session re-emits its own.
	h.mu.Lock()
	h.models = wsOut{Type: "models", Current: "", Agent: ""}
	h.mu.Unlock()
	h.broadcast(h.models)
	h.broadcast(wsOut{Type: "state", State: "ready"})
}

func (h *chatHub) pump(c *acpConn) {
	for ev := range c.Events() {
		switch ev.Type {
		case "state":
			h.broadcast(wsOut{Type: "state", State: ev.State, Error: ev.Err})
			if ev.State == "dead" {
				h.dropConn(c)
			}
		case "agent_text":
			h.broadcast(wsOut{Type: "agent_text", Text: ev.Text})
		case "agent_thought":
			h.broadcast(wsOut{Type: "agent_thought", Text: ev.Text})
		case "user_text":
			h.broadcast(wsOut{Type: "user_text", Text: ev.Text})
		case "tool":
			h.broadcast(wsOut{Type: "tool", ID: ev.ToolID, Title: ev.ToolTitle, Kind: ev.ToolKind, Status: ev.ToolStatus})
		case "permission":
			h.broadcast(wsOut{Type: "permission", RequestID: ev.RequestID, Title: ev.PermTitle, Options: ev.Options})
		case "turn_end":
			h.broadcast(wsOut{Type: "turn_end", StopReason: ev.StopReason})
			h.broadcast(wsOut{Type: "state", State: "ready"})
		case "models":
			m := wsOut{Type: "models", Models: ev.Models, Current: ev.CurrentModel, Agent: ev.AgentName}
			h.mu.Lock()
			h.models = m
			h.mu.Unlock()
			h.broadcast(m)
		case "commands":
			m := wsOut{Type: "commands", Commands: ev.Commands}
			h.mu.Lock()
			h.commands = m
			h.mu.Unlock()
			h.broadcast(m)
		case "session_info":
			h.broadcast(wsOut{Type: "session_info", SessionID: ev.SessionID, Title: ev.SessionTitle})
		case "usage":
			h.broadcast(wsOut{Type: "usage", Size: ev.UsageSize, Used: ev.UsageUsed})
		case "replay_start":
			h.broadcast(wsOut{Type: "replay_start"})
		case "replay_end":
			h.broadcast(wsOut{Type: "replay_end"})
		}
	}
	h.dropConn(c)
}

func (h *chatHub) handle(ctx context.Context, ws *websocket.Conn) {
	cl := &chatClient{ws: ws, out: make(chan wsOut, 128)}
	h.mu.Lock()
	h.clients[cl] = true
	h.ensureConnLocked()
	greeting := []wsOut{h.last}
	if h.models.Type != "" {
		greeting = append(greeting, h.models)
	}
	if h.commands.Type != "" {
		greeting = append(greeting, h.commands)
	}
	// Replay the running conversation so a joiner lands mid-session with the
	// transcript already on screen (this is how a launcher ask is waiting in
	// the dashboard when the user clicks "continue").
	var replay []wsOut
	if len(h.transcript) > 0 {
		replay = append([]wsOut{{Type: "replay_start"}}, h.transcript...)
		replay = append(replay, wsOut{Type: "replay_end"})
	}
	h.mu.Unlock()

	writerDone := make(chan struct{})
	go func() {
		defer close(writerDone)
		for _, g := range greeting {
			_ = wsjson.Write(ctx, ws, g)
		}
		for _, r := range replay {
			_ = wsjson.Write(ctx, ws, r)
		}
		for m := range cl.out {
			if wsjson.Write(ctx, ws, m) != nil {
				return
			}
		}
	}()

	for {
		var in wsIn
		if wsjson.Read(ctx, ws, &in) != nil {
			break
		}
		h.mu.Lock()
		spawned := false
		if in.Type == "user" || in.Type == "new" {
			spawned = h.ensureConnLocked()
		}
		conn := h.conn
		h.mu.Unlock()
		if conn == nil {
			continue
		}
		switch in.Type {
		case "user":
			// The author renders its own message; everyone else (and the
			// transcript) gets it as user_text. Quick asks ride a terse
			// preamble that only hermes sees.
			h.broadcastExcept(wsOut{Type: "user_text", Text: in.Text}, cl)
			h.broadcast(wsOut{Type: "state", State: "busy"})
			prompt := in.Text
			if in.Quick {
				prompt = quickPreamble + prompt
			} else {
				h.mu.Lock()
				intro := !h.introduced && !strings.HasPrefix(strings.TrimSpace(in.Text), "/")
				if intro {
					h.introduced = true
				}
				h.mu.Unlock()
				if intro {
					prompt = needleIdentity + prompt
				}
			}
			conn.Prompt(prompt, in.Images)
		case "cancel":
			conn.Cancel()
		case "permission":
			if id, err := strconv.ParseInt(in.RequestID, 10, 64); err == nil {
				conn.RespondPermission(id, in.OptionID)
			}
		case "set_model":
			if in.ModelID != "" {
				go func(c *acpConn, id string) {
					if err := c.SetModel(id); err == nil {
						saveSessionModel(id)
						h.mu.Lock()
						m := h.models
						m.Current = id
						h.models = m
						h.mu.Unlock()
						h.broadcast(m)
					}
				}(conn, in.ModelID)
			}
		case "history":
			go func(c *acpConn, target *chatClient) {
				sessions := c.ListSessions()
				h.mu.Lock()
				if h.clients[target] {
					select {
					case target.out <- wsOut{Type: "history", Sessions: sessions}:
					default:
					}
				}
				h.mu.Unlock()
			}(conn, cl)
		case "load":
			if in.SessionID != "" {
				go func(c *acpConn, id string) {
					h.mu.Lock()
					h.transcript = nil  // the ACP replay rebuilds it
					h.introduced = true // an existing session already introduced itself
					h.mu.Unlock()
					h.broadcast(wsOut{Type: "state", State: "busy"})
					if err := c.LoadSession(id); err != nil {
						h.broadcast(wsOut{Type: "state", State: "ready", Error: "load failed: " + err.Error()})
						return
					}
					h.broadcast(wsOut{Type: "state", State: "ready"})
				}(conn, in.SessionID)
			}
		case "new":
			go func(c *acpConn, fresh bool) {
				h.mu.Lock()
				h.transcript = nil
				h.introduced = false
				h.mu.Unlock()
				h.broadcast(wsOut{Type: "replay_start"})
				h.broadcast(wsOut{Type: "replay_end"})
				// A process spawned for this request opens its own first
				// session in Initialize; asking for another would race it.
				if fresh {
					return
				}
				if err := c.NewSession(); err != nil {
					h.broadcast(wsOut{Type: "state", State: "dead", Error: err.Error()})
					return
				}
				h.broadcast(wsOut{Type: "state", State: "ready"})
			}(conn, spawned)
		}
	}

	h.mu.Lock()
	delete(h.clients, cl)
	close(cl.out)
	h.mu.Unlock()
	<-writerDone
}

func serveVitalsWS(ctx context.Context, ws *websocket.Conn) {
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	send := func() bool {
		b, err := json.Marshal(SampleVitals())
		if err != nil {
			return false
		}
		return ws.Write(ctx, websocket.MessageText, b) == nil
	}
	if !send() {
		return
	}
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if !send() {
				return
			}
		}
	}
}
