---
name: ryoku
description: >
  Customize a Ryoku desktop: an Arch Linux system with a Hyprland compositor and
  a Quickshell shell (the QS Bar, the dock, widgets, the launcher, and the Hub).
  Use for end-user requests that touch the desktop or its config. Triggers:
  Hyprland, window rules, keybinds, monitors, gaps, borders, the bar, the dock,
  bar widgets, plugins, themes, wallpaper, colours, night light, idle, lock
  screen, and user-facing ryoku commands (ryoku, ryoku-shell, ryoku-hub,
  ryogami, ryoku-rashin). Read the vault first; act through commands, not by
  editing shipped files.
---

# Ryoku

Ryoku is an Arch Linux desktop: a Hyprland compositor, a single Quickshell shell
that draws the bar, the dock, the launcher, the popouts and the widgets, and a
set of Go command-line tools that own the config. This skill is for changing a
running Ryoku system on behalf of its user. It is not for developing Ryoku
itself (editing the source checkout, writing migrations, cutting a release).

## When to use this skill

Use it whenever a request would change the desktop or read its state: the bar
layout and widgets, the dock, Hyprland behaviour, themes and wallpaper, keybinds,
idle and lock, plugins, or any `~/.config` file Ryoku owns. If you are about to
guess a path or edit a config file under `~/.config`, stop and use this skill.

Do not use it to modify the Ryoku source tree, and never treat a shipped file as
a place to store a user's choice.

## Read the vault first

A maintained map of THIS machine lives in the Rashin vault at
`~/.local/share/ryoku/rashin/`. Read it before searching the filesystem or
guessing where anything lives:

- `AGENTS.md`: the entry contract and the vault's own rules.
- `desktop.md`: the map. Every subsystem, the config path that owns it, the
  binary that owns it, and how to reload it. Its generated "Bar and dock"
  section lists every bar widget id, its visibility key, and the bar and dock
  commands. Read this before touching the bar.
- `system.md`, `packages.md`, `user.md`, `habits.md`: hardware, packages, where
  this user diverges from the shipped defaults, and this user's directories and
  tool stack.

`user.md` lists the user's own choices; never revert one to a shipped default
without being asked. Write durable notes to `memory/`, dated notes to
`journal/YYYY-MM-DD.md`; never edit inside a `rashin:generated` fence, a reindex
overwrites it.

Topic guides sit beside this file. Read the matching one first:

- [`bar.md`](bar.md): the QS Bar and the dock, their layout model, and the
  `ryoku-shell bar` / `ryoku-shell dock` commands.
- [`plugins.md`](plugins.md): installing, listing, and removing shell plugins
  with `ryoku plugin`, and Ryostore.

## Safety rules

Ryoku separates the files it ships from the files you own, so an update can
refresh the base freely while your changes stand. Respect the split:

- **Never edit a shipped file in place.** `/usr/share/ryoku/` (the packaged
  base) and the files Ryoku lays into `~/.config/quickshell/` are re-laid on
  every `ryoku update` (`ryoku materialize` clobbers every shipped file), so an
  edit there is lost on the next update. Reading them is safe and useful.
- **A user override goes to the overlay:** `~/.config/ryoku/user_edits/`, which
  mirrors `~/.config`. A file there wins at its mirrored path and survives every
  update. To change a shipped Hyprland or app config, drop your version at the
  mirrored path under `user_edits` (a fork), or, better, use the dedicated
  override file the tool already reads (`hypr/user.lua`, `hypr/settings.lua`,
  `kitty/user.conf`, `fish/user.fish`), which the package never ships and never
  touches. `ryoku reset <path>` drops an overlay file back to the base.
- **Prefer a command over a file edit.** The tool that owns a setting is its one
  writer; hand-editing its store drifts. Ryoku Settings' own state (bar, colours,
  launcher, device lighting) lives under `~/.config/ryoku/*.json`, written by
  their tools (the shell daemon, `ryoku-hub`, `ryogami`); do not hand-edit those
  JSON stores, drive them through the command or the GUI so one writer stays in
  charge.

## Command discovery

Ryoku's behaviour lives behind five command-line tools, all self-documenting.
Prefer a command to a file edit; read a command's `--help` before running it.

| Tool | Owns |
|---|---|
| `ryoku` | Updates, rollback, status, reload, materialize, reset, doctor. See `docs/cli.md`. |
| `ryoku-shell` | The live shell: the bar, the dock, menus, popouts, and the `shell.json` settings store (the sole writer of `shell.json`). |
| `ryoku-hub` | Ryoku Settings and the Hyprland config it generates (`hypr get`, `hypr matugen set`, ...). |
| `ryogami` | Wallpapers and the colour palette (`ryogami wallpaper set|next|random`). |
| `ryoku-rashin` | The optional agent OS: the vault, wiring, the dashboard, `index`, `wire`. |

```bash
ryoku --help                 # the ryoku CLI surface
ryoku-shell bar catalog      # every bar widget, its id, and its settings
ryoku-shell bar list         # the live bar, per section, with shown state
ryogami wallpaper --help
```

To find WHERE a setting is read (which QML file, which key), use `prowl-agent`
inside the vault's read-only source mirror at
`~/.local/share/ryoku/rashin/source/`, which indexes the live `~/.config`:

```bash
cd ~/.local/share/ryoku/rashin/source && prowl-agent search "barPosition"
cd ~/.local/share/ryoku/rashin/source && prowl-agent find barShellStyle
```

The mirror is read-only and rebuilt on every reindex; never edit files in it,
edit the real path `desktop.md` names.

## Decision framework

When a request would change the system, in order:

1. **Is there a command for it?** Use it. The bar and dock have a full CLI
   (`ryoku-shell bar ...`, `ryoku-shell dock ...`, see `bar.md`); wallpaper has
   `ryogami wallpaper set`; updates have `ryoku update`.
2. **Is it a plugin?** A shell widget installs from git with
   `ryoku plugin add <url> --bar`, or from Ryostore; see `plugins.md`. Never
   run a plugin's code to install it. A Hyprland compositor plugin (title
   bars, cursor motion, key sounds, a `.so` the compositor loads) is managed
   by `ryoku-hub hypr plugins list|rebuild|add|remove` and Settings >
   Plugins; a "version mismatch" after an update means
   `ryoku-hub hypr plugins rebuild --stale`.
3. **Is it a config edit with no command?** Edit the override, never the shipped
   file: the tool's own `user.*` file, or a fork at the mirrored path under
   `~/.config/ryoku/user_edits/`. Then reload (`ryoku reload`, or `hyprctl
   reload` for Hyprland).
4. **Is it a theme or wallpaper?** Drive it through `ryogami` and `ryoku-hub`,
   which own the colour master; never write the palette or theme shadow by hand.
5. **Is it a package?** `ryoku update` for the whole system; pacman/yay for one
   package.
6. **Unsure a command exists?** Read the tool's `--help`, or `desktop.md`.

## Example requests

- "Move the clock to the right" -> `ryoku-shell bar move clock --section right`
- "Hide the GPU widget" -> `ryoku-shell bar hide gpu`
- "Show the battery widget again" -> `ryoku-shell bar show battery`
- "Put the bar at the bottom" -> `ryoku-shell bar position bottom`
- "Make the bar islands" -> `ryoku-shell bar form islands`
- "Reset the bar to defaults" -> `ryoku-shell bar defaults`
- "Open the bar settings" -> `ryoku-shell bar settings`
- "Turn the dock off" -> `ryoku-shell dock hide`
- "Pin Firefox to the dock" -> `ryoku-shell dock pin firefox`
- "Add a weather plugin from GitHub" -> `ryoku plugin add <git-url> --bar`
- "List my installed plugins" -> `ryoku plugin list`
- "Lock after ten minutes" -> fork `hypr/hypridle.conf` into
  `~/.config/ryoku/user_edits/hypr/hypridle.conf` and set the lock `listener`'s
  `timeout` to `600`, then `ryoku materialize` lays the fork live and
  `pkill -x hypridle; setsid hypridle -c ~/.config/hypr/hypridle.conf &`
  restarts the idle daemon on it (hypridle reads its config only at start;
  `hyprctl reload` does not reach it)
- "Change my wallpaper" -> `ryogami wallpaper set <path>`
- "Next wallpaper" -> `ryogami wallpaper next`
- "Update the system" -> `ryoku update`
- "Roll back a bad update" -> `ryoku rollback`
