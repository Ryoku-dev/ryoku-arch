# Ryostage (舞台)

The desktop as a stage: the wallpaper is the backdrop, the subject and any
extra cut-outs are the layers, and the clock, widgets and the audio
visualizer are the cast, arranged in front of or behind them. Depth and
Parallax used to be two features with two engines, two settings files, two
sidebar tabs and two artifact folders. They are one thing: **Depth is a
stage with a single still layer in front of the widgets; Parallax is the
same stage with motion on.** Ryostage is that one thing.

Names, so the parts are findable:

| Part | Name | Where |
|---|---|---|
| The feature and its sidebar tab | **Stage** (`stage` quick-settings module) | `quickshell/shell/modules/stage/`, `QuickSettingsStage.qml` |
| The cut-out engine helper | **`ryostage`** | `ryoku/shell/scripts/ryostage`, shipped to `/usr/bin` |
| The daemon module | `stage` topic and verbs | `ryoku/shell/ipc/stage.go` |
| The settings | `~/.config/ryoku/stage.json` | user-owned, GUI-managed, never materialized |
| Per-wallpaper scene state | `~/.local/state/ryoku/stage-walls.json` | daemon-owned |
| Artifacts | `~/Pictures/Stage/<stem>/` | the user's files, one folder per wallpaper |
| Engine runtime and models | `~/.local/state/ryoku/ryostage/` | one venv, one model cache |

`ryoku-depth`, `ryoku-parallax-engine`, `depth.json`, `parallax.json`,
`depth-walls.json`, `~/Pictures/Depth`, `~/Pictures/Parallax` and the
`depth`/`parallax` tabs are retired; the doctor migrates all of them (below).

## The mental model a user needs

Three levels, and most people stop at the first.

1. **Effect.** Off, **Subject in front** (the old Depth), or **Parallax**
   (the subject and layers drift with the cursor, the backdrop is recoloured
   behind them). One three-way control at the top of the Stage tab, plus a
   live preview of the current wallpaper's cut. Turning either on for a
   wallpaper the engine has not cut yet runs the cut once and remembers it
   per wallpaper, exactly as Depth did.
2. **Look.** Quality (Draft / Standard / Fine), edge fade, strength, shadow
   with its angle dial. These apply to the subject layer; every layer inherits
   them until it is edited on its own.
3. **Scene** (collapsed by default). The layer list (the auto subject plus any
   `layer-NN.png` the user adds), per-layer knobs (motion, idle animation,
   audio reactivity, offsets), the cast order (which widgets and the
   visualizer sit in front of or behind each layer), presets, and the
   maintenance actions (open the folder, re-cut, clear cache).

Nothing in level 1 or 2 mentions layers, z-order, inpainting or models. The
words "Depth" and "Parallax" survive only as the names of the two effects.

## Models: one catalogue, visible provenance

`ryostage` owns the curated list, and the UI renders it instead of hardcoding
tiers:

```
ryostage models --json
[
  {"id":"u2netp","label":"Draft","tier":"draft","size":"4.6 MB","installed":true,
   "licence":"Apache-2.0 (mirrored weights)","upstream":"https://github.com/xuebinqin/U-2-Net"},
  {"id":"birefnet-general-lite","label":"Fine","tier":"fine","size":"224 MB","installed":false,
   "licence":"MIT","upstream":"https://github.com/ZhengPeng7/BiRefNet"}
]
```

The Quality control maps Draft -> `u2netp`, Standard -> `u2netp` with alpha
matting, Fine -> `birefnet-general-lite` with matting. Picking a tier whose
model is not installed shows the size and a **Download** button in place;
`Remove` frees it again. The runtime (`rembg[cpu]`, MIT, on ONNX Runtime,
MIT) installs once, on the first enable, into the shared cache. Nothing ML
ships in the base image. Both scripts' licence notes live in the engine's
header and here, so a packager can check them.

## Engine: `ryostage`

One bash helper, the only place model logic lives. Backend resolution is
unchanged from `ryoku-depth` (the managed venv first, then a system Python in
rembg's range, `uv` provisioning a managed 3.13 otherwise).

| Subcommand | Contract |
|---|---|
| `check` | exit 0 and print `available` when the runtime and at least one model are present, else `missing` and non-zero |
| `models [--json]` | the curated catalogue: ids one per line, or the JSON above |
| `install [model...]` | provision the runtime and fetch the named models (default `u2netp`); opt-in, streams progress |
| `remove <model>` | drop a cached model |
| `cut <in> <out.png> [--model id] [--matting]` | the subject as an alpha-matted PNG; never writes a partial file |
| `inpaint <image> <mask> <out.png>` | fill the cut-out's hole with the surrounding colour (the parallax backdrop) |

Cache: `~/.local/state/ryoku/ryostage/{venv,models}`. On first run the
helper adopts a pre-split `~/.local/state/ryoku/depth` or `.../parallax` tree by
rename (same filesystem, no re-download); a leftover second tree is reported
by the doctor as reclaimable space.

## Daemon: `ipc/stage.go`

One worker, one registry, one topic. It replaces `depth.go` and `parallax.go`.

- **Registry** `~/.local/state/ryoku/stage-walls.json`:
  `{ "current": "<path>", "walls": { "<path>": { "effect": "off|subject|parallax",
  "mode": "auto|manual", "scene": [...], "layers": [ {per-layer knobs} ] } } }`.
  Per-wallpaper, because a cut belongs to one image and a user's arrangement
  belongs to that image.
- **Artifacts** `~/Pictures/Stage/<stem>/`: `subject.png` (the auto cut),
  `background.png` (the inpainted backdrop, only when parallax is on),
  `layer-NN.png` (manual layers), `.index.json` (mtime reuse). The old
  `~/Pictures/Depth/<wallpaper>-depth.png` becomes `subject.png` of its stem;
  `~/Pictures/Parallax/<stem>/` is moved whole.
- **Topic** `stage`: `{ "wall": <path>, "effect": ..., "busy": bool, "stage": "cut|inpaint",
  "percent": n, "subject": "<path>", "background": "<path>", "layers": [...],
  "scene": [...], "rev": mtime }`. QML renders from this and nothing else.
  ryogami keeps folding the subject as `depth` in the wallpaper frame for
  pixel-lock, unchanged on the wire.
- **Verbs** (`ryoku-shell stage ...`): `set-effect <off|subject|parallax>`,
  `set-mode <auto|manual>`, `refresh`, `cancel`, `status`, `set-scene <json>`,
  `set-layer <index> <json>`, `add-layer <path>`, `remove-layer <path>`,
  `clear`. `depth *` and `parallax *` are gone; the shell is updated with
  them.
- A wallpaper switch reconciles and never auto-generates (Depth's rule): a
  wallpaper with a stage reuses it instantly, one without shows the plain
  wallpaper. Generation runs only on an effect change, a quality change,
  re-cut, or a manual-layer edit.

## Settings: `~/.config/ryoku/stage.json`

Global only; anything per-wallpaper is in the registry.

| Key | Default | What it is |
|---|---|---|
| `quality` | `draft` | `draft` / `standard` / `fine`, the model + matting pair |
| `feather`, `lift`, `shadow`, `shadowAngle` | `0.15`, `1.0`, `0`, `90` | defaults every layer inherits |
| `motion` | `{mouse:true, sensitivity:1, range:0.3, wallpaper:0.2}` | parallax drift |
| `preset` | `none` | `none`, `softdepth`, `audiopulse`, `cinematic` |
| `front` | `[]` | widget ids drawn above the subject when no per-wall scene exists (migrated from depth) |

Migration is a doctor check (`stage settings`): `depth.json` and
`parallax.json` fold into `stage.json`, `depth-walls.json` and `layers.pz`
into `stage-walls.json`, the two picture folders into `~/Pictures/Stage`,
the two quick-settings tabs into one `stage` tab in the same position, and the
two state caches into one. Every step is idempotent and leaves the user's
files where they were on failure.

## Rendering: `modules/stage/`

`StageBackground.qml` (the recoloured backdrop with drift, only for the
parallax effect, one layer-shell surface per monitor at `Background`),
`StageLayer.qml` (one cut-out band at its scene z, with feather, lift,
shadow, drift, idle animation and audio reactivity), and the desktop reads its
own monitor's entry from the `stage` topic, keyed by wallpaper path. The
Subject-in-front effect is a `StageLayer` above the widgets with motion off:
there is no second renderer for Depth.

## Editing on the desktop

Right-click on the desktop gains **Edit stage**. It opens the existing
compose mode (widgets draggable, the compose bar) with the Stage tab docked,
and each element's right-click menu carries **In front of the subject /
Behind the subject** and, with parallax on, its layer. Knobs stay in the
sidebar; the desktop is only the canvas. That is the whole editor: no
floating inspectors, no second settings surface.

## Delivery

`ryostage` ships in `ryoku-shell` (`/usr/bin/ryostage`) and via `deploy.sh`;
the QML in `ryoku-desktop`. `tests/shell-tool-availability.sh` gates
`[stage-engine]=ryostage` is not needed (the runtime is opt-in), but the helper
must be on both install paths, which the delivery check enforces.
