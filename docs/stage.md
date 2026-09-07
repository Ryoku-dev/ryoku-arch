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

One feature: **Depth**. It lifts the wallpaper's subject in front of your
widgets. Depth has one optional motion, **Parallax**, which lets the scene
drift with the pointer over a recoloured backdrop. Parallax is a switch inside
Depth, never a sibling with its own settings: the same cut, the same quality,
the same edge and shadow. Nothing about the feature is configured twice.

Where things live:

- **Super+Esc, Stage card**: the two switches (Depth, Parallax) with a live
  preview, and one button, `Edit desktop`. That is all the sidebar holds.
- **Right-click the desktop**: `Edit widgets` and `Edit shell layout`, two
  separate sessions (below), plus `Change wallpaper`, `Settings`, `Reload shell`.

## Editing: two sessions, one language

Both sessions share one visual grammar, Ryoku's own (the frame bar's glass,
its type, its accent), not Material: a floating **island** docked at the top
centre of the monitor, an optional second row that belongs to the current
selection, labelled outlines on the things you can touch, and floating
**panels** that can be moved, pinned and closed. No sidebar, no bottom bar.

### Edit widgets (Ryostage)

```
          ┌────────────────────────────────────────────────────────┐
          │ Edit desktop · DP-2     Depth  Widgets  Visualizer   ✓ Done │   island
          │ [selection row: what the selected thing can do]         │
          └────────────────────────────────────────────────────────┘
   ┌ Clock ─────────┐                    ┌ Depth ───────── ✥ 📌 ✕ ┐
   │ (outlined, drag │                   │ Depth      on            │  floating panel
   │  to move, corner│                   │ Parallax   off           │  (moves, pins, closes;
   │  to resize)     │                   │ Quality  Draft·Std·Fine  │   remembers its spot)
   └─────────────────┘                   │ Edge      ──o────        │
                                         │ Shadow    ──o──── (dial) │
                                         │ Layers   Subject  ...    │
                                         └──────────────────────────┘
```

- The island's first row names the session and the monitor, holds the three
  scopes (`Depth`, `Widgets`, `Visualizer`) and `Done`. `Reset` appears only
  once something changed this session.
- **Depth scope**: the island's second row is the two switches and Quality;
  the `Depth` panel (a floating window) carries Edge, Shadow with its dial, and
  the layer list: each layer with `Behind widgets / In front of widgets`,
  near/far while Parallax is on, remove (never the subject), and `Add layer`
  (cut from a picture, or a PNG). The subject on the desktop gets an outline
  labelled `Subject`; cutting shows a ring on it.
- **Widgets scope**: every desktop widget gets an outline with its name and
  state (`Clock`, `Clock · locked`, `Clock · hidden`); drag to move, corner to
  resize, with a live size readout on the island's second row. Click one and
  the second row shows its actions: `Lock`, `Settings` (opens that widget's
  settings as a floating panel with the same move/pin/close chrome), `Hide`.
  The row also has `Add widget`, which lists the ones that are off.
- **Visualizer scope**: the visualizer is outlined and draggable/resizable
  exactly as its old placer did (that placer is what runs here); the second
  row has `On desktop / Above windows`, `Style`, and `Hide`.
- Session rules: Escape cancels the current gesture, a second Escape leaves;
  `Done` leaves; nothing needs saving. The desktop lifts above windows and
  the dock hides while editing.

### Edit shell layout

The same island, scoped to the shell's surfaces: `Bar`, `Dock`, `Quick
settings`, `Theme`, `Wallpaper` (the frame bar's menus). Each surface is
outlined with its name and current edge; the island's second row offers the
edges that surface may take (`Top / Bottom / Left / Right`, only the legal
ones) and applies on click. Dropping two menus on one edge swaps them. Nothing
here touches Depth or widgets; that separation is the point.

### Panels

A floating panel is a small window inside the editor: a title row with a
grab handle (move), a pin (keeps it open after Done), and close; a body no
wider than 360 px. Panels remember their last position per monitor in
`~/.local/state/ryoku/stage-ui.json`. Only one settings panel is open at a
time; opening another replaces it.

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
  published on every change and on each generation phase. QML renders from it
  and nothing else. `subject`/`background` are absolute paths ("" until fresh);
  `rev` is the max mtime across the wall's `subject.png`/`background.png`/
  `layer-NN.png`, so the shell busts every url with the one revision. The frame
  layers carry `{out, label, enabled, front, depth}` and no per-layer rev, and
  `layers[0]` is always the subject slot.
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

The daemon reads `quality`; the shell reads the rest. On the first start after
v2 a v1 `stage.json` (one still carrying `feather`, `lift`, `preset` or the
`motion.{mouse,sensitivity,range,wallpaper}` sub-knobs) is folded once and
rewritten atomically: `feather` -> `edge`, `lift` and `preset` dropped, and the
motion sub-knobs reduce to `motion.amount` (`mouse: false` -> `subtle`,
else `sensitivity >= 1.5` -> `strong`, else `normal`) with `motion.idle`/
`motion.music` defaulted. An already-v2 file is left alone; the daemon never
creates the GUI-owned file. A stable box that skipped v1 has no `stage.json` but
still carries the retired `depth.json`/`parallax.json`; those are folded instead
(model+matting -> `quality`, higher tier winning; `feather` -> `edge`;
`shadow`/`shadowAngle` scalars kept, per-layer arrays skipped).

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
0..1 is near..far for Parallax drift. The v1 registry is folded once, gated by
`~/.local/state/ryoku/migrations/ryostage-v2`: `effect: subject` becomes
`depth`, a `scene` order reduces to each layer's `front` (a layer listed after
any `widget:*` token is `front: true`), a v1 `depthFactor` becomes `depth`, and
`mode`, `scene` and the other per-layer knobs are dropped. A v1 manual wall's
`layer-NN.png` entries are kept after a prepended subject slot. Under the same
marker and before the v1 fold, the retired Depth (`depth-walls.json` +
`~/Pictures/Depth`) and Parallax (`layers.pz` + `~/Pictures/Parallax`) state a
stable box still carries is folded in for walls v1 has not claimed, its
artifacts moved by rename into `~/Pictures/Stage/<stem>/`, so both upgrade paths
converge on one registry.

## Rendering: `modules/stage/`

One surface, one stack. The desktop surface draws, back to front:
`StageBackdrop.qml` (Parallax only: the inpainted `background.png`, sized with
the wallpaper's own fit and drifting with the cursor, so it covers the
wallpaper's baked subject and can never misalign with ryogami's surface), then
the layers marked behind the widgets (z 2), then the widgets (z 3), then the
layers marked in front (`StageLayer.qml`: edge, shadow and angle from the global
look, drift by the layer's `depth` x the shared motion Amount, idle and music;
z 4), then any widget the user lifted into `front` (z 5). Depth is the same
stack with `motionEnabled: false` and no backdrop, so the still cut is
pixel-locked over the wallpaper's own subject. There is no second renderer, no
separate layer-shell surface, and no path that can draw the subject twice.
While the engine cuts, the subject layer dims and draws its own progress ring.

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
