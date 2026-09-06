# Theming: how colour reaches an app

Ryoku *generates* a palette; Omarchy *ships* one. That difference is smaller than
it looks, and the part worth copying is not the palette at all -- it is how the
palette reaches the applications.

## How Ryoku works today

One palette, rendered outward.

    wallpaper --matugen--> colors.json ------> Quickshell singletons (Scheme)
                              |
                              +--> matugen templates --> ~/.config/<app>/...

`ryoku/shell/ipc/matugen.go` runs matugen against the current wallpaper, writes
`~/.cache/ryoku/colors.json`, and renders the templates in
`ryoku/shell/matugen/` into each app's config. A fixed named theme skips
generation and renders the catalog palette through the same templates.

Eighteen apps are covered: kitty, the Hyprland border, btop and qt6ct always;
gtk3, gtk4, vesktop, equibop, qt5ct, obs, zed, heroic, telegram, steam, cava,
ghostty, micro and papirus behind the app-suite toggle.

Ryotunes, the native music client, joins the suite too: matugen renders its
Material 3 palette as a Ryoku skin at `~/.config/ryotunes/skins/matugen/skin.json`,
which the client loads as its "System" theme.

## How Omarchy works

A theme is a *folder* of per-app files. One directory always holds the active
one, at a path that never changes:

    ~/.config/omarchy/themes/<name>/    colors.toml, btop.theme, neovim.lua, ...
    ~/.config/omarchy/current/theme/    the active one, rebuilt in place

It is a real directory, not a symlink. `omarchy-theme-set` builds `next-theme/`
-- copy the official theme, copy the user's same-named theme over it, render
templates into the gaps -- then `rm -rf current/theme && mv next-theme
current/theme`. A half-written theme is never visible.

The stable *path* is what the design rests on. Because `current/theme/btop.theme`
means the same thing forever, an app is wired to it exactly once and never
touched again. Three ways, depending on what the app allows:

- an `@import` / `source` / `include` line in a shipped config (hyprland,
  hyprlock, kitty, alacritty, ghostty, foot, waybar, walker, swayosd)
- a permanent symlink made once at install (btop, mako, helix, neovim)
- a copy or an API call, for apps that will not read a foreign file (vscode,
  chromium, GNOME, obsidian)

Generation and hand-authoring meet in one rule. `omarchy-theme-set-templates`
compiles `colors.toml` into sed substitutions and renders `default/themed/*.tpl`,
but **skips any output file that already exists**. The theme's own files were
copied in first, so a theme shipping its own `waybar.css` suppresses
`waybar.css.tpl` entirely. Per file, hand-authored beats generated.

Colours are never derived from the wallpaper -- there is no matugen, pywal or
wallust anywhere in the tree. Light vs dark is a marker file, `light.mode`.
Omarchy 4 is moving the other way, templating `neovim.lua` and `vscode.json` so
themes shrink toward `colors.toml` plus previews: converging on the generated
model Ryoku already has.

## What is worth adopting

**The stable path, not the palette.** Ryoku renders straight into each app's
final destination. That has two costs:

- Two templates own the app's *whole* config, not a colour fragment:
  `cava -> ~/.config/cava/config` and `ghostty -> ~/.config/ghostty/config`
  (`ryoku/shell/matugen/apps.toml`). A user's own settings in either file are
  overwritten on the next wallpaper change.
- A theme has no single location. There is nothing to point at, export, or
  install -- which is exactly why a third-party theme folder cannot be supported
  today.

Rendering into one theme directory and pointing app configs at it fixes both,
and makes a generated palette and a downloaded theme interchangeable.

**One manifest.** Omarchy's app set is a directory listing. Ryoku's is spread
across `ryoku/shell/matugen/config.toml`, `ryoku/shell/matugen/apps.toml`,
`templateGroup()` in `ryoku/shell/ipc/matugen.go`, and a second group switch plus
a default roster in `ryoku/hub/backend/matugen.go`. Four places must agree about
what "gtk" means. One manifest -- app, template, destination, how it is included,
how it reloads -- would be the single source the renderer, the roster and the Hub
all read.

**Not** the hand-authoring. Ryoku's whole point is that the palette follows the
wallpaper; Omarchy themes are fixed. The catalog of 57 named palettes already
covers the fixed case.

## Coverage gap

Apps Omarchy themes that Ryoku does not, most visible first:

| App | Note |
|---|---|
| Browser (chromium / brave) | Omarchy sets it through a managed policy file |
| Neovim | `neovim.lua` in the theme dir |
| VS Code / Codium | written into the app's settings, not a config file |
| Fish shell + fzf | `colors.fish`, `fzf.fish` |
| hyprlock | Ryoku has qylock, which takes no palette yet |
| superfile | file manager |

Omarchy also themes waybar, walker, mako and swayosd. Ryoku replaces all four
with its own surfaces, which already read the palette directly -- no gap.

Ryoku covers what Omarchy does not: telegram, heroic, obs, micro, qt5ct/qt6ct.

## Supporting a third-party theme folder (later)

The **palette** half of this already ships. RyoStore's Themes category imports a
theme's colours (its `colors.toml`, pre-converted into Ryoku's palette shape and
hosted under `ryostore/colorschemes`) into a named Ryoku colour scheme, so a
HANCORE theme shows in the Color-scheme picker and matugen fans it into every
app. The rest of this section is the larger, still-future part: using a theme's
own hand-authored per-app files verbatim.

A repo like `HANCORE-linux/omarchy-harbordark-theme` is a flat directory of
per-app files plus `backgrounds/`. Once app configs read from a stable theme
directory, installing one is: clone it into a themes dir, rebuild the active
directory from it, reload.

Omarchy's skip-if-exists rule is the piece worth copying wholesale, because it
makes generated and downloaded themes the same kind of thing: copy the theme's
own files in first, then render Ryoku's matugen templates only into the gaps. A
theme that ships `btop.theme` keeps its own; one that ships only `colors.toml`
gets everything generated. Ryoku's 57-palette catalog and a downloaded folder
then stop being separate mechanisms.

What must land first is the stable directory and the manifest above. The install
step is small after that.
