# Contributing to Ryoku

Thanks for helping build Ryoku. This guide covers how to work in this repository
so your change lands cleanly. It is short on purpose; the deeper detail lives in
[`docs/`](docs/) and [`AGENTS.md`](AGENTS.md).

## Before you start

Read these first, then keep them open while you work:

- [`AGENTS.md`](AGENTS.md) the cardinal rules. They are not negotiable, and most
  are enforced by the git hooks.
- [`docs/ryoku.md`](docs/ryoku.md) what Ryoku is and how the parts fit.
- [`docs/structure.md`](docs/structure.md) where everything lives and the one job
  it has.
- [`docs/conventions.md`](docs/conventions.md) how code and config are written
  here.
- [`docs/development.md`](docs/development.md) the deploy, test, and commit loop.

## The cardinal rules, in brief

- **Organization is the point.** Every file and folder has one purpose and
  appears once. Search before adding; if a thing exists, reference it rather than
  copying it.
- **The Hyprland config is Lua.** Author it as Lua modules under
  `ryoku/hyprland/`, one concern per file. Never hand-write a raw `hyprland.conf`.
- **One concern per file.** A Lua module does one thing; a QML component is one
  component in one file.
- **The repository is the source of truth.** Deployment is one way, from the
  repository into the live machine. Never copy a live tweak back; change the
  repository and redeploy.
- **Pass the git hooks.** Never bypass them. `--no-verify` is forbidden.
- **Do not bury code in comments.** Comment the *why* when it is not obvious,
  never the *what*. Delete dead code instead of commenting it out.

## Set up the dev loop

Ryoku is developed on a running Ryoku (or Arch + Hyprland) machine. Edit the
repository, deploy, and test live:

```bash
ryoku/shell/dev-run.sh       # build ryoku-shell and run it from the checkout (hot reload)
ryoku/shell/dev-binds.sh on  # bind the shell keys for this session
ryoku/shell/dev-stop.sh      # stop the dev shell
ryoku/shell/deploy.sh        # lay the repo configs into ~/.config one way
```

`dev-run.sh` leaves your own `~/.config` untouched. Use `deploy.sh` to apply the
full set, or let the installer's deploy step do it on a fresh machine.

## Where changes go

- A **package**: the right set in `system/packages/` (`base` for everyone, `dev`
  for toolchains, `hardware` per profile, `aur` for the AUR). Prefer the official
  repositories over the AUR when both have it.
- A **keybind**: `ryoku/hyprland/modules/binds.lua`.
- A **Hyprland concern**: a new module under `ryoku/hyprland/modules/` plus one
  `require` in `hyprland.lua`. Do not grow an unrelated module.
- A **shell surface**: a new component under `ryoku/shell/quickshell/`, with any
  state wired through `ryoku-shell` (`ryoku/shell/ipc/`).
- A **system helper**: a `ryoku-<thing>` script under `system/hardware/.../`,
  installed via `install_bin` in `installation/backend/lib/deploy.sh`, and invoked
  by name from Lua autostart or a keybind.

## Verify before you commit

Test behavior on the running system, not only that a file parses:

- Lua: `luac -p <file>` parses every changed Lua file.
- Shell scripts: `bash -n <file>`; the pre-commit hook also checks staged scripts,
  and `shellcheck` runs on push.
- QML: `qmllint <file>` when available.
- Installer: run the backend with `RYOKU_DRYRUN=1` and the required `RYOKU_*`
  variables to print every action without touching a disk.

Go programs (the TUI, `ryoku-shell`, `ryoku-hub`) and the `Ryoku.Blobs` QML plugin
ship prebuilt in the ISO. The target has no build toolchain, so never assume `go`,
`cmake`, or `ninja` at install time.

## Commits

Every commit passes the hooks in `.githooks/`. Never use `--no-verify`.

- Subjects are `[area] scope: imperative summary`, where area is one of
  `global`, `installation`, `system`, `ryoku`, `docs`, `test`, `tooling`,
  `release`. Shell changes use `[global]`.
- Keep the subject short: 72 characters or fewer, no trailing period. Long or
  technical detail belongs in the body, not the subject.
- No em-dash anywhere in text. No authorship or attribution trailers. No filler.
- One logical change per commit.
- Update the matching `CHANGELOG.md` in the area you touched.

### Release notes

When a change is something a user would notice, add a plain-language note as a
commit trailer. The release bot (`bin/ryoku-release-notes`) harvests these into
the GitHub release, grouped under New / Fixed / Removed; a commit with no note
stays internal.

    Note: New: pin an app by right-clicking it in the dock
    Note: Fixed: right-clicking a dock app now saves or removes the pin
    Note: Removed: the old instant-replay buffer

Write it the way you would tell a friend, not the way you would tell a compiler.
Attach a demo image or gif with a trailing `| <path-or-url>`, where a
repo-relative path lives under `release/media/`:

    Note: New: redesigned wallpaper picker | release/media/wallpaper.gif

A note only reaches a release if its commit reaches the tag intact, so `main`
advances by fast-forward from `unstable-dev`, and a release is the **Stable
Release** workflow run on `main` (`bump_type: none` tags the version `main`
carries). Never squash-merge into a release
branch: squashing collapses commits and drops their notes.

A release line carries a name (`CODENAME`, its story in `release/names.md`);
the release is titled with it and a line's first release opens with the story.
Starting a new line is one commit that changes `CODENAME`, adds the section
and the line's ASCII mark (`ryoku/cli/internal/updater/art/<name>.txt`),
before the release that begins it.

## Pull requests

1. Fork the repository and branch off the current development branch.
2. Make one focused change, with its changelog entry, and verify it on a running
   system.
3. Make sure the hooks pass locally; do not bypass them.
4. Open a pull request describing what changed and how you tested it.

## Reporting bugs and ideas

- Bugs: open a [Bug issue](https://github.com/ryoku-dev/ryoku-arch/issues/new/choose)
  with system details and steps to reproduce.
- Ideas, questions, and feature suggestions:
  [Discussions](https://github.com/ryoku-dev/ryoku-arch/discussions).
- Security reports: see [`SECURITY.md`](SECURITY.md). Do not file them as public
  issues.
