# The store

Ryoku's extras are delivered through **RyoStore**: a browsable catalogue of
rices, lockscreens, bar styles, fastfetch styles, plugins, and bundles that
install into the running desktop without activating themselves. Remote
catalogues live in `ryostore`; RyoStore owns discovery and installation;
Ryoku Settings manages what is already present.

## How it works today

- **Catalogue = `ryostore`.** Each kind of thing (bundles, plugins,
  nautilus packs, livewalls, colorschemes) is a folder with a `registry.json`.
  An item is invisible to RyoStore until it is listed there. RyoStore fetches
  the repo at runtime (`RYOSTORE_BASE`, default the GitHub `main` raw tree)
  and caches it under `~/.cache/ryoku/extras`, so the catalogue still renders
  offline.
- **Store UI = RyoStore.** The standalone Quickshell app presents every
  category through one artwork-led showroom with global search, Library state,
  reversible details, explicit local status, and install-only actions. Ryoku
  Settings remains the destination for activation, configuration, updates,
  placement, and removal.
- **Install = the actuator.** `ryostore-install` routes each bundle item by
  type: `package` through `pacman -Syu` / the AUR helper (one package at a time,
  so one failure never strands the rest), `script` through `installers/<name>.sh`,
  and `plugin` / `nautilus-pack` through the shell's guest paths. It runs in a
  floating terminal for the sudo prompt; a bundle's `requires` (such as
  `multilib`) is ensured first. Removal is symmetric.
- **Guests = host/guest.** The shell is the *host*; a bundle ships *guests*
  (a plugin that renders in a widget or frame-popout host, a nautilus pack that
  drops right-click scripts). A guest declares its host and mounts on install,
  reload, and use with no extra setup; removing the bundle takes the guest and
  its state with it. All the guest's code lives in `ryostore`, not here, so
  the shell stays a host and the catalogue stays independent.

## Decision: build Ryostore

The conditions for a standalone store are now present. The catalogue spans six
distinct product categories, discovery is split across unrelated Settings
pages, and the store is intended to be a visible front door for the Ryoku
ecosystem. Ryostore replaces those browse surfaces rather than duplicating them.

There is one door for discovery and installation:

- **Ryostore discovers and installs.** It owns remote catalogues, cached
  metadata, search, previews, item details, installation, and installed-state
  summaries.
- **Ryoku Settings manages what is present.** It owns activation, configuration,
  updates, removal, placement, and applied-state controls.
- **Install never activates.** Installing a rice, lockscreen, plugin, bar style,
  or future fastfetch style must not change the desktop. Completion offers
  **Open in Settings**.

The first release exposes Lockscreens, Plugins, Bundles, Rices, Bar styles, and
Fastfetch styles. A category without a live remote registry remains visible with
an honest empty plate. It never receives fake specimens.

## Product shape

RyoStore is a standalone Quickshell app in the same family as Ryoport and
Ryowalls. Its ideal window is 1180 by 760, clamped to the available screen.
The header remains usable at smaller sizes: Discover, Search, and Library stay
visible while category labels occupy a clipped horizontal strip that scrolls
the focused category into view.

The first view is a living showroom, not a dashboard. A full-bleed stage gives
the committed product's artwork, title, state, and actions visual priority. A
horizontal filmstrip below it browses the current collection with pointer,
touchpad, wheel, and keyboard input. Hover may preview only artwork and title;
status and actions always belong to the committed selection.

The fixed header exposes one semantic route order:

```text
Discover
Lockscreens · Rices · Themes · Bar styles · Fastfetch · Plugins · Bundles
Search
Library
```

**Library** is a first-class cross-category collection. Every item writes its
state explicitly:

- `ACTIVE` for the rice, lockscreen, bar, or fastfetch style currently worn;
- `ENABLED` for a running plugin;
- `INSTALLED` for an owned but inactive item;
- `<installed> / <total> INSTALLED` for a partial bundle;
- `UPDATE` when a newer store-managed version is available.

Opening a product expands its selected cover into a reversible dossier with
real preview art and screenshots, then author, source, version, compatibility,
exact local state, description, and actions. Closing the dossier returns to the
same collection, selection, filmstrip offset, and focus. Actual preview art may
keep its color because it is the item being evaluated; app chrome remains paper
and ink, with no permanent rail, inspector panel, grain, or dashboard cards.

## Interaction contract

Navigation preserves context rather than replacing pages:

- `/` and `Ctrl+K` open and focus global search from anywhere;
- `Esc` closes detail, then search, restoring the exact collection frame at
  each layer; it never silently quits;
- Left/Right move the pending filmstrip selection, Home/End reach its bounds,
  and Enter commits the pending product;
- wheel and drag gestures settle to one committed cover;
- Tab follows Discover, categories, Search, then Library;
- quitting during an active installation requires a second quit action.

Search is global and grouped by category. Results retain state, so a query such
as `installed clock` can find an installed lockscreen without navigating to its
category. Returning from search restores the previous route, category,
selection, visible filmstrip offset, and focused control.

Installation feedback stays in the detail:

1. The primary action locks immediately and reads `INSTALLING`.
2. The detail reports the real fetching, verifying, installing, or complete
   stage.
3. The backend is re-probed after completion and whenever the window regains
   focus.
4. Success becomes `INSTALLED` with `OPEN IN SETTINGS`.
5. Failure keeps the detail open, prints the actionable error, and offers
   `RETRY`.

Bundles retain the existing floating terminal because package authorization and
long-running output belong there. The dossier lists every component and current
count before the user starts `INSTALL <n> ITEMS`; live report state keeps the
showroom synchronized while the terminal owns privileged work.

Motion uses the shared tokens for short hover, selection, stage, and detail
transitions. Reduced motion removes scale, parallax, kinetic travel, and
shared-element movement rather than merely shortening them. Focus is always
visible, text uses the contrast-solved ink tiers, and every pointer action has a
keyboard equivalent.

## Unified subsystem

Store ownership lives in one folder:

```text
ryoku/apps/ryostore/
  backend/
    go.mod
    main.go
    model.go
    cache.go
    provider_locks.go
    provider_plugins.go
    provider_bundles.go
    provider_rices.go
    provider_bars.go
    provider_fastfetch.go
  quickshell/
    shell.qml
    App.qml
    StoreHeader.qml
    ShowroomStage.qml
    Filmstrip.qml
    SearchLayer.qml
    ProductDetail.qml
    ProductCover.qml
    StatusReadout.qml
    lib/
      store.js
    Singletons/
      Store.qml
      qmldir
    logo.svg
  ryostore.desktop
```

Each QML file owns one surface. More focused files may be added when a real
surface requires them; unrelated views are not merged to keep the file count
small.

The Go backend builds to `/usr/bin/ryostore` through the existing first-party app
packaging loop. It normalizes all providers into one JSON contract:

```text
Category
  id, name, group, description, count, installedCount

Item
  id, category, name, summary, description
  art, screenshots, author, version, compatibility
  installed, active, enabled, installedCount, totalCount
  updateAvailable, metadata
```

The public command surface is deliberately small:

```text
ryostore catalog [--refresh]
ryostore install <category> <id>
ryostore open <discover|library|category>
ryostore settings <category> [id]
```

QML invokes this contract instead of maintaining six bespoke process and state
models. Adding a specimen changes only its upstream registry or owning local
manifest. Adding a category adds one provider and one header entry; the generic
stage, filmstrip, search, Library projection, and detail surface need no new QML
page.

Runtime implementations remain with their owning subsystem. A bar style still
lives under `modules/bar/barstyles/<id>/`, a qylock theme under the qylock theme tree,
and a plugin in the plugin data directory. Ryostore owns their catalogue adapter
and installation, not a second runtime copy.

## Provider behavior

- **Lockscreens:** fetch the qylock catalogue, preview cache, and install-only
  theme downloader. Installed and active state come from the local qylock theme
  tree and current theme. Settings retains preview and activation.
- **Plugins:** browse only the canonical external product registry. The common
  transaction engine atomically installs, updates, and removes the receipt-owned
  plugin tree; receipts provide installed version and update state, while
  `plugins.json` remains the sole owner of enablement, placement, and settings.
  Install never enables a plugin, removal preserves that user state, and the
  running shell watches Store revisions and keys Loader URLs by installed
  version so updated content and services replace themselves without a reload.
- **Bundles:** fetch the `ryostore` bundle registry and join it with
  `ryostore-install status`. Partial counts are first-class. Settings owns
  installed bundle status and removal.
- **Rices:** fetch and install the `ryostore` rice registry. Installed and
  active state come from the local rices tree and active marker. Appearance
  retains apply, capture, fork, export, delete, and local rice management.
- **Color schemes (Themes):** fetch the `ryostore` colorschemes registry and
  present it through a per-provider subtab strip (HANCORE-linux, Noctalia) with a
  My themes tab for the installed library. Install copies the entry's Noctalia
  palette into `~/.local/share/ryoku/themes/<id>` (install-only); the shell daemon
  converts it to its 34-role palette, so a downloaded scheme appears in the
  Color-scheme picker (Super+W and the Hub) and applies through `theme.theme`.
  Activation stays in that picker, never on install.
- **Bar styles:** expose the shipped runtime style manifests and the active
  `shell.json` value. The current development styles are all visible and report
  installed state. Settings retains selection and configuration.
- **Fastfetch styles:** expose the category and active local state. Until a
  style registry exists, the category renders its honest upcoming plate.
  Fastfetch editing remains in Settings.

Each provider can fail independently. Cached catalogue data and local state
remain visible while the header marks the degraded source as `SEARCH / OFFLINE`.
A failed lockscreen source cannot blank plugins, bundles, or the Library
collection.

## Migration

Store-specific code moves out of the Hub instead of being copied:

- qylock catalogue, cache, and install-only download move to Ryostore; the Hub
  keeps installed list, preview, selection, and greeter application;
- plugin and bundle catalogue, cache, and install paths move to Ryostore;
- rice catalogue and installation move to Ryostore;
- the Hub Store page and remote browse modes are removed;
- Add-ons keeps plugin management and gains installed bundle status and removal;
- Lockscreen, Appearance, Add-ons, Bar Studio, and Fastfetch gain one
  `BROWSE RYOSTORE` route where appropriate;
- existing callers of moved commands migrate to `/usr/bin/ryostore`, with no
  compatibility shim or duplicated command left in `ryoku-hub`;
- `ryostore settings` starts or focuses Ryoku Settings and uses the Hub's
  existing `nav` IPC target to open the correct management section.

This is a clean cutover. Ryostore is the only browse surface after the migration.

## Verification

Backend tests use local fixtures for every provider. They cover normalization,
installed and active precedence, update state, partial bundles, stale cache
fallback, malformed registries, missing assets, and install-only behavior.
Existing store tests move with their implementations.

A backend smoke scenario uses temporary XDG directories:

1. run `ryostore catalog` against the full fixture;
2. install one fixture specimen;
3. run the catalogue again;
4. observe `installed: true` and `active: false`.

Pure JavaScript tests cover grouping, filtering, search ranking, status
precedence, and restored browse state. `qmllint` checks all new and touched QML.

The live app is deployed from the checkout and exercised with `ydotool` and
`grim`:

- Discover, every category, a detail, and exact return restoration;
- global search and Library;
- keyboard-only navigation;
- successful fixture install and retryable fixture failure;
- Open in Settings deep links;
- offline cached rendering;
- ideal and cramped window compositions.

The captured frames are inspected for spacing, clipping, focus, status
legibility, loading and error plates, and detail motion. A visible window alone
is not acceptance.

Delivery is complete when the Hub contains no duplicate remote store, all moved
callers use Ryostore, the existing app packaging loop ships the Quickshell tree,
binary, desktop entry, and icon, focused checks pass, and the relevant app,
Hub, structure, and delivery documentation reflects the cutover.
