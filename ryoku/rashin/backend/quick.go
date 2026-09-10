package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// quick.go is the fast lane for launcher asks: a fabric-style pattern (one
// terse system prompt + the vault's generated maps) sent as a direct
// chat-completions call on the same model connection hermes is configured
// with. No Python spawn, no full agent: most questions come back in a second
// or two. The model may call a small set of read-only Go tools (quicktools.go)
// for live state; anything heavier escalates to the real hermes session (the
// model answers a sentinel instead).

const toolsSentinel = "TOOLS_REQUIRED"

// maxToolRounds bounds the fast-lane agent loop so a quick ask stays quick.
const maxToolRounds = 4

const quickPattern = `You are Rashin, the resident agent of this Ryoku (Arch Linux, Hyprland) machine, answering a quick ask from the launcher.

You have read-only tools for live state: system_query (packages, updates, service, processes, disk, kernel, gpu, network), read_file, list_dir, search_code (the Ryoku source), and fetch_url (public web pages). Use them when the map below is not enough, then answer.

Rules:
- Reply with just the answer: one or two sentences, or a tight list. No preamble, no follow-up questions, no markdown headers.
- The machine map below is current; prefer it and your tools over guessing.
- Only escalate when the request needs something your tools cannot do: generating or editing files or images, an interactive browser, running a hermes skill, or any action that changes the system. In that case reply with exactly TOOLS_REQUIRED and nothing else.`

// quickTarget is a resolved direct model connection.
type quickTarget struct {
	BaseURL string
	Key     string
	Model   string
	Label   string // provider:model for logs and the dashboard
}

// quickProviders maps a provider id to its openai-compatible endpoint and the
// env var holding its key. The user picks one with `ryoku-rashin backend`, or
// it is derived from hermes's own provider.
var quickProviders = map[string]struct {
	base   string
	keyEnv string
}{
	"openrouter": {"https://openrouter.ai/api/v1", "OPENROUTER_API_KEY"},
	"openai":     {"https://api.openai.com/v1", "OPENAI_API_KEY"},
	"groq":       {"https://api.groq.com/openai/v1", "GROQ_API_KEY"},
	"deepseek":   {"https://api.deepseek.com/v1", "DEEPSEEK_API_KEY"},
	"mistral":    {"https://api.mistral.ai/v1", "MISTRAL_API_KEY"},
	"together":   {"https://api.together.xyz/v1", "TOGETHER_API_KEY"},
	"xai":        {"https://api.x.ai/v1", "XAI_API_KEY"},
	"cerebras":   {"https://api.cerebras.ai/v1", "CEREBRAS_API_KEY"},
	"ollama":     {"http://127.0.0.1:11434/v1", "OLLAMA_API_KEY"},
	"local":      {"http://127.0.0.1:8080/v1", "LOCAL_API_KEY"},
}

// providerIDs lists the known providers, sorted, for the CLI and the picker.
func providerIDs() []string {
	ids := make([]string, 0, len(quickProviders))
	for id := range quickProviders {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

// readyProviders lists providers usable right now: a key is present, or the
// endpoint is keyless (local). The picker dims the rest.
func readyProviders() []string {
	var out []string
	for _, id := range providerIDs() {
		p := quickProviders[id]
		if isLocalURL(p.base) || envValue(p.keyEnv) != "" {
			out = append(out, id)
		}
	}
	return out
}

// rashinEnvPath is rashin's own key file, next to its config. Keys here are
// not shared with hermes, so the assistant's backend is not hermes-locked.
func rashinEnvPath() string {
	return filepath.Join(filepath.Dir(ConfigPath()), "rashin.env")
}

// envValue reads one key for the fast lane. Process env wins, then rashin's own
// env file, then hermes's .env for back-compat. Empty key or nothing found -> "".
func envValue(key string) string {
	if key == "" {
		return ""
	}
	if v := os.Getenv(key); v != "" {
		return v
	}
	for _, p := range []string{rashinEnvPath(), filepath.Join(home(), ".hermes", ".env")} {
		if v := envFileValue(p, key); v != "" {
			return v
		}
	}
	return ""
}

// envFileValue reads KEY=value from a dotenv-style file (quotes trimmed).
func envFileValue(path, key string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "#") {
			continue
		}
		if v, ok := strings.CutPrefix(line, key+"="); ok {
			return strings.Trim(strings.TrimSpace(v), `"'`)
		}
	}
	return ""
}

// isLocalURL: keyless endpoints (ollama and friends) are fine on loopback.
func isLocalURL(u string) bool {
	return strings.Contains(u, "127.0.0.1") || strings.Contains(u, "localhost")
}

// resolveQuickTarget picks the fast lane's model connection: an explicit
// rashin.json quick override (provider, or a raw baseUrl) first, else hermes's
// own configured provider when it speaks plain chat-completions. OAuth backends
// (openai-codex) and native anthropic cannot be called directly, so they report
// unavailable and asks take the session lane.
func resolveQuickTarget(cfg Config) (quickTarget, error) {
	provider, model, _ := hermesModel()
	if cfg.Quick.Provider != "" {
		provider = cfg.Quick.Provider
	}
	// Track the remembered session model so the terminal fast lane defaults to
	// the same model as the sidebar and dashboard; an explicit Quick.Model in
	// the rashin config still overrides.
	if saved := savedSessionModel(); saved != "" {
		model = saved
		if i := strings.IndexByte(saved, ':'); i >= 0 {
			model = saved[i+1:]
		}
	}

	t := quickTarget{Model: cfg.Quick.Model, BaseURL: cfg.Quick.BaseURL}
	if t.Model == "" {
		t.Model = model
	}
	keyEnv := cfg.Quick.KeyEnv

	if t.BaseURL == "" {
		if p, ok := quickProviders[provider]; ok {
			t.BaseURL = p.base
			if keyEnv == "" {
				keyEnv = p.keyEnv
			}
		}
	}
	if t.BaseURL == "" {
		return t, fmt.Errorf("provider %q has no direct endpoint; quick asks use the hermes session", provider)
	}
	if strings.Contains(t.BaseURL, "chatgpt.com") || strings.Contains(t.BaseURL, "anthropic.com") {
		return t, fmt.Errorf("provider %q is not directly callable; quick asks use the hermes session", provider)
	}
	if t.Model == "" {
		return t, fmt.Errorf("no model configured")
	}
	t.Key = envValue(keyEnv)
	if t.Key == "" && !isLocalURL(t.BaseURL) {
		return t, fmt.Errorf("no API key for %s (set %s in ~/.config/ryoku/rashin.env); quick asks use the hermes session", provider, keyEnv)
	}
	t.Label = provider + ":" + t.Model
	if provider == "" && cfg.Quick.Model != "" {
		t.Label = "quick:" + t.Model
	}
	return t, nil
}

// vaultQuickContext inlines the generated maps (fence bodies only) as the
// pattern's knowledge. Small by construction; capped defensively.
func vaultQuickContext() string {
	var b strings.Builder
	for _, name := range []string{"system.md", "desktop.md", "user.md", "habits.md"} {
		raw, err := ReadVaultFile(name)
		if err != nil {
			continue
		}
		body := string(raw)
		if bi := strings.Index(body, vaultFenceBegin); bi >= 0 {
			if ei := strings.Index(body, vaultFenceEnd); ei > bi {
				body = body[bi+len(vaultFenceBegin) : ei]
			}
		}
		body = strings.TrimSpace(body)
		if len(body) > 8*1024 {
			body = body[:8*1024]
		}
		fmt.Fprintf(&b, "## %s\n%s\n\n", name, body)
	}
	return b.String()
}

// chatMessage is one turn in the fast-lane conversation.
type chatMessage struct {
	Role       string     `json:"role"`
	Content    string     `json:"content"`
	ToolCalls  []toolCall `json:"tool_calls,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
}

type toolCall struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Function struct {
		Name      string `json:"name"`
		Arguments string `json:"arguments"`
	} `json:"function"`
}

// laneSpec parameterizes the fast-lane agent loop: the quick (launcher) and
// terminal lanes share the loop, the streaming, and the escalation sentinel,
// differing in persona, toolset, and prior turns.
type laneSpec struct {
	system  string                                              // full system prompt
	tools   []map[string]any                                    // advertised schemas
	exec    func(ctx context.Context, name, args string) string // tool executor
	history []chatMessage                                       // prior exchange (continuation)
}

func quickSpec() laneSpec {
	return laneSpec{
		system: quickPattern + "\n\n# The machine map\n\n" + vaultQuickContext(),
		tools:  quickToolSchemas(),
		exec:   execQuickTool,
	}
}

// quickComplete runs the launcher fast lane; see laneComplete.
func quickComplete(ctx context.Context, t quickTarget, question string,
	onDelta func(string), onTool func(id, title, status string)) (string, error) {
	return laneComplete(ctx, t, quickSpec(), question, onDelta, onTool)
}

// laneComplete runs the fast-lane agent loop: up to maxToolRounds of tool
// calls, then the final answer. onDelta streams the answer text (after the
// sentinel is ruled out); onTool fires as each tool runs so the launcher,
// terminal, and dashboard can show what it is doing.
func laneComplete(ctx context.Context, t quickTarget, spec laneSpec, question string,
	onDelta func(string), onTool func(id, title, status string)) (string, error) {
	msgs := make([]chatMessage, 0, len(spec.history)+2)
	msgs = append(msgs, chatMessage{Role: "system", Content: spec.system})
	msgs = append(msgs, spec.history...)
	msgs = append(msgs, chatMessage{Role: "user", Content: question})
	for round := 0; round <= maxToolRounds; round++ {
		// The last round forbids tools so the model must answer.
		tools := spec.tools
		if round == maxToolRounds {
			tools = nil
		}
		text, calls, err := quickRound(ctx, t, msgs, tools, onDelta)
		if err != nil {
			return "", err
		}
		if len(calls) == 0 {
			out := strings.TrimSpace(text)
			if strings.HasPrefix(out, toolsSentinel) {
				return "", errNeedsTools
			}
			if out == "" {
				return "", fmt.Errorf("empty answer")
			}
			return out, nil
		}
		// Record the assistant's tool-call turn, then each tool result.
		msgs = append(msgs, chatMessage{Role: "assistant", Content: text, ToolCalls: calls})
		for _, c := range calls {
			if onTool != nil {
				onTool(c.ID, toolTitle(c), "in_progress")
			}
			result := spec.exec(ctx, c.Function.Name, c.Function.Arguments)
			if onTool != nil {
				onTool(c.ID, toolTitle(c), "completed")
			}
			msgs = append(msgs, chatMessage{Role: "tool", ToolCallID: c.ID, Content: result})
		}
	}
	return "", fmt.Errorf("tool loop did not converge")
}

func toolTitle(c toolCall) string {
	var a struct {
		Topic, Arg, Path, Query, URL string
	}
	_ = json.Unmarshal([]byte(c.Function.Arguments), &a)
	switch c.Function.Name {
	case "system_query":
		if a.Arg != "" {
			return "checking " + a.Topic + ": " + a.Arg
		}
		return "checking " + a.Topic
	case "read_file":
		return "reading " + a.Path
	case "list_dir":
		return "listing " + a.Path
	case "search_code":
		return "searching code: " + a.Query
	case "propose":
		return "shaping the commands"
	case "fetch_url":
		return "fetching " + a.URL
	default:
		return c.Function.Name
	}
}

// quickRound performs one streaming model call, assembling both the content
// (streamed via onDelta, head held until the sentinel is ruled out) and any
// tool_calls (fragmented across deltas by index). Streaming keeps the answer
// fading in even though the loop can also call tools.
func quickRound(ctx context.Context, t quickTarget, msgs []chatMessage, tools []map[string]any,
	onDelta func(string)) (string, []toolCall, error) {
	payload := map[string]any{
		"model":    t.Model,
		"stream":   true,
		"messages": msgs,
	}
	if len(tools) > 0 {
		payload["tools"] = tools
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return "", nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		strings.TrimRight(t.BaseURL, "/")+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if t.Key != "" {
		req.Header.Set("Authorization", "Bearer "+t.Key)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		msg, _ := readCapped(resp, 300)
		return "", nil, fmt.Errorf("model endpoint %d: %s", resp.StatusCode, msg)
	}

	var answer strings.Builder
	held := true
	byIndex := map[int]*toolCall{}
	var order []int
	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 64*1024), 4<<20)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "[DONE]" {
			break
		}
		var chunk struct {
			Choices []struct {
				Delta struct {
					Content   string `json:"content"`
					ToolCalls []struct {
						Index    int    `json:"index"`
						ID       string `json:"id"`
						Function struct {
							Name      string `json:"name"`
							Arguments string `json:"arguments"`
						} `json:"function"`
					} `json:"tool_calls"`
				} `json:"delta"`
			} `json:"choices"`
		}
		if json.Unmarshal([]byte(data), &chunk) != nil || len(chunk.Choices) == 0 {
			continue
		}
		d := chunk.Choices[0].Delta
		for _, tc := range d.ToolCalls {
			cur, ok := byIndex[tc.Index]
			if !ok {
				cur = &toolCall{Type: "function"}
				byIndex[tc.Index] = cur
				order = append(order, tc.Index)
			}
			if tc.ID != "" {
				cur.ID = tc.ID
			}
			if tc.Function.Name != "" {
				cur.Function.Name = tc.Function.Name
			}
			cur.Function.Arguments += tc.Function.Arguments
		}
		if d.Content == "" {
			continue
		}
		answer.WriteString(d.Content)
		if held {
			head := strings.TrimSpace(answer.String())
			if strings.HasPrefix(toolsSentinel, head) || strings.HasPrefix(head, toolsSentinel) {
				continue
			}
			held = false
			if onDelta != nil {
				onDelta(answer.String())
			}
			continue
		}
		if onDelta != nil {
			onDelta(d.Content)
		}
	}
	var calls []toolCall
	for _, idx := range order {
		c := byIndex[idx]
		if c.Function.Name != "" {
			if c.ID == "" {
				c.ID = fmt.Sprintf("call_%d", idx)
			}
			calls = append(calls, *c)
		}
	}
	return strings.TrimSpace(answer.String()), calls, nil
}

var errNeedsTools = fmt.Errorf("needs tools")

func readCapped(resp *http.Response, n int) (string, error) {
	buf := make([]byte, n)
	m, err := resp.Body.Read(buf)
	return strings.TrimSpace(string(buf[:m])), err
}

// warmHermes spawns the shared session at daemon start, so neither the
// dashboard's first message nor a session-lane ask pays the Python cold
// start. Costs hermes's resident memory from boot; that is the point of an
// enabled agent OS.
func (h *chatHub) warm() {
	if !HermesStatus().Configured {
		return
	}
	h.mu.Lock()
	h.ensureConnLocked()
	h.mu.Unlock()
}

// quickTime bounds the fast lane; escalation needs time for real model calls.
const quickTimeout = 75 * time.Second
