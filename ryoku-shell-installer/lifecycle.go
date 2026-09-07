package main

// lifecycle.go: cross-run resume state and the --uninstall mode. a run
// records every completed step id plus the backup dir in a state file; a
// rerun after a crash or power loss offers to resume from the failed step
// (auto with --yes) instead of redoing work against a half-changed system.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"ryoku-i18n"
)

type runState struct {
	Completed []string `json:"completed"`
	BackupDir string   `json:"backupDir"`
	Updated   string   `json:"updated"`
}

func statePath(home string) string {
	return filepath.Join(home, ".local/state/ryoku/shell-install-state.json")
}

func loadState(home string) *runState {
	b, err := os.ReadFile(statePath(home))
	if err != nil {
		return nil
	}
	var s runState
	if json.Unmarshal(b, &s) != nil || len(s.Completed) == 0 {
		return nil
	}
	return &s
}

func (s *runState) has(id string) bool {
	for _, c := range s.Completed {
		if c == id {
			return true
		}
	}
	return false
}

// markStepDone records a finished step; the file is rewritten after every
// step so a kill at any point leaves an accurate resume point.
func (e *engine) markStepDone(id string) {
	if e.dry {
		return
	}
	if e.state == nil {
		e.state = &runState{}
	}
	if !e.state.has(id) {
		e.state.Completed = append(e.state.Completed, id)
	}
	if e.backupDir != "" {
		e.state.BackupDir = e.backupDir
	}
	e.state.Updated = time.Now().Format(time.RFC3339)
	b, err := json.MarshalIndent(e.state, "", "  ")
	if err != nil {
		return
	}
	p := statePath(e.f.homeDir)
	if os.MkdirAll(filepath.Dir(p), 0o755) == nil {
		_ = os.WriteFile(p, append(b, '\n'), 0o644)
	}
}

// clearState removes the resume file after a fully successful run.
func (e *engine) clearState() {
	if !e.dry {
		_ = os.Remove(statePath(e.f.homeDir))
	}
}

// ---- uninstall ----

// confirm asks on the terminal; --yes answers everything with yes.
func confirm(rd *bufio.Reader, q string, yes bool) bool {
	if yes {
		fmt.Println(q + " [y/N] y (--yes)")
		return true
	}
	fmt.Print(q + " [y/N] ")
	ln, err := rd.ReadString('\n')
	if err != nil {
		return false
	}
	ln = strings.ToLower(strings.TrimSpace(ln))
	return ln == "y" || ln == "yes"
}

// runUninstall removes the ryoku packages, retires the [ryoku] repo stanza,
// then walks the backup chain newest to oldest running each restore.sh with
// confirmation: that is the honest inverse of possibly repeated installs,
// each script undoes exactly what its run changed (configs, disabled
// services, display manager, shell). session packages (sddm, pipewire, ...)
// are left alone, they may predate Ryoku and removing them can kill a box.
func runUninstall(yes, dry bool) int {
	fmt.Println(bold(cBrand, "ryoku-shell-install") + fg(cSub, " "+i18n.T("(uninstall)")))
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		fmt.Println(i18n.T("cannot resolve your home directory"))
		return 1
	}
	rd := bufio.NewReader(os.Stdin)
	run := func(name string, args ...string) error {
		line := shellJoin(name, args)
		if dry {
			fmt.Println("DRYRUN: " + line)
			return nil
		}
		fmt.Println("$ " + line)
		c := exec.Command(name, args...)
		c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
		return c.Run()
	}

	// 1. packages, one -R transaction; ryoku-desktop depends on the rest so
	// pacman orders the removal itself.
	var installed []string
	for _, p := range ryokuPkgs {
		if activeDistro.id == "arch" && pacmanHas(p) {
			installed = append(installed, p)
		}
	}
	if len(installed) == 0 {
		fmt.Println(i18n.T("no ryoku packages installed"))
	} else if confirm(rd, i18n.Tf("remove %s?", strings.Join(installed, " ")), yes) {
		if err := run("sudo", append([]string{"-n", "pacman", "-R", "--noconfirm"}, installed...)...); err != nil {
			fmt.Println(i18n.T("warning: package removal failed; fix pacman and re-run (continuing with restore)"))
		}
	}

	// 2. the [ryoku] repo stanza; original kept next to it.
	if b, err := os.ReadFile("/etc/pacman.conf"); err == nil && activeDistro.id == "arch" && ryokuStanzaRe.Match(b) {
		if confirm(rd, i18n.T("drop the [ryoku] repository from /etc/pacman.conf?"), yes) {
			stripped := stripPacmanSection(string(b), "ryoku")
			if dry {
				fmt.Println(i18n.T("DRYRUN: rewrite /etc/pacman.conf without [ryoku]"))
			} else {
				if err := run("sudo", "-n", "cp", "/etc/pacman.conf", "/etc/pacman.conf.pre-ryoku-uninstall"); err == nil {
					c := exec.Command("sudo", "-n", "tee", "/etc/pacman.conf")
					c.Stdin = strings.NewReader(stripped)
					c.Stdout = nil
					if err := c.Run(); err != nil {
						fmt.Println(i18n.T("warning: could not rewrite /etc/pacman.conf"))
					}
				}
			}
		}
	}

	// 3. backups, newest first. each restore.sh is additive-safe: it puts
	// back the exact files its run saved and re-enables what that run
	// disabled. walking the whole chain ends at the pre-Ryoku state.
	root := filepath.Join(home, ".local/state/ryoku/shell-install")
	backups, _ := filepath.Glob(filepath.Join(root, "backup-*"))
	sort.Sort(sort.Reverse(sort.StringSlice(backups)))
	restored := 0
	for _, b := range backups {
		rs := filepath.Join(b, "restore.sh")
		if _, err := os.Stat(rs); err != nil {
			continue
		}
		if !confirm(rd, i18n.Tf("run %s?", rs), yes) {
			fmt.Println(i18n.Tf("skipped %s (and everything older; the chain only makes sense in order)", b))
			break
		}
		if dry {
			fmt.Println("DRYRUN: bash " + rs)
			restored++
			continue
		}
		if err := run("bash", rs); err != nil {
			fmt.Println(i18n.Tf("warning: %s reported an error; inspect it and re-run by hand if needed", rs))
		}
		restored++
	}
	if len(backups) == 0 {
		fmt.Println(i18n.Tf("no backups found under %s", root))
	}

	if !dry {
		_ = os.Remove(statePath(home))
	}
	fmt.Println(bold(cGreen, i18n.T("uninstall finished")) + fg(cSub, i18n.Tf(" (%d backup(s) restored)", restored)))
	fmt.Println(i18n.T("kept: session packages (sddm, networkmanager, pipewire, ...) and the backups"))
	fmt.Println(i18n.Tf("under %s; delete those directories once you are sure.", root))
	return 0
}
