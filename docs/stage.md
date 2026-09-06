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

The two retired engine helpers (the old Depth and Parallax segmentation
scripts), `depth.json`, `parallax.json`, `depth-walls.json`, `~/Pictures/Depth`,
`~/Pictures/Parallax` and the `depth`/`parallax` tabs are retired; the doctor
migrates all of them (below).

## The mental model a user needs

One stack, back to front: the **backdrop** (the wallpaper), the **layers**
(the cut-out subject, plus any picture you add), and the **widgets**. A layer
is either behind the widgets or in front of them. That is the whole model,
and the Stage tab shows exactly that and nothing engine-shaped.

```
 Stage
 [ preview card: the wallpaper with the subject lifted            ]
 [ while cutting: the same card dims, a progress ring + Stop      ]
 Effect     ( Off | Depth | Parallax )
            "Depth: the subject sits in front of your widgets."
 LOOK
 Quality    ( Draft | Standard | Fine )          "224 MB  Download"
 Edge       [-----o----]
 Shadow     [--o-------]  (o) angle dial, shown only while Shadow > 0
 MOTION                                   (only while Parallax)
 Amount     ( Subtle | Normal | Strong )
 Idle       ( None | Float | Breathe )
 [x] React to music
 LAYERS
 [ img ] Subject            ( Behind | In front )   [near ---o--- far]
 [ img ] Lantern.png        ( Behind | In front )   [near --o---- far]  x
 + Add layer   (Cut from a picture... / From a PNG...)
 ARRANGE
 [ Edit on desktop ] [ Open folder ] [ Re-cut ] [ Clear cut-outs ]
```

Rules that keep it simple:

- **Every idea has one control.** Edge, shadow and quality live once, in
  Look, and apply to every layer. There are no per-layer look overrides.
- **A layer has three properties**: on/off, *behind or in front of the
  widgets*, and *near or far* (how much it drifts in Parallax; ignored in
  Depth). Nothing else. Offsets, per-layer opacity, per-layer audio and
  animation, mouse caps and presets are gone: Amount / Idle / React to music
  cover the whole stack.
- **Depth and Parallax are the same stack.** Depth renders the layers still;
  Parallax adds drift and the recoloured backdrop. Switching effect never
  re-cuts: the cut depends on the wallpaper and the quality only.
- **Labels never clip**: the effect control is `Off | Depth | Parallax` (the
  names people already use) and the one-line caption under it explains the
  selected one.
- **The preview card owns progress.** Cutting dims the card and draws a ring
  with a Stop button on it; nothing else in the tab moves or appears.
- The audio visualizer keeps its own placement (its own tab); it is not a
  stage layer.

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
unchanged from the old Depth engine (the managed venv first, then a system Python in
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

One worker, one registry (below), one topic.

- **Artifacts** `~/Pictures/Stage/<stem>/`: `subject.png` (the cut),
  `background.png` (the inpainted backdrop, made once the first time
  Parallax is chosen for that wallpaper), `layer-NN.png` (added layers),
  `.index.json` (mtime + quality reuse).
- **Topic** `stage`: `{ current, busy, stage: "cut"|"inpaint"|"", percent,
  walls: { <path>: { effect, subject, background, rev, layers: [...] } } }`,
  published on every change. QML renders from it and nothing else.
- **Verbs** (`ryoku-shell stage ...`): `set-effect <off|depth|parallax>`,
  `set-layer <index> <json>` (enabled/front/depth), `add-layer <png>`,
  `cut-layer <picture>` (runs the engine on another picture and adds the
  result), `remove-layer <index>`, `refresh` (re-cut), `cancel`, `clear`,
  `status`, `models`.
- **Rules**: a wallpaper switch reconciles and never generates; a stage is
  per wallpaper; videos are skipped; an effect switch never re-cuts (only
  Parallax's first use on a wallpaper adds the inpaint); a failure leaves the
  effect off with a logged reason. The subject is still handed to ryogami as
  `depth` for the Depth effect only, unchanged on the wire.

## Settings: `~/.config/ryoku/stage.json`

Global only; anything per-wallpaper is in the registry.

| Key | Default | What it is |
|---|---|---|
| `quality` | `draft` | `draft` / `standard` / `fine`, the model + matting pair |
| `edge` | `0.15` | edge softness of every cut-out (0..1) |
| `shadow` | `0` | drop shadow behind every layer (0..1) |
| `shadowAngle` | `90` | shadow direction in degrees, 0 = right, 90 = down |
| `motion.amount` | `normal` | `subtle` / `normal` / `strong`: cursor drift, and the idle amplitude |
| `motion.idle` | `none` | `none` / `float` / `breathe` |
| `motion.music` | `false` | layers react to the shared spectrum |
| `front` | `[]` | widget ids drawn above the layers marked "in front" when the user lifts specific widgets from the desktop editor |

The daemon reads `quality`; the shell reads the rest. `feather`, `lift`,
`motion.{mouse,sensitivity,range,wallpaper}` and `preset` from the first
Ryostage cut are folded once (`feather` -> `edge`; any `mouse: false` ->
`amount: subtle`, `preset` dropped) and the file rewritten.

## Registry: per-wallpaper stage

`~/.local/state/ryoku/stage-walls.json`:

```
{ "current": "<path>",
  "walls": { "<path>": {
      "effect": "off|depth|parallax",
      "layers": [ { "out": "<png>", "label": "Subject", "enabled": true,
                    "front": true, "depth": 0.5 }, ... ] } } }
```

`layers[0]` is always the subject the engine cut (`subject.png`); every
later entry is a picture the user added (`layer-NN.png`, cut from a picture
or dropped in as a PNG). `front` is behind/in front of the widgets; `depth`
0..1 is near..far for Parallax drift. `effect: subject` and `mode`, `scene`
and the per-layer knobs from the first Ryostage cut are migrated once: a
`scene` order is reduced to each layer's `front`, `subject` becomes `depth`.

## Rendering: `modules/stage/`

One surface, one stack. The desktop surface draws, back to front: the
backdrop (`StageBackdrop.qml`: the inpainted `background.png` with drift,
only for Parallax, sized with the wallpaper's own fit so it can never
misalign with ryogami's surface underneath), then every layer marked behind
the widgets, then the widgets, then every layer marked in front
(`StageLayer.qml`: edge, shadow, drift by `depth`, idle, music). Depth is the
same stack with `motionEnabled: false` and no backdrop. There is no
second renderer, no separate layer-shell surface, and no path that can draw
the subject twice: the wallpaper's own subject is covered by the backdrop in
Parallax and is pixel-locked under the still cut in Depth.

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

## Verification

- Daemon: `go build ./...` and its unit tests: the `stage` topic carries the
  frame fields, the worker coalesces off the wallpaper hot path, and the registry
  parses.
- Doctor: hermetic Go tests for the rail migration (retired `depth`/`parallax`
  fold to one `stage` tab, idempotent), the settings migration, and the
  `ryostage cache` reclaim.
- QML: `qmllint` on the new and edited `modules/stage/` files.
- Engine: `bash -n` + shellcheck on `ryostage`; `check`, `models --json` and a
  `cut` against a provisioned cache.
- Delivery: `ryostage` is on both install paths (`deploy.sh` and the
  `ryoku-shell` PKGBUILD), enforced by the delivery check.
- The live visual result and real cut quality need a running session with the
  engine provisioned, exercised on the dev box via `dev-run.sh`.
