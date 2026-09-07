package doctor

import (
	"bytes"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
	"strings"

	i18n "ryoku-i18n"
)

// The user overlay (~/.config/ryoku/user_edits) is where a user's config edits
// live, laid over the Ryoku-owned base on every update. This reconciler seeds
// the how-to guide and, for boxes upgraded from the retired "adopt" step, moves
// the tool's own user files (user.lua, monitors_user.lua, kitty/user.conf) back
// OUT of the overlay. Those are edited in place; a frozen overlay copy of one
// was re-laid over the live file every update, silently wiping edits made after
// the copy was taken (the "it wipes my user.lua on every update" report).
// Idempotent.

func reconcileUserEdits(checkOnly bool) recResult {
	edits := sys.UserEditsDir()
	cfg := sys.ConfigHome()
	guide := filepath.Join(edits, "README.md")

	needGuide := !sys.Exists(guide)
	var stale []string
	for _, rel := range sys.LiveOwnedConfig {
		if sys.Exists(filepath.Join(edits, rel)) {
			stale = append(stale, rel)
		}
	}
	if !needGuide && len(stale) == 0 {
		return okRes(i18n.T("overlay is set up"))
	}
	if checkOnly {
		if len(stale) > 0 {
			return wouldRes(i18n.T("a stale overlay copy of %s overrides your live edits on every update"), strings.Join(stale, ", ")).
				withFix(i18n.T("ryoku doctor moves it back out so the live file is the only copy"))
		}
		return wouldRes(i18n.T("the overlay is missing its how-to guide")).
			withFix(i18n.T("ryoku doctor writes %s"), guide)
	}
	if err := os.MkdirAll(edits, 0o755); err != nil {
		return failRes(i18n.T("could not create the overlay dir %s: %v"), edits, err)
	}

	var did []string
	if needGuide {
		if err := os.WriteFile(guide, []byte(userEditsGuide), 0o644); err != nil {
			return failRes(i18n.T("could not write the overlay guide: %v"), err).withFix("ryoku doctor")
		}
		did = append(did, i18n.T("wrote the guide"))
	}
	var freed []string
	for _, rel := range stale {
		if err := retireOverlayCopy(rel, cfg, edits); err != nil {
			return failRes(i18n.T("could not move %s out of the overlay: %v"), rel, err).
				withFix(i18n.T("move ~/.config/ryoku/user_edits/%s to ~/.config/%s by hand"), rel, rel)
		}
		freed = append(freed, rel)
	}
	if len(freed) > 0 {
		did = append(did, i18n.Tf("stopped the overlay from overriding your live %s", strings.Join(freed, ", ")))
	}
	if len(did) == 0 {
		return okRes(i18n.T("overlay is set up"))
	}
	return fixedRes("%s", strings.Join(did, "; "))
}

// retireOverlayCopy moves a live-owned file OUT of the overlay, where the retired
// adopt step used to copy it. overlayUserEdits no longer lays these, so the live
// file is the one that applies; this drops the dead overlay copy without losing
// anything:
//
//	live == overlay   drop the dead duplicate
//	live missing      restore the overlay copy to its live home
//	live differs      back the overlay copy up to <live>.overlay.bak, then drop
//	                  it (the live file, which now wins, is left untouched)
func retireOverlayCopy(rel, cfg, edits string) error {
	src := filepath.Join(edits, rel)
	live := filepath.Join(cfg, rel)
	ob, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	switch lb, lerr := os.ReadFile(live); {
	case os.IsNotExist(lerr):
		if err := sys.CopyFile(src, live); err != nil {
			return err
		}
	case lerr != nil:
		return lerr
	case bytes.Equal(ob, lb):
		// dead duplicate; nothing to preserve.
	default:
		if err := sys.CopyFile(src, live+".overlay.bak"); err != nil {
			return err
		}
	}
	if err := os.Remove(src); err != nil {
		return err
	}
	// drop the overlay parent dir if it is now empty (best-effort).
	_ = os.Remove(filepath.Dir(src))
	return nil
}

// userEditsGuide is seeded at the overlay root as README.md (which the overlay
// never lays into the live config), so a hand-editor who opens
// ~/.config/ryoku/user_edits sees what the tree is for and, just as important,
// what does NOT belong here.
const userEditsGuide = `# The overlay: ~/.config/ryoku/user_edits

This folder mirrors ~/.config. A file you put here is laid on top of Ryoku's own
copy on every update, so it wins and survives while Ryoku's base file keeps
getting fixes underneath. Empty is fine.

Use the overlay for one thing: FORK a whole Ryoku file you want to fully own.

    Copy it here at the same path and edit it, e.g.
        ~/.config/ryoku/user_edits/hypr/modules/binds.lua
    ryoku doctor then warns when an update changes the original, and
    ryoku reset hypr/modules/binds.lua hands it back.

Ryoku Settings (Super + ,) writes hypr/settings.lua and hypr/rebinds.lua here.
Change those in the GUI, not by hand.

--- Simple tweaks do NOT go here -----------------------------------------

Edit the tool's own user file at its normal place. Ryoku never overwrites these,
so your edits always survive an update:

    ~/.config/hypr/user.lua           Hyprland binds, window rules, raw config
    ~/.config/hypr/monitors_user.lua  pin a display (see monitors_user.lua.example)
    ~/.config/kitty/user.conf         your kitty overrides

Putting one of those in this overlay is the old, broken way: the overlay froze a
copy and re-laid it over your live file every update, wiping later edits. If you
find one here, move it back to the path above; ryoku doctor does this for you.

--- Commands -------------------------------------------------------------

    ryoku reset <path>   drop one forked file, back to Ryoku's default
    ryoku reset          drop everything here (asks first)
    ryoku recovery       last resort: wipe all edits and settings, pure Ryoku

--- Notes ----------------------------------------------------------------

.md files here (like this one) are never copied into the live config, so keep
your own notes beside your edits.
`
