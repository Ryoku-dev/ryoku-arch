package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

type ryotunesSkinsFixture struct {
	cache     *Cache
	entries   []ProductEntry
	skins     map[string][]byte
	responses map[string][]byte
}

func newRyotunesSkinsFixture(t *testing.T) ryotunesSkinsFixture {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(t.TempDir(), "config"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(t.TempDir(), "data"))
	t.Setenv("XDG_STATE_HOME", filepath.Join(t.TempDir(), "state"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(t.TempDir(), "cache"))

	skins := map[string][]byte{
		"nord-dark":        skinJSON("nord-dark", "Nord Dark", "#88c0d0", "#2e3440"),
		"catppuccin-mocha": skinJSON("catppuccin-mocha", "Catppuccin Mocha", "#89b4fa", "#1e1e2e"),
	}
	responses := make(map[string][]byte)
	entries := make([]ProductEntry, 0, len(skins))
	for _, id := range []string{"nord-dark", "catppuccin-mocha"} {
		body := skins[id]
		bodyHash := sha256.Sum256(body)
		manifest := ProductManifest{
			Schema: 1, ID: id, Category: "ryotunes-skins", Version: "1.0.0",
			Destination: filepath.ToSlash(filepath.Join("ryoku", "ryotunes-skins", id)),
			Files: []ProductFile{{
				Source: "skin.json", Destination: "skin.json", Mode: "0644",
				Size: int64(len(body)), SHA256: fmt.Sprintf("%x", bodyHash), Install: true,
			}},
		}
		manifestRaw, err := json.Marshal(manifest)
		if err != nil {
			t.Fatal(err)
		}
		manifestHash := sha256.Sum256(manifestRaw)
		entry := ProductEntry{
			ID: id, Name: id, Version: "1.0.0", Path: "ryotunes-skins/" + id,
			Author: "Ryoku Team", Summary: "Ryotunes skin", Description: "A Ryotunes skin.",
			Tags: []string{"dark"}, Accent: "#88c0d0", Surface: "#2e3440",
			Preview: "preview.webp", Screenshots: []string{}, Manifest: "manifest.json",
			ManifestSHA256: fmt.Sprintf("%x", manifestHash),
		}
		entries = append(entries, entry)
		responses["/ryotunes-skins/"+id+"/manifest.json"] = manifestRaw
		responses["/ryotunes-skins/"+id+"/skin.json"] = body
	}
	registryRaw, err := json.Marshal(map[string]any{"schema": 1, "ryotunes-skins": entries})
	if err != nil {
		t.Fatal(err)
	}
	responses["/ryotunes-skins/registry.json"] = registryRaw

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, ok := responses[r.URL.Path]
		if !ok {
			http.NotFound(w, r)
			return
		}
		_, _ = w.Write(body)
	}))
	t.Cleanup(server.Close)
	return ryotunesSkinsFixture{
		cache:     &Cache{client: server.Client(), base: server.URL, dir: t.TempDir(), memo: map[string]memoEntry{}},
		entries:   entries,
		skins:     skins,
		responses: responses,
	}
}

func skinJSON(id, name, sun, paper string) []byte {
	return []byte(fmt.Sprintf("{\n  \"format\": 1,\n  \"id\": %q,\n  \"name\": %q,\n"+
		"  \"modes\": {\"dark\": {\"paper\": %q, \"ink\": \"#eceff4\", \"sun\": %q}}\n}\n",
		id, name, paper, sun))
}

func writeClientPrefs(t *testing.T, skin string) {
	t.Helper()
	path := filepath.Join(configHome(), "ryotunes", "client.json")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(skin), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestRyotunesSkinsProviderInstallActiveFromClientPrefs(t *testing.T) {
	fixture := newRyotunesSkinsFixture(t)
	provider := newRyotunesSkinsProvider(fixture.cache)

	items, _, err := provider.Load(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 || items[0].Installed || items[1].Installed {
		t.Fatalf("initial items = %+v", items)
	}
	if items[0].Art == "" || items[0].Manifest == "" {
		t.Fatalf("missing external metadata: %+v", items[0])
	}
	// The author drives the store's per-provider subtab strip.
	if got, _ := items[0].Metadata["provider"].(string); got != "Ryoku Team" {
		t.Fatalf("metadata.provider = %q, want Ryoku Team", got)
	}

	// Naming a skin in client.json before it is installed must not mark it
	// active: the store reports active only for a skin it actually owns.
	writeClientPrefs(t, `{"skin":"nord-dark","themeMode":"dark"}`)
	items, _, err = provider.Load(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if items[0].Active {
		t.Fatalf("uninstalled skin read as active: %+v", items[0])
	}

	if err := provider.Install(context.Background(), "nord-dark"); err != nil {
		t.Fatal(err)
	}
	dst, _, err := productDestination("ryotunes-skins", "nord-dark")
	if err != nil {
		t.Fatal(err)
	}
	if raw, err := os.ReadFile(filepath.Join(dst, "skin.json")); err != nil ||
		string(raw) != string(fixture.skins["nord-dark"]) {
		t.Fatalf("installed skin.json = %q, err=%v", raw, err)
	}
	if _, err := readReceipt("ryotunes-skins", "nord-dark"); err != nil {
		t.Fatalf("install wrote no receipt: %v", err)
	}

	// Installed and worn: active flips for that skin only.
	items, _, err = provider.Load(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if !items[0].Installed || !items[0].Active || items[1].Active {
		t.Fatalf("worn items = %+v", items)
	}

	// Switching the worn skin in prefs moves the active flag off the installed
	// (but no longer worn) skin.
	writeClientPrefs(t, `{"skin":"catppuccin-mocha"}`)
	items, _, err = provider.Load(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if items[0].Active {
		t.Fatalf("unworn skin still active: %+v", items[0])
	}

	if err := provider.Remove(context.Background(), "nord-dark"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dst, "skin.json")); !os.IsNotExist(err) {
		t.Fatalf("remove left skin.json behind: %v", err)
	}
	items, _, err = provider.Load(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if items[0].Installed {
		t.Fatalf("removed skin still installed: %+v", items[0])
	}
}

func TestRyotunesSkinsProviderToleratesBrokenClientPrefs(t *testing.T) {
	fixture := newRyotunesSkinsFixture(t)
	provider := newRyotunesSkinsProvider(fixture.cache)
	if err := provider.Install(context.Background(), "nord-dark"); err != nil {
		t.Fatal(err)
	}

	// A missing client.json: no error, nothing active.
	items, _, err := provider.Load(context.Background(), false)
	if err != nil {
		t.Fatalf("missing client.json errored: %v", err)
	}
	if items[0].Active {
		t.Fatalf("skin active without prefs: %+v", items[0])
	}

	// A malformed client.json is a local problem, not a source outage: the
	// provider loads cleanly and reads nothing as active.
	writeClientPrefs(t, "{ this is not json")
	items, _, err = provider.Load(context.Background(), false)
	if err != nil {
		t.Fatalf("malformed client.json errored: %v", err)
	}
	if items[0].Active {
		t.Fatalf("skin active from malformed prefs: %+v", items[0])
	}
}

func TestRyotunesSkinsProviderTreatsMissingRegistryAsSourceError(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	defer server.Close()
	cache := &Cache{client: server.Client(), base: server.URL, dir: t.TempDir(), memo: map[string]memoEntry{}}
	if _, _, err := newRyotunesSkinsProvider(cache).Load(context.Background(), false); err == nil {
		t.Fatal("missing registry was accepted as an empty catalogue")
	}
}
