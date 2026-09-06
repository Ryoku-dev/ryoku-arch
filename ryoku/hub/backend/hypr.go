package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// system-level (Hyprland) tweaks the Hub exposes, persisted as one JSON store
// and rendered into one Lua file the live config loads. the store at
// ~/.config/ryoku/hypr.json is the editable truth; settings.lua at
// ~/.config/hypr/ is generated from it and require()d by hyprland.lua after the
// base modules and before user.lua, so settings.lua overrides the shipped
// defaults and a hand-written user.lua still wins over both.
//
// only divergences from the defaults are written, so an untouched setting falls
// through to its base module (and picks up future base improvements) rather
// than being pinned. live edits apply flash-free via `hyprctl eval` (the hl
// API); Save persists + reloads to lock the state in, which also handles the
// removals (a dropped rule or bind) eval can't undo.

// Appearance: general / decoration / animations keywords.
type Appearance struct {
	GapsIn               int     `json:"gapsIn"`
	GapsOut              int     `json:"gapsOut"`
	BorderSize           int     `json:"borderSize"`
	Rounding             int     `json:"rounding"`
	RoundingPower        float64 `json:"roundingPower"`
	ActiveOpacity        float64 `json:"activeOpacity"`
	InactiveOpacity      float64 `json:"inactiveOpacity"`
	DimInactive          bool    `json:"dimInactive"`
	DimStrength          float64 `json:"dimStrength"`
	BlurEnabled          bool    `json:"blurEnabled"`
	BlurSize             int     `json:"blurSize"`
	BlurPasses           int     `json:"blurPasses"`
	BlurXray             bool    `json:"blurXray"`
	BlurVibrancy         float64 `json:"blurVibrancy"`
	BlurNoise            float64 `json:"blurNoise"`
	ShadowEnabled        bool    `json:"shadowEnabled"`
	ShadowRange          int     `json:"shadowRange"`
	ShadowPower          int     `json:"shadowPower"`
	GlowEnabled          bool    `json:"glowEnabled"`
	GlowRange            int     `json:"glowRange"`
	GlowColor            string  `json:"glowColor"`
	Animations           bool    `json:"animations"`
	Layout               string  `json:"layout"`
	ActiveBorder         string  `json:"activeBorder"`
	InactiveBorder       string  `json:"inactiveBorder"`
	ResizeOnBorder       bool    `json:"resizeOnBorder"`
	SnapEnabled          bool    `json:"snapEnabled"`
	WobblyWindows        bool    `json:"wobblyWindows"`
	WindowStyle          string  `json:"windowStyle"`
	AnimatedBorder       bool    `json:"animatedBorder"`
	BorderAngleSpeed     float64 `json:"borderAngleSpeed"`
	FullscreenOpacity    float64 `json:"fullscreenOpacity"`
	DimSpecial           float64 `json:"dimSpecial"`
	DimAround            float64 `json:"dimAround"`
	DimModal             bool    `json:"dimModal"`
	BorderPartOfWindow   bool    `json:"borderPartOfWindow"`
	BlurContrast         float64 `json:"blurContrast"`
	BlurBrightness       float64 `json:"blurBrightness"`
	BlurSpecial          bool    `json:"blurSpecial"`
	BlurPopups           bool    `json:"blurPopups"`
	BlurIgnoreOpacity    bool    `json:"blurIgnoreOpacity"`
	BlurNewOptimizations bool    `json:"blurNewOptimizations"`
	BlurVibrancyDarkness float64 `json:"blurVibrancyDarkness"`
	ShadowSharp          bool    `json:"shadowSharp"`
	ShadowScale          float64 `json:"shadowScale"`
	ShadowColor          string  `json:"shadowColor"`
	ExtendBorderGrab     int     `json:"extendBorderGrab"`
	HoverIconOnBorder    bool    `json:"hoverIconOnBorder"`
	NoFocusFallback      bool    `json:"noFocusFallback"`
	ResizeCorner         int     `json:"resizeCorner"`
	GapsWorkspaces       int     `json:"gapsWorkspaces"`
}

// Dwindle: the dwindle layout keywords the hub exposes on the Look tab while
// that layout is selected. Emitted as a `dwindle = {}` block, diffed against the
// defaults like the appearance leaves.
type Dwindle struct {
	PreserveSplit      bool    `json:"preserveSplit"`
	SmartSplit         bool    `json:"smartSplit"`
	SmartResizing      bool    `json:"smartResizing"`
	DefaultSplitRatio  float64 `json:"defaultSplitRatio"`
	ForceSplit         string  `json:"forceSplit"` // follow | left/top | right/bottom
	UseActiveForSplits bool    `json:"useActiveForSplits"`
}

// Master: the master layout keywords the hub exposes on the Look tab while that
// layout is selected. Emitted as a `master = {}` block.
type Master struct {
	Mfact         float64 `json:"mfact"`
	NewStatus     string  `json:"newStatus"` // master | slave | inherit
	NewOnTop      bool    `json:"newOnTop"`
	Orientation   string  `json:"orientation"` // left | right | top | bottom | center
	SmartResizing bool    `json:"smartResizing"`
}

// Input: the input keyword (keyboard, pointer, touchpad) + the pointer-adjacent
// misc/gestures keys the Input page edits alongside them.
type Input struct {
	KbLayout           string  `json:"kbLayout"`
	KbVariant          string  `json:"kbVariant"`
	KbOptions          string  `json:"kbOptions"`
	NumlockByDefault   bool    `json:"numlockByDefault"`
	FollowMouse        int     `json:"followMouse"`
	Sensitivity        float64 `json:"sensitivity"`
	AccelProfile       string  `json:"accelProfile"`
	LeftHanded         bool    `json:"leftHanded"`
	MouseNaturalScroll bool    `json:"mouseNaturalScroll"`
	MouseScrollFactor  float64 `json:"mouseScrollFactor"`
	MiddleClickPaste   bool    `json:"middleClickPaste"`
	NaturalScroll      bool    `json:"naturalScroll"`
	TapToClick         bool    `json:"tapToClick"`
	TapAndDrag         bool    `json:"tapAndDrag"`
	Clickfinger        bool    `json:"clickfinger"`
	MiddleEmulation    bool    `json:"middleEmulation"`
	TouchScrollFactor  float64 `json:"touchScrollFactor"`
	DisableWhileTyping bool    `json:"disableWhileTyping"`
	RepeatRate         int     `json:"repeatRate"`
	RepeatDelay        int     `json:"repeatDelay"`
	WorkspaceSwipe     bool    `json:"workspaceSwipe"`
	SwipeFingers       int     `json:"swipeFingers"`
	SwipeInvert        bool    `json:"swipeInvert"`
	SwipeCreateNew     bool    `json:"swipeCreateNew"`
	SwipeDistance      int     `json:"swipeDistance"`
}

// Cursor: theme + size + the cursor-section niceties. live = `hyprctl
// setcursor`. persisted as env in settings.lua (so spawned apps see it) + a
// start hook that wins over the base autostart's setcursor (which registers
// earlier).
type Cursor struct {
	Theme           string `json:"theme"`
	Size            int    `json:"size"`
	InactiveTimeout int    `json:"inactiveTimeout"`
	HideOnKeyPress  bool   `json:"hideOnKeyPress"`
}

type EnvVar struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// WindowRule = one user rule: optional class/title match + one action. Action is
// the rule keyword; Value carries its argument where one applies (opacity, size,
// move, workspace).
type WindowRule struct {
	Class  string `json:"class"`
	Title  string `json:"title"`
	Action string `json:"action"`
	Value  string `json:"value"`
}

// LayerRule: target a layer-shell surface by namespace (bar, launcher, notif
// daemon). Action = the rule; Value = the argument for ignorealpha/dimaround.
type LayerRule struct {
	Namespace string `json:"namespace"`
	Action    string `json:"action"`
	Value     string `json:"value"`
}

// AppOverride: per-app appearance overrides. Match by class (and optional
// title); each set field becomes an hl.window_rule prop that beats the global
// decoration for matching windows, so one app can look different without
// touching the global look. Numeric fields use -1 for "inherit"; the toggles
// use "inherit" plus "off" (or "on" for opaque).
type AppOverride struct {
	Class      string  `json:"class"`
	Title      string  `json:"title"`
	Opacity    float64 `json:"opacity"`    // -1 inherit, else 0..1
	Rounding   int     `json:"rounding"`   // -1 inherit, else >= 0
	BorderSize int     `json:"borderSize"` // -1 inherit, else >= 0
	Blur       string  `json:"blur"`       // inherit | off
	Shadow     string  `json:"shadow"`     // inherit | off
	Dim        string  `json:"dim"`        // inherit | off
	Anim       string  `json:"anim"`       // inherit | off
	Opaque     string  `json:"opaque"`     // inherit | on
}

type Autostart struct {
	Command string `json:"command"`
}

// Keybind = a user shortcut. action "exec" runs Value; the dispatcher actions
// (close, fullscreen, togglefloating) take no value.
type Keybind struct {
	Keys    string `json:"keys"`
	Action  string `json:"action"`
	Value   string `json:"value"`
	Release bool   `json:"release,omitempty"`
}

// AnimCurve = a user bezier. P0/P3 fixed at (0,0) and (1,1); only the two
// control points stored. redefining a base name overrides it.
type AnimCurve struct {
	Name string  `json:"name"`
	X0   float64 `json:"x0"`
	Y0   float64 `json:"y0"`
	X1   float64 `json:"x1"`
	Y1   float64 `json:"y1"`
}

// AnimItem: override one animation leaf (windows, fade, workspaces, ...).
type AnimItem struct {
	Leaf    string  `json:"leaf"`
	Enabled bool    `json:"enabled"`
	Speed   float64 `json:"speed"`
	Bezier  string  `json:"bezier"`
	Style   string  `json:"style"`
}

// Anim: per-leaf + per-curve overrides (the global on/off lives in Appearance).
// curves first, items second -- items may reference the curves.
type Anim struct {
	Items  []AnimItem  `json:"items"`
	Curves []AnimCurve `json:"curves"`
}

// Plugins: the optional Hyprland compositor plugins the Hub can enable and
// configure. Each is off by default (so an untouched system generates nothing
// for it and the plugin never loads); enabling one makes genPlugins emit an
// hl.plugin.load of its copy plus its config, the config behind a loaded
// check (luaPluginLoaded) so a missing or ABI-mismatched .so degrades to
// "off", never a config error. Friendly field names here map to upstream
// option keys in pluginBlocks.
type DynamicCursors struct {
	Enabled bool    `json:"enabled"`
	Mode    string  `json:"mode"` // rotate | tilt | stretch
	Shake   bool    `json:"shake"`
	Magnify float64 `json:"magnify"`
}

type Hyprbars struct {
	Enabled  bool `json:"enabled"`
	Height   int  `json:"height"`
	TextSize int  `json:"textSize"`
	Blur     bool `json:"blur"`
	Buttons  bool `json:"buttons"`
}

type Imgborders struct {
	Enabled bool    `json:"enabled"`
	Image   string  `json:"image"`
	Sizes   string  `json:"sizes"`  // "left,right,top,bottom" px
	Insets  string  `json:"insets"` // "left,right,top,bottom" px
	Scale   float64 `json:"scale"`
	Smooth  bool    `json:"smooth"`
	Blur    bool    `json:"blur"`
}

type Hyprglass struct {
	Enabled      bool    `json:"enabled"`
	Preset       string  `json:"preset"` // clear | subtle | high_contrast | glass
	BlurStrength float64 `json:"blurStrength"`
	Opacity      float64 `json:"opacity"`
	Tint         string  `json:"tint"` // RRGGBBAA hex, no leading 0x
	Brightness   float64 `json:"brightness"`
	Theme        string  `json:"theme"` // dark | light
}

type Hyprfocus struct {
	Enabled bool    `json:"enabled"`
	Mode    string  `json:"mode"`    // flash | bounce (plugin: shrink) | slide
	Opacity float64 `json:"opacity"` // fade_opacity, for flash
	Bounce  float64 `json:"bounce"`  // bounce_strength, for bounce
	Slide   float64 `json:"slide"`   // slide_height px, for slide
}

// Hyprscrolling is not a compositor plugin: the scrolling layout moved into
// Hyprland core (0.54+) as the "scrolling" layout, configured under the core
// `scrolling` category. It has no Enabled of its own -- it applies whenever the
// tiling layout is "scrolling" (the Look tab's existing choice). These are its
// tuning knobs, emitted as core config (no plugin load).
type Hyprscrolling struct {
	ColumnWidth float64 `json:"columnWidth"`
	FollowFocus bool    `json:"followFocus"`
}

// Keysounds is Ryoku's own plugin (ryoku/hyprland/plugins/keysounds): a sound
// on every key press from a shipped or user profile.
type Keysounds struct {
	Enabled bool    `json:"enabled"`
	Profile string  `json:"profile"` // a dir under /usr/share/ryoku/keysounds or ~/.local/share/ryoku/keysounds
	Volume  float64 `json:"volume"`  // 0..1
	Release bool    `json:"release"` // also play the key-up sample
}

// ExtraPlugin is a plugin the user added from a git repository (or hyprpm laid
// down) rather than one Ryoku bundles: the Hub has no curated knobs for it, so
// its settings are the config keys detected in its .so, stored by their full
// path under `plugin:` ("hyprexpo:columns") with the value type the control
// produced (bool, number, string).
type ExtraPlugin struct {
	Enabled bool           `json:"enabled"`
	Config  map[string]any `json:"config,omitempty"`
}

type Plugins struct {
	DynamicCursors DynamicCursors         `json:"dynamicCursors"`
	Hyprbars       Hyprbars               `json:"hyprbars"`
	Imgborders     Imgborders             `json:"imgborders"`
	Hyprglass      Hyprglass              `json:"hyprglass"`
	Hyprfocus      Hyprfocus              `json:"hyprfocus"`
	Keysounds      Keysounds              `json:"keysounds"`
	Hyprscrolling  Hyprscrolling          `json:"hyprscrolling"`
	Extra          map[string]ExtraPlugin `json:"extra,omitempty"`
}

type Overrides struct {
	Appearance     Appearance        `json:"appearance"`
	Dwindle        Dwindle           `json:"dwindle"`
	Master         Master            `json:"master"`
	Input          Input             `json:"input"`
	Cursor         Cursor            `json:"cursor"`
	Env            []EnvVar          `json:"env"`
	WindowRules    []WindowRule      `json:"windowRules"`
	Autostart      []Autostart       `json:"autostart"`
	Keybinds       []Keybind         `json:"keybinds"`
	Anim           Anim              `json:"anim"`
	LayerRules     []LayerRule       `json:"layerRules"`
	AppOverrides   []AppOverride     `json:"appOverrides"`
	Plugins        Plugins           `json:"plugins"`
	Apps           map[string]string `json:"apps,omitempty"`
	KeybindRebinds map[string]string `json:"keybindRebinds,omitempty"`

	// Unbinds: default chords config import must drop so an imported bind that
	// shadows a shipped one actually wins. Hyprland stacks binds on a key rather
	// than replacing, so without the unbind both the shipped and the imported
	// bind fire. Rendered as hl.unbind() lines before the keybinds, i.e. after
	// binds.lua registered the shipped chord and before the imported bind re-adds
	// it. Empty on an untouched system, so settings.lua is unchanged.
	Unbinds []string `json:"unbinds,omitempty"`

	// inputSaved: the store carries an explicit input section, i.e. the user has
	// saved input settings through the hub at least once. genConfig then pins the
	// kb_* keys unconditionally, so a saved layout (even "us") beats keyboard.lua,
	// which loads earlier and would otherwise silently win.
	inputSaved bool
}

// defaultOverrides mirrors the shipped Hyprland modules (decoration.lua,
// input.lua, keyboard.lua, env.lua/autostart.lua cursor) so the UI shows the
// real baseline and "Reset to defaults" actually restores it. keep these in
// step with the base; only divergence from here is ever written to settings.lua.
func defaultOverrides() Overrides {
	return Overrides{
		Appearance: Appearance{
			GapsIn: 12, GapsOut: 18, BorderSize: 2, Rounding: 0, RoundingPower: 4,
			ActiveOpacity: 1, InactiveOpacity: 0.94,
			DimInactive: false, DimStrength: 0.5,
			BlurEnabled: true, BlurSize: 4, BlurPasses: 1,
			BlurXray: false, BlurVibrancy: 0.17, BlurNoise: 0.01,
			ShadowEnabled: true, ShadowRange: 45, ShadowPower: 4,
			GlowEnabled: false, GlowRange: 10, GlowColor: "#ee33cc",
			Animations: true, Layout: "dwindle",
			ActiveBorder: "#e0563b", InactiveBorder: "#313a4d",
			ResizeOnBorder: true, SnapEnabled: false,
			WobblyWindows: false, WindowStyle: "pop",
			AnimatedBorder: false, BorderAngleSpeed: 3,
			FullscreenOpacity: 1, DimSpecial: 0.2, DimAround: 0.4,
			DimModal: true, BorderPartOfWindow: true,
			BlurContrast: 0.8916, BlurBrightness: 1, BlurSpecial: false, BlurPopups: false,
			BlurIgnoreOpacity: true, BlurNewOptimizations: true, BlurVibrancyDarkness: 0,
			ShadowSharp: false, ShadowScale: 1, ShadowColor: "#000000",
			ExtendBorderGrab: 15, HoverIconOnBorder: true, NoFocusFallback: false,
			ResizeCorner: 0, GapsWorkspaces: 0,
		},
		Dwindle: Dwindle{PreserveSplit: false, SmartSplit: false, SmartResizing: true, DefaultSplitRatio: 1, ForceSplit: "follow", UseActiveForSplits: true},
		Master:  Master{Mfact: 0.55, NewStatus: "slave", NewOnTop: false, Orientation: "left", SmartResizing: true},
		Input: Input{
			KbLayout: "us", KbVariant: "", KbOptions: "", NumlockByDefault: false,
			FollowMouse: 2, Sensitivity: 0, AccelProfile: "",
			LeftHanded: false, MouseNaturalScroll: false, MouseScrollFactor: 1,
			MiddleClickPaste: true,
			NaturalScroll:    false, TapToClick: true, TapAndDrag: true,
			Clickfinger: false, MiddleEmulation: false, TouchScrollFactor: 1,
			DisableWhileTyping: true,
			RepeatRate:         25, RepeatDelay: 600,
			WorkspaceSwipe: false, SwipeFingers: 3,
			SwipeInvert: true, SwipeCreateNew: true, SwipeDistance: 300,
		},
		Cursor:       Cursor{Theme: "Bibata-Modern-Ice", Size: 24, InactiveTimeout: 0, HideOnKeyPress: false},
		Env:          []EnvVar{},
		WindowRules:  []WindowRule{},
		Autostart:    []Autostart{},
		Keybinds:     []Keybind{},
		Anim:         Anim{Items: []AnimItem{}, Curves: []AnimCurve{}},
		LayerRules:   []LayerRule{},
		AppOverrides: []AppOverride{},
		Plugins: Plugins{
			DynamicCursors: DynamicCursors{Enabled: false, Mode: "tilt", Shake: true, Magnify: 4.0},
			Hyprbars:       Hyprbars{Enabled: false, Height: 26, TextSize: 11, Blur: true, Buttons: true},
			Imgborders:     Imgborders{Enabled: false, Image: "", Sizes: "8,8,8,8", Insets: "0,0,0,0", Scale: 1.0, Smooth: true, Blur: false},
			Hyprglass:      Hyprglass{Enabled: false, Preset: "clear", BlurStrength: 2.0, Opacity: 1.0, Tint: "8899aa22", Brightness: 1.0, Theme: "dark"},
			Hyprfocus:      Hyprfocus{Enabled: false, Mode: "flash", Opacity: 0.8, Bounce: 0.95, Slide: 20},
			Keysounds:      Keysounds{Enabled: false, Profile: "cherry-mx-brown", Volume: 0.6, Release: true},
			Hyprscrolling:  Hyprscrolling{ColumnWidth: 0.5, FollowFocus: true},
		},
	}
}

func hyprStorePath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "hypr.json")
}

func hyprConfigDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "hypr")
}

// userEditsHyprDir is the hypr slice of the user overlay tree,
// ~/.config/ryoku/user_edits/hypr. The Hub authors its generated Lua here so it
// survives an update as a user edit; writeOverlayLua reflects the same bytes into
// the live ~/.config/hypr so the running session reloads at once.
func userEditsHyprDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "user_edits", "hypr")
}

// loadOverrides: read the store, overlay on the defaults. a partial or older
// store still yields a complete object (missing fields keep the default).
// while no input settings were ever saved, the kb_* baseline comes from the
// live compositor (keyboard.lua may have seeded a non-us layout at install),
// so the hub reports the truth instead of the hardcoded "us".
func loadOverrides() Overrides {
	o := defaultOverrides()
	b, err := os.ReadFile(hyprStorePath())
	if err == nil {
		o.inputSaved = storeHasInput(b)
	}
	if !o.inputSaved {
		liveKbDefaults(&o.Input)
	}
	if err == nil {
		_ = json.Unmarshal(b, &o)
	}
	if o.Env == nil {
		o.Env = []EnvVar{}
	}
	if o.WindowRules == nil {
		o.WindowRules = []WindowRule{}
	}
	if o.AppOverrides == nil {
		o.AppOverrides = []AppOverride{}
	}
	if o.Autostart == nil {
		o.Autostart = []Autostart{}
	}
	if o.Keybinds == nil {
		o.Keybinds = []Keybind{}
	}
	if o.Anim.Items == nil {
		o.Anim.Items = []AnimItem{}
	}
	if o.Anim.Curves == nil {
		o.Anim.Curves = []AnimCurve{}
	}
	if o.LayerRules == nil {
		o.LayerRules = []LayerRule{}
	}
	return o
}

// storeHasInput reports whether the stored JSON carries an explicit input
// section. saveOverrides always writes the full struct, so a present input key
// means the user saved input settings at least once.
func storeHasInput(b []byte) bool {
	var probe struct {
		Input json.RawMessage `json:"input"`
	}
	if json.Unmarshal(b, &probe) != nil {
		return false
	}
	return len(probe.Input) > 0 && string(probe.Input) != "null"
}

// liveKbDefaults asks the running compositor for its effective kb_* values
// (`hyprctl getoption -j`, read-only) so the unsaved baseline matches the real
// session. on failure (headless, no hyprctl) the hardcoded defaults stand.
func liveKbDefaults(in *Input) {
	opts := []struct {
		name string
		dst  *string
	}{
		{"input:kb_layout", &in.KbLayout},
		{"input:kb_variant", &in.KbVariant},
		{"input:kb_options", &in.KbOptions},
	}
	for _, o := range opts {
		b, err := exec.Command("hyprctl", "getoption", o.name, "-j").Output()
		if err != nil {
			continue
		}
		var v struct {
			Str string `json:"str"`
		}
		if json.Unmarshal(b, &v) != nil {
			continue
		}
		if s := strings.TrimSpace(v.Str); s != "" {
			*o.dst = s
		}
	}
}

func saveOverrides(o Overrides) error {
	p := hyprStorePath()
	b, err := json.MarshalIndent(o, "", "  ")
	if err != nil {
		return err
	}
	return atomicWrite(p, b, 0o644)
}

func atomicWrite(path string, b []byte, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	if _, err := f.Write(b); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Chmod(mode); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}

func parseOverrides(s string) (Overrides, error) {
	o := defaultOverrides()
	if err := json.Unmarshal([]byte(s), &o); err != nil {
		return o, fmt.Errorf("parse overrides JSON: %w", err)
	}
	// a hub snapshot carries explicit input values; saving it pins the kb_* keys.
	o.inputSaved = true
	return o, nil
}

// runHypr: dispatch for `ryoku-hub hypr <sub> [arg]`.
func runHypr(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("hypr needs get|defaults|save|preview|restore|cursors|layouts|variants|anim-preset|plugins")
	}
	switch args[0] {
	case "get":
		o := loadOverrides()
		_ = writeGeneratedLua(o) // re-emit settings.lua if a deploy wiped it
		_ = writeRebindsLua(o)   // re-emit the K() table too
		return printJSON(o)
	case "defaults":
		return printJSON(defaultOverrides())
	case "save":
		if len(args) < 2 {
			return fmt.Errorf("hypr save needs a JSON argument")
		}
		o, err := parseOverrides(args[1])
		if err != nil {
			return err
		}
		prev := loadOverrides()
		if err := saveOverrides(o); err != nil {
			return err
		}
		if err := writeGeneratedLua(o); err != nil {
			return err
		}
		if err := writeRebindsLua(o); err != nil {
			return err
		}
		hyprReload()
		// a reload only acts on a changed set of declared paths, and only
		// unloads what it loaded itself: a plugin dropped by hand (a rebuild)
		// or by the probe stays where it is. So: load what is enabled but
		// missing, drop what was turned off, then push every plugin's config,
		// since one that has just come up ran its config line before it existed.
		loadEnabledPlugins(o)
		for _, id := range pluginsTurnedOff(prev, o) {
			unloadPluginCopies(id)
		}
		hyprEval(genPluginConfig(o))
		// reload restores config keywords but not the cursor, which is imperative
		// state set via setcursor rather than a keyword. Without this a saved
		// theme change only lands live if a preview happened to run for the final
		// value first, so a quick pick-then-save left the old pointer on screen.
		setLiveCursor(o.Cursor)
		return nil
	case "preview":
		if len(args) < 2 {
			return fmt.Errorf("hypr preview needs a JSON argument")
		}
		o, err := parseOverrides(args[1])
		if err != nil {
			return err
		}
		hyprEval(liveLua(o))
		return nil
	case "plugins":
		return runHyprPlugins(args[1:])
	case "restore":
		// revert the live session to the saved state by reloading (settings.lua +
		// base modules). resets every keyword exactly, including ones eval can't
		// push back to a default. the cursor is set imperatively (setcursor), so a
		// reload alone would leave a previewed cursor live; re-assert the saved one.
		hyprReload()
		o := loadOverrides()
		setLiveCursor(o.Cursor)
		return nil
	case "cursors":
		return printJSON(listCursorThemes())
	case "layouts":
		return printJSON(listKbLayouts())
	case "variants":
		if len(args) < 2 {
			return fmt.Errorf("hypr variants needs a layout code")
		}
		return printJSON(listKbVariants(args[1]))
	case "scheme":
		if len(args) < 2 {
			return printJSON(map[string]string{"scheme": currentScheme()})
		}
		return applyScheme(args[1])
	case "ryoku-theme":
		return applyRyokuTheme()
	case "theme-apps":
		if len(args) < 2 {
			return printJSON(map[string]bool{"themeApps": currentThemeApps()})
		}
		return applyThemeApps(args[1] == "on" || args[1] == "true")
	case "gtk-theme":
		if len(args) < 2 {
			return printJSON(map[string]string{"gtkTheme": currentGtkTheme()})
		}
		return applyGtkTheme(args[1])
	case "gnome-accent":
		if len(args) < 2 {
			return printJSON(map[string]bool{"gnomeAccent": currentGnomeAccent()})
		}
		return applyGnomeAccent(args[1] == "on" || args[1] == "true")
	case "matugen":
		return runMatugenCmd(args[1:])
	case "anim-preset":
		if len(args) < 2 {
			return printJSON(map[string]string{"preset": currentAnimPreset()})
		}
		return applyAnimPreset(args[1])
	default:
		return fmt.Errorf("unknown hypr subcommand: %s", args[0])
	}
}

func printJSON(v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	os.Stdout.Write(b)
	fmt.Println()
	return nil
}

func hyprEval(lua string) {
	if strings.TrimSpace(lua) == "" {
		return
	}
	_ = exec.Command("hyprctl", "eval", lua).Run()
}

func hyprReload() {
	_ = exec.Command("hyprctl", "reload").Run()
}

// anim-preset: the active Hyprland animation personality. The name is a plain
// file modules/animations.lua reads at load; set writes it and reloads.
var animPresets = map[string]bool{
	"ryoku": true, "dusky": true, "bounce": true, "fade": true, "fast": true,
	"mechanical": true, "minimal": true, "rage": true, "slowmotion": true,
	"air": true, "hallucination": true, "exaggerated": true, "disable": true,
}

func animPresetPath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "anim-preset")
}

func currentAnimPreset() string {
	b, err := os.ReadFile(animPresetPath())
	if err != nil {
		return "ryoku"
	}
	name := strings.TrimSpace(string(b))
	if !animPresets[name] {
		return "ryoku"
	}
	return name
}

func applyAnimPreset(name string) error {
	if !animPresets[name] {
		return fmt.Errorf("unknown animation preset %q", name)
	}
	if err := atomicWrite(animPresetPath(), []byte(name+"\n"), 0o644); err != nil {
		return err
	}
	hyprReload()
	return nil
}

// setLiveCursor applies the pointer theme imperatively. hyprctl reload restores
// config keywords but not the cursor (setcursor is not a keyword), so both save
// and restore re-assert it for a theme change to land on screen at once.
func setLiveCursor(c Cursor) {
	_ = exec.Command("hyprctl", "setcursor", c.Theme, fmt.Sprintf("%d", c.Size)).Run()
}

// writeOverlayLua authors a generated overlay file in the user_edits tree (the
// source of truth, kept across updates) and reflects the same bytes into the live
// hypr dir so a reload picks them up immediately, without a full materialize.
func writeOverlayLua(name string, body []byte) error {
	if err := atomicWrite(filepath.Join(userEditsHyprDir(), name), body, 0o644); err != nil {
		return err
	}
	return atomicWrite(filepath.Join(hyprConfigDir(), name), body, 0o644)
}

// writeGeneratedLua renders settings.lua from the overrides (diffed against the
// shipped defaults) into the user overlay, reflected live.
func writeGeneratedLua(o Overrides) error {
	return writeOverlayLua("settings.lua", []byte(genLua(o, paletteDriven())))
}

// staticThemeActive reports whether a fixed named colour scheme is selected in
// shell.json (theme.theme names a catalog palette, not the two dynamic variants
// Default and Wallpaper). Its palette drives the window border through
// decoration.lua's hypr-colors.lua, so settings.lua must not pin a fixed
// col.active_border over it.
func staticThemeActive() bool {
	b, err := os.ReadFile(shellStorePath())
	if err != nil {
		return false
	}
	var s struct {
		Theme struct {
			Theme string `json:"theme"`
		} `json:"theme"`
	}
	if json.Unmarshal(b, &s) != nil {
		return false
	}
	switch s.Theme.Theme {
	case "", "Default", "Wallpaper":
		return false
	}
	return true
}

// paletteDriven reports whether the window colours come from a live palette (the
// wallpaper-follow master or a fixed named scheme) rather than the user's fixed
// border choice. When true the generated config omits the solid col.active_border
// so decoration.lua's palette border (hypr-colors.lua) wins in both modes.
func paletteDriven() bool {
	return loadThemeState().FollowWallpaper || staticThemeActive()
}

// writeRebindsLua renders the key-rebind table binds.lua's K() consults, one
// [default chord] = chosen chord entry per rebind. Always written (return {} when
// empty) so clearing the last rebind leaves no stale table behind.
func writeRebindsLua(o Overrides) error {
	keys := make([]string, 0, len(o.KeybindRebinds))
	for k := range o.KeybindRebinds {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	b.WriteString("-- Generated by Ryoku Settings (Keybinds page); change it in the GUI, not here.\nreturn {\n")
	for _, from := range keys {
		to := strings.TrimSpace(o.KeybindRebinds[from])
		from = strings.TrimSpace(from)
		if from == "" || to == "" || from == to {
			continue
		}
		fmt.Fprintf(&b, "\t[%s] = %s,\n", luaStr(from), luaStr(to))
	}
	b.WriteString("}\n")
	return writeOverlayLua("rebinds.lua", []byte(b.String()))
}

// genApps exports env vars for the chosen browser and terminal so the CLI and
// xdg-open honour the same choice the keybinds launch via ryoku-app; a later
// hl.env wins over env.lua. The editor keeps env.lua's default: a terminal editor
// wants $EDITOR as the bare binary, not the windowed launch the keybind uses, so
// it is set through the Environment page rather than guessed here.
func genApps(o Overrides) string {
	var b strings.Builder
	if v := strings.TrimSpace(o.Apps["browser"]); v != "" {
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr("BROWSER"), luaStr(v))
	}
	if v := strings.TrimSpace(o.Apps["terminal"]); v != "" {
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr("TERMINAL"), luaStr(v))
	}
	if b.Len() > 0 {
		b.WriteString("\n")
	}
	return b.String()
}

// --- Lua generation -------------------------------------------------------

const luaHeader = `-- Generated by Ryoku Settings (Super + ,). Lives in the user_edits overlay,
-- overwritten on every change, so change it in the GUI, not by hand. Loaded
-- after Ryoku's defaults and before your user.lua, which still wins.

`

func genLua(o Overrides, follow bool) string {
	var b strings.Builder
	b.WriteString(luaHeader)

	if cfg := genConfig(o, follow); cfg != "" {
		b.WriteString(cfg)
	}
	if m := genMotion(o, false); m != "" {
		b.WriteString(m)
	}
	if ab := genAnimatedBorder(o, follow, false); ab != "" {
		b.WriteString(ab)
	}
	if anim := genAnimBlock(o); anim != "" {
		b.WriteString(anim)
		b.WriteString("\n")
	}
	if g := genGesture(o); g != "" {
		b.WriteString(g)
		b.WriteString("\n")
	}
	// cursor divergence exports env too: env.lua exports the base theme early
	// and a later hl.env wins, so spawned apps see the picked cursor (the start
	// hook's setcursor only reaches the compositor + XWayland).
	if d := defaultOverrides().Cursor; o.Cursor.Theme != d.Theme || o.Cursor.Size != d.Size {
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr("XCURSOR_THEME"), luaStr(o.Cursor.Theme))
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr("XCURSOR_SIZE"), luaStr(fmt.Sprintf("%d", o.Cursor.Size)))
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr("HYPRCURSOR_THEME"), luaStr(o.Cursor.Theme))
		fmt.Fprintf(&b, "hl.env(%s, %s)\n\n", luaStr("HYPRCURSOR_SIZE"), luaStr(fmt.Sprintf("%d", o.Cursor.Size)))
	}
	for _, e := range o.Env {
		if strings.TrimSpace(e.Key) == "" {
			continue
		}
		fmt.Fprintf(&b, "hl.env(%s, %s)\n", luaStr(e.Key), luaStr(e.Value))
	}
	if len(o.Env) > 0 {
		b.WriteString("\n")
	}
	if ap := genApps(o); ap != "" {
		b.WriteString(ap)
	}
	for i, r := range o.WindowRules {
		if rl := genWindowRule(i, r); rl != "" {
			b.WriteString(rl)
		}
	}
	for i, r := range o.LayerRules {
		if rl := genLayerRule(i, r); rl != "" {
			b.WriteString(rl)
		}
	}
	for i, a := range o.AppOverrides {
		if rl := genAppOverride(i, a); rl != "" {
			b.WriteString(rl)
		}
	}
	if ub := genUnbinds(o); ub != "" {
		b.WriteString(ub)
	}
	for _, k := range o.Keybinds {
		if kb := genKeybind(k); kb != "" {
			b.WriteString(kb)
		}
	}
	if pl := genPlugins(o); pl != "" {
		b.WriteString(pl)
	}
	if start := genStartHook(o); start != "" {
		b.WriteString("\n")
		b.WriteString(start)
	}
	return b.String()
}

// pluginDir is where the [ryoku] repo (release/packages) installs the optional
// Hyprland compositor plugin .so files. genPlugins loads them by absolute path.
const pluginDir = "/usr/lib/hyprland/plugins"

// pluginSoPath resolves the copy of a compositor plugin settings.lua should
// load: the local build (deploy.sh on a checkout, the Hub's Rebuild) before the
// package copy, but only a copy whose .abi receipt matches the compositor this
// file is generated for (the running one, else the installed headers). A copy
// with no receipt is taken on trust. "" means nothing loadable is installed:
// every copy is stale or the plugin is missing, and the load is left out, so
// Hyprland does not refuse it with a notification on every reload. The Plugins
// page reports the same verdict with a Rebuild.
func pluginSoPath(id string) string {
	target := liveCompositor().abi
	if !target.ok() {
		target, _ = headersABI()
	}
	c, ok, stale := pickCopy(pluginCopies(id), target)
	if !ok || stale {
		return ""
	}
	return c.Path
}

// pluginsTurnedOff lists the plugins enabled in prev that the new store turns
// off, so a Save can unload them from the running compositor.
func pluginsTurnedOff(prev, next Overrides) []string {
	var off []string
	for _, d := range bundledPlugins {
		if pluginEnabled(prev, d.ID) && !pluginEnabled(next, d.ID) {
			off = append(off, d.ID)
		}
	}
	for _, id := range sortedExtraIDs(prev.Plugins.Extra) {
		if prev.Plugins.Extra[id].Enabled && !next.Plugins.Extra[id].Enabled {
			off = append(off, id)
		}
	}
	return off
}

// pluginBlock is one enabled compositor plugin, resolved for emission: the
// copy to load, the name Hyprland reports for it once loaded, and its config.
type pluginBlock struct {
	id     string
	name   string // as `hyprctl plugins list` reports it; the guard's key
	so     string // "" when no copy built for this Hyprland is installed
	config string // the `plugin = { ... }` table, "" when nothing to set
	extra  string // verbatim Lua after the config (the hyprbars buttons)
}

// luaPluginLoaded is the guard every plugin block runs its config behind.
// hl.plugin.load only declares a path: Hyprland loads the declared set after
// the whole config pass and then reloads once more, so the config line has to
// wait for that second pass, and the only thing true for every loaded plugin
// is its entry in hl.get_loaded_plugins() (the hl.plugin.<name> namespace only
// exists for a plugin that registers Lua functions). Setting hl.config on a
// plugin that is not loaded is no Lua error (a pcall catches nothing); it paints
// Hyprland's "unknown config key" overlay, so the guard is not optional.
const luaPluginLoaded = `local function ryoku_plugin_loaded(name)
  for _, p in ipairs(hl.get_loaded_plugins()) do
    if p.name == name then return true end
  end
  return false
end

`

// genPlugins renders the optional Hyprland compositor plugins the user enabled
// for settings.lua: per plugin, an hl.plugin.load of its copy plus its
// hl.config behind luaPluginLoaded, all inside a pcall so a missing or
// ABI-mismatched .so degrades to "off" instead of aborting settings.lua. The
// scrolling layout is Hyprland core (not a plugin): its knobs emit as the core
// `scrolling` category when that layout is selected.
func genPlugins(o Overrides) string {
	var b strings.Builder
	blocks := pluginBlocks(o)
	if len(blocks) > 0 {
		b.WriteString(luaPluginLoaded)
	}
	for _, pb := range blocks {
		if pb.so == "" {
			fmt.Fprintf(&b, "-- %s: no copy built for this Hyprland; rebuild it from Settings > Plugins\n\n", pb.id)
			continue
		}
		b.WriteString("pcall(function()\n")
		fmt.Fprintf(&b, "  hl.plugin.load(%s)\n", luaStr(pb.so))
		b.WriteString(pb.configLua("  "))
		b.WriteString("end)\n\n")
	}
	b.WriteString(genScrolling(o))
	return b.String()
}

// genPluginConfig renders only the config of the enabled plugins, for
// `hyprctl eval`: the live preview while a setting is being changed, and the
// pass after a Save's reload or a load by hand, when a plugin that has just
// come up still holds its defaults (settings.lua's config line ran before the
// load landed).
func genPluginConfig(o Overrides) string {
	var b strings.Builder
	for _, pb := range pluginBlocks(o) {
		if pb.so == "" || pb.config == "" {
			continue
		}
		if b.Len() == 0 {
			b.WriteString(luaPluginLoaded)
		}
		b.WriteString(pb.configLua(""))
	}
	return b.String()
}

// configLua is the guarded config of one block, indented for its context.
func (pb pluginBlock) configLua(indent string) string {
	if pb.config == "" && pb.extra == "" {
		return ""
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%sif ryoku_plugin_loaded(%s) then\n", indent, luaStr(pb.name))
	if pb.config != "" {
		fmt.Fprintf(&b, "%s  hl.config({ plugin = %s })\n", indent, pb.config)
	}
	b.WriteString(pb.extra)
	fmt.Fprintf(&b, "%send\n", indent)
	return b.String()
}

// typedBlock is a bundled plugin's block: its options under one section.
// Section keys use underscores: the Lua config normalises "dynamic_cursors"
// to the plugin's dashed "dynamic-cursors" (a dashed key is rejected as
// unknown; verified live against Hyprland 0.55.4).
func typedBlock(id, section string, opts []string, extra string) pluginBlock {
	d, _ := bundledByID(id)
	return pluginBlock{
		id: id, name: d.Loaded, so: pluginSoPath(id),
		config: fmt.Sprintf("{ %s = { %s } }", section, strings.Join(opts, ", ")),
		extra:  extra,
	}
}

// pluginBlocks resolves every enabled plugin, bundled ones first in the
// registry's order, then the added ones.
func pluginBlocks(o Overrides) []pluginBlock {
	var out []pluginBlock
	p := o.Plugins

	if dc := p.DynamicCursors; dc.Enabled {
		opts := []string{
			"enabled = true",
			fmt.Sprintf("mode = %s", luaStr(dc.Mode)),
			fmt.Sprintf("shake = { enabled = %t, base = %s }", dc.Shake, luaNum(dc.Magnify)),
		}
		out = append(out, typedBlock("dynamic-cursors", "dynamic_cursors", opts, ""))
	}

	if hb := p.Hyprbars; hb.Enabled {
		opts := []string{
			"enabled = true",
			fmt.Sprintf("bar_height = %d", hb.Height),
			fmt.Sprintf("bar_text_size = %d", hb.TextSize),
			fmt.Sprintf("bar_blur = %t", hb.Blur),
		}
		var extra string
		if hb.Buttons {
			// close + fullscreen toggle, traffic-light colours; re-added on each
			// reload (hyprbars clears buttons in onPreConfigReload). "\u00d7" and
			// "+" render in any font, so no Nerd Font dependency.
			extra = "    hl.plugin.hyprbars.add_button({ bg_color = \"rgb(ff5f57)\", fg_color = \"rgb(ffffff)\", size = 12, icon = \"\u00d7\", action = \"hyprctl dispatch killactive\" })\n" +
				"    hl.plugin.hyprbars.add_button({ bg_color = \"rgb(28c840)\", fg_color = \"rgb(ffffff)\", size = 12, icon = \"+\", action = \"hyprctl dispatch fullscreen 1\" })\n"
		}
		out = append(out, typedBlock("hyprbars", "hyprbars", opts, extra))
	}

	if ib := p.Imgborders; ib.Enabled {
		opts := []string{
			"enabled = true",
			fmt.Sprintf("image = %s", luaStr(ib.Image)),
			fmt.Sprintf("sizes = %s", luaStr(ib.Sizes)),
			fmt.Sprintf("insets = %s", luaStr(ib.Insets)),
			fmt.Sprintf("scale = %s", luaNum(ib.Scale)),
			fmt.Sprintf("smooth = %t", ib.Smooth),
			fmt.Sprintf("blur = %t", ib.Blur),
		}
		out = append(out, typedBlock("imgborders", "imgborders", opts, ""))
	}

	if hg := p.Hyprglass; hg.Enabled {
		opts := []string{
			"enabled = 1",
			fmt.Sprintf("default_preset = %s", luaStr(hg.Preset)),
			fmt.Sprintf("blur_strength = %s", luaNum(hg.BlurStrength)),
			fmt.Sprintf("glass_opacity = %s", luaNum(hg.Opacity)),
			fmt.Sprintf("tint_color = 0x%s", luaHex8(hg.Tint)),
			fmt.Sprintf("brightness = %s", luaNum(hg.Brightness)),
			fmt.Sprintf("default_theme = %s", luaStr(hg.Theme)),
		}
		out = append(out, typedBlock("hyprglass", "hyprglass", opts, ""))
	}

	if hf := p.Hyprfocus; hf.Enabled {
		// The package tracks upstream's hyprpm pin for the running Hyprland, and
		// the 0.56 plugin renamed its keys: the focus animation is chosen per
		// input source and the bounce effect became shrink. The store keeps the
		// stable mode/bounce names; only the emit follows the plugin.
		anim := hf.Mode
		if anim == "bounce" {
			anim = "shrink"
		}
		opts := []string{
			"enable = true",
			fmt.Sprintf("keyboard_focus_animation = %s", luaStr(anim)),
			`mouse_focus_animation = "none"`,
			fmt.Sprintf("fade_opacity = %s", luaNum(hf.Opacity)),
			fmt.Sprintf("shrink_percentage = %s", luaNum(hf.Bounce)),
			fmt.Sprintf("slide_height = %s", luaNum(hf.Slide)),
		}
		out = append(out, typedBlock("hyprfocus", "hyprfocus", opts, ""))
	}

	if ks := p.Keysounds; ks.Enabled {
		opts := []string{
			"enabled = true",
			fmt.Sprintf("profile = %s", luaStr(ks.Profile)),
			fmt.Sprintf("volume = %s", luaNum(ks.Volume)),
			fmt.Sprintf("release = %t", ks.Release),
		}
		out = append(out, typedBlock("keysounds", "keysounds", opts, ""))
	}

	// plugins the user added from git (or hyprpm laid down): the load, then the
	// detected keys the user changed, as nested tables from their colon paths.
	for _, id := range sortedExtraIDs(p.Extra) {
		if ep := p.Extra[id]; ep.Enabled {
			out = append(out, extraBlock(id, ep.Config))
		}
	}
	return out
}

// genScrolling: the scrolling layout is Hyprland core (0.54+), configured under
// the core `scrolling` category, not a plugin. Its knobs emit only when the
// layout is selected, diffed against the core defaults.
func genScrolling(o Overrides) string {
	if o.Appearance.Layout != "scrolling" {
		return ""
	}
	var b strings.Builder
	hs, dhs := o.Plugins.Hyprscrolling, defaultOverrides().Plugins.Hyprscrolling
	var sc []string
	if hs.ColumnWidth != dhs.ColumnWidth {
		sc = append(sc, fmt.Sprintf("column_width = %s", luaNum(hs.ColumnWidth)))
	}
	if hs.FollowFocus != dhs.FollowFocus {
		sc = append(sc, fmt.Sprintf("follow_focus = %t", hs.FollowFocus))
	}
	if len(sc) > 0 {
		fmt.Fprintf(&b, "hl.config({ scrolling = { %s } })\n\n", strings.Join(sc, ", "))
	}

	// Follow focus is inert while the pointer can't move focus: with the
	// shipped follow_mouse = 2 (detached) hovering a peeked column never
	// scrolls it in until you click (#56). So when follow focus is on, let
	// the pointer drive focus too -- unless the user pinned their own value.
	if hs.FollowFocus && o.Input.FollowMouse == defaultOverrides().Input.FollowMouse {
		b.WriteString("hl.config({ input = { follow_mouse = 1 } })\n\n")
	}
	return b.String()
}

// extraBlock is an added plugin's block: the config keys the user set, stored
// as full paths under `plugin:` ("hyprexpo:columns"), as nested tables. The
// Lua config normalises dashed names to underscores, so every component is
// emitted that way. The name the plugin reports (the guard's key) comes from
// its receipt once a load has revealed it, the id until then.
func extraBlock(id string, cfg map[string]any) pluginBlock {
	name := id
	if r, ok := readReceipt(id); ok && r.Loaded != "" {
		name = r.Loaded
	}
	pb := pluginBlock{id: id, name: name, so: pluginSoPath(id)}
	if tree := luaConfigTree(cfg); len(tree) > 0 {
		pb.config = renderLuaTable(tree)
	}
	return pb
}

// luaConfigTree nests colon-path keys into tables: "a:b:c" -> { a = { b = { c } } }.
func luaConfigTree(cfg map[string]any) map[string]any {
	tree := map[string]any{}
	for _, k := range sortedKeys(cfg) {
		parts := strings.Split(k, ":")
		if len(parts) < 2 {
			continue
		}
		for i := range parts {
			parts[i] = strings.ReplaceAll(parts[i], "-", "_")
		}
		cur := tree
		for _, p := range parts[:len(parts)-1] {
			next, ok := cur[p].(map[string]any)
			if !ok {
				next = map[string]any{}
				cur[p] = next
			}
			cur = next
		}
		cur[parts[len(parts)-1]] = cfg[k]
	}
	return tree
}

func sortedKeys(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

var luaIdentRe = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// renderLuaTable renders a nested map as a Lua table constructor with stable
// key order; a key that is not a bare identifier is bracketed.
func renderLuaTable(t map[string]any) string {
	var parts []string
	for _, k := range sortedKeys(t) {
		key := k
		if !luaIdentRe.MatchString(k) {
			key = "[" + luaStr(k) + "]"
		}
		parts = append(parts, key+" = "+luaValue(t[k]))
	}
	return "{ " + strings.Join(parts, ", ") + " }"
}

// luaValue renders a store value by its JSON type: a bool, a number (integral
// ones without a fraction, so an int option reads one), a string, a table.
func luaValue(v any) string {
	switch x := v.(type) {
	case bool:
		return strconv.FormatBool(x)
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	case int:
		return strconv.Itoa(x)
	case string:
		return luaStr(x)
	case map[string]any:
		return renderLuaTable(x)
	}
	return luaStr(fmt.Sprint(v))
}

// luaHex8 sanitises an RRGGBBAA hex string (optionally #- or 0x-prefixed) to a
// bare 8-digit lowercase hex for a Lua 0x literal; a malformed value falls back
// to the hyprglass default tint so a typo can't produce invalid Lua.
func luaHex8(s string) string {
	s = strings.TrimPrefix(strings.TrimPrefix(strings.ToLower(strings.TrimSpace(s)), "0x"), "#")
	if len(s) != 8 {
		return "8899aa22"
	}
	for _, c := range s {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return "8899aa22"
		}
	}
	return s
}

// genConfig: one hl.config({...}) holding only the general / decoration / input
// / animations leaves that diverge from the defaults. exception: once input
// settings were saved, the kb_* keys are pinned unconditionally, because
// keyboard.lua loads before settings.lua and a diffed-away "us" would let it
// silently win over what the UI shows.
func genConfig(o Overrides, follow bool) string {
	d := defaultOverrides()
	var general, deco, input, cursor, misc, gestures, dwindle, master []string

	a, da := o.Appearance, d.Appearance
	if a.GapsIn != da.GapsIn {
		general = append(general, fmt.Sprintf("gaps_in = %d", a.GapsIn))
	}
	if a.GapsOut != da.GapsOut {
		general = append(general, fmt.Sprintf("gaps_out = %d", a.GapsOut))
	}
	if a.BorderSize != da.BorderSize {
		general = append(general, fmt.Sprintf("border_size = %d", a.BorderSize))
	}
	if a.Layout != da.Layout {
		general = append(general, fmt.Sprintf("layout = %s", luaStr(a.Layout)))
	}
	if a.ResizeOnBorder != da.ResizeOnBorder {
		general = append(general, fmt.Sprintf("resize_on_border = %t", a.ResizeOnBorder))
	}
	if a.SnapEnabled != da.SnapEnabled {
		general = append(general, fmt.Sprintf("snap = { enabled = %t }", a.SnapEnabled))
	}
	if a.AnimatedBorder {
		// the active border is a rotating gradient (genAnimatedBorder); only the
		// inactive colour is a plain override, and only when colours are fixed.
		if !follow {
			general = append(general, fmt.Sprintf("[\"col.inactive_border\"] = %s", luaStr(luaRGB(a.InactiveBorder))))
		}
	} else if !follow {
		general = append(general, fmt.Sprintf("[\"col.active_border\"] = %s", luaStr(luaRGB(a.ActiveBorder))))
		general = append(general, fmt.Sprintf("[\"col.inactive_border\"] = %s", luaStr(luaRGB(a.InactiveBorder))))
	}
	if a.ExtendBorderGrab != da.ExtendBorderGrab {
		general = append(general, fmt.Sprintf("extend_border_grab_area = %d", a.ExtendBorderGrab))
	}
	if a.HoverIconOnBorder != da.HoverIconOnBorder {
		general = append(general, fmt.Sprintf("hover_icon_on_border = %t", a.HoverIconOnBorder))
	}
	if a.NoFocusFallback != da.NoFocusFallback {
		general = append(general, fmt.Sprintf("no_focus_fallback = %t", a.NoFocusFallback))
	}
	if a.ResizeCorner != da.ResizeCorner {
		general = append(general, fmt.Sprintf("resize_corner = %d", a.ResizeCorner))
	}
	if a.GapsWorkspaces != da.GapsWorkspaces {
		general = append(general, fmt.Sprintf("gaps_workspaces = %d", a.GapsWorkspaces))
	}

	if a.Rounding != da.Rounding {
		deco = append(deco, fmt.Sprintf("rounding = %d", a.Rounding))
	}
	if a.RoundingPower != da.RoundingPower {
		deco = append(deco, fmt.Sprintf("rounding_power = %s", luaNum(a.RoundingPower)))
	}
	if a.ActiveOpacity != da.ActiveOpacity {
		deco = append(deco, fmt.Sprintf("active_opacity = %s", luaNum(a.ActiveOpacity)))
	}
	if a.InactiveOpacity != da.InactiveOpacity {
		deco = append(deco, fmt.Sprintf("inactive_opacity = %s", luaNum(a.InactiveOpacity)))
	}
	if a.DimInactive != da.DimInactive {
		deco = append(deco, fmt.Sprintf("dim_inactive = %t", a.DimInactive))
	}
	if a.DimStrength != da.DimStrength {
		deco = append(deco, fmt.Sprintf("dim_strength = %s", luaNum(a.DimStrength)))
	}
	if a.FullscreenOpacity != da.FullscreenOpacity {
		deco = append(deco, fmt.Sprintf("fullscreen_opacity = %s", luaNum(a.FullscreenOpacity)))
	}
	if a.DimSpecial != da.DimSpecial {
		deco = append(deco, fmt.Sprintf("dim_special = %s", luaNum(a.DimSpecial)))
	}
	if a.DimAround != da.DimAround {
		deco = append(deco, fmt.Sprintf("dim_around = %s", luaNum(a.DimAround)))
	}
	if a.DimModal != da.DimModal {
		deco = append(deco, fmt.Sprintf("dim_modal = %t", a.DimModal))
	}
	if a.BorderPartOfWindow != da.BorderPartOfWindow {
		deco = append(deco, fmt.Sprintf("border_part_of_window = %t", a.BorderPartOfWindow))
	}
	var blur []string
	if a.BlurEnabled != da.BlurEnabled {
		blur = append(blur, fmt.Sprintf("enabled = %t", a.BlurEnabled))
	}
	if a.BlurSize != da.BlurSize {
		blur = append(blur, fmt.Sprintf("size = %d", a.BlurSize))
	}
	if a.BlurPasses != da.BlurPasses {
		blur = append(blur, fmt.Sprintf("passes = %d", a.BlurPasses))
	}
	if a.BlurXray != da.BlurXray {
		blur = append(blur, fmt.Sprintf("xray = %t", a.BlurXray))
	}
	if a.BlurVibrancy != da.BlurVibrancy {
		blur = append(blur, fmt.Sprintf("vibrancy = %s", luaNum(a.BlurVibrancy)))
	}
	if a.BlurNoise != da.BlurNoise {
		blur = append(blur, fmt.Sprintf("noise = %s", luaNum(a.BlurNoise)))
	}
	if a.BlurContrast != da.BlurContrast {
		blur = append(blur, fmt.Sprintf("contrast = %s", luaNum(a.BlurContrast)))
	}
	if a.BlurBrightness != da.BlurBrightness {
		blur = append(blur, fmt.Sprintf("brightness = %s", luaNum(a.BlurBrightness)))
	}
	if a.BlurSpecial != da.BlurSpecial {
		blur = append(blur, fmt.Sprintf("special = %t", a.BlurSpecial))
	}
	if a.BlurPopups != da.BlurPopups {
		blur = append(blur, fmt.Sprintf("popups = %t", a.BlurPopups))
	}
	if a.BlurIgnoreOpacity != da.BlurIgnoreOpacity {
		blur = append(blur, fmt.Sprintf("ignore_opacity = %t", a.BlurIgnoreOpacity))
	}
	if a.BlurNewOptimizations != da.BlurNewOptimizations {
		blur = append(blur, fmt.Sprintf("new_optimizations = %t", a.BlurNewOptimizations))
	}
	if a.BlurVibrancyDarkness != da.BlurVibrancyDarkness {
		blur = append(blur, fmt.Sprintf("vibrancy_darkness = %s", luaNum(a.BlurVibrancyDarkness)))
	}
	if len(blur) > 0 {
		deco = append(deco, "blur = { "+strings.Join(blur, ", ")+" }")
	}
	var shadow []string
	if a.ShadowEnabled != da.ShadowEnabled {
		shadow = append(shadow, fmt.Sprintf("enabled = %t", a.ShadowEnabled))
	}
	if a.ShadowRange != da.ShadowRange {
		shadow = append(shadow, fmt.Sprintf("range = %d", a.ShadowRange))
	}
	if a.ShadowPower != da.ShadowPower {
		shadow = append(shadow, fmt.Sprintf("render_power = %d", a.ShadowPower))
	}
	if a.ShadowSharp != da.ShadowSharp {
		shadow = append(shadow, fmt.Sprintf("sharp = %t", a.ShadowSharp))
	}
	if a.ShadowScale != da.ShadowScale {
		shadow = append(shadow, fmt.Sprintf("scale = %s", luaNum(a.ShadowScale)))
	}
	if a.ShadowColor != da.ShadowColor {
		shadow = append(shadow, fmt.Sprintf("color = %s", luaStr(luaRGB(a.ShadowColor))))
	}
	if len(shadow) > 0 {
		deco = append(deco, "shadow = { "+strings.Join(shadow, ", ")+" }")
	}
	var glow []string
	if a.GlowEnabled != da.GlowEnabled {
		glow = append(glow, fmt.Sprintf("enabled = %t", a.GlowEnabled))
	}
	if a.GlowRange != da.GlowRange {
		glow = append(glow, fmt.Sprintf("range = %d", a.GlowRange))
	}
	if a.GlowColor != da.GlowColor {
		glow = append(glow, fmt.Sprintf("color = %s", luaStr(luaRGB(a.GlowColor))))
	}
	if len(glow) > 0 {
		deco = append(deco, "glow = { "+strings.Join(glow, ", ")+" }")
	}

	dw, ddw := o.Dwindle, d.Dwindle
	if dw.PreserveSplit != ddw.PreserveSplit {
		dwindle = append(dwindle, fmt.Sprintf("preserve_split = %t", dw.PreserveSplit))
	}
	if dw.SmartSplit != ddw.SmartSplit {
		dwindle = append(dwindle, fmt.Sprintf("smart_split = %t", dw.SmartSplit))
	}
	if dw.SmartResizing != ddw.SmartResizing {
		dwindle = append(dwindle, fmt.Sprintf("smart_resizing = %t", dw.SmartResizing))
	}
	if dw.DefaultSplitRatio != ddw.DefaultSplitRatio {
		dwindle = append(dwindle, fmt.Sprintf("default_split_ratio = %s", luaNum(dw.DefaultSplitRatio)))
	}
	if dw.ForceSplit != ddw.ForceSplit {
		dwindle = append(dwindle, fmt.Sprintf("force_split = %d", dwindleForceSplit(dw.ForceSplit)))
	}
	if dw.UseActiveForSplits != ddw.UseActiveForSplits {
		dwindle = append(dwindle, fmt.Sprintf("use_active_for_splits = %t", dw.UseActiveForSplits))
	}

	ms, dms := o.Master, d.Master
	if ms.Mfact != dms.Mfact {
		master = append(master, fmt.Sprintf("mfact = %s", luaNum(ms.Mfact)))
	}
	if ms.NewStatus != dms.NewStatus {
		master = append(master, fmt.Sprintf("new_status = %s", luaStr(ms.NewStatus)))
	}
	if ms.NewOnTop != dms.NewOnTop {
		master = append(master, fmt.Sprintf("new_on_top = %t", ms.NewOnTop))
	}
	if ms.Orientation != dms.Orientation {
		master = append(master, fmt.Sprintf("orientation = %s", luaStr(ms.Orientation)))
	}
	if ms.SmartResizing != dms.SmartResizing {
		master = append(master, fmt.Sprintf("smart_resizing = %t", ms.SmartResizing))
	}

	in, di := o.Input, d.Input
	if o.inputSaved {
		input = append(input,
			fmt.Sprintf("kb_layout = %s", luaStr(in.KbLayout)),
			fmt.Sprintf("kb_variant = %s", luaStr(in.KbVariant)),
			fmt.Sprintf("kb_options = %s", luaStr(in.KbOptions)))
	} else {
		if in.KbLayout != di.KbLayout {
			input = append(input, fmt.Sprintf("kb_layout = %s", luaStr(in.KbLayout)))
		}
		if in.KbVariant != di.KbVariant {
			input = append(input, fmt.Sprintf("kb_variant = %s", luaStr(in.KbVariant)))
		}
		if in.KbOptions != di.KbOptions {
			input = append(input, fmt.Sprintf("kb_options = %s", luaStr(in.KbOptions)))
		}
	}
	if in.NumlockByDefault != di.NumlockByDefault {
		input = append(input, fmt.Sprintf("numlock_by_default = %t", in.NumlockByDefault))
	}
	if in.FollowMouse != di.FollowMouse {
		input = append(input, fmt.Sprintf("follow_mouse = %d", in.FollowMouse))
	}
	if in.Sensitivity != di.Sensitivity {
		input = append(input, fmt.Sprintf("sensitivity = %s", luaNum(in.Sensitivity)))
	}
	if in.AccelProfile != di.AccelProfile {
		input = append(input, fmt.Sprintf("accel_profile = %s", luaStr(in.AccelProfile)))
	}
	if in.LeftHanded != di.LeftHanded {
		input = append(input, fmt.Sprintf("left_handed = %t", in.LeftHanded))
	}
	if in.MouseNaturalScroll != di.MouseNaturalScroll {
		input = append(input, fmt.Sprintf("natural_scroll = %t", in.MouseNaturalScroll))
	}
	if in.MouseScrollFactor != di.MouseScrollFactor {
		input = append(input, fmt.Sprintf("scroll_factor = %s", luaNum(in.MouseScrollFactor)))
	}
	if in.RepeatRate != di.RepeatRate {
		input = append(input, fmt.Sprintf("repeat_rate = %d", in.RepeatRate))
	}
	if in.RepeatDelay != di.RepeatDelay {
		input = append(input, fmt.Sprintf("repeat_delay = %d", in.RepeatDelay))
	}
	var touch []string
	if in.NaturalScroll != di.NaturalScroll {
		touch = append(touch, fmt.Sprintf("natural_scroll = %t", in.NaturalScroll))
	}
	if in.TapToClick != di.TapToClick {
		touch = append(touch, fmt.Sprintf("tap_to_click = %t", in.TapToClick))
	}
	if in.TapAndDrag != di.TapAndDrag {
		touch = append(touch, fmt.Sprintf("tap_and_drag = %t", in.TapAndDrag))
	}
	if in.Clickfinger != di.Clickfinger {
		touch = append(touch, fmt.Sprintf("clickfinger_behavior = %t", in.Clickfinger))
	}
	if in.MiddleEmulation != di.MiddleEmulation {
		touch = append(touch, fmt.Sprintf("middle_button_emulation = %t", in.MiddleEmulation))
	}
	if in.TouchScrollFactor != di.TouchScrollFactor {
		touch = append(touch, fmt.Sprintf("scroll_factor = %s", luaNum(in.TouchScrollFactor)))
	}
	if in.DisableWhileTyping != di.DisableWhileTyping {
		touch = append(touch, fmt.Sprintf("disable_while_typing = %t", in.DisableWhileTyping))
	}
	if len(touch) > 0 {
		input = append(input, "touchpad = { "+strings.Join(touch, ", ")+" }")
	}

	c, dc := o.Cursor, d.Cursor
	if c.InactiveTimeout != dc.InactiveTimeout {
		cursor = append(cursor, fmt.Sprintf("inactive_timeout = %d", c.InactiveTimeout))
	}
	if c.HideOnKeyPress != dc.HideOnKeyPress {
		cursor = append(cursor, fmt.Sprintf("hide_on_key_press = %t", c.HideOnKeyPress))
	}

	if in.MiddleClickPaste != di.MiddleClickPaste {
		misc = append(misc, fmt.Sprintf("middle_click_paste = %t", in.MiddleClickPaste))
	}

	if in.SwipeInvert != di.SwipeInvert {
		gestures = append(gestures, fmt.Sprintf("workspace_swipe_invert = %t", in.SwipeInvert))
	}
	if in.SwipeCreateNew != di.SwipeCreateNew {
		gestures = append(gestures, fmt.Sprintf("workspace_swipe_create_new = %t", in.SwipeCreateNew))
	}
	if in.SwipeDistance != di.SwipeDistance {
		gestures = append(gestures, fmt.Sprintf("workspace_swipe_distance = %d", in.SwipeDistance))
	}

	var sections []string
	if len(general) > 0 {
		sections = append(sections, "  general = { "+strings.Join(general, ", ")+" }")
	}
	if len(dwindle) > 0 {
		sections = append(sections, "  dwindle = { "+strings.Join(dwindle, ", ")+" }")
	}
	if len(master) > 0 {
		sections = append(sections, "  master = { "+strings.Join(master, ", ")+" }")
	}
	if len(deco) > 0 {
		sections = append(sections, "  decoration = { "+strings.Join(deco, ", ")+" }")
	}
	if len(input) > 0 {
		sections = append(sections, "  input = { "+strings.Join(input, ", ")+" }")
	}
	if len(cursor) > 0 {
		sections = append(sections, "  cursor = { "+strings.Join(cursor, ", ")+" }")
	}
	if len(misc) > 0 {
		sections = append(sections, "  misc = { "+strings.Join(misc, ", ")+" }")
	}
	if len(gestures) > 0 {
		sections = append(sections, "  gestures = { "+strings.Join(gestures, ", ")+" }")
	}
	if !o.Appearance.Animations {
		sections = append(sections, "  animations = { enabled = false }")
	}
	if len(sections) == 0 {
		return ""
	}
	return "hl.config({\n" + strings.Join(sections, ",\n") + ",\n})\n\n"
}

// dwindleForceSplit maps the friendly force-split labels the UI stores onto
// Hyprland's dwindle:force_split integer (0 follows the cursor, 1 forces
// left/top, 2 forces right/bottom).
func dwindleForceSplit(s string) int {
	switch s {
	case "left/top":
		return 1
	case "right/bottom":
		return 2
	default:
		return 0
	}
}

// windowRuleField maps the pretty boolean action keys the UI stores onto the
// hl.window_rule field names where they differ. a wrong name here errors inside
// settings.lua and silently disables everything after it, so keep this in step
// with the live API (see hypr_test.go's field-name table).
var windowRuleField = map[string]string{
	"nodim": "no_dim", "noanim": "no_anim", "noblur": "no_blur",
	"noshadow": "no_shadow", "nofocus": "no_focus", "stayfocused": "stay_focused",
	"keepaspectratio": "keep_aspect_ratio",
}

func genWindowRule(i int, r WindowRule) string {
	if r.Action == "" {
		return ""
	}
	var match []string
	if r.Class != "" {
		match = append(match, fmt.Sprintf("class = %s", luaStr(r.Class)))
	}
	if r.Title != "" {
		match = append(match, fmt.Sprintf("title = %s", luaStr(r.Title)))
	}
	if len(match) == 0 {
		return ""
	}
	var prop string
	switch r.Action {
	case "float", "tile", "pin", "fullscreen", "maximize", "center", "immediate", "pseudo",
		"opaque", "xray", "nodim", "noanim", "noblur", "noshadow", "nofocus", "stayfocused",
		"keepaspectratio", "norounding", "noborder":
		// boolean effects; the stored action keys stay stable, the emitted Lua
		// field is the hl API name (which is not always the action key).
		field := windowRuleField[r.Action]
		switch r.Action {
		case "norounding":
			prop = "rounding = 0"
		case "noborder":
			prop = "border_size = 0"
		default:
			if field == "" {
				field = r.Action
			}
			prop = field + " = true"
		}
	case "opacity":
		prop = fmt.Sprintf("opacity = %s", luaNum(parseFloat(r.Value, 1)))
	case "size":
		w, h := parseWxH(r.Value)
		prop = fmt.Sprintf("size = { %d, %d }", w, h)
	case "move":
		x, y := parseWxH(r.Value)
		prop = fmt.Sprintf("move = { %d, %d }", x, y)
	case "workspace":
		prop = fmt.Sprintf("workspace = %s", luaStr(r.Value))
	case "idleinhibit":
		v := r.Value
		if v != "always" && v != "focus" && v != "fullscreen" {
			v = "always"
		}
		prop = fmt.Sprintf("idle_inhibit = %s", luaStr(v))
	case "suppressevent":
		v := r.Value
		if v != "maximize" && v != "fullscreen" && v != "activate" && v != "activatefocus" {
			v = "maximize"
		}
		prop = fmt.Sprintf("suppress_event = %s", luaStr(v))
	default:
		return ""
	}
	name := fmt.Sprintf("ryoku-user-%d", i+1)
	return fmt.Sprintf("hl.window_rule({ name = %s, match = { %s }, %s })\n",
		luaStr(name), strings.Join(match, ", "), prop)
}

func genLayerRule(i int, r LayerRule) string {
	if strings.TrimSpace(r.Namespace) == "" || r.Action == "" {
		return ""
	}
	var prop string
	switch r.Action {
	case "blur":
		prop = "blur = true"
	case "noanim":
		prop = "no_anim = true"
	case "blurpopups":
		prop = "blur_popups = true"
	case "xray":
		prop = "xray = true"
	case "abovelock":
		prop = "above_lock = true"
	case "noshadow":
		// legacy action: layer surfaces lost their shadow effect in Hyprland's
		// rule rewrite. drop it instead of emitting a field the runtime rejects
		// (one bad line would kill the whole generated file).
		return ""
	case "ignorealpha":
		prop = fmt.Sprintf("ignore_alpha = %s", luaNum(parseFloat(r.Value, 0.5)))
	case "dimaround":
		// bool in the hl API; the dim amount is decoration:dim_around.
		prop = "dim_around = true"
	default:
		return ""
	}
	name := fmt.Sprintf("ryoku-layer-%d", i+1)
	return fmt.Sprintf("hl.layer_rule({ name = %s, match = { namespace = %s }, %s })\n",
		luaStr(name), luaStr(r.Namespace), prop)
}

// genAppOverride renders one app's appearance overrides as a single
// hl.window_rule: only the set fields become props, so an unset field inherits
// the global decoration. numeric -1 and toggle "inherit" mean "leave alone". a
// wrong field name would break settings.lua, so every prop here is a proven
// hl.window_rule field (see genWindowRule and hypr_test.go's field table).
func genAppOverride(i int, a AppOverride) string {
	var match []string
	if a.Class != "" {
		match = append(match, fmt.Sprintf("class = %s", luaStr(a.Class)))
	}
	if a.Title != "" {
		match = append(match, fmt.Sprintf("title = %s", luaStr(a.Title)))
	}
	if len(match) == 0 {
		return ""
	}
	var props []string
	if a.Opacity >= 0 && a.Opacity <= 1 {
		props = append(props, fmt.Sprintf("opacity = %s", luaNum(a.Opacity)))
	}
	if a.Rounding >= 0 {
		props = append(props, fmt.Sprintf("rounding = %d", a.Rounding))
	}
	if a.BorderSize >= 0 {
		props = append(props, fmt.Sprintf("border_size = %d", a.BorderSize))
	}
	if a.Blur == "off" {
		props = append(props, "no_blur = true")
	}
	if a.Shadow == "off" {
		props = append(props, "no_shadow = true")
	}
	if a.Dim == "off" {
		props = append(props, "no_dim = true")
	}
	if a.Anim == "off" {
		props = append(props, "no_anim = true")
	}
	if a.Opaque == "on" {
		props = append(props, "opaque = true")
	}
	if len(props) == 0 {
		return ""
	}
	name := fmt.Sprintf("ryoku-app-%d", i+1)
	return fmt.Sprintf("hl.window_rule({ name = %s, match = { %s }, %s })\n",
		luaStr(name), strings.Join(match, ", "), strings.Join(props, ", "))
}

func genKeybind(k Keybind) string {
	if strings.TrimSpace(k.Keys) == "" {
		return ""
	}
	var dsp string
	switch k.Action {
	case "exec", "":
		if strings.TrimSpace(k.Value) == "" {
			return ""
		}
		dsp = fmt.Sprintf("hl.dsp.exec_cmd(%s)", luaStr(k.Value))
	case "close":
		dsp = "hl.dsp.window.close()"
	case "fullscreen":
		dsp = "hl.dsp.window.fullscreen()"
	case "togglefloating":
		dsp = "hl.dsp.window.float({ action = \"toggle\" })"
	default:
		return ""
	}
	if k.Release {
		return fmt.Sprintf("hl.bind(%s, %s, { release = true })\n", luaStr(k.Keys), dsp)
	}
	return fmt.Sprintf("hl.bind(%s, %s)\n", luaStr(k.Keys), dsp)
}

// genUnbinds drops the shipped chords config import must release so an imported
// bind wins. Emitted before genKeybind's binds, i.e. after binds.lua registered
// the shipped chord (an earlier module) and before the imported bind re-adds it,
// so only the user's bind survives on the key.
func genUnbinds(o Overrides) string {
	var b strings.Builder
	for _, c := range o.Unbinds {
		if c = strings.TrimSpace(c); c == "" {
			continue
		}
		fmt.Fprintf(&b, "hl.unbind(%s)\n", luaStr(c))
	}
	return b.String()
}

// genStartHook runs the cursor setcursor + any user autostart commands at
// session start. registers after the base autostart, so its setcursor wins.
func genStartHook(o Overrides) string {
	var lines []string
	d := defaultOverrides().Cursor
	if o.Cursor.Theme != d.Theme || o.Cursor.Size != d.Size {
		lines = append(lines, fmt.Sprintf("  hl.exec_cmd(%s)",
			luaStr(fmt.Sprintf("hyprctl setcursor %s %d", o.Cursor.Theme, o.Cursor.Size))))
	}
	for _, a := range o.Autostart {
		if strings.TrimSpace(a.Command) == "" {
			continue
		}
		lines = append(lines, fmt.Sprintf("  hl.exec_cmd(%s)", luaStr(a.Command)))
	}
	if len(lines) == 0 {
		return ""
	}
	return "hl.on(\"hyprland.start\", function()\n" + strings.Join(lines, "\n") + "\nend)\n"
}

// fullConfigLua = every appearance/input leaf set explicitly (not only the
// diffs), so eval forces the exact state, including a value moved back to its
// default. genConfig stays diff-based for settings.lua; the live preview needs
// to reset any key, not only push it away from the baseline.
func fullConfigLua(o Overrides, follow bool) string {
	a, in, c := o.Appearance, o.Input, o.Cursor
	dw, ms := o.Dwindle, o.Master
	general := []string{
		fmt.Sprintf("gaps_in = %d", a.GapsIn),
		fmt.Sprintf("gaps_out = %d", a.GapsOut),
		fmt.Sprintf("border_size = %d", a.BorderSize),
		fmt.Sprintf("layout = %s", luaStr(a.Layout)),
		fmt.Sprintf("resize_on_border = %t", a.ResizeOnBorder),
		fmt.Sprintf("snap = { enabled = %t }", a.SnapEnabled),
		fmt.Sprintf("extend_border_grab_area = %d", a.ExtendBorderGrab),
		fmt.Sprintf("hover_icon_on_border = %t", a.HoverIconOnBorder),
		fmt.Sprintf("no_focus_fallback = %t", a.NoFocusFallback),
		fmt.Sprintf("resize_corner = %d", a.ResizeCorner),
		fmt.Sprintf("gaps_workspaces = %d", a.GapsWorkspaces),
	}
	if !follow {
		general = append(general,
			fmt.Sprintf("[\"col.active_border\"] = %s", luaStr(luaRGB(a.ActiveBorder))),
			fmt.Sprintf("[\"col.inactive_border\"] = %s", luaStr(luaRGB(a.InactiveBorder))))
	}
	deco := []string{
		fmt.Sprintf("rounding = %d", a.Rounding),
		fmt.Sprintf("rounding_power = %s", luaNum(a.RoundingPower)),
		fmt.Sprintf("active_opacity = %s", luaNum(a.ActiveOpacity)),
		fmt.Sprintf("inactive_opacity = %s", luaNum(a.InactiveOpacity)),
		fmt.Sprintf("fullscreen_opacity = %s", luaNum(a.FullscreenOpacity)),
		fmt.Sprintf("dim_inactive = %t", a.DimInactive),
		fmt.Sprintf("dim_strength = %s", luaNum(a.DimStrength)),
		fmt.Sprintf("dim_special = %s", luaNum(a.DimSpecial)),
		fmt.Sprintf("dim_around = %s", luaNum(a.DimAround)),
		fmt.Sprintf("dim_modal = %t", a.DimModal),
		fmt.Sprintf("border_part_of_window = %t", a.BorderPartOfWindow),
		fmt.Sprintf("blur = { enabled = %t, size = %d, passes = %d, xray = %t, vibrancy = %s, noise = %s, "+
			"contrast = %s, brightness = %s, special = %t, popups = %t, ignore_opacity = %t, new_optimizations = %t, vibrancy_darkness = %s }",
			a.BlurEnabled, a.BlurSize, a.BlurPasses, a.BlurXray, luaNum(a.BlurVibrancy), luaNum(a.BlurNoise),
			luaNum(a.BlurContrast), luaNum(a.BlurBrightness), a.BlurSpecial, a.BlurPopups, a.BlurIgnoreOpacity, a.BlurNewOptimizations, luaNum(a.BlurVibrancyDarkness)),
		fmt.Sprintf("shadow = { enabled = %t, range = %d, render_power = %d, sharp = %t, scale = %s }",
			a.ShadowEnabled, a.ShadowRange, a.ShadowPower, a.ShadowSharp, luaNum(a.ShadowScale)),
		fmt.Sprintf("glow = { enabled = %t, range = %d, color = %s }",
			a.GlowEnabled, a.GlowRange, luaStr(luaRGB(a.GlowColor))),
	}
	input := []string{
		fmt.Sprintf("kb_layout = %s", luaStr(in.KbLayout)),
		fmt.Sprintf("kb_variant = %s", luaStr(in.KbVariant)),
		fmt.Sprintf("kb_options = %s", luaStr(in.KbOptions)),
		fmt.Sprintf("numlock_by_default = %t", in.NumlockByDefault),
		fmt.Sprintf("follow_mouse = %d", in.FollowMouse),
		fmt.Sprintf("sensitivity = %s", luaNum(in.Sensitivity)),
		fmt.Sprintf("accel_profile = %s", luaStr(in.AccelProfile)),
		fmt.Sprintf("left_handed = %t", in.LeftHanded),
		fmt.Sprintf("natural_scroll = %t", in.MouseNaturalScroll),
		fmt.Sprintf("scroll_factor = %s", luaNum(in.MouseScrollFactor)),
		fmt.Sprintf("repeat_rate = %d", in.RepeatRate),
		fmt.Sprintf("repeat_delay = %d", in.RepeatDelay),
		fmt.Sprintf("touchpad = { natural_scroll = %t, tap_to_click = %t, tap_and_drag = %t, "+
			"clickfinger_behavior = %t, middle_button_emulation = %t, scroll_factor = %s, disable_while_typing = %t }",
			in.NaturalScroll, in.TapToClick, in.TapAndDrag,
			in.Clickfinger, in.MiddleEmulation, luaNum(in.TouchScrollFactor), in.DisableWhileTyping),
	}
	return "hl.config({\n" +
		"  general = { " + strings.Join(general, ", ") + " },\n" +
		"  decoration = { " + strings.Join(deco, ", ") + " },\n" +
		"  input = { " + strings.Join(input, ", ") + " },\n" +
		fmt.Sprintf("  cursor = { inactive_timeout = %d, hide_on_key_press = %t },\n", c.InactiveTimeout, c.HideOnKeyPress) +
		fmt.Sprintf("  misc = { middle_click_paste = %t },\n", in.MiddleClickPaste) +
		fmt.Sprintf("  gestures = { workspace_swipe_invert = %t, workspace_swipe_create_new = %t, workspace_swipe_distance = %d },\n",
			in.SwipeInvert, in.SwipeCreateNew, in.SwipeDistance) +
		fmt.Sprintf("  animations = { enabled = %t },\n", a.Animations) +
		fmt.Sprintf("  dwindle = { preserve_split = %t, smart_split = %t, smart_resizing = %t, default_split_ratio = %s, force_split = %d, use_active_for_splits = %t },\n",
			dw.PreserveSplit, dw.SmartSplit, dw.SmartResizing, luaNum(dw.DefaultSplitRatio), dwindleForceSplit(dw.ForceSplit), dw.UseActiveForSplits) +
		fmt.Sprintf("  master = { mfact = %s, new_status = %s, new_on_top = %t, orientation = %s, smart_resizing = %t },\n",
			luaNum(ms.Mfact), luaStr(ms.NewStatus), ms.NewOnTop, luaStr(ms.Orientation), ms.SmartResizing) +
		"})\n"
}

// genAnimItem: one hl.animation override line.
func genAnimItem(it AnimItem) string {
	if strings.TrimSpace(it.Leaf) == "" {
		return ""
	}
	parts := []string{
		fmt.Sprintf("leaf = %s", luaStr(it.Leaf)),
		fmt.Sprintf("enabled = %t", it.Enabled),
		fmt.Sprintf("speed = %s", luaNum(it.Speed)),
	}
	if it.Bezier != "" {
		parts = append(parts, fmt.Sprintf("bezier = %s", luaStr(it.Bezier)))
	}
	if it.Style != "" {
		parts = append(parts, fmt.Sprintf("style = %s", luaStr(it.Style)))
	}
	return fmt.Sprintf("hl.animation({ %s })\n", strings.Join(parts, ", "))
}

// genAnimBlock = the user's bezier curves (first, so the items can reference
// them) + the per-leaf animation overrides.
func genAnimBlock(o Overrides) string {
	var b strings.Builder
	for _, c := range o.Anim.Curves {
		if strings.TrimSpace(c.Name) == "" {
			continue
		}
		fmt.Fprintf(&b, "hl.curve(%s, { type = \"bezier\", points = { { %s, %s }, { %s, %s } } })\n",
			luaStr(c.Name), luaNum(c.X0), luaNum(c.Y0), luaNum(c.X1), luaNum(c.Y1))
	}
	for _, it := range o.Anim.Items {
		if a := genAnimItem(it); a != "" {
			b.WriteString(a)
		}
	}
	return b.String()
}

// genGesture: the workspace-swipe touchpad gesture when enabled. the base
// config ships no gesture, so an empty string leaves swipe off.
func genGesture(o Overrides) string {
	if !o.Input.WorkspaceSwipe {
		return ""
	}
	n := o.Input.SwipeFingers
	if n < 3 {
		n = 3
	}
	return fmt.Sprintf("hl.gesture({ fingers = %d, direction = \"horizontal\", action = \"workspace\" })\n", n)
}

// wobbleCurve = an easeOutBack overshoot: a moved window shoots a touch past its
// mark and springs back, so a dragged float trails the cursor and settles with a
// little wobble. only emitted when the toggle is on.
const wobbleCurve = "hl.curve(\"ryokuWobble\", { type = \"bezier\", points = { { 0.34, 1.56 }, { 0.64, 1 } } })\n"

// genMotion: the window-motion toggles the Look tab owns (spring drag, open and
// close style), kept out of the diff-based hl.config so wobble can define its own
// curve. full marks a live preview, which restates the base feel too so eval can
// switch a toggle back off; settings.lua (full = false) writes only what diverges.
func genMotion(o Overrides, full bool) string {
	a := o.Appearance
	var b strings.Builder
	switch {
	case a.WobblyWindows:
		b.WriteString(wobbleCurve)
		b.WriteString("hl.animation({ leaf = \"windowsMove\", enabled = true, speed = 5, bezier = \"ryokuWobble\" })\n")
	case full:
		// reset the drag back to the base windows feel for the preview.
		b.WriteString("hl.animation({ leaf = \"windowsMove\", enabled = true, speed = 3.2, bezier = \"ryokuSettle\" })\n")
	}
	switch a.WindowStyle {
	case "slide", "gnomed":
		fmt.Fprintf(&b, "hl.animation({ leaf = \"windowsIn\", enabled = true, speed = 3.8, bezier = \"ryokuBloom\", style = %s })\n", luaStr(a.WindowStyle))
		fmt.Fprintf(&b, "hl.animation({ leaf = \"windowsOut\", enabled = true, speed = 2.4, bezier = \"ryokuSettle\", style = %s })\n", luaStr(a.WindowStyle))
	default:
		if full {
			b.WriteString("hl.animation({ leaf = \"windowsIn\", enabled = true, speed = 3.8, bezier = \"ryokuBloom\", style = \"popin 78%\" })\n")
			b.WriteString("hl.animation({ leaf = \"windowsOut\", enabled = true, speed = 2.4, bezier = \"ryokuSettle\", style = \"popin 86%\" })\n")
		}
	}
	return b.String()
}

// gradientBorderBlock re-reads the live palette accents at load time (like
// decoration.lua) so the rotating border re-themes with the wallpaper on reload.
const gradientBorderBlock = "do\n" +
	"  local ok, wc = pcall(dofile, os.getenv(\"HOME\") .. \"/.cache/ryoku/hypr-colors.lua\")\n" +
	"  local function rgb(h, f) if type(h) ~= \"string\" then h = f end return \"rgb(\" .. h:gsub(\"#\", \"\") .. \")\" end\n" +
	"  hl.config({ general = { [\"col.active_border\"] = { colors = { rgb(ok and wc and wc.active, \"#e0563b\"), rgb(ok and wc and wc.inactive, \"#313a4d\") }, angle = 45 } } })\n" +
	"end\n"

// solidBorderBlock restores the plain palette active border, for a preview that
// switches the rotating border back off.
const solidBorderBlock = "do\n" +
	"  local ok, wc = pcall(dofile, os.getenv(\"HOME\") .. \"/.cache/ryoku/hypr-colors.lua\")\n" +
	"  local function rgb(h, f) if type(h) ~= \"string\" then h = f end return \"rgb(\" .. h:gsub(\"#\", \"\") .. \")\" end\n" +
	"  hl.config({ general = { [\"col.active_border\"] = rgb(ok and wc and wc.active, \"#e0563b\") } })\n" +
	"end\n"

// borderAngleHyprSpeed maps the friendly 1..10 rotation speed the UI shows onto
// Hyprland's deciseconds-per-turn (higher is slower there), so a bigger slider
// value spins faster. clamped so a stray value can't stall the sweep.
func borderAngleHyprSpeed(friendly float64) float64 {
	if friendly < 1 {
		friendly = 1
	}
	if friendly > 10 {
		friendly = 10
	}
	return 110 - friendly*10
}

// genAnimatedBorder: a rotating gradient on the active window border. off writes
// nothing to settings.lua (the base solid border stands); a live preview instead
// stops the sweep and restores the solid border so the toggle reads at once. the
// gradient reads the palette accents at load time when colours follow the
// wallpaper, and uses the fixed border colours otherwise.
func genAnimatedBorder(o Overrides, follow, full bool) string {
	a := o.Appearance
	if !a.AnimatedBorder {
		if !full {
			return ""
		}
		var b strings.Builder
		b.WriteString("hl.animation({ leaf = \"borderangle\", enabled = false, speed = 1, bezier = \"linear\" })\n")
		if follow {
			b.WriteString(solidBorderBlock) // fullConfigLua emits no border while following
		}
		return b.String()
	}
	var b strings.Builder
	if follow {
		b.WriteString(gradientBorderBlock)
	} else {
		grad := fmt.Sprintf("{ colors = { %s, %s }, angle = 45 }", luaStr(luaRGB(a.ActiveBorder)), luaStr(luaRGB(a.InactiveBorder)))
		fmt.Fprintf(&b, "hl.config({ general = { [\"col.active_border\"] = %s } })\n", grad)
	}
	fmt.Fprintf(&b, "hl.animation({ leaf = \"borderangle\", enabled = true, speed = %s, bezier = \"linear\", style = \"loop\" })\n",
		luaNum(borderAngleHyprSpeed(a.BorderAngleSpeed)))
	return b.String()
}

// liveLua = full-config preview + cursor + the loaded plugins' config, applied
// flash-free via hyprctl eval (appearance / input / cursor / plugin settings).
// rules, keybinds, env, autostart are not previewed; they apply on Save via
// reload, as does turning a plugin on or off (a load is a reload's job).
func liveLua(o Overrides) string {
	follow := paletteDriven()
	return fullConfigLua(o, follow) + genMotion(o, true) + genAnimatedBorder(o, follow, true) +
		genAnimBlock(o) + genGesture(o) + genPluginConfig(o) +
		fmt.Sprintf("hl.exec_cmd(%s)\n", luaStr(fmt.Sprintf("hyprctl setcursor %s %d", o.Cursor.Theme, o.Cursor.Size)))
}

// --- Lua value helpers ----------------------------------------------------

func luaStr(s string) string {
	r := strings.NewReplacer("\\", "\\\\", "\"", "\\\"", "\n", "\\n", "\r", "\\r")
	return "\"" + r.Replace(s) + "\""
}

func luaNum(f float64) string {
	s := fmt.Sprintf("%g", f)
	if !strings.ContainsAny(s, ".eE") {
		s += ".0"
	}
	return s
}

// luaRGB: "#rrggbb" (or "rrggbb") -> Hyprland's rgb(rrggbb) form.
func luaRGB(hex string) string {
	h := strings.TrimPrefix(strings.TrimSpace(hex), "#")
	return "rgb(" + h + ")"
}

func parseFloat(s string, fallback float64) float64 {
	var f float64
	if _, err := fmt.Sscanf(strings.TrimSpace(s), "%g", &f); err != nil {
		return fallback
	}
	return f
}

// parseWxH: "1500x850" (or "1500 850" / "1500,850") -> two ints.
func parseWxH(s string) (int, int) {
	s = strings.NewReplacer("x", " ", "X", " ", ",", " ").Replace(s)
	var a, b int
	fmt.Sscan(s, &a, &b)
	return a, b
}

// --- environment enumeration ----------------------------------------------

// listCursorThemes: installed cursor themes = icon-theme dirs that contain a
// cursors/ subdir, across the standard search paths, dedup'd and sorted.
func listCursorThemes() []string {
	seen := map[string]bool{}
	for _, dir := range iconSearchDirs() {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			if _, err := os.Stat(filepath.Join(dir, e.Name(), "cursors")); err == nil {
				seen[e.Name()] = true
			}
		}
	}
	out := make([]string, 0, len(seen))
	for n := range seen {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

func iconSearchDirs() []string {
	home := os.Getenv("HOME")
	dataHome := os.Getenv("XDG_DATA_HOME")
	if dataHome == "" {
		dataHome = filepath.Join(home, ".local", "share")
	}
	return []string{
		filepath.Join(home, ".icons"),
		filepath.Join(dataHome, "icons"),
		"/usr/share/icons",
		"/usr/local/share/icons",
	}
}

// listKbLayouts: X11 keyboard layout codes from the xkb rules base, each as
// {code, name}. falls back to a small common set if the base is absent.
func listKbLayouts() []map[string]string {
	out := parseXkbLayouts("/usr/share/X11/xkb/rules/base.lst")
	if len(out) == 0 {
		out = parseXkbLayouts("/usr/share/X11/xkb/rules/evdev.lst")
	}
	if len(out) == 0 {
		for _, c := range []string{"us", "gb", "de", "fr", "es", "it", "ru", "jp"} {
			out = append(out, map[string]string{"code": c, "name": strings.ToUpper(c)})
		}
	}
	return out
}

// listKbVariants: X11 variant codes for one layout from the xkb rules base,
// each as {code, name}. an unknown layout (or an absent base) yields [].
func listKbVariants(layout string) []map[string]string {
	out := parseXkbVariants("/usr/share/X11/xkb/rules/base.lst", layout)
	if len(out) == 0 {
		out = parseXkbVariants("/usr/share/X11/xkb/rules/evdev.lst", layout)
	}
	if out == nil {
		out = []map[string]string{}
	}
	return out
}

// parseXkbVariants reads the "! variant" block of an xkb rules .lst file and
// keeps the entries for one layout. lines look like
// "  <variant>  <layout>: <description>"; the layout field can carry several
// comma-separated codes, so it is split before matching.
func parseXkbVariants(path, layout string) []map[string]string {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []map[string]string
	in := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		t := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(t, "!") {
			in = t == "! variant"
			continue
		}
		if !in || t == "" {
			continue
		}
		fields := strings.Fields(t)
		if len(fields) < 2 {
			continue
		}
		code := fields[0]
		rest := strings.TrimSpace(strings.TrimPrefix(t, code))
		layouts, desc, ok := strings.Cut(rest, ":")
		if !ok {
			continue
		}
		match := false
		for _, l := range strings.Split(layouts, ",") {
			if strings.TrimSpace(l) == layout {
				match = true
				break
			}
		}
		if !match {
			continue
		}
		out = append(out, map[string]string{"code": code, "name": strings.TrimSpace(desc)})
	}
	return out
}

// parseXkbLayouts reads the "! layout" block of an xkb rules .lst file.
func parseXkbLayouts(path string) []map[string]string {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []map[string]string
	in := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		t := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(t, "!") {
			in = t == "! layout"
			continue
		}
		if !in || t == "" {
			continue
		}
		fields := strings.Fields(t)
		if len(fields) < 2 {
			continue
		}
		code := fields[0]
		name := strings.TrimSpace(strings.TrimPrefix(t, code))
		out = append(out, map[string]string{"code": code, "name": name})
	}
	return out
}
