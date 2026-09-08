# Window controls

The shipped shortcuts live in `ryoku/hyprland/modules/binds.lua`; the stateful
operations live in `modules/window_controls.lua`, required by the binds module.
They use Hyprland's Lua API directly, without a helper process or compositor
plugin.

| Shortcut | Action |
|---|---|
| Alt+Tab / Alt+Shift+Tab | Cycle forward / backward through windows on the active workspace, not most-recently-used switching. |
| Super+Shift+wheel up / down | Focus the spatial column to the left / right in the scrolling layout. This uses the layout's focus operation, so it never switches to a neighbouring monitor. The compositor's `scrolling.wrap_focus` setting controls wrapping at the ends. |
| Super+Alt+F | Expand the active tiled scrolling column to full width, then restore its immediately preceding fraction on the next press. This is not fullscreen or maximization; Super+F keeps its existing action. |
| Super+A | Float the window at 1000x660 and centre it. Press again to tile it without applying a floating size or centring to the tiled window, restoring the pre-float scrolling column fraction when known. |
| Super+Ctrl+Left / Right | Shrink / grow a tiled scrolling column by 0.02 per key repeat. Floating windows and other layouts keep the original 40-pixel relative resize. |

Column changes use `hl.dsp.layout("colresize ...")` in both directions, including
restores. Hyprland animates those changes using the user's animation settings;
Ryoku does not override disabled animations or apply a pixel resize to a tiled
scrolling window. Super+Ctrl+Up/Down and the Super+R resize submap are unchanged.
Super+wheel still switches workspaces; Super+Tab still opens the overview.

## Saved widths

The helper reads `hl.get_active_window().layout.column.width`, not the window's
animated pixel size or a default fraction. Each expansion captures a fresh
fraction. If the column has been manually narrowed since expansion, the next
Super+Alt+F expands from that new width instead of restoring an older one.
Super+Ctrl+Left/Right explicitly cancels the expansion's saved restore width.
A column already at full width with no saved expansion is left alone.

Floating while expanded preserves both transitions: tile back to full width,
then Super+Alt+F returns to the original narrower column. State is private to the
Lua session, keyed by window address, and removed on window close or workspace
move. Reloading the config forgets saved widths. Retention is bounded to the
128 most recently used windows even if an older compositor cannot register the
lifecycle events; in that case immediate close/address-reuse cleanup cannot be
guaranteed.

Full-column toggling and wheel focus do nothing outside tiled scrolling windows.
If active-window introspection is unavailable or there is no active window,
helper actions do nothing. If layout introspection or the layout dispatcher is
unavailable, horizontal resize falls back to the original pixel operation and
floating still works without column restoration. Missing or invalid column
fractions (outside 0.1 through 1) are not guessed from pixels: expansion is
skipped and float return uses the compositor's tiling placement.

## Settings and overrides

Settings > Keybinds > System and the keybind cheatsheet read the same shipped
`hl.bind(K(...), ...)` lines and their descriptions. Keyboard shortcuts remain
rebindable through the existing System editor; wheel bindings remain visible
but are not recordable there, matching the existing pointer-binding policy.
No Custom entries are installed. Existing `rebinds.lua` choices keep working.

A fork of `hypr/modules/binds.lua` in the user overlay wins over the shipped
file and therefore needs these changes merged manually. There is no need to
replace any other part of the config. Packages ship the new module with the
existing Hyprland config tree, and normal materialization delivers it.

### Optional wheel cooldown workaround

Some compositor versions pass wheel events through to the focused application
while a wheel shortcut is on cooldown, scrolling its contents during window
switching. If you encounter that behaviour, you can opt out of the cooldown in
your user-owned `hypr/user.lua`:

```lua
hl.config({ binds = { scroll_event_delay = 0 } })
```

This is a **global** change: it removes the delay for every wheel binding,
including workspace switching, and high-resolution wheels or touchpads may then
trigger several actions quickly. Ryoku deliberately leaves the compositor's
default intact. Remove the override and reload to restore that default.

## Verification

From the repository root, without changing the running desktop:

```sh
lua tests/hyprland-window-controls.lua
luac -p ryoku/hyprland/modules/window_controls.lua
luac -p ryoku/hyprland/modules/binds.lua
(cd ryoku/hub/backend && go test ./...)
```

The Lua harness supplies compositor objects and records real helper dispatches;
it also loads the shipped binds with and without rebinds. The Go regression reads
the shipped Lua rather than a second inventory. These tests verify actions and
state, not rendered animation or hardware wheel behaviour. On a compositor,
check both repeat directions, two monitors, a manual resize between toggles,
floating an expanded column, a closed window, and another tiling layout before
release.

API references: [dispatchers](https://wiki.hypr.land/Configuring/Basics/Dispatchers),
[scrolling layout](https://wiki.hypr.land/configuring/layouts/scrolling-layout/),
and [Lua events](https://wiki.hypr.land/configuring/core/advanced-configuration/events/).
