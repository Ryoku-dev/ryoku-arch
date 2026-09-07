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
widgets. **Parallax** is a switch inside Depth: the same cut, the same look,
now drifting with the pointer over an inpainted backdrop. Nothing is configured
twice.

Three ways to change the desktop, all from its right-click menu:

- **Edit widgets**: move, resize, add, remove and configure widgets.
- **Edit shell**: the bar, the dock, the edge menus, Depth and Parallax.
- **Customize visualizer**: the visualizer's own editor (its looks, colour,
  bands, mirror, peaks, gain, smoothing, angle, lean, size), placed on the
  desktop.

The two Stage switches sit in that menu as well, so turning Depth or Parallax
on never needs an editor.

## The desktop right-click menu

```
Edit widgets
Edit shell
Customize visualizer
Change wallpaper
[Depth      (o)] [Parallax   ( )]     <- two switch cards, side by side
Settings
Reload shell
```

The switch cards sit directly above `Settings`. Each is a label plus a switch;
tapping either keeps the menu open so the effect is seen at once.

- Depth on: `set-effect depth`. Depth off: `set-effect off` (Parallax's switch
  falls with it).
- Parallax on: `set-effect parallax`, and Depth's switch turns on with it if it
  was off (one tap, no "enable Depth first"). Parallax off: `set-effect depth`.
- While the engine cuts (first enable on a wallpaper), the Depth card's value
  reads `Cutting 40%` from the daemon's status; the switch stays on.

## Edit widgets

The desktop lifts above open windows, the dock and bar step back, and every
enabled widget wears a frame:

- a 1 px outline with the widget's name at its top-left;
- drag anywhere on it to move (grid-snapped, live), the bottom-right bracket to
  resize;
- two small buttons on its top-right: **Settings** (opens that widget's own
  menu: design, lock, size, opacity, colour, snap) and **Remove** (hides it).

Nothing is locked while editing: `locked` is false for every widget for the
length of the session, and a widget added during the session is draggable the
moment it appears. Per-widget Lock still applies outside the session.

One toolbar docked top-centre, one row:

```
Edit widgets   [+ Add widget v]  [Visualizer...]        [Reset]  [Done]
```

- **Add widget** drops a panel under the button: one row per widget (clock,
  calendar, music, all-in-one, stats, weather, notes, every plugin widget, the
  visualizer) with a switch; on adds it at its default anchor, off removes it.
- **Visualizer...** leaves this session and opens Customize visualizer.
- **Reset** restores widgets.json as it was when the session opened (enabled
  set, free positions, sizes); it appears only once something changed.
- **Done** (or Escape, or a click on bare wallpaper when nothing is selected)
  leaves. There is no Save; the desktop is the document.

## Edit shell

A ribbon in the MS Paint sense: docked to the top of the screen, full width,
two rows. Row one is the tabs; row two is the active tab's controls, in
labelled groups separated by thin dividers, with each group's name in small
caps under its controls. Buttons that need more than a row (`Layers`,
`Pinned apps`, `Modules`) drop a panel down from the button, Paint's
Colours/Rotate way; one panel at a time, click elsewhere or Escape closes it.

```
| Edit shell   [Bar] [Dock] [Menus] [Depth] [Parallax]           [Reset] [Done] |
| [Top|Bottom]  |  (o) Auto-hide  |  [Islands|Full|Fit|Dock|Notch]  |  Size ---o--  |
|   POSITION    |    BEHAVIOUR    |            FORM                  |     SIZE      |
```

The desktop lifts above windows (the same lift as Edit widgets) so the stage
and the widgets are the canvas; the bar and the dock stay visible and live on
top of it (they move to the Overlay layer for the session), so a change is
seen on the real thing, not a stand-in. The ribbon sits under the bar when the
bar is at the top. Every change applies immediately through the seams the Hub
uses (`settings.patch` for `qsbar` and `frameBars`, the Dock singleton, the
stage daemon), and **Reset** puts back everything the session touched.

Tabs and their groups:

- **Bar**: Position `Top | Bottom`; Behaviour `Auto-hide`; Form
  `Islands | Full | Fit | Dock | Notch`; Size (scale 0.8 to 1.3); Surface
  `Frost`, `Shadow`, `Border`, Corners (0 to 24); Modules (drop-down: the
  left / centre / right module lists with move and remove).
- **Dock**: Show `Dock`; Position `Auto | Top | Bottom | Left | Right` (Auto is
  the edge opposite the bar); Style `Ledger | Islands | Rail | Seal | Tanzaku`;
  Behaviour `Auto-hide`, `Magnify`, `Media chip`; Surface `Frost`, `Shadow`,
  `Labels`; Apps (drop-down: the pinned list with remove and reorder, and a
  Pin an app picker).
- **Menus**: Menu `Quick settings | Theme | Wallpaper | Weather` (a chip per
  menu; the chosen one is outlined on its edge); Edge
  `Top | Bottom | Left | Right` (two menus asked for one edge swap); Stretch
  `Always | Never` (expansion); Width (minWidth).
- **Depth**: Depth switch; Subject `Behind widgets | In front`; Edge slider;
  Shadow slider with the angle dial; Quality `Draft | Standard | Fine` with a
  **Re-cut** button; Layers (drop-down: one row per layer with front/behind,
  drift when Parallax is on, and remove; `Cut a picture...`, `Add a PNG...`,
  `Clear cut-outs`).
- **Parallax**: Parallax switch; Drift slider (near to far, the selected
  layer's depth, the subject by default); Motion `Amount Subtle | Normal |
  Strong`, `Idle None | Float | Breathe`, `React to music`; Mouse
  `Follow mouse`, Sensitivity, Range; Backdrop drift.

On the canvas, the Bar, Dock and Menus tabs outline every surface with its
name and edge; the selected surface's legal edges show as strips, and clicking
a strip is the same as the Edge control. The Depth and Parallax tabs outline
the subject and every layer (click to select; the cut ring sits on the subject
while the engine runs).

### Nothing re-cuts without a confirm

Edge, Shadow, Subject and Drift are render-only and apply as they move. Only
these run the engine, and each needs a second, explicit press:

- **Quality**: choosing a tier marks it pending (the tile highlights, the
  Re-cut button fills and reads `Re-cut in Fine`); Re-cut writes the tier and
  refreshes; a click elsewhere or Escape drops the pending tier. A tier whose
  model is not installed shows `Download 224 MB` in the same place first.
- **Cut a picture...**: the file picker, then the picked name with `Cut` and
  `Cancel`.
- **Clear cut-outs**: `Clear` and `Cancel`.
- Turning Depth on for a wallpaper that has no cut is itself the consent; the
  switch shows progress.

While the engine runs, the Re-cut button becomes `Stop` with the percentage.

## Customize visualizer

The visualizer's own editor, unchanged: the Placer (drag to move, corner to
size, dot to turn, scroll to resize) with its EditBar fixed to a screen edge.
The menu row (and the Edit widgets toolbar's `Visualizer...`) turns the
visualizer on if it is off and opens it. Its Done closes it.

## The Stage card (Super+Esc)

Preview, `Depth`, `Parallax`, `Edit shell`, `Edit widgets`. Nothing else.

## Session model

`modules/stage/Singletons/StageSession.qml`: `mode` is `""`, `"widgets"` or
`"shell"`; `monitor` names the screen that opened it; `tab` is the ribbon's
tab; `selected` is a widget id, a surface id or `layer:N`; `panel` is the
drop-down that is open; `dirty` shows Reset. `escapeStep()` unwinds one level
per press: an open drop-down, then a pending confirm, then the selection, then
the session. Each editor captures its own snapshot on enter and restores it on
`resetRequested`.

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
| `motion.mouse` | `true` | Parallax follows the pointer at all |
| `motion.sensitivity` | `1.0` | the pointer's pull (0..2) |
| `motion.range` | `1.0` | how far a layer may travel (0..2) |
| `motion.backdrop` | `1.0` | the inpainted backdrop's own drift (0..1) |
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
look, drift by the layer's `depth` x the shared motion Amount x Sensitivity x
Range while Follow mouse is on, idle and music; z 4), then any widget the user
lifted into `front` (z 5). Depth is the same
stack with `motionEnabled: false` and no backdrop, so the still cut is
pixel-locked over the wallpaper's own subject. There is no second renderer, no
separate layer-shell surface, and no path that can draw the subject twice.
While the engine cuts, the subject layer dims and draws its own progress ring.

The editors sit beside the stack, not in it: Edit widgets is
`modules/stage/StageWidgetsEditor.qml` (the toolbar), `StageOutline.qml` (the
frame on every widget) and `StageAddPanel.qml` (the Add widget drop-down),
mounted by the desktop surface, which lifts to the Top layer for either
session; Edit shell is `modules/shell-layout/` (`ShellRibbon.qml` and one
`*Tab.qml` per tab, `RibbonGroup.qml`, `RibbonDropdown.qml`,
`ShellLayoutCanvas.qml`, `Singletons/Layout.qml`), its own Overlay surface per
monitor that maps 150 ms after the session opens so it lands above the bar and
dock, which step to Overlay for the session. Config writes from a Reset go out
as one write per file (`Config.setMany`, the settle timer), because a burst of
single-key writes interleaves with the watcher's reloads of older versions and
can put an old value back.

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
