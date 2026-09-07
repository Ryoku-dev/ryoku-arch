package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// The screenshot capture menu and the screen-share picker were both in-shell
// frame menus that have since been retired: the capture UI moved to a floating
// card surface and the share picker moved into the desktop portal's own dialog.
// A machine upgrading from a release that persisted them still carries
// menus.screenshot_menu, menus.screenshare_menu, and frameBars.menus.screenshare,
// where nothing reads them any more. This strips those retired leaves and leaves
// every other menu (and every other key) untouched. Surgical and idempotent: a
// store already free of all three is left alone.
func reconcileRetiredMenus(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no shell.json yet (seeded on first shell run)"))
	}
	migrated, changed, err := stripRetiredMenus(raw)
	if err != nil {
		return warnRes(i18n.T("shell.json does not parse (%v); the shell falls back to defaults"), err).
			withFix(i18n.T("delete %s to re-seed it"), path)
	}
	if !changed {
		return okRes(i18n.T("shell.json carries no retired shell menus"))
	}
	if checkOnly {
		return wouldRes(i18n.T("shell.json still carries retired shell menus")).
			withFix(i18n.T("ryoku doctor strips them in place"))
	}
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, migrated, 0o644); err != nil {
		return failRes(i18n.T("could not write %s: %v"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return failRes(i18n.T("could not replace %s: %v"), path, err)
	}
	return fixedRes(i18n.T("stripped the retired shell menus from shell.json"))
}

// stripRetiredMenus removes the retired in-shell menus from a shell store --
// menus.screenshot_menu, menus.screenshare_menu, and frameBars.menus.screenshare
// -- keeping every other key (and every sibling menu) as its own raw bytes. An
// absent leaf is a no-op, so a store already free of all three comes back
// unchanged; a malformed menus or frameBars object errors rather than being
// silently rewritten.
func stripRetiredMenus(raw []byte) ([]byte, bool, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		return nil, false, err
	}
	changed := false
	// menus.screenshot_menu and menus.screenshare_menu: the two retired top-level
	// frame menus.
	if menusRaw, ok := top["menus"]; ok {
		var menus map[string]json.RawMessage
		if err := json.Unmarshal(menusRaw, &menus); err != nil {
			return nil, false, err
		}
		dropped := false
		for _, id := range []string{"screenshot_menu", "screenshare_menu"} {
			if _, ok := menus[id]; ok {
				delete(menus, id)
				dropped = true
			}
		}
		if dropped {
			repacked, err := json.Marshal(menus)
			if err != nil {
				return nil, false, err
			}
			top["menus"] = repacked
			changed = true
		}
	}
	// frameBars.menus.screenshare: the retired share-picker frame-menu record,
	// one level deeper than the top-level menus namespace.
	if frameRaw, ok := top["frameBars"]; ok {
		var frame map[string]json.RawMessage
		if err := json.Unmarshal(frameRaw, &frame); err != nil {
			return nil, false, err
		}
		if menusRaw, ok := frame["menus"]; ok {
			var menus map[string]json.RawMessage
			if err := json.Unmarshal(menusRaw, &menus); err != nil {
				return nil, false, err
			}
			if _, ok := menus["screenshare"]; ok {
				delete(menus, "screenshare")
				repackedMenus, err := json.Marshal(menus)
				if err != nil {
					return nil, false, err
				}
				frame["menus"] = repackedMenus
				repackedFrame, err := json.Marshal(frame)
				if err != nil {
					return nil, false, err
				}
				top["frameBars"] = repackedFrame
				changed = true
			}
		}
	}
	if !changed {
		return nil, false, nil
	}
	out, err := json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}

// The capture (screenshot/record) UI moved again: from the floating Super+S popup
// to a quick-settings subtab that sits after Weather, so the shipped module rail
// gained a "capture" entry. A machine that persisted the pre-capture default
// still lists exactly [home, notifications, weather] and never shows the tab.
// reconcileCaptureModule upgrades only that exact retired list, leaving a
// hand-customized rail alone (add it in Bar Studio). Idempotent: once capture is
// present the list no longer matches and it is a no-op.
func reconcileCaptureModule(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no shell.json yet (seeded on first shell run)"))
	}
	migrated, changed, err := addCaptureModule(raw)
	if err != nil {
		return warnRes(i18n.T("shell.json does not parse (%v); the shell falls back to defaults"), err).
			withFix(i18n.T("delete %s to re-seed it"), path)
	}
	if !changed {
		return okRes(i18n.T("quick-settings rail carries the capture tab (or a custom module list)"))
	}
	if checkOnly {
		return wouldRes(i18n.T("quick-settings rail predates the Super+S capture tab")).
			withFix(i18n.T("ryoku doctor adds it after Weather"))
	}
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, migrated, 0o644); err != nil {
		return failRes(i18n.T("could not write %s: %v"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return failRes(i18n.T("could not replace %s: %v"), path, err)
	}
	return fixedRes(i18n.T("added the capture tab to the quick-settings rail after Weather"))
}

// addCaptureModule appends "capture" to a shell store whose quick-settings module
// rail is exactly the retired default [home, notifications, weather]. Every
// sibling menu and every top-level key is preserved as its own raw bytes; a
// customized rail (or one already carrying capture) comes back unchanged, and a
// store with no frameBars/menus/quick-settings.modules is a no-op.
func addCaptureModule(raw []byte) ([]byte, bool, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		return nil, false, err
	}
	frameRaw, ok := top["frameBars"]
	if !ok {
		return nil, false, nil
	}
	var frame map[string]json.RawMessage
	if err := json.Unmarshal(frameRaw, &frame); err != nil {
		return nil, false, err
	}
	menusRaw, ok := frame["menus"]
	if !ok {
		return nil, false, nil
	}
	var menus map[string]json.RawMessage
	if err := json.Unmarshal(menusRaw, &menus); err != nil {
		return nil, false, err
	}
	qsRaw, ok := menus["quick-settings"]
	if !ok {
		return nil, false, nil
	}
	var qs map[string]json.RawMessage
	if err := json.Unmarshal(qsRaw, &qs); err != nil {
		return nil, false, err
	}
	var modules []string
	if err := json.Unmarshal(qs["modules"], &modules); err != nil {
		return nil, false, nil
	}
	// Only the exact retired default is upgraded; a customized rail is left alone.
	if len(modules) != 3 || modules[0] != "home" || modules[1] != "notifications" || modules[2] != "weather" {
		return nil, false, nil
	}
	next, err := json.Marshal([]string{"home", "notifications", "weather", "capture"})
	if err != nil {
		return nil, false, err
	}
	qs["modules"] = next
	qsBytes, err := json.Marshal(qs)
	if err != nil {
		return nil, false, err
	}
	menus["quick-settings"] = qsBytes
	menusBytes, err := json.Marshal(menus)
	if err != nil {
		return nil, false, err
	}
	frame["menus"] = menusBytes
	frameBytes, err := json.Marshal(frame)
	if err != nil {
		return nil, false, err
	}
	top["frameBars"] = frameBytes
	out, err := json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}
