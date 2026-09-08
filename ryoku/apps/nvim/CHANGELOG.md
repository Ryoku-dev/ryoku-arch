# Changelog: ryoku/apps/nvim/

## Unreleased

### Added
- LazyVim-based Neovim config ported from upstream Ryoku (`init.lua`,
  `lua/config/{autocmds,keymaps,lazy,options}.lua`, `lua/plugins/*`, and the
  `.ryoku-lazyvim` marker). `lua/config/lazy.lua` self-bootstraps lazy.nvim by
  cloning it from GitHub on first launch, so the config is standalone.
- `lua/plugins/ryoku-dashboard.lua` carries the verbatim Ryoku ASCII startup
  logo as the snacks.nvim dashboard header, the headline feature.
- Adapted for the slim Arch build: dropped the upstream-only `ryoku-shell`
  theme everywhere it was referenced. `tokyonight` (shipped by LazyVim) is now
  the effective default colorscheme with a `habamax` fallback, the lazy.nvim
  install list is `{ "tokyonight", "habamax" }`, and the `<leader>rr`
  "reload Ryoku theme" keymap (which drove `ryoku-shell`) was removed.

### Fixed
- Config no longer resets on `ryoku update`. The tree is seeded once and then
  left to the user, so edits, added plugins and LazyVim's own state survive
  (delivered by the `ryoku` CLI materialize seed).
