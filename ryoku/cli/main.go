// ryoku = the user-facing CLI for the distro. one front door to updates,
// rollback, and the shell. It is a thin dispatcher: each command is owned by
// an internal package, orchestrating pacman / yay / snapper / materialize
// rather than reimplementing them.
//
//	ryoku update            snapshot -> channel pull or pacman -Syu -> deploy -> reload
//	ryoku rollback          list releases + snapshots; --to <tag> moves back to a release; [id] guides a snapshot restore
//	ryoku snapshots         list snapper snapshots
//	ryoku status            version, commits behind the channel, snapshot count
//	ryoku materialize       lay the base configs into ~/.config (override-safe)
//	ryoku reset [path]      drop a user_edits override, back to the Ryoku default
//	ryoku reload            restart the shell + reload Hyprland
//	ryoku deploy            DEV ONLY: build + materialize from a checkout
//	ryoku recovery          last resort: reset to main + redeploy (overwrites configs)
//	ryoku doctor            run convergent reconcilers (also runs inside update)
//	ryoku debug             print a shareable diagnostic bundle for bug reports
//
// The concerns live in their own folders: internal/updater (update, status,
// rollback, channel, run-state, materialize, version), internal/doctor (the
// convergent reconcilers), and internal/sys (shared low-level primitives).
package main

import (
	"fmt"
	"os"

	"ryoku-cli/internal/doctor"
	"ryoku-cli/internal/importer"
	"ryoku-cli/internal/keyboard"
	"ryoku-cli/internal/keyring"
	"ryoku-cli/internal/securitykey"
	"ryoku-cli/internal/sys"
	"ryoku-cli/internal/updater"
)

func main() {
	scrubQuickshellCrashEnv()
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "update":
		err = updater.Update(os.Args[2:])
	case "materialize":
		err = updater.Materialize()
	case "reset":
		err = updater.Reset(os.Args[2:])
	case "rollback":
		err = updater.Rollback(os.Args[2:])
	case "boot-guard":
		err = updater.BootGuard(os.Args[2:])
	case "snapshots":
		err = updater.Snapshots()
	case "status":
		err = updater.Status(os.Args[2:])
	case "version", "--version", "-v":
		err = updater.Version(os.Args[2:])
	case "reload":
		err = sys.Run("ryoku-shell", "reload")
	case "deploy":
		err = updater.Deploy(os.Args[2:])
	case "recovery":
		err = cmdRecovery(os.Args[2:])
	case "track":
		err = cmdTrack(os.Args[2:])
	case "plugin":
		err = cmdPlugin(os.Args[2:])
	case "doctor":
		err = doctor.Run(os.Args[2:])
	case "debug":
		err = doctor.Debug(os.Args[2:])
	case "keyring":
		err = keyring.Run(os.Args[2:])
	case "security-key":
		err = securitykey.Run(os.Args[2:])
	case "keyboard":
		err = keyboard.Run(os.Args[2:])
	case "import":
		err = importer.Run(os.Args[2:])
	case "-h", "--help", "help", "":
		usage()
	default:
		die("unknown command: %s", os.Args[1])
	}
	if err != nil {
		die("%v", err)
	}
}

func usage() {
	fmt.Print(`Usage: ryoku <command>

  update         apply channel commits (or pacman -Syu), redeploy, reload
  track <chan>   packages: stable|testing|unstable-dev|main|v<tag>; add --source to build from a checkout
  rollback       list releases and snapshots; --to <tag> puts the Ryoku set back on that release
  rollback [id]  guide restoring snapshot <id> from the boot menu
  snapshots      list snapper snapshots
  status         version, commits behind the channel, snapshot count
  version        print the running version (--branch = channel · sha)
  materialize    lay the base configs into ~/.config (keeps your overrides)
  reset [path]   drop a user_edits override (no path: all, -y skips confirm)
  reload         restart the shell and reload Hyprland
  deploy         DEV ONLY: deploy from a repo checkout (RYOKU_REPO)
  recovery       last resort: reset to main and redeploy (overwrites configs)
  doctor         run convergent reconcilers (idempotent stateful fixes)
  debug          print a shareable diagnostic bundle for bug reports
  keyring        show or set how the GNOME keyring unlocks at sign-in
  security-key   enroll and wire a FIDO2/U2F security key for PAM
  import <path>  bring an existing config in: scan, resolve clashes, apply (--undo)
  plugin <cmd>   install/remove/list/validate a shell plugin from git
`)
}

func die(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "ryoku: "+format+"\n", a...)
	os.Exit(1)
}
