package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// acp.go speaks the Agent Client Protocol: newline-delimited JSON-RPC 2.0
// over the hermes acp child's stdio. One conn drives one hermes session whose
// cwd is the vault, so terminal hermes and the dashboard share one memory.

type PermOption struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Kind string `json:"kind"`
}

// ModelInfo is one selectable model advertised by the agent.
type ModelInfo struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
}

// CommandInfo is one slash command the agent understands.
type CommandInfo struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Hint        string `json:"hint,omitempty"`
}

// SessionMeta is one stored session, for the history drawer.
type SessionMeta struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Cwd       string `json:"cwd,omitempty"`
	UpdatedAt string `json:"updatedAt,omitempty"`
}

// AcpEvent is the translated stream ws.go forwards to the dashboard.
type AcpEvent struct {
	Type         string // state | agent_text | agent_thought | user_text | tool | permission | turn_end | models | commands | session_info | usage | replay_start | replay_end
	State        string
	Err          string
	Text         string
	ToolID       string
	ToolTitle    string
	ToolKind     string
	ToolStatus   string
	RequestID    string
	PermTitle    string
	Options      []PermOption
	StopReason   string
	Models       []ModelInfo
	CurrentModel string
	AgentName    string
	Commands     []CommandInfo
	SessionID    string
	SessionTitle string
	UsageSize    int
	UsageUsed    int
}

type rpcMsg struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      *int64          `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type acpConn struct {
	in     io.Writer
	closer io.Closer

	writeMu sync.Mutex
	nextID  atomic.Int64

	mu        sync.Mutex
	pending   map[int64]chan rpcMsg
	sessionID string
	vault     string
	closed    bool
	// answeredPerms: a permission request is replied to exactly once, even
	// when the dashboard and the terminal race to answer it.
	answeredPerms map[int64]bool

	// configStamp is the hermes config the process loaded at spawn; hermes
	// reads config.yaml and .env once, so a session outlives a `hermes setup`
	// run in a terminal with the old provider and keys (issue 145).
	configStamp string

	// negotiated at initialize: the agreed protocol version and the agent's
	// optional capabilities. ACP methods beyond the baseline (session/load) and
	// image prompt content are gated on these so a minimal agent never chokes.
	protoVersion int
	loadSession  bool
	promptImages bool
	// agentName is the chat backend's display name (Hermes, Oh My Pi, ...), so
	// the UI can label the session even when the agent advertises no model list.
	agentName string

	events chan AcpEvent
}

// hermesConfigStamp fingerprints the files hermes loads at startup.
func hermesConfigStamp() string {
	var b strings.Builder
	for _, p := range []string{hermesConfig(), filepath.Join(home(), ".hermes", ".env")} {
		if st, err := os.Stat(p); err == nil {
			fmt.Fprintf(&b, "%s:%d:%d;", p, st.ModTime().UnixNano(), st.Size())
		}
	}
	return b.String()
}

// stale reports that hermes's config changed since this process started, so
// its provider and keys no longer match what the terminal runs.
func (c *acpConn) stale() bool {
	return c.configStamp != hermesConfigStamp()
}

func newACPConn(in io.Writer, out io.Reader, closer io.Closer) *acpConn {
	c := &acpConn{
		in:            in,
		closer:        closer,
		pending:       map[int64]chan rpcMsg{},
		events:        make(chan AcpEvent, 256),
		answeredPerms: map[int64]bool{},
	}
	go c.readLoop(out)
	return c
}

func (c *acpConn) Events() <-chan AcpEvent { return c.events }

func (c *acpConn) send(v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_, err = c.in.Write(append(b, '\n'))
	return err
}

func (c *acpConn) request(method string, params any) (json.RawMessage, error) {
	id := c.nextID.Add(1)
	ch := make(chan rpcMsg, 1)
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil, errors.New("acp connection closed")
	}
	c.pending[id] = ch
	c.mu.Unlock()

	p, err := json.Marshal(params)
	if err != nil {
		return nil, err
	}
	if err := c.send(rpcMsg{JSONRPC: "2.0", ID: &id, Method: method, Params: p}); err != nil {
		return nil, err
	}
	resp, ok := <-ch
	if !ok {
		return nil, errors.New("acp connection closed")
	}
	if resp.Error != nil {
		return nil, fmt.Errorf("acp %s: %s", method, resp.Error.Message)
	}
	return resp.Result, nil
}

func (c *acpConn) notify(method string, params any) {
	p, err := json.Marshal(params)
	if err != nil {
		return
	}
	_ = c.send(rpcMsg{JSONRPC: "2.0", Method: method, Params: p})
}

func (c *acpConn) respond(id int64, result any) {
	r, err := json.Marshal(result)
	if err != nil {
		return
	}
	_ = c.send(rpcMsg{JSONRPC: "2.0", ID: &id, Result: r})
}

// sessionResult is the shape session/new|load|resume share: model state rides
// along with the id.
type sessionResult struct {
	SessionID string `json:"sessionId"`
	Models    *struct {
		Available []struct {
			ModelID     string `json:"modelId"`
			Name        string `json:"name"`
			Description string `json:"description"`
		} `json:"availableModels"`
		CurrentModelID string `json:"currentModelId"`
	} `json:"models"`
}

// emitModels always emits a models event for a fresh session, carrying the
// backend's name so the UI can label the agent even when it advertises no
// models (omp, for one). A stale model from a different backend is never shown.
func (c *acpConn) emitModels(res json.RawMessage) {
	var out sessionResult
	_ = json.Unmarshal(res, &out)
	var ms []ModelInfo
	current := ""
	if out.Models != nil {
		ms = make([]ModelInfo, 0, len(out.Models.Available))
		for _, m := range out.Models.Available {
			ms = append(ms, ModelInfo{ID: m.ModelID, Name: m.Name, Description: m.Description})
		}
		current = out.Models.CurrentModelID
	}
	c.emit(AcpEvent{Type: "models", Models: ms, CurrentModel: current, AgentName: c.agentName})
}

// reconcileModel keeps a fresh session on the remembered model, and remembers
// the live model when nothing is stored yet, so every surface and `status`
// agree on one model that survives restarts.
func (c *acpConn) reconcileModel(res json.RawMessage, method string) {
	var out sessionResult
	if json.Unmarshal(res, &out) != nil || out.Models == nil {
		return
	}
	current := out.Models.CurrentModelID
	saved := savedSessionModel()
	avail := func(id string) bool {
		for _, m := range out.Models.Available {
			if m.ModelID == id {
				return true
			}
		}
		return false
	}
	// A remembered pick that is still on offer: apply it to this fresh session.
	if method == "session/new" && saved != "" && saved != current && avail(saved) {
		if err := c.SetModel(saved); err == nil {
			ms := make([]ModelInfo, 0, len(out.Models.Available))
			for _, m := range out.Models.Available {
				ms = append(ms, ModelInfo{ID: m.ModelID, Name: m.Name, Description: m.Description})
			}
			c.emit(AcpEvent{Type: "models", Models: ms, CurrentModel: saved})
			return
		}
	}
	// Nothing stored yet: remember whatever the fresh session runs so status and
	// the pickers reflect the live model. A stored pick is left untouched even
	// when this session's list lacks it, so a momentary or partial model list
	// never clobbers the user's choice.
	if current != "" && saved == "" {
		saveSessionModel(current)
	}
}

// acpClientVersion is the latest ACP protocol version this client speaks.
const acpClientVersion = 1

// Initialize performs the ACP handshake and opens the vault session. It sends
// our client info and the version we speak, then records what the agent
// negotiated back so optional methods stay gated to what the agent supports.
func (c *acpConn) Initialize(vault string) error {
	c.vault = vault
	c.protoVersion = acpClientVersion
	res, err := c.request("initialize", map[string]any{
		"protocolVersion": acpClientVersion,
		"clientCapabilities": map[string]any{
			"fs":       map[string]bool{"readTextFile": false, "writeTextFile": false},
			"terminal": false,
		},
		"clientInfo": map[string]any{
			"name": "ryoku-rashin", "title": "Ryoku Rashin", "version": "1",
		},
	})
	if err != nil {
		return err
	}
	c.applyInitResult(res)
	return c.openSession("session/new", map[string]any{"cwd": vault, "mcpServers": prowlMCPServers()})
}

// applyInitResult records the negotiated protocol version and the agent's
// optional capabilities from the initialize response.
func (c *acpConn) applyInitResult(res json.RawMessage) {
	var out struct {
		ProtocolVersion int `json:"protocolVersion"`
		AgentCapabilities struct {
			LoadSession        bool `json:"loadSession"`
			PromptCapabilities struct {
				Image bool `json:"image"`
			} `json:"promptCapabilities"`
		} `json:"agentCapabilities"`
	}
	if json.Unmarshal(res, &out) != nil {
		return
	}
	if out.ProtocolVersion > 0 {
		c.protoVersion = out.ProtocolVersion
	}
	c.loadSession = out.AgentCapabilities.LoadSession
	c.promptImages = out.AgentCapabilities.PromptCapabilities.Image
}

// openSession issues new/load and installs the returned session id.
func (c *acpConn) openSession(method string, params map[string]any) error {
	res, err := c.request(method, params)
	if err != nil {
		return err
	}
	var out sessionResult
	if err := json.Unmarshal(res, &out); err != nil || out.SessionID == "" {
		return errors.New(method + ": no sessionId")
	}
	c.mu.Lock()
	c.sessionID = out.SessionID
	c.mu.Unlock()
	c.emitModels(res)
	c.reconcileModel(res, method)
	return nil
}

// NewSession abandons the current session for a fresh one in the vault.
func (c *acpConn) NewSession() error {
	return c.openSession("session/new", map[string]any{"cwd": c.vault, "mcpServers": prowlMCPServers()})
}

// LoadSession switches to a stored session; hermes replays its transcript as
// session/update notifications before the response arrives.
func (c *acpConn) LoadSession(id string) error {
	if !c.loadSession {
		return errors.New("this agent does not support loading past sessions")
	}
	c.emit(AcpEvent{Type: "replay_start"})
	err := c.openSession("session/load", map[string]any{
		"sessionId": id, "cwd": c.vault, "mcpServers": prowlMCPServers(),
	})
	c.emit(AcpEvent{Type: "replay_end"})
	return err
}

// ListSessions fetches stored session metadata over ACP.
func (c *acpConn) ListSessions() []SessionMeta {
	res, err := c.request("session/list", map[string]any{})
	if err != nil {
		return nil
	}
	var out struct {
		Sessions []struct {
			SessionID string `json:"sessionId"`
			Title     string `json:"title"`
			Cwd       string `json:"cwd"`
			UpdatedAt string `json:"updatedAt"`
		} `json:"sessions"`
	}
	if json.Unmarshal(res, &out) != nil {
		return nil
	}
	list := make([]SessionMeta, 0, len(out.Sessions))
	for _, s := range out.Sessions {
		list = append(list, SessionMeta{ID: s.SessionID, Title: cleanTitle(s.Title), Cwd: s.Cwd, UpdatedAt: s.UpdatedAt})
	}
	return list
}

// cleanTitle drops a session title that is only the injected identity preamble;
// hermes occasionally titles a fresh session from the whole first prompt.
func cleanTitle(t string) string {
	if len(t) >= 8 && t[:8] == "[system:" {
		return ""
	}
	return t
}

// stripIdentityPreamble removes the injected Needle identity from a replayed
// user message, so a loaded session shows the question the user actually typed
// (hermes stores the full prompt, preamble and all, and replays it verbatim).
func stripIdentityPreamble(s string) string {
	if len(s) < 8 || s[:8] != "[system:" {
		return s
	}
	for i := 0; i+1 < len(s); i++ {
		if s[i] == ']' && s[i+1] == ' ' {
			return s[i+2:]
		}
	}
	return s
}

// SetModel switches the session's model.
func (c *acpConn) SetModel(modelID string) error {
	c.mu.Lock()
	sid := c.sessionID
	c.mu.Unlock()
	_, err := c.request("session/set_model", map[string]any{
		"sessionId": sid, "modelId": modelID,
	})
	return err
}

// PromptImage is one attached image: raw base64 plus its mime type.
type PromptImage struct {
	Data     string `json:"data"`
	MimeType string `json:"mimeType"`
}

// Prompt runs one user turn; the turn_end event carries the stop reason.
// Images ride along as ACP image content blocks (base64 required by schema).
func (c *acpConn) Prompt(text string, images []PromptImage) {
	blocks := make([]map[string]any, 0, 1+len(images))
	if text != "" {
		blocks = append(blocks, map[string]any{"type": "text", "text": text})
	}
	// Only attach images when the agent advertised image prompt support; a
	// text-only agent would otherwise reject the whole turn.
	if c.promptImages {
		for _, im := range images {
			blocks = append(blocks, map[string]any{
				"type": "image", "data": im.Data, "mimeType": im.MimeType,
			})
		}
	}
	if len(blocks) == 0 {
		return
	}
	go func() {
		// A freshly (re)spawned session may still be running Initialize; wait
		// for its id so a prompt sent right after a respawn is not lost — an
		// empty-session prompt fails and would kill the new session, cascading
		// every later send into the same death.
		sid := c.waitSession(15 * time.Second)
		if sid == "" {
			c.emit(AcpEvent{Type: "state", State: "dead", Err: "session not ready"})
			return
		}
		res, err := c.request("session/prompt", map[string]any{
			"sessionId": sid,
			"prompt":    blocks,
		})
		if err != nil {
			c.emit(AcpEvent{Type: "state", State: "dead", Err: err.Error()})
			return
		}
		var out struct {
			StopReason string `json:"stopReason"`
			Usage      *struct {
				TotalTokens int `json:"totalTokens"`
			} `json:"usage"`
		}
		_ = json.Unmarshal(res, &out)
		c.emit(AcpEvent{Type: "turn_end", StopReason: out.StopReason})
	}()
}

// waitSession blocks until the session id is set (Initialize done), the conn
// closes, or the timeout elapses; returns "" if no id ever arrives.
func (c *acpConn) waitSession(timeout time.Duration) string {
	deadline := time.Now().Add(timeout)
	for {
		c.mu.Lock()
		sid, closed := c.sessionID, c.closed
		c.mu.Unlock()
		if sid != "" || closed || time.Now().After(deadline) {
			return sid
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func (c *acpConn) Cancel() {
	c.mu.Lock()
	sid := c.sessionID
	c.mu.Unlock()
	c.notify("session/cancel", map[string]string{"sessionId": sid})
}

// RespondPermission answers an inbound session/request_permission request.
func (c *acpConn) RespondPermission(requestID int64, optionID string) {
	c.mu.Lock()
	if c.answeredPerms[requestID] {
		c.mu.Unlock()
		return
	}
	c.answeredPerms[requestID] = true
	c.mu.Unlock()
	outcome := map[string]any{"outcome": "cancelled"}
	if optionID != "" {
		outcome = map[string]any{"outcome": "selected", "optionId": optionID}
	}
	c.respond(requestID, map[string]any{"outcome": outcome})
}

func (c *acpConn) Close() {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return
	}
	c.closed = true
	for id, ch := range c.pending {
		close(ch)
		delete(c.pending, id)
	}
	c.mu.Unlock()
	if c.closer != nil {
		_ = c.closer.Close()
	}
}

func (c *acpConn) emit(ev AcpEvent) {
	select {
	case c.events <- ev:
	default: // a stalled dashboard must not wedge the agent
	}
}

func (c *acpConn) readLoop(out io.Reader) {
	sc := bufio.NewScanner(out)
	sc.Buffer(make([]byte, 64*1024), 16*1024*1024)
	for sc.Scan() {
		line := sc.Bytes()
		if len(line) == 0 {
			continue
		}
		var msg rpcMsg
		if json.Unmarshal(line, &msg) != nil {
			continue
		}
		switch {
		case msg.ID != nil && msg.Method != "":
			c.handleAgentRequest(msg)
		case msg.ID != nil:
			c.mu.Lock()
			ch, ok := c.pending[*msg.ID]
			if ok {
				delete(c.pending, *msg.ID)
			}
			c.mu.Unlock()
			if ok {
				ch <- msg
			}
		case msg.Method == "session/update":
			c.handleUpdate(msg.Params)
		}
	}
	c.mu.Lock()
	c.closed = true
	for id, ch := range c.pending {
		close(ch)
		delete(c.pending, id)
	}
	c.mu.Unlock()
	c.emit(AcpEvent{Type: "state", State: "dead"})
	close(c.events)
}

func (c *acpConn) handleAgentRequest(msg rpcMsg) {
	switch msg.Method {
	case "session/request_permission":
		var p struct {
			ToolCall struct {
				Title string `json:"title"`
			} `json:"toolCall"`
			Options []struct {
				OptionID string `json:"optionId"`
				Name     string `json:"name"`
				Kind     string `json:"kind"`
			} `json:"options"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		opts := make([]PermOption, 0, len(p.Options))
		for _, o := range p.Options {
			opts = append(opts, PermOption{ID: o.OptionID, Name: o.Name, Kind: o.Kind})
		}
		c.emit(AcpEvent{
			Type:      "permission",
			RequestID: fmt.Sprint(*msg.ID),
			PermTitle: p.ToolCall.Title,
			Options:   opts,
		})
	default:
		// Unknown inbound request: JSON-RPC method-not-found keeps the child sane.
		id := *msg.ID
		_ = c.send(rpcMsg{JSONRPC: "2.0", ID: &id, Error: &rpcError{Code: -32601, Message: "method not found"}})
	}
}

func (c *acpConn) handleUpdate(params json.RawMessage) {
	var p struct {
		Update struct {
			SessionUpdate string `json:"sessionUpdate"`
			Content       struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
			ToolCallID string `json:"toolCallId"`
			Title      string `json:"title"`
			Kind       string `json:"kind"`
			Status     string `json:"status"`
			// available_commands_update
			AvailableCommands []struct {
				Name        string `json:"name"`
				Description string `json:"description"`
				Input       *struct {
					Hint string `json:"hint"`
				} `json:"input"`
			} `json:"availableCommands"`
			// usage_update
			Size int `json:"size"`
			Used int `json:"used"`
			// session_info_update reuses Title; UpdatedAt unused for now.
		} `json:"update"`
		SessionID string `json:"sessionId"`
	}
	if json.Unmarshal(params, &p) != nil {
		return
	}
	u := p.Update
	switch u.SessionUpdate {
	case "agent_message_chunk":
		c.emit(AcpEvent{Type: "agent_text", Text: u.Content.Text})
	case "agent_thought_chunk":
		c.emit(AcpEvent{Type: "agent_thought", Text: u.Content.Text})
	case "user_message_chunk":
		c.emit(AcpEvent{Type: "user_text", Text: stripIdentityPreamble(u.Content.Text)})
	case "tool_call", "tool_call_update":
		status := u.Status
		if status == "" {
			status = "pending"
		}
		c.emit(AcpEvent{
			Type: "tool", ToolID: u.ToolCallID, ToolTitle: u.Title,
			ToolKind: u.Kind, ToolStatus: status,
		})
	case "available_commands_update":
		cmds := make([]CommandInfo, 0, len(u.AvailableCommands))
		for _, cm := range u.AvailableCommands {
			hint := ""
			if cm.Input != nil {
				hint = cm.Input.Hint
			}
			cmds = append(cmds, CommandInfo{Name: cm.Name, Description: cm.Description, Hint: hint})
		}
		c.emit(AcpEvent{Type: "commands", Commands: cmds})
	case "usage_update":
		c.emit(AcpEvent{Type: "usage", UsageSize: u.Size, UsageUsed: u.Used})
	case "session_info_update":
		c.emit(AcpEvent{Type: "session_info", SessionID: p.SessionID, SessionTitle: cleanTitle(u.Title)})
	}
}

// startACP spawns the configured chat agent's ACP command with the vault as its
// working directory. Hermes is the recommended default; resolveChatBackend
// falls back to it when a chosen agent's adapter is absent.
func startACP(vault string) (*acpConn, error) {
	b, ok := resolveChatBackend(LoadConfig())
	if !ok {
		return nil, errors.New("no chat agent available; install Hermes (recommended) or a supported ACP agent")
	}
	stamp := hermesConfigStamp()
	cmd := exec.Command(b.Argv[0], b.Argv[1:]...)
	cmd.Dir = vault
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	cmd.Stderr = nil // hermes logs to stderr; silence rather than corrupt ndjson
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	c := newACPConn(stdin, stdout, stdin)
	c.configStamp = stamp
	c.agentName = b.Name
	go func() { _ = cmd.Wait() }()
	return c, nil
}
