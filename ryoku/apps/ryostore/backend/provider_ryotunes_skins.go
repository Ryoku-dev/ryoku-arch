// The ryotunes-skins provider serves the ryostore Ryotunes-skins catalogue.
// A skin installs as a generic product into the store-owned directory
// (dataHome/ryoku/ryotunes-skins/<id>), which Ryotunes searches as its "store"
// skin source. The store only installs and removes; selection happens inside
// Ryotunes (Settings › Appearance, or `ryotunes-cli skin use <id>`), which
// records the worn skin in ~/.config/ryotunes/client.json. An item reads as
// active when that file's "skin" key equals its id. The entry's author drives
// the store's per-provider subtab strip, like colorschemes.
package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
)

const ryotunesSkinsCategory = "ryotunes-skins"

type ryotunesSkinsProvider struct {
	cache      *Cache
	clientPath string
}

func newRyotunesSkinsProvider(cache *Cache) ryotunesSkinsProvider {
	return ryotunesSkinsProvider{
		cache:      cache,
		clientPath: filepath.Join(configHome(), "ryotunes", "client.json"),
	}
}

func (ryotunesSkinsProvider) Category() Category {
	return Category{
		ID:          ryotunesSkinsCategory,
		Name:        "Ryotunes skins",
		Group:       "wear",
		Description: "Skins for Ryotunes - palette, type, radii and motion. Install here, pick it in Ryotunes › Settings › Appearance.",
	}
}

func (p ryotunesSkinsProvider) Load(ctx context.Context, refresh bool) ([]Item, SourceState, error) {
	entries, state, err := loadProductRegistry(ctx, p.cache, ryotunesSkinsCategory, refresh)
	if err != nil {
		return nil, state, err
	}
	// The worn skin is a local preference, not a source fact: a missing or
	// malformed client.json simply means nothing reads as active, never an
	// error that would fold the whole store into "offline".
	active := p.activeSkin()
	items := make([]Item, 0, len(entries))
	for _, entry := range entries {
		item, err := productEntryItem(p.cache.base, ryotunesSkinsCategory, entry)
		if err != nil {
			return nil, state, err
		}
		item.Active = item.Installed && entry.ID == active
		// The store's per-provider subtab strip keys on metadata.provider, so
		// surface the skin's author there the way colorschemes does.
		item.Metadata = map[string]any{"provider": entry.Author}
		items = append(items, item)
	}
	return items, state, nil
}

func (p ryotunesSkinsProvider) Install(ctx context.Context, id string) error {
	entries, _, err := loadProductRegistry(ctx, p.cache, ryotunesSkinsCategory, false)
	if err != nil {
		return err
	}
	entry, err := findProductEntry(entries, id)
	if err != nil {
		return err
	}
	return installProduct(ctx, p.cache, ryotunesSkinsCategory, entry)
}

// activeSkin reads the id of the currently worn skin from Ryotunes' prefs file
// (~/.config/ryotunes/client.json, "skin" key). A file that is absent or cannot
// be parsed yields "" so no installed skin reads as active; it never errors.
func (p ryotunesSkinsProvider) activeSkin() string {
	raw, err := os.ReadFile(p.clientPath)
	if err != nil {
		return ""
	}
	var doc struct {
		Skin string `json:"skin"`
	}
	if json.Unmarshal(raw, &doc) != nil {
		return ""
	}
	return doc.Skin
}
