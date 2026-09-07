# Ryoku packages

The Ryoku desktop ships as signed pacman packages served from the `[ryoku]`
repository (`Server = https://repo.ryoku.dev/stable/$arch`). Each directory here is one
package; the publish CI builds every `PKGBUILD` and pushes the results to the
repo. Packages publish only from `main` release tags, never from `unstable-dev`.

## The set

- `ryoku-keyring` -- the release signing key, into `/usr/share/pacman/keyrings`.
  Installed first so pacman trusts the repo. (Built from key material beside its
  own PKGBUILD; the only package that is not built from the source tree.)
- `ryoku-shell` -- the shell IPC daemon (Go), to `/usr/bin/ryoku-shell`.
- `ryoku-hub` -- the Hub backend (Go), to `/usr/bin/ryoku-hub`.
- `ryoku` -- the control CLI (update / rollback / snapshots / materialize / ...),
  to `/usr/bin/ryoku`.
- `ryoku-blobs` -- the `Ryoku.Blobs` QML plugin, to
  `/usr/lib/qt6/qml/Ryoku/Blobs`.
- `hypr-dynamic-cursors`, `ryoku-hypr-plugins` (hyprbars + hyprfocus),
  `hyprglass`, `imgborders` -- the optional Hyprland compositor plugins the Hub
  can toggle, into `/usr/lib/hyprland/plugins/`. Each builds from source
  version-matched to the build host's Hyprland (its `prepare()` reads the plugin's
  `hyprpm.toml` and checks out the commit paired with the running Hyprland), so
  they track the shipped compositor with no manual pin bumps. Off until enabled
  in Ryoku Settings.
- `ryoku-desktop` -- the umbrella. Depends on the packages above plus the user-facing
  desktop runtime, lays the base configuration under `/usr/share/ryoku/config`,
  and installs the helper scripts (`ryoku-cmd-*`, the hardware `ryoku-*`,
  `ryoku-fastfetch`) to `/usr/bin` and the GPU udev rule to
  `/usr/lib/udev/rules.d`.

## Build-from-checkout model

Most of these PKGBUILDs build from the checked-out monorepo, not from release tarballs.
`source=()` is empty; each PKGBUILD derives the repo root as `$startdir/../../..`,
because the CI runs `makepkg` in place inside each package directory within a
full checkout. The Go binaries and the QML plugin are built into `$srcdir`, so
the source tree is never modified, and `makepkg --clean` removes `$srcdir` and
`$pkgdir` afterward.

The `gpk` and `ryoku-keyring` PKGBUILDs are the exceptions: they fetch a pinned
upstream artifact (a release binary and the release key material, respectively)
rather than building from the checkout.

makedepends across the set: `go` (ryoku-shell, ryoku-hub, ryoku),
`cmake ninja qt6-shadertools qt6-declarative` (ryoku-blobs), and `rust` + `git`
(hyprland-preview-share-picker, asusctl), on top of the assumed `base-devel`.
`ryoku-hub` (`github.com/BurntSushi/toml`) needs network at build time.

## Configs and materialize

`ryoku-desktop` installs the base configs to `/usr/share/ryoku/config`, mirroring
the `~/.config` layout (for example `hypr/hyprland.lua`, `quickshell/...`,
`quickshell/hub/...`, `fish/config.fish`, `qt6ct/qt6ct.conf`, `starship.toml`). The
Hyprland tree includes `scripts/`, so after materialize the `ryoku-cmd-*` and
`*.sh` helpers also sit at `~/.config/hypr/scripts`, where the shell invokes them
by absolute path.

`ryoku materialize` (run as the user, on login or by hand) copies that tree into
`~/.config`: it clobbers the files it owns and prunes files dropped from a
release, but never touches user files such as `hypr/user.lua` or
`fish/user.fish`. Package install runs as root and cannot write a user's home, so
the `ryoku-desktop` install scriptlet only prints the materialize hint.
