# The launcher

The launcher is the Ryoku command palette: a standalone, centered overlay
summoned with `Super + Space`. It searches and launches apps, calculates, runs
system actions, manages clipboard and snippets, switches windows, searches the
web, finds files, installs packages, controls any media player, and searches and
plays free music from YouTube Music. It is a full rebuild of the old pill
app-list, dropped from the pill so it has the room a Raycast/Alfred-class palette
needs.

It lives in `ryoku/shell/quickshell/launcher/`, a Quickshell component supervised
by the `ryoku-shell` daemon (a peer of `pill`/`ryoshot`), kept warm so it opens
instantly and toggles with `ryoku-shell launcher`.

## Launcher variants

Hero is the default launcher. Ryoku Settings -> App Launcher offers three
complete styles and saves the choice as `variant` in
`~/.config/ryoku/launcher.json`:

- **Main** is a compact command palette with the centered RestDashboard image
  card and the shared provider, result, and action contracts.
- **Hero** is the full image-backed Shutter launcher with its dashboard, local
  frost, result drawer, action shelf, and complete provider set.
- **OkShell** is the lean applications-only list: search, hidden-app toggle, and
  sliding row selection.
- **Kairos** is the island launcher, the one the Kairos bar style ships: the pill
  grows out of that style's resting island at the top of the screen into the
  clock, the app search and the app list. It masks input to the pill rather than
  the window, so the desktop around it stays clickable; Escape (or Super+Space
  again) closes it.

The resident `shell.qml` selector loads the saved catalog entry without changing
the stable `ryoku-shell launcher` command or socket. An unknown saved ID resolves
to Hero. If a selected QML entrypoint cannot load, the selector tries OkShell
once. Switching an open launcher closes it before replacing the component.

## Structure and contracts

- `catalog.json` is the ordered registry. It names the default, load-error
  fallback, entrypoint, preview, and capabilities for every launcher.
- `shell.qml` owns only selection, switching, fallback, and the stable command
  surface.
- `shared/` owns the providers, singletons, JavaScript libraries, result/action
  contracts, and art reused by more than one variant.
- `variants/<id>/Main.qml` is the runtime root. It implements `show(mon)`,
  `hide()`, `toggle(mon)`, `stateDump()`, and the read-only `shown` property.
- `variants/<id>/Preview.qml` is the visual-only 720 x 250 Ryoku Settings
  preview. It accepts `settings` and emits `editRequested(key, value)` when the
  preview supports editing.

Preview controls are capability-gated by the catalog, so adding a variant does
not add irrelevant settings to other designs.

## Adding a launcher variant

1. Create `variants/<id>/` with one component per QML file.
2. Implement the runtime contract in `variants/<id>/Main.qml`.
3. Add a visual-only `variants/<id>/Preview.qml` using shared tokens and art.
4. Add one safe `variants/<id>/...qml` row to `catalog.json`, including only the
   capabilities the preview actually supports.
5. Select it in Ryoku Settings and smoke-test show, hide, search, execution, and
   switching from an already-open launcher.
6. Add focused unit and live scenarios under `launcher/shared/lib/` and
   `launcher/qa/`; run the launcher QA suite and review its screenshot.

## Hero anatomy

- `variants/hero/Launcher.qml` is the card body: the search row over the rest
  dashboard, the all-apps grid (`Ctrl+A`), action-mode tabs (`/` prefix), or the
  ranked result list.
- `variants/hero/SearchRow.qml` is the 力 glyph, query field, result counter,
  Google Lens, and music-recognition controls.
- `variants/hero/ResultList.qml`, `ResultGrid.qml`, `NowPlaying.qml`, and
  `RestDashboard.qml` are the main views. `ActionPanel.qml` is the per-item verb
  sheet (`Ctrl+K`), and `CategoryTabs.qml` is the action-mode tab bar.

## Providers

Each capability is a provider: its own folder under `shared/providers/<name>/`,
a single QML component implementing the `Provider` contract (`providerId`,
optional `prefix`, `query(text) -> rows`). The `Dispatcher` singleton routes a
prefixed query to one provider and fans an unprefixed one across the default
set, merged by score. Adding a provider is a folder plus one line in
`shared/providers/Providers.qml`; the dispatcher discovers it by registration,
never by an edit to the routing.

| Provider | Prefix | What it does |
|---|---|---|
| apps | (default), `>` | launch desktop apps, fuzzy + launch-frequency ranked |
| calc | `=`, leading digit | qalc: math, units, currency |
| actions | `/` | system actions (lock, wallpaper, screenshot, night light, media keys, settings) in category tabs |
| clipboard | `;` | cliphist history, copy or delete |
| windows | (default) | switch Hyprland windows |
| web | `?` | web search with `!bang` site shortcuts, plus an inline DuckDuckGo instant answer |
| files | (default, 3+ chars) | fd file search, open or reveal |
| snippets | (default) | text expander (`{date}`/`{clipboard}`/`{selection}`/`{cursor}`) + quicklinks (`{query}`) |
| packages | `install`/`remove`/`search` | GPK across every package manager |
| mpris | (default, media words) | now-playing + transport for any player |
| script | per-script keyword | run rofi-script / dmenu scripts |
| rashin ask | `\` | one terse question to the Rashin agent (hermes): a pulsing strip names what it is doing (tool, thinking, writing), then the answer renders as selectable text over action chips. The daemon detects entities in the answer and each becomes a chip: real files open in nvim, folders in the file manager, URLs in the browser, shell commands and hex colors (with a live swatch) copy to the clipboard, plus COPY for the whole answer and CONTINUE IN DASHBOARD. Chips walk with the arrow keys and fire with ENTER; typing re-asks. Needs Rashin enabled; see `rashin.md` |

Ranking and protocol logic live as testable JavaScript in `shared/lib/` and each
provider's folder (`fuzzy.js`, `dispatch.js`, `rofiscript.js`, `wave.js`,
per-provider parsers), each with a `.test.mjs` run by `node`.

## Media

The launcher surfaces whatever is already playing so you can control it without
leaving the palette.

- **Any player** (mpris): the now-playing row controls whatever is playing
  (Spotify, a browser tab, an app) with play/pause/next/prev. It appears when the
  query mentions a media word or matches the current track.
- The now-playing card on the rest screen shows album art, title/artist, elapsed
  and total time, and the signature wavy seekbar (a sine that animates only while
  playing); the fill advances off a 500ms MPRIS position poll. A live cava wave
  sweeps behind it while a track plays, gated so the analyser runs only while the
  launcher is open and something is playing. For a player with no cover (some
  browsers) it fetches one from the keyless iTunes Search API by artist and title
  (noise-stripped for a better hit).

## Extending it

- **Scripts** (no code): drop a `{ keyword, name, exec }` entry in
  `~/.config/ryoku/launcher-scripts.json`. The script speaks the rofi-script /
  fuzzel dmenu protocol (newline rows, `\0key\x1fvalue` directives,
  `ROFI_RETV`/`ROFI_INFO` env), so existing rofi/fuzzel scripts work unchanged.
- **Snippets / quicklinks**: `~/.config/ryoku/launcher-snippets.json` and
  `launcher-quicklinks.json`.
- **A native provider**: add `shared/providers/<name>/<Name>.qml` (a `Provider`),
  register it in `shared/providers/Providers.qml`. Shell-backed providers run
  their process async with a debounce and call `Dispatcher.notifyAsync()` when
  results land.

## Performance

The launcher is one resident process. While open it has no RAM ceiling (album-art
decode, mpv, blur). At rest it sheds the heavy work: no media process runs until a
track is played, the clipboard is read on demand (not watched), and file/package
searches only fork past a length gate. Keystroke-to-result never animates; the
motion budget is spent on the window show/hide and the action-panel open
(`shared/Singletons/Motion.qml`).

## Theming

Colors, spacing, and motion are tokens in
`shared/Singletons/{Theme,Metrics,Motion}.qml`;
components read them, never hardcoded values. With Settings -> Shell -> Match
wallpaper on, `Theme` resolves to the live wallpaper palette (the same `shell.json`
flag and `colors.json` the rest of the shell uses), so the launcher recolors with
the system theme.
