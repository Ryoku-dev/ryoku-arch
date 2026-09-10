package main

import (
	"bufio"
	"encoding/json"
	"io"
	"testing"
	"time"
)

// fakeAgent scripts the other end of the ACP wire: it reads client lines from
// r and writes agent lines to w, mimicking hermes acp closely enough to prove
// the handshake, streaming translation, permission round trip, and cancel.
type fakeAgent struct {
	lines chan rpcMsg
	w     io.Writer
	t     *testing.T
}

// read pops the next client frame. A dedicated goroutine drains the pipe so
// client writes never block on the synchronous io.Pipe (a real hermes stdin
// is OS-buffered; the fake must not be stricter than the real thing).
func (f *fakeAgent) read() rpcMsg {
	f.t.Helper()
	select {
	case m, ok := <-f.lines:
		if !ok {
			f.t.Fatal("fake agent: client closed early")
		}
		return m
	case <-time.After(3 * time.Second):
		f.t.Fatal("fake agent: timeout waiting for client frame")
	}
	return rpcMsg{}
}

func (f *fakeAgent) write(v any) {
	f.t.Helper()
	b, _ := json.Marshal(v)
	if _, err := f.w.Write(append(b, '\n')); err != nil {
		f.t.Fatalf("fake agent write: %v", err)
	}
}

func (f *fakeAgent) respond(id int64, result any) {
	r, _ := json.Marshal(result)
	f.write(rpcMsg{JSONRPC: "2.0", ID: &id, Result: r})
}

func (f *fakeAgent) update(session string, update map[string]any) {
	p, _ := json.Marshal(map[string]any{"sessionId": session, "update": update})
	f.write(rpcMsg{JSONRPC: "2.0", Method: "session/update", Params: p})
}

func newTestPair(t *testing.T) (*acpConn, *fakeAgent) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	cr, cw := io.Pipe() // client -> agent
	ar, aw := io.Pipe() // agent -> client
	conn := newACPConn(cw, ar, cw)
	fa := &fakeAgent{lines: make(chan rpcMsg, 64), w: aw, t: t}
	go func() {
		sc := bufio.NewScanner(cr)
		for sc.Scan() {
			var m rpcMsg
			if json.Unmarshal(sc.Bytes(), &m) == nil {
				fa.lines <- m
			}
		}
		close(fa.lines)
	}()
	return conn, fa
}

func expectEvent(t *testing.T, ch <-chan AcpEvent, typ string) AcpEvent {
	t.Helper()
	select {
	case ev, ok := <-ch:
		if !ok {
			t.Fatalf("event channel closed waiting for %s", typ)
		}
		if ev.Type != typ {
			t.Fatalf("got event %q, want %q (%+v)", ev.Type, typ, ev)
		}
		return ev
	case <-time.After(3 * time.Second):
		t.Fatalf("timeout waiting for %s event", typ)
	}
	return AcpEvent{}
}

func TestACPHandshakePromptStreamPermissionCancel(t *testing.T) {
	conn, fa := newTestPair(t)
	defer conn.Close()

	done := make(chan error, 1)
	go func() { done <- conn.Initialize("/tmp/vault") }()

	init := fa.read()
	if init.Method != "initialize" {
		t.Fatalf("first request %q, want initialize", init.Method)
	}
	fa.respond(*init.ID, map[string]any{"protocolVersion": 1})

	newSess := fa.read()
	if newSess.Method != "session/new" {
		t.Fatalf("second request %q, want session/new", newSess.Method)
	}
	var np struct {
		Cwd string `json:"cwd"`
	}
	_ = json.Unmarshal(newSess.Params, &np)
	if np.Cwd != "/tmp/vault" {
		t.Fatalf("session cwd %q, want /tmp/vault", np.Cwd)
	}
	fa.respond(*newSess.ID, map[string]any{"sessionId": "s1"})

	if err := <-done; err != nil {
		t.Fatalf("Initialize: %v", err)
	}

	// One user turn with streaming chunks and a tool call.
	conn.Prompt("hello", nil)
	prompt := fa.read()
	if prompt.Method != "session/prompt" {
		t.Fatalf("got %q, want session/prompt", prompt.Method)
	}
	fa.update("s1", map[string]any{
		"sessionUpdate": "agent_message_chunk",
		"content":       map[string]string{"type": "text", "text": "Hi "},
	})
	fa.update("s1", map[string]any{
		"sessionUpdate": "tool_call", "toolCallId": "t1",
		"title": "Reading system.md", "kind": "read", "status": "in_progress",
	})
	fa.update("s1", map[string]any{
		"sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed",
	})

	ev := expectEvent(t, conn.Events(), "agent_text")
	if ev.Text != "Hi " {
		t.Fatalf("chunk text %q", ev.Text)
	}
	ev = expectEvent(t, conn.Events(), "tool")
	if ev.ToolID != "t1" || ev.ToolStatus != "in_progress" {
		t.Fatalf("tool event %+v", ev)
	}
	ev = expectEvent(t, conn.Events(), "tool")
	if ev.ToolStatus != "completed" {
		t.Fatalf("tool update %+v", ev)
	}

	// Permission round trip: agent asks, client answers allow.
	permID := int64(77)
	pp, _ := json.Marshal(map[string]any{
		"sessionId": "s1",
		"toolCall":  map[string]string{"title": "Run ls"},
		"options": []map[string]string{
			{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
			{"optionId": "deny", "name": "Deny", "kind": "reject_once"},
		},
	})
	fa.write(rpcMsg{JSONRPC: "2.0", ID: &permID, Method: "session/request_permission", Params: pp})

	ev = expectEvent(t, conn.Events(), "permission")
	if ev.RequestID != "77" || len(ev.Options) != 2 || ev.PermTitle != "Run ls" {
		t.Fatalf("permission event %+v", ev)
	}
	conn.RespondPermission(77, "allow")
	permResp := fa.read()
	if permResp.ID == nil || *permResp.ID != 77 {
		t.Fatalf("permission response id %+v", permResp.ID)
	}
	var pr struct {
		Outcome struct {
			Outcome  string `json:"outcome"`
			OptionID string `json:"optionId"`
		} `json:"outcome"`
	}
	_ = json.Unmarshal(permResp.Result, &pr)
	if pr.Outcome.Outcome != "selected" || pr.Outcome.OptionID != "allow" {
		t.Fatalf("permission outcome %+v", pr)
	}

	// Turn end.
	fa.respond(*prompt.ID, map[string]any{"stopReason": "end_turn"})
	ev = expectEvent(t, conn.Events(), "turn_end")
	if ev.StopReason != "end_turn" {
		t.Fatalf("stop reason %q", ev.StopReason)
	}

	// Cancel is a notification.
	conn.Cancel()
	cancel := fa.read()
	if cancel.Method != "session/cancel" || cancel.ID != nil {
		t.Fatalf("cancel frame %+v", cancel)
	}
}

func TestACPDeadChildEmitsDeadState(t *testing.T) {
	cr, cw := io.Pipe()
	ar, aw := io.Pipe()
	conn := newACPConn(cw, ar, cw)
	_ = cr
	_ = aw.Close() // child dies immediately

	ev := expectEvent(t, conn.Events(), "state")
	if ev.State != "dead" {
		t.Fatalf("state %q, want dead", ev.State)
	}
}

func TestACPV2ImagesModelsSessions(t *testing.T) {
	conn, fa := newTestPair(t)
	defer conn.Close()

	done := make(chan error, 1)
	go func() { done <- conn.Initialize("/tmp/vault") }()
	init := fa.read()
	fa.respond(*init.ID, map[string]any{"protocolVersion": 1, "agentCapabilities": map[string]any{"loadSession": true, "promptCapabilities": map[string]any{"image": true}}})
	newSess := fa.read()
	fa.respond(*newSess.ID, map[string]any{
		"sessionId": "s1",
		"models": map[string]any{
			"currentModelId": "openai-codex:gpt-5.5",
			"availableModels": []map[string]string{
				{"modelId": "openai-codex:gpt-5.5", "name": "GPT 5.5"},
				{"modelId": "openai-codex:gpt-5.5-mini", "name": "GPT 5.5 mini"},
			},
		},
	})
	if err := <-done; err != nil {
		t.Fatalf("Initialize: %v", err)
	}

	// Models from session/new surface as a models event.
	ev := expectEvent(t, conn.Events(), "models")
	if ev.CurrentModel != "openai-codex:gpt-5.5" || len(ev.Models) != 2 {
		t.Fatalf("models event %+v", ev)
	}

	// Image blocks ride the prompt.
	conn.Prompt("what is this", []PromptImage{{Data: "aGk=", MimeType: "image/png"}})
	prompt := fa.read()
	var pp struct {
		Prompt []map[string]any `json:"prompt"`
	}
	_ = json.Unmarshal(prompt.Params, &pp)
	if len(pp.Prompt) != 2 || pp.Prompt[1]["type"] != "image" || pp.Prompt[1]["mimeType"] != "image/png" {
		t.Fatalf("prompt blocks %+v", pp.Prompt)
	}
	fa.respond(*prompt.ID, map[string]any{"stopReason": "end_turn"})
	expectEvent(t, conn.Events(), "turn_end")

	// available_commands_update and usage_update translate.
	fa.update("s1", map[string]any{
		"sessionUpdate": "available_commands_update",
		"availableCommands": []map[string]any{
			{"name": "help", "description": "List commands"},
			{"name": "model", "description": "Switch model", "input": map[string]string{"hint": "model id"}},
		},
	})
	ev = expectEvent(t, conn.Events(), "commands")
	if len(ev.Commands) != 2 || ev.Commands[1].Hint != "model id" {
		t.Fatalf("commands event %+v", ev)
	}
	fa.update("s1", map[string]any{"sessionUpdate": "usage_update", "size": 200000, "used": 12345})
	ev = expectEvent(t, conn.Events(), "usage")
	if ev.UsageSize != 200000 || ev.UsageUsed != 12345 {
		t.Fatalf("usage event %+v", ev)
	}

	// set_model round trip.
	setDone := make(chan error, 1)
	go func() { setDone <- conn.SetModel("openai-codex:gpt-5.5-mini") }()
	setReq := fa.read()
	if setReq.Method != "session/set_model" {
		t.Fatalf("got %q, want session/set_model", setReq.Method)
	}
	fa.respond(*setReq.ID, map[string]any{})
	if err := <-setDone; err != nil {
		t.Fatalf("SetModel: %v", err)
	}

	// session/list translates to SessionMeta.
	listDone := make(chan []SessionMeta, 1)
	go func() { listDone <- conn.ListSessions() }()
	listReq := fa.read()
	if listReq.Method != "session/list" {
		t.Fatalf("got %q, want session/list", listReq.Method)
	}
	fa.respond(*listReq.ID, map[string]any{
		"sessions": []map[string]string{
			{"sessionId": "old1", "title": "Keybinds", "updatedAt": "2026-07-02T02:00:00Z"},
		},
	})
	sessions := <-listDone
	if len(sessions) != 1 || sessions[0].Title != "Keybinds" {
		t.Fatalf("sessions %+v", sessions)
	}

	// load replays: replay_start, replayed user chunk, replay_end.
	loadDone := make(chan error, 1)
	go func() { loadDone <- conn.LoadSession("old1") }()
	expectEvent(t, conn.Events(), "replay_start")
	loadReq := fa.read()
	if loadReq.Method != "session/load" {
		t.Fatalf("got %q, want session/load", loadReq.Method)
	}
	fa.update("old1", map[string]any{
		"sessionUpdate": "user_message_chunk",
		"content":       map[string]string{"type": "text", "text": "old question"},
	})
	ev = expectEvent(t, conn.Events(), "user_text")
	if ev.Text != "old question" {
		t.Fatalf("user_text %+v", ev)
	}
	fa.respond(*loadReq.ID, map[string]any{"sessionId": "old1"})
	if err := <-loadDone; err != nil {
		t.Fatalf("LoadSession: %v", err)
	}
	expectEvent(t, conn.Events(), "replay_end")
}
