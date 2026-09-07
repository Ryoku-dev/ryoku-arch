package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// The full-height system sidebar was retired in favor of configurable modules
// inside the Super+Escape quick-settings menu. Remove only its persisted frame
// surface record; user-selected quick-settings modules and every sibling setting
// remain untouched.
func reconcileLegacySystemSidebar(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no shell.json yet (seeded on first shell run)"))
	}
	migrated, changed, err := stripLegacySystemSidebar(raw)
	if err != nil {
		return warnRes(i18n.T("shell.json does not parse (%v); the shell falls back to defaults"), err).
			withFix(i18n.T("delete %s to re-seed it"), path)
	}
	if !changed {
		return okRes(i18n.T("shell.json carries no retired system sidebar"))
	}
	if checkOnly {
		return wouldRes(i18n.T("shell.json still carries retired frameBars.surfaces.system")).
			withFix(i18n.T("ryoku doctor strips it in place"))
	}

	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, migrated, 0o644); err != nil {
		return failRes(i18n.T("could not write %s: %v"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return failRes(i18n.T("could not replace %s: %v"), path, err)
	}
	return fixedRes(i18n.T("stripped retired frameBars.surfaces.system from shell.json"))
}

func stripLegacySystemSidebar(raw []byte) ([]byte, bool, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		return nil, false, err
	}
	frameBarsRaw, ok := top["frameBars"]
	if !ok {
		return nil, false, nil
	}
	var frameBars map[string]json.RawMessage
	if err := json.Unmarshal(frameBarsRaw, &frameBars); err != nil {
		return nil, false, err
	}
	surfacesRaw, ok := frameBars["surfaces"]
	if !ok {
		return nil, false, nil
	}
	var surfaces map[string]json.RawMessage
	if err := json.Unmarshal(surfacesRaw, &surfaces); err != nil {
		return nil, false, err
	}
	if _, ok := surfaces["system"]; !ok {
		return nil, false, nil
	}
	delete(surfaces, "system")

	repackedSurfaces, err := json.Marshal(surfaces)
	if err != nil {
		return nil, false, err
	}
	frameBars["surfaces"] = repackedSurfaces
	repackedFrameBars, err := json.Marshal(frameBars)
	if err != nil {
		return nil, false, err
	}
	top["frameBars"] = repackedFrameBars
	out, err := json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}
