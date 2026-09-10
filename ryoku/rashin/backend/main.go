package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const usage = `ryoku-rashin: the Ryoku agent OS daemon

  serve [--if-enabled]   run the dashboard and agent bridge on 127.0.0.1
  index                  regenerate the vault maps (system, desktop, packages, repo, user, habits)
  repo-index <root> [out]  build the Ryoku source map from a checkout (build/deploy time)
  ask <question>         one-shot quick ask against the shared session (launcher)
  term <question>        terminal ask: answer + a ready-to-run command plan (the 'rashin' command)
  setup                  one-click Hermes install, onboarding, and wiring
  wire [agent]           apply vault pointers (all detected agents, or one)
  unwire [agent]         remove vault pointers
  status [--json]        report daemon, vault, hermes, and wiring state
  enable [--at-boot]     start the daemon now and at every login; --at-boot
                         adds user lingering so it starts with the machine
  disable                stop the daemon and turn autostart off (opt out of the default)
  ensure                 default-on convergence: enable at boot unless the user opted out
  backend [provider[:model]]  view or set the fast-lane assistant backend ('auto' follows hermes)
  paths [--json]         show every skill/vault/prowl path (and a paste snippet for any agent)
  agent [use <id>]       list agents + chat backends, or set which agent drives the chat

Invoked as 'rashin', a bare argument is a terminal ask; status/enable/disable/
setup/index still work as subcommands.
`

func main() {
	// Invoked as `rashin` (a symlink), the whole argv is a terminal ask,
	// except the handful of daemon subcommands a user still expects to work.
	if filepath.Base(os.Args[0]) == "rashin" {
		if err := dispatchRashin(os.Args[1:]); err != nil {
			fmt.Fprintln(os.Stderr, "rashin:", err)
			os.Exit(1)
		}
		return
	}
	if len(os.Args) < 2 {
		fmt.Print(usage)
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "serve":
		ifEnabled := len(os.Args) > 2 && os.Args[2] == "--if-enabled"
		err = cmdServe(ifEnabled)
	case "index":
		err = cmdIndex()
	case "repo-index":
		err = cmdRepoIndex(argOr(2, ""), argOr(3, ""))
	case "ask":
		err = cmdAsk(strings.Join(os.Args[2:], " "))
	case "chat":
		err = cmdChat(os.Args[2:])
	case "term":
		err = cmdTerm(os.Args[2:])
	case "setup":
		err = cmdSetup()
	case "wire":
		err = cmdWire(argOr(2, ""))
	case "unwire":
		err = cmdUnwire(argOr(2, ""))
	case "status":
		err = cmdStatus(len(os.Args) > 2 && os.Args[2] == "--json")
	case "enable":
		err = cmdEnable(len(os.Args) > 2 && os.Args[2] == "--at-boot")
	case "disable":
		err = cmdDisable()
	case "ensure":
		err = cmdEnsure()
	case "backend":
		err = cmdBackend(os.Args[2:])
	case "paths":
		err = cmdPaths(pathsFormat(os.Args[2:]))
	case "agent":
		err = cmdAgent(os.Args[2:])
	default:
		fmt.Print(usage)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ryoku-rashin:", err)
		os.Exit(1)
	}
}

// dispatchRashin routes the `rashin` command: daemon subcommands pass
// through; everything else is a terminal ask.
func dispatchRashin(args []string) error {
	if len(args) > 0 {
		switch args[0] {
		case "status":
			return cmdStatus(len(args) > 1 && args[1] == "--json")
		case "enable":
			return cmdEnable(len(args) > 1 && args[1] == "--at-boot")
		case "disable":
			return cmdDisable()
		case "ensure":
			return cmdEnsure()
		case "backend":
			return cmdBackend(args[1:])
		case "paths":
			return cmdPaths(pathsFormat(args[1:]))
		case "agent":
			return cmdAgent(args[1:])
		case "setup":
			return cmdSetup()
		case "index":
			return cmdIndex()
		}
	}
	return cmdTerm(args)
}

func argOr(i int, def string) string {
	if len(os.Args) > i {
		return os.Args[i]
	}
	return def
}

// pathsFormat maps the `paths` flags to cmdPaths' format: --json, --snippet, or
// the human default.
func pathsFormat(args []string) string {
	for _, a := range args {
		switch a {
		case "--json":
			return "json"
		case "--snippet":
			return "snippet"
		}
	}
	return ""
}
