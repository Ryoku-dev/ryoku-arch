package keyboard

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

func usageText() string {
	return i18n.T("Usage: ryoku keyboard <command>\n\n  status [--json]      what layout each layer uses: desktop, greeter, console,\n                       and whether the boot image still carries an older one\n  detect               the layout this system records, and where it came from\n  apply [<layout>]     put a layout on the greeter and the console, and rebuild\n                       the boot image so the disk passphrase prompt follows.\n                       No layout means the desktop's own.\n      --no-boot        skip the boot image rebuild (greeter and TTY only)\n")
}

// Run is the `ryoku keyboard` entry point.
func Run(args []string) error {
	if len(args) == 0 {
		fmt.Print(usageText())
		return nil
	}
	switch args[0] {
	case "status":
		return runStatus(args[1:])
	case "detect":
		return runDetect()
	case "apply":
		return runApply(args[1:])
	case "-h", "--help", "help":
		fmt.Print(usageText())
		return nil
	}
	return fmt.Errorf(i18n.T("unknown keyboard command: %s"), args[0])
}

// DesktopLayout reads the layout the desktop uses, from the Hub's store. That
// store is the source of truth: settings.lua is generated from it.
func DesktopLayout() Layout {
	b, err := os.ReadFile(filepath.Join(sys.ConfigHome(), "ryoku", "hypr.json"))
	if err != nil {
		return Layout{}
	}
	var o struct {
		Input struct {
			KbLayout  string `json:"kbLayout"`
			KbVariant string `json:"kbVariant"`
			KbOptions string `json:"kbOptions"`
		} `json:"input"`
	}
	if json.Unmarshal(b, &o) != nil {
		return Layout{}
	}
	return Layout{Layout: o.Input.KbLayout, Variant: o.Input.KbVariant, Options: o.Input.KbOptions}
}

// State is every layer at once, plus whether they agree.
type State struct {
	Desktop    string `json:"desktop"`
	Greeter    string `json:"greeter"`
	Console    string `json:"console"`
	ConsoleXkb string `json:"console_as_layout"`
	BootImage  string `json:"boot_image"`
	BootStale  bool   `json:"boot_stale"`
	Agrees     bool   `json:"agrees"`
}

// Read gathers all four layers. Greeter and console are compared in xkb terms,
// so a console keymap that spells the same layout differently (uk for gb) is
// not reported as drift.
func Read() State {
	d := DesktopLayout().Primary()
	stale, img := BootStale()
	s := State{
		Desktop:    d,
		Greeter:    strings.SplitN(X11Layout(), ",", 2)[0],
		Console:    ConsoleKeymap(),
		ConsoleXkb: ConsoleAsXkb(ConsoleKeymap()),
		BootImage:  img,
		BootStale:  stale,
	}
	// A layer that says nothing is unset, not disagreeing; it simply has not
	// been written yet, which the greeter case covers on a fresh install.
	greeterOK := s.Greeter == "" || s.Desktop == "" || s.Greeter == s.Desktop
	consoleOK := s.ConsoleXkb == "" || s.Desktop == "" || s.ConsoleXkb == s.Desktop
	s.Agrees = greeterOK && consoleOK && !s.BootStale
	return s
}

func runStatus(args []string) error {
	s := Read()
	if len(args) > 0 && args[0] == "--json" {
		b, err := json.MarshalIndent(s, "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(b))
		return nil
	}
	fmt.Printf(i18n.T("desktop   %s\n"), orUnset(s.Desktop))
	fmt.Printf(i18n.T("greeter   %s\n"), orUnset(s.Greeter))
	fmt.Printf(i18n.T("console   %s%s\n"), orUnset(s.Console), xkbNote(s))
	if s.BootImage == "" {
		fmt.Printf(i18n.T("boot      no image found\n"))
	} else if s.BootStale {
		fmt.Printf(i18n.T("boot      %s is older than %s, so the passphrase prompt still uses the keymap it was built with\n"),
			filepath.Base(s.BootImage), VconsolePath)
	} else {
		fmt.Printf(i18n.T("boot      %s carries the current keymap\n"), filepath.Base(s.BootImage))
	}
	if s.Agrees {
		fmt.Println(i18n.T("\nevery layer agrees."))
	} else {
		fmt.Println(i18n.T("\nthey disagree; `ryoku keyboard apply` puts the desktop's layout on all of them."))
	}
	return nil
}

func xkbNote(s State) string {
	if s.ConsoleXkb != "" && s.ConsoleXkb != s.Console {
		return fmt.Sprintf(i18n.T(" (%s as a layout)"), s.ConsoleXkb)
	}
	return ""
}

func orUnset(v string) string {
	if v == "" {
		return i18n.T("unset")
	}
	return v
}

func runDetect() error {
	got := Detect(X11Layout(), ConsoleKeymap(), SystemLocale())
	if got.Layout == "" {
		fmt.Println(i18n.T("nothing on this system records a keyboard layout"))
		return nil
	}
	fmt.Printf(i18n.T("%s (from %s)\n"), got.Layout, got.Source)
	return nil
}

func runApply(args []string) error {
	noBoot := false
	want := ""
	for _, a := range args {
		switch {
		case a == "--no-boot":
			noBoot = true
		case strings.HasPrefix(a, "-"):
			return fmt.Errorf(i18n.T("unknown flag: %s"), a)
		case want == "":
			want = a
		default:
			return fmt.Errorf(i18n.T("only one layout may be given"))
		}
	}
	l := DesktopLayout()
	if want != "" {
		l.Layout = want
	}
	if l.Primary() == "" {
		return fmt.Errorf(i18n.T("no layout to apply: pass one, or set it in Ryoku Settings"))
	}
	if err := ApplySystem(l); err != nil {
		return err
	}
	fmt.Printf(i18n.T("greeter and console set to %s\n"), l.Primary())
	if noBoot {
		fmt.Println(i18n.T("boot image left alone; the disk passphrase prompt keeps its old keymap until `sudo mkinitcpio -P`"))
		return nil
	}
	fmt.Println(i18n.T("rebuilding the boot image so the passphrase prompt follows..."))
	if err := RebuildBootImage(); err != nil {
		return fmt.Errorf(i18n.T("%w\ngreeter and console are set; rerun `sudo mkinitcpio -P` to finish"), err)
	}
	fmt.Println(i18n.T("done: the passphrase prompt, greeter, console and desktop all use"), l.Primary())
	return nil
}
