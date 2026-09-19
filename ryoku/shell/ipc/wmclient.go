package main

import (
	"context"
	"encoding/json"
	"reflect"
	"time"

	wm "ryoku-wm"
)

// The daemon reaches the compositor only through d.wmc and the state its watcher
// keeps warm. activeMonitor resolves on the keybind hot path, so it is a mutex
// read with no fork.

func (d *daemon) startWM() {
	d.wmTopic = d.registerTopic("wm")
	d.publishWM()
	d.registerCall("wm.act", func(raw json.RawMessage) (any, error) {
		var a struct {
			Action string   `json:"action"`
			Args   []string `json:"args"`
		}
		if err := json.Unmarshal(raw, &a); err != nil {
			return nil, err
		}
		if err := d.wmc.Act(wm.Action(a.Action), a.Args...); err != nil {
			return nil, err
		}
		return map[string]any{"ok": true}, nil
	})
	go d.watchWindowManager()
}

func (d *daemon) activeMonitor() string {
	d.wmMu.Lock()
	defer d.wmMu.Unlock()
	return d.activeMon
}

// onWMFrame folds one watch frame into the cache and republishes the wm topic.
// A FrameFocus with an empty output clears the cached focus.
func (d *daemon) onWMFrame(f wm.Frame) {
	d.wmMu.Lock()
	changed := false
	switch f.Kind {
	case wm.FrameFocus:
		changed = !reflect.DeepEqual(d.activeMon, f.FocusedOutput)
		d.activeMon = f.FocusedOutput
	case wm.FrameOutputs:
		changed = !reflect.DeepEqual(d.wmOutputs, f.Outputs)
		d.wmOutputs = f.Outputs
	case wm.FrameWorkspaces:
		changed = !reflect.DeepEqual(d.wmWorkspaces, f.Workspaces)
		d.wmWorkspaces = f.Workspaces
	case wm.FrameWindows:
		changed = !reflect.DeepEqual(d.wmWindows, f.Windows)
		d.wmWindows = f.Windows
	case wm.FrameReady:
		changed = !d.wmReady
		d.wmReady = true
	}
	d.wmMu.Unlock()

	if !changed {
		return
	}

	switch f.Kind {
	case wm.FrameFocus, wm.FrameOutputs, wm.FrameWorkspaces:
		select {
		case d.widgetSig <- struct{}{}:
		default:
		}
	}
	d.publishWM()
}

// wmTopicFrame carries caps and state in one coalesced frame so a QML consumer
// needs a single subscription. Every capability is present with an explicit
// boolean and the lists are never null, so a consumer never tells absent from
// false.
type wmTopicFrame struct {
	Provider       string                 `json:"provider"`
	WorkspaceModel string                 `json:"workspaceModel"`
	Ready          bool                   `json:"ready"`
	Caps           map[wm.Capability]bool `json:"caps"`
	FocusedOutput  string                 `json:"focusedOutput"`
	Outputs        []wm.Output            `json:"outputs"`
	Workspaces     []wm.Workspace         `json:"workspaces"`
	Windows        []wm.Window            `json:"windows"`
	ConfigFiles    []string               `json:"configFiles"`
}

func (d *daemon) publishWM() {
	if d.wmTopic == nil {
		return
	}
	caps, _ := d.wmc.Caps()
	all := wm.All()
	frame := wmTopicFrame{
		Provider:       caps.Name,
		WorkspaceModel: string(caps.WorkspaceModel),
		Caps:           make(map[wm.Capability]bool, len(all)),
		Outputs:        []wm.Output{},
		Workspaces:     []wm.Workspace{},
		Windows:        []wm.Window{},
		ConfigFiles:    []string{},
	}
	for _, c := range all {
		frame.Caps[c] = caps.Has(c)
	}
	if caps.ConfigFiles != nil {
		frame.ConfigFiles = caps.ConfigFiles
	}
	d.wmMu.Lock()
	frame.Ready = d.wmReady
	frame.FocusedOutput = d.activeMon
	if d.wmOutputs != nil {
		frame.Outputs = d.wmOutputs
	}
	if d.wmWorkspaces != nil {
		frame.Workspaces = d.wmWorkspaces
	}
	if d.wmWindows != nil {
		frame.Windows = d.wmWindows
	}
	d.wmMu.Unlock()
	if b, err := json.Marshal(frame); err == nil {
		d.wmTopic.publish(b)
	}
}

// watchWindowManager supervises the provider's watch stream for the daemon's
// life, reconnecting with backoff so a compositor restart never leaves the cache
// permanently cold. Backoff resets once a stream has delivered a frame.
func (d *daemon) watchWindowManager() {
	const minBackoff = 150 * time.Millisecond
	const maxBackoff = 5 * time.Second
	backoff := minBackoff
	for {
		select {
		case <-d.quit:
			return
		default:
		}

		ctx, cancel := context.WithCancel(context.Background())
		go func() {
			select {
			case <-d.quit:
				cancel()
			case <-ctx.Done():
			}
		}()
		gotFrame := false
		_ = d.wmc.Watch(ctx, func(f wm.Frame) {
			gotFrame = true
			d.onWMFrame(f)
		})
		cancel()

		select {
		case <-d.quit:
			return
		default:
		}
		if gotFrame {
			backoff = minBackoff
		}
		select {
		case <-d.quit:
			return
		case <-time.After(backoff):
		}
		backoff = capDur(backoff*2, maxBackoff)
	}
}
