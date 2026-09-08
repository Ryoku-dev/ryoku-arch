# system/extras/

The extras subsystem: the helpers that install, remove, and report the optional
**bundles** the Ryoku Hub's Extras section offers. They ship to `/usr/bin` with
`ryoku-desktop` and are driven by the Hub; nothing here runs at boot.

A bundle is a curated set of tools (packages, small installer scripts, and shell
plugins) defined in the `ryostore` catalogue
(`https://github.com/ryoku-dev/ryostore`, under `bundles/`). `ryoku-hub`
fetches and caches that catalogue; the helpers here do the work.

## The helpers

- `ryostore-install` the actuator. Reads a bundle definition from the
  catalogue cache (`ryoku-hub extras cache`), then installs, removes, or reports
  its items. Routes each `package` item to the official repos or the AUR, runs
  each `script` item's installer from the catalogue, and leaves `plugin` items to
  the shell's plugin path. It publishes a per-bundle JSON report under
  `$XDG_RUNTIME_DIR/ryostore/<id>.json` that the Hub watches for live state.
  `status` reports presence without changing anything; `install`/`remove` mutate
  and so run from the Hub's floating terminal, where `sudo` and the AUR helper
  have a TTY. `RYOSTORE_DRYRUN=1` prints the plan and changes nothing.
- `ryoku-pkg-add` install official-repo packages (`pacman -S`).
- `ryoku-pkg-aur-add` install AUR packages with the system AUR helper (yay/paru).
- `ryoku-pkg-remove` remove packages and their now-orphaned dependencies.
- `ryoku-pkg-multilib` enable the `[multilib]` repo, for bundles that declare
  `"requires": ["multilib"]` (Gaming needs it for Steam and the lib32 libraries).
- `ryoku-pkg-cachyos` add the `[cachyos-v3]` repo (CachyOS key, x86-64-v3 only)
  so `linux-cachyos` installs through pacman, for bundles that declare
  `"requires": ["cachyos"]` (CachyOS Kernel). Additive and idempotent: it never
  touches `[core]`/`[extra]` or the stock kernel, and leaves out the baseline
  `[cachyos]` repo and its forked pacman.
- `ryoku-cmd-present` the one presence test (`command -v`) shared by the actuator
  and the catalogue's installer scripts.

## Detection and routing

Detection is decided one way: a `package` item is present when `pacman -Qq`
finds it; a `script` item is present when its `detect` command is on `PATH`.
Routing is decided at install time: a package that resolves with `pacman -Si` is
an official-repo package, otherwise it is built from the AUR. A bundle author
only ever writes the package name.

## Boundaries

`ryoku-hub` owns all network and disk for the catalogue (fetch, cache, installer
resolution); these scripts never fetch. Package transactions go through pacman
and the AUR helper; this subsystem does not reimplement them.
