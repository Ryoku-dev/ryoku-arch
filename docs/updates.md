# Updates and delivery

How a change in this repo reaches a running machine, and the contract that keeps
a user's install a mirror of a dev checkout. Read this before adding a config
file, a `shell.json` key, or anything a user must receive.

## Two worlds, one result

- A **dev box** runs the checkout: `ryoku deploy` builds the binaries and lays
  `ryoku/` into `~/.config`. `ryoku update` on it tracks `origin/main` (the git
  channel) and redeploys.
- A **user box** runs signed packages: `ryoku update` runs `pacman -Syu` from the
  `[ryoku]` repo, then `ryoku materialize`, then `ryoku doctor`.

They must converge. A change that lands on one but not the other is the bug this
page exists to prevent.

## `ryoku update`

Snapper pre-snapshot, then the channel (git fast-forward, or `pacman -Syu` from
`[ryoku]`), then stage2 through the just-installed binary: quiesce the shell,
`ryoku materialize`, reload Hyprland, restart the shell, `ryoku doctor`, snapper
post-snapshot. Each stage publishes to `$XDG_RUNTIME_DIR/ryoku-update.json` (the
ordered steps, the current label, a live log tail, and, on failure, the error
and the pre-update snapshot), so the update island and the Hub's Updates page
render a determinate run and a one-click rollback.

After the desktop is back, the update refreshes the agent OS when it is present:
`ryoku-rashin index` regenerates the vault and re-indexes the config mirror with
Prowl, then `prowl-agent` is brought current. On a dev box (Prowl on PATH but
not owned by a pacman package) it runs `prowl-agent update`; a packaged box
already got the new build from `pacman -Syu`, so the step just logs that the
binary is managed by pacman. Both are best effort and never fail an update.

### The boot guard

A packaged update that moves the box to another release arms a boot guard:
stage2 writes `/var/lib/ryoku/update-pending.json` (previous release, new
release, the pre-update snapshot, the boot it ran in). `ryoku-boot-guard.service`
runs `ryoku boot-guard` as root early in every boot, before the display
manager, and only while that marker exists. The shell daemon records a good
boot once the shell has stayed up 45 s (`/var/lib/ryoku/boot/ok-<uid>`, the boot
id); a record from any boot other than the one the update ran in disarms the
guard. Without one, the boot counts: on the second, the guard tracks the
previous release back (`ryoku track <from>` plus `pacman -Syu`; the Ryoku set
only, Arch untouched), re-materializes every user's config from it, and leaves
a notice `ryoku doctor` shows once. On a third it points the Limine boot menu
at the pre-update snapshot entry, for the case where the packages were not what
broke. `sudo ryoku boot-guard --disarm` clears a marker by hand. The `ryoku`
package ships the unit and its tmpfiles entry; the doctor enables the unit and
prepares the record directory on every update, so boxes installed before it get
it on their next update.

## materialize: the config a user receives

`ryoku materialize` lays the package's base config (`/usr/share/ryoku/config`,
mirrored by `ryoku/shell/deploy.sh` on a dev box) into `~/.config`:

- Every shipped file is copied over on every update (the previous Ryoku copy is
  clobbered) and files dropped from a release are pruned; `~/.config/quickshell`
  is converged wholesale.
- A short **seed list** (`generatedSeed` in `ryoku/cli/materialize.go`:
  `hypr/monitors.lua`, `hypr/gpu.lua`, `hypr/keyboard.lua`,
  `fastfetch/config.jsonc`, `kitty/current-theme.conf`) is copied only when
  absent, never clobbered: per-machine or user-owned state an update must keep.
- The user overlay (`~/.config/ryoku/user_edits`, mirroring `~/.config`) is laid
  on top last, so a file there wins at its mirrored path; see below. Anything the
  package never ships (`hypr/user.lua`, `kitty/user.conf`, a forked module) is
  left alone regardless.

So the QML and the `Config.qml` defaults reach users on every update. A **new**
`shell.json` key is safe: the user's file lacks it, and the shell reads the new
`Config.qml` default.

## user_edits: your edits, kept apart

Ryoku-owned config and user edits live in separate trees, so an update refreshes
the base freely while your edits stand. The base is the restore point; the
overlay is yours.

- **base** `/usr/share/ryoku/config` (the checkout on a dev box): pristine,
  re-laid in full on every update, so every fix and addition lands first.
- **user_edits** `~/.config/ryoku/user_edits`, mirroring `~/.config`, sparse:
  only what you changed. `materialize` overlays it last, so a file here wins at
  its mirrored path. Empty means pure base and the overlay is a no-op.

Two ways to override, neither of which blocks a fix:

- **Overlay (default).** The tool's own last-wins include: Hyprland loads the
  base modules, then `settings.lua` and `user.lua` last; kitty `globinclude`s
  `user.conf`. The base loads underneath, so a new upstream keybind still arrives
  while your file wins on what it sets.
- **Fork (opt-in).** A whole copy of a shipped file shadows the base one. You own
  it now, so an upstream fix to that file will not reach you automatically. Your
  forks are the files you see in the overlay; `ryoku reset <path>` takes the new
  base.

Ryoku Settings writes its generated `hypr/settings.lua` and `hypr/rebinds.lua`
into the overlay (authored under `user_edits`, reflected live). Its other state
(bar, colours, launcher, device lighting) it keeps under `~/.config/ryoku`,
GUI-managed and update-safe: the package ships no file there, so `materialize`
never clobbers or prunes it and a keyboard keeps the look you gave it across an
update. `ryoku reset` drops an override; `ryoku recovery` is the last
resort, wiping the overlay and that state back to shipped defaults.

## doctor: converging what materialize can't

`ryoku doctor` runs convergent reconcilers for the stateful drift materialize
can't state declaratively (disk, boot, session, and the user-owned
`~/.config/ryoku/*.json` materialize never rewrites). Reconcilers stand in for a
migration ledger: each is idempotent and safe on every update, and is retired
once every supported install has run it. `reconcileShellConfig` migrates a stale
`shell.json` (drops retired keys, revives the bar, clamps geometry).
`reconcileLauncherLocalFrostDefault` moves only the launcher's retired shipped
`bgBlur: 12` to the new 2 px local-frost default, then records a marker so a
later deliberate 12 remains a user choice.
`reconcileUserEdits` seeds the how-to guide and, for boxes upgraded from the
retired adopt step, moves the tool's own user files (`hypr/user.lua`,
`hypr/monitors_user.lua`, `kitty/user.conf`) back OUT of the overlay. Those are
edited in place; a frozen overlay copy of one used to be re-laid over the live
file on every update, wiping edits made afterward. Idempotent.
`reconcileMimeDefaults` clears the default-app map an older release froze into
`~/.config/mimeapps.list`: entries that only copy Ryoku's shipped values are
dropped (the file goes if that is all it held), and anything the user chose
stays. Ryoku's map ships to `/usr/share/applications/mimeapps.list` now, the
bottom of the XDG mimeapps chain, so it sets the defaults without ever
outranking a user's pick.
`reconcileShellInstances` clears a desktop that is running twice: a shell surface
orphaned by a daemon that was killed keeps drawing, and Quickshell allows a second
instance of one config, so the replacement draws over it. It keeps the instance
the supervising daemon started and stops the rest.
`reconcileShellLoad` gets a black screen back. Every surface is one Quickshell
instance, so a single QML file that cannot load takes the whole desktop, at login
and after an update alike. It reads the load failure from the shell daemon's
surface log (or loads the config once when there is no log), scopes the repair to
the module the loader blamed, moves a user override that breaks the desktop aside
as `.broken`, puts back every shipped file the live tree no longer matches, and
restarts the shell. When the shipped file is itself at fault it says so and names
`ryoku update` and `ryoku rollback`, the two things that help.
`reconcileHyprPlugins` keeps the enabled Hyprland compositor plugins loading
across a Hyprland bump: a plugin is ABI-locked to the exact compositor build
and every copy Ryoku builds carries an `.abi` receipt, so after an update it
rebuilds each enabled plugin whose receipts no longer match the installed
headers (`ryoku-hub hypr plugins rebuild --stale`, the Plugins page's builder)
before the next login, and names the toolchain to install when a box has none.
See `docs/hyprland-plugins.md`.

## Publishing: releases and channels

The `[ryoku]` repo is published into named states, all under the one bucket
mount the repo domain serves (`repo.ryoku.dev/stable/<key>` is bucket object
`<key>`; the `stable` path segment is the mount, not the channel):

| Directory | Channel | Written when |
|---|---|---|
| `x86_64/` | **stable**: the URL every installed box has | a release tag is published: a byte copy of that release |
| `releases/<tag>/x86_64/` | one frozen release; never rewritten | the tag is published (`publish-repo.yml` refuses an existing directory) |
| `releases/index.json` | the release ledger, newest first | after each release |
| `channels/testing/x86_64/` | **testing** | every push to `unstable-dev` |

So a box on stable moves between named releases, and can be put back on any
earlier one. Each build carries a strictly increasing package version
(`core.r<commit-count>.g<sha>`) that `pacman -Syu` upgrades to, and the
`ryoku-desktop` package writes `/etc/ryoku-release` (`RELEASE=`, `CHANNEL=`,
`VERSION=`, `COMMIT=`) so a box can say which release it runs; `release.json`
beside each channel's db says which one the channel serves.

A release is a tag: `main` advances only by fast-forward from `unstable-dev`,
and publishing nothing on that push. The maintainer runs **Stable Release**
(`bump_type: none` tags the `VERSION` main already carries; a bump rewrites it
first), which tags `main`, publishes `releases/<tag>/`, moves the stable
pointer onto it, records the ledger entry, and dispatches both release ISOs
(plain Arch and CachyOS) from that frozen directory, so an ISO named for a
release installs exactly that release. Arch itself keeps rolling between
releases; only the Ryoku set is frozen.

**Work on `unstable-dev` reaches testing on every push, and stable only when a
release is tagged.**

On a packaged box the channel is nothing but the `Server` line of the `[ryoku]`
stanza, so there is no second state to drift from it:

- `ryoku track stable | testing | v<tag>` rewrites that line and runs an update
  that moves the Ryoku set to what the channel serves, down as well as up
  (`pacman -Syu`, then an explicit `-S ryoku-desktop`, whose exact-version
  depends bring the whole set along). A tag pins the box to that release until
  it is tracked away.
- `ryoku rollback --to v<tag>` is `track` onto a frozen release: the Ryoku set
  goes back in one pacman transaction while Arch stays current. Bare
  `ryoku rollback` lists the ledger and the snapshots.
- `ryoku status` reports `release` (this box) and `channelRelease` (what the
  channel serves); `ryoku version` prints the release tag.
- The doctor names the channel it finds and warns, without touching it, when
  `[ryoku]` points at a mirror Ryoku does not publish.

A checkout box (`ryoku track main | unstable-dev`) tracks git branches instead
and rebuilds from source; see `docs/development.md`.

### Release names

Every release line has a name from the creation stories Ryoku draws on (the
Kojiki and the Theogony), in the order those stories tell them; `CODENAME`
holds the current one and `release/names.md` tells each name's story. The
name changes when a line begins (the pre-1.0 line is Onogoro, the first
island; 1.0 is Amaterasu) and every release inside the line keeps it. It
travels with the release: `build-repo.sh` writes it into `release.json` and
the ryoku-desktop package into `/etc/ryoku-release` (`NAME=`), the publish
copies it into `releases/index.json`, the Stable Release and Release Notes
workflows title the tag and the GitHub release with it (a line's first release
opens with its story), and a box shows it in `ryoku version --pretty` (which
fastfetch's OS line uses), `ryoku status`, `ryoku rollback`, the update
island (when the channel serves the next line) and the Hub's Updates page.

## The contract

- **A user-facing config file must be delivered by a path a user runs**: shipped
  in a package (then materialized) or seeded by the installer. A file only
  `deploy.sh` lays, or one no path lays, reaches no user. `ryoku-dev-verify-delivery`
  fails the commit on such an orphan.
- **A removed or renamed `shell.json` key, or a changed default that must reach
  existing users, needs a `doctor` reconciler** (materialize never edits a user's
  `shell.json`). An additive key needs nothing.
- **Never ship into a path the user's own tools write, and never write a tool's
  output into a shipped path.** `materialize` clobbers every shipped file, so
  laying Ryoku's defaults where an app writes the user's choice resets that
  choice on each update: `~/.config/mimeapps.list` did exactly that to default
  apps. Ship such defaults one layer down where the format provides one
  (`/usr/share/applications/mimeapps.list` for mime defaults), or make the file
  a `generatedSeed` if it has no layering. The same rule read the other way:
  a rice used to copy its emblem over the shipped
  `fastfetch/fastfetch-emblem.png`, and every update put the brand mark back.
  Anything Ryoku writes on the user's behalf (an imported logo, a rice asset)
  goes to a user-owned name the package never ships (`fastfetch/ryoku-logo.*`).
- **A user override belongs in `~/.config/ryoku/user_edits`, never in a shipped
  path.** The base still ships every file (the delivery check stays green) and
  the overlay wins on top. A whole-file fork opts out of upstream fixes for that
  one file, so prefer an overlay for anything additive. An edit made to a
  shipped file in place is not lost either: `materialize` notices bytes that
  match neither what it laid last time nor what it ships now, copies them into
  the overlay as a fork, lays the base, and lists the files it kept. Hyprland
  additions (rules, binds) belong in `hypr/user.lua` or the Hub, which are
  never re-laid.
- **Everything a user runs must converge on update, wherever it lives.**
  `materialize` covers `~/.config`; a payload installed elsewhere (the lock
  bundle under `~/.local/share`, the SDDM greeter skin under
  `/usr/share/sddm/themes`) needs a `doctor` reconciler that compares content
  with the shipped copy and re-lays it on drift, not one that only checks it
  exists. An install-once path silently pins every existing box to the release
  it was installed with: the lock shipped fixes for weeks that no updated box
  ever received.
- **One master per setting.** Two stores that both claim a value drift, and the
  next sync of either undoes the other: the colour master is `shell.json`
  `theme.theme` (the daemon shadows it into `theme.json` `followWallpaper` on
  every load), so the Hub's scheme cards and a rice select the theme through
  `ryoku-shell theme` instead of writing the shadow. A new setting gets one
  writer; every other surface reads.
- **Shipped QML must load, not just exist.** One file that cannot instantiate
  blanks its whole surface (a Hub page, a shell root), and Quickshell reports it
  only in the instance log. `bin/ryoku-dev-lint-qml` fails on the qmllint
  classes that mean "will not load", resolved against the installed modules;
  the publish gate runs it over the materialized tree.
- **Login restarts the session daemons.** The user manager can outlive a
  session (linger, a relogin after a compositor crash) and still hold a
  `ryoku-shell` bound to the dead compositor; `start` then does nothing and the
  login lands on bare Hyprland. The autostart reloads units, clears a start
  limit, and `restart`s the shell and wallpaper daemons every session.
- **A change reaches stable only when a release is tagged**, and testing on
  every `unstable-dev` push. Keep the gap small; the delivery check reports it
  on every push.

## Checks

- `bin/ryoku-dev-verify-delivery` flags orphan configs (hard fail) and reports
  the publish lag. It runs in `pre-commit`, `post-commit`, and the Delivery check
  workflow.
- The install-test workflow builds the ISO and runs a real, unattended install in
  a VM, then verifies the desktop comes up, so a broken install or a missing
  package is caught before a user hits it.
- The publish (`publish-repo.yml`) builds and signs the repo once, keeps it as
  a workflow artifact, installs ryoku-desktop from that artifact on Arch and
  CachyOS with the release key verified (`installation/tests/container-install.sh`
  with `RYOKU_PREBUILT_REPO=1`), and uploads the same artifact. What was tested
  is byte-for-byte what ships; a run that fails the gate publishes nothing.
- `bin/ryoku-dev-lint-qml <config-root>...` fails on QML that cannot load. The
  publish gate (`installation/tests/container-install.sh`) runs it over the
  materialized shell and Hub trees against the installed Qt modules, the same
  import path a user's session resolves; run it on a dev box after
  `ryoku deploy` before pushing a QML change.
