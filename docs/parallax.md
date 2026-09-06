# Parallax

A layer module for the wallpaper. The composition is a dedicated
layer-shell surface at `WlrLayer.Background` (one `PanelWindow` per
monitor, click-through, keyboard-less, namespace `ryoku-parallax`) that
paints the recoloured background and drifts with the cursor; the layer
bands render inside the desktop surface at their scene z, so layers,
widgets and the audio visualizer really interleave on screen.

Two cutout modes per wallpaper:

* **Auto** - the daemon shells the standalone engine
  (`ryoku-parallax-engine`, own venv and model cache under
  `~/.local/state/ryoku/parallax`, no dependency on `ryoku-depth`):
  1. `cutout` produces the subject as an alpha-matted PNG;
  2. `inpaint` recolours the cutout's hole with the surrounding colour
     (fill holes, close gaps, widen the rim, then one mean over the
     surrounding ring), so a drifted subject reveals the backdrop
     instead of its own ghost.
* **Manual** - the user drops `layer-NN.png` files into the wallpaper's
  folder; the daemon lists whatever it finds. No engine runs.

Every artifact lives in `~/Pictures/Parallax/<stem>/`: the recoloured
background (`background.png`), the numbered layers (`layer-NN.png`) and
the registry (`~/Pictures/Parallax/layers.pz`, daemon-owned). The
global knobs live in `~/.config/ryoku/parallax.json`; a cut is reused
by mtime, so the same wallpaper is never reprocessed.

## Per-layer model

Each layer is an object with its own knobs, indexed by layer (0 = layer
1, back of the scene), all writable live from the sidebar:

| Knob | Default | What it does |
|---|---|---|
| `layerEnabled` | true | Layer visible on the desktop. |
| `parallax` | 1.0 | Cursor strength multiplier (0..2). |
| `depth` | 0.5 | Depth factor (0..1); deeper layers drift more. |
| `mouseMax` | 32 | Max cursor drift in px per axis (0..96). |
| `opacity` | 1.0 | Layer alpha (0..1). |
| `offsetX` / `offsetY` | 0 | Manual positional offset in px. |
| `shadow` | 0 | Drop shadow strength 0..1 (depth effect's recipe). |
| `shadowAngle` | 90 | Shadow direction in degrees (0 = right, 90 = down), set with a draggable dial. |
| `feather` | 0 | Edge blur 0..1 (depth effect's feather). |
| `lift` | 0 | Subject pop 0..1 (depth effect's lift). |
| `audioLevel` | 0 | Audio reactivity 0..1 via the shared spectrum. |
| `animType` | none | Idle motion: none, float, pulse, scale, wiggle, rotate. |
| `animSpeed` / `animAmplitude` | 0.5 / 10 | Animation speed (0.1..3) and amplitude (px or deg). |

Global motion knobs: `mouseEnabled`, `mouseSensitivity` (0.05..2),
`mouseRange` (0.02..1 of the drift cap), `wallpaperParallax` (0..1: the
base drifts at this share, layers at their own knobs, so the rate
difference is the visible parallax). Presets (`none`, `softdepth`,
`audiopulse`, `cinematic`) tune the whole stack at once; `none` resets
the defaults. Sliders are drag-only (the mouse wheel never changes a
value).

## Visualizer and scene order

The audio visualizer draws inline inside the desktop at its scene z
while parallax owns the background; the standalone surface hides (it
reappears while placing). The Order panel reorders layers, active
widgets and the visualizer with up/down arrows, persisted per wallpaper
by the daemon (`set-scene`). The order is real: each entry's z comes
from the scene list, so a widget or the visualizer can sit between two
layers. Off, widget z falls back to the depth front toggle.

## How the parts fit

```
ryoku-shell daemon (Go)                    shell (QML)
-----------------------                    -----------
parallax set-enabled / set-mode /          modules/parallax/Singletons/Config.qml
  add-layer / remove-layer / refresh        reads parallax.json (knobs) and
  -> parallaxWorker (coalescing)            layers.pz (registry),
  -> auto mode:  ryoku-parallax-engine      exposes the active wallpaper's
                   cutout + inpaint          layer urls, per-layer knobs and
  -> manual mode: read <stem>/layer-NN.png   the scene z math
  -> writes layers.pz                      modules/parallax/ParallaxBand.qml
      (per-wall opt-in + layer paths)        (one layer: cursor drift, feather,
                                              lift, angled shadow, animation,
                                              audio reactivity)
                                            modules/parallax/ParallaxBackground.qml
                                              owns the WlrLayer.Background
                                              surface (recoloured background +
                                              drift); Desktop.qml hosts the
                                              bands, the inline visualizer and
                                              hides its backdrop while parallax
                                              owns.
```

- **Engine.** `ryoku-parallax-engine` is a standalone copy of
  `ryoku-depth` cut to subject-only. Own state dir and models, so the
  parallax module never depends on the depth install. Commands: `check`,
  `models`, `cutout <in> <out> [--model ID] [--alpha-matting]`,
  `inpaint <image> <mask> <out>`, `install [model...]`, `remove <model>`.
- **Worker.** `ipc/parallax.go` mirrors the wallpaper topic, then for
  each opted-in wallpaper generates or reuses the layer set. Opt-in is
  per wallpaper and persists (`ryoku-shell parallax set-enabled 1|0`);
  `set-mode` switches auto/manual; `refresh` re-runs the worker;
  `add-layer` / `remove-layer` manage the manual folder (the remove
  validates the path stays inside the wallpaper's folder). A refresh
  while a cut is running, or within ten seconds of the previous finish,
  is a no-op. `parallax status` returns
  `{busy, current, layers, mode, stage, percent}`.
- **Scene.** `parallax.json` `scene` is the ordered list: `wallpaper`,
  `layer:<i>` (1..N), `widget:<id>`, `visualizer`. Empty means the
  program computes the default. The tab's arrows move a row over or
  under the others; Reset returns to the default.
- **Render.** With the module on, `Desktop.qml` hides its backdrop (the
  parallax surface owns the background layer), hosts the bands at their
  scene z, and draws the visualizer inline; widgets resolve their z from
  the same list. Off, everything behaves as before.

## Configuration: `~/.config/ryoku/parallax.json`

Self-seeded, watched, GUI-managed (the Parallax tab in the Super+Esc
quick-settings panel, beside the Depth tab).

| Key | Default | What it is |
|---|---|---|
| `enabled` | `false` | Module gate: layers only render when on. |
| `mode` | `auto` | Cutout source: `auto` or `manual`. Per-wall overrides live in `layers.pz`. |
| `model` | `u2netp` | Subject-tier model for the standalone engine. |
| `alphaMatting` | `false` | Alpha-matting on the subject cutout. |
| `bands` | `1` | Fallback layer count before a wallpaper is cut. |
| `mouseEnabled` / `mouseSensitivity` / `mouseRange` | true / 0.9 / 1.0 | Global mouse reactivity. |
| `wallpaperParallax` | `0.5` | Wallpaper drift strength (0..1 of the cap). |
| `parallax` [], `depth` [], `mouseMax` [], `opacity` [], `offsetX` [], `offsetY` [], `shadow` [], `shadowAngle` [], `feather` [], `lift` [], `audioLevel` [], `animType` [], `animSpeed` [], `animAmplitude` [], `layerEnabled` [] | per-layer arrays | The per-layer knobs (table above). |
| `scene` | `[]` | Ordered scene list; `[]` = program default. |

Registry: `~/Pictures/Parallax/layers.pz` (daemon-owned):
`{walls: {<path>: {enabled, mode, scene}}, layers: {<path>:
[{out, rev, label}...]}}`.

Manual folder layout: `~/Pictures/Parallax/<stem>/layer-NN.png` where
`<stem>` is the wallpaper's basename minus extension and `NN` is at
least two digits, sorted ascending (lowest `NN` = back of the scene).

Engine status stream: `~/.local/state/ryoku/parallax/progress`, one
JSON document per line; the last line carries `stage: "done"` on
success or `"cancelled"` on SIGKILL.

## Delivery

QML and the Go worker ship in the shell tree; the engine installs to
`/usr/bin` next to `ryoku-depth`. `parallax.json` is self-seeded and
`layers.pz` is daemon-owned.
