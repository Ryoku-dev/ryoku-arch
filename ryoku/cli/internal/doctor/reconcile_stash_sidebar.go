package doctor

import (
	"encoding/json"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// The stash Features page moved from a full-span left sidebar to a floating card
// on the right (Super+T). A machine that persisted frameBars still carries the old
// surfaces.stash.anchor: "left", which normalize keeps, so the page would grow from
// the wrong edge. Flip that one leaf to "right" in place. Idempotent.
func reconcileStashSidebar(checkOnly bool) recResult {
	path := filepath.Join(sys.ConfigHome(), "ryoku", "shell.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return okRes(i18n.T("no shell.json yet (seeded on first shell run)"))
	}
	migrated, changed, err := moveStashRight(raw)
	if err != nil {
		return warnRes(i18n.T("shell.json does not parse (%v); the shell falls back to defaults"), err).
			withFix(i18n.T("delete %s to re-seed it"), path)
	}
	if !changed {
		return okRes(i18n.T("stash Features page anchors right"))
	}
	if checkOnly {
		return wouldRes(i18n.T("shell.json still anchors the stash Features page to the left edge")).
			withFix(i18n.T("ryoku doctor moves it to the right in place"))
	}
	tmp := path + ".ryoku-tmp"
	if err := os.WriteFile(tmp, migrated, 0o644); err != nil {
		return failRes(i18n.T("could not write %s: %v"), tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return failRes(i18n.T("could not replace %s: %v"), path, err)
	}
	return fixedRes(i18n.T("moved the stash Features page to the right edge in shell.json"))
}

// moveStashRight flips frameBars.surfaces.stash.anchor "left" -> "right", keeping
// every other key as raw bytes. An absent subtree or a non-"left" anchor is a no-op.
func moveStashRight(raw []byte) ([]byte, bool, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		return nil, false, err
	}
	fbRaw, ok := top["frameBars"]
	if !ok {
		return nil, false, nil
	}
	var frameBars map[string]json.RawMessage
	if err := json.Unmarshal(fbRaw, &frameBars); err != nil {
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
	stashRaw, ok := surfaces["stash"]
	if !ok {
		return nil, false, nil
	}
	var stash map[string]json.RawMessage
	if err := json.Unmarshal(stashRaw, &stash); err != nil {
		return nil, false, err
	}
	anchorRaw, ok := stash["anchor"]
	if !ok {
		return nil, false, nil
	}
	var anchor string
	if err := json.Unmarshal(anchorRaw, &anchor); err != nil {
		return nil, false, err
	}
	if anchor != "left" {
		return nil, false, nil
	}
	right, err := json.Marshal("right")
	if err != nil {
		return nil, false, err
	}
	stash["anchor"] = right
	if surfaces["stash"], err = json.Marshal(stash); err != nil {
		return nil, false, err
	}
	if frameBars["surfaces"], err = json.Marshal(surfaces); err != nil {
		return nil, false, err
	}
	if top["frameBars"], err = json.Marshal(frameBars); err != nil {
		return nil, false, err
	}
	out, err := json.MarshalIndent(top, "", "  ")
	if err != nil {
		return nil, false, err
	}
	return append(out, '\n'), true, nil
}
