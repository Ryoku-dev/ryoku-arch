// Package sys holds the low-level infrastructure the ryoku CLI's updater,
// doctor, and materialize concerns all share: process exec, package and unit
// queries, filesystem facts, XDG paths, and terminal styling. It carries no
// domain logic of its own, only the primitives, defined once so no two
// concerns keep their own copy.
package sys

import (
	"bufio"
	"os"
	"os/exec"
	"strings"
)

// Run executes name with args wired to the parent's stdio, so pacman, git, and
// friends stream straight to the terminal.
func Run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}

// Sudo runs args under sudo with the same stdio as Run.
func Sudo(args ...string) error { return Run("sudo", args...) }

// RunOut runs name with args and returns its stdout, no stdio wiring.
func RunOut(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).Output()
	return string(out), err
}

// Has reports whether name resolves on PATH.
func Has(name string) bool { _, err := exec.LookPath(name); return err == nil }

// Exists reports whether the path exists.
func Exists(p string) bool { _, err := os.Stat(p); return err == nil }

// PathPresent reports whether something already occupies p -- a regular file, a
// directory, or a symlink, INCLUDING a dangling one. Unlike Exists it does not
// follow the link (os.Lstat, not os.Stat), so a user's symlink into a dotfiles
// repo counts as present even when its target is momentarily unavailable (an
// unmounted repo at early boot). Guards a seed from overwriting a slot the user
// already owns.
func PathPresent(p string) bool { _, err := os.Lstat(p); return err == nil }

// PkgInstalled reports whether a pacman package is installed.
func PkgInstalled(name string) bool {
	return exec.Command("pacman", "-Q", name).Run() == nil
}

// UnitEnabled reports whether a systemd unit is enabled (or static/alias --
// anything systemctl reports as will-start).
func UnitEnabled(unit string) bool {
	return exec.Command("systemctl", "is-enabled", "--quiet", unit).Run() == nil
}

// InstalledVersion is the installed ryoku-desktop package version, or "".
func InstalledVersion() string {
	out, err := RunOut("pacman", "-Q", "ryoku-desktop")
	if err != nil {
		return ""
	}
	f := strings.Fields(strings.TrimSpace(out))
	if len(f) == 2 {
		return f[1]
	}
	return ""
}

// CountNonEmpty counts the non-blank lines in s.
func CountNonEmpty(s string) int {
	n := 0
	sc := bufio.NewScanner(strings.NewReader(s))
	for sc.Scan() {
		if strings.TrimSpace(sc.Text()) != "" {
			n++
		}
	}
	return n
}
