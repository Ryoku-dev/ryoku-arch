package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Rice authoring stays in Ryoku Settings. Remote catalogue and install
// ownership belongs exclusively to Ryostore.

// productFile is one row of a RyoStore product manifest's files[]: a payload
// file laid inside the product, its integrity (size + sha256), the mode it
// installs with, and whether the actuator lands it on the user's disk
// (install) or it is store-only display art (install false).
type productFile struct {
	Source      string `json:"source"`
	Destination string `json:"destination"`
	Mode        string `json:"mode"`
	Size        int64  `json:"size"`
	Sha256      string `json:"sha256"`
	Install     bool   `json:"install"`
}

// riceManifest is the product's rice.json: the RyoStore product envelope
// (schema/id/category/version/destination/files) fused with the look metadata
// carried verbatim from the source rice. Field order mirrors the migrated
// catalogue examples (rices/lofi/rice.json).
type riceManifest struct {
	Schema      int                        `json:"schema"`
	ID          string                     `json:"id"`
	Category    string                     `json:"category"`
	Version     string                     `json:"version"`
	Destination string                     `json:"destination"`
	Slug        string                     `json:"slug"`
	Name        string                     `json:"name"`
	Author      string                     `json:"author,omitempty"`
	Blurb       string                     `json:"blurb,omitempty"`
	Tags        []string                   `json:"tags,omitempty"`
	CreatedWith string                     `json:"createdWith,omitempty"`
	Color       RiceColor                  `json:"color"`
	Assets      RiceAssets                 `json:"assets"`
	Look        map[string]map[string]any  `json:"look"`
	Layers      map[string]json.RawMessage `json:"layers,omitempty"`
	Files       []productFile              `json:"files"`
}

// riceStoreEntry mirrors one entry in the catalogue's rices/registry.json under
// the v1 store schema: required catalogue fields (with manifestSha256 pinning
// the product's rice.json) plus the look summary the Hub renders. The wallpaper
// and hero binaries are GitHub Release assets referenced by absolute URL; the
// small text/images (preview, palette, screenshots) live in-repo. Field order
// mirrors rices/registry.json.
type riceStoreEntry struct {
	ID             string   `json:"id"`
	Name           string   `json:"name"`
	Version        string   `json:"version"`
	Path           string   `json:"path"`
	Author         string   `json:"author"`
	Summary        string   `json:"summary"`
	Description    string   `json:"description"`
	Tags           []string `json:"tags"`
	Accent         string   `json:"accent"`
	Surface        string   `json:"surface"`
	Preview        string   `json:"preview"`
	Screenshots    []string `json:"screenshots"`
	Manifest       string   `json:"manifest"`
	ManifestSha256 string   `json:"manifestSha256"`
	Blurb          string   `json:"blurb,omitempty"`
	CreatedWith    string   `json:"createdWith,omitempty"`
	Color          string   `json:"color,omitempty"`
	Palette        string   `json:"palette,omitempty"`
	Rounding       int      `json:"rounding"`
	Wallpaper      string   `json:"wallpaper,omitempty"`
	Hero           string   `json:"hero,omitempty"`
}

type riceRegistry struct {
	Schema int              `json:"schema"`
	Rices  []riceStoreEntry `json:"rices"`
}

const riceStoreVersion = "1.0.0"

func extrasReleaseURL(asset string) string {
	return "https://github.com/ryoku-dev/ryostore/releases/download/rices/" + asset
}

// publishRice lays a local rice into a catalogue checkout's store structure as
// a v1 product (rices/<slug>/rice.json + payload files) and upserts its
// registry entry, leaving only the Release-asset upload and the git commit to
// the author. this is the "extract configs, commit to extras" path: everything
// mechanical is done, the human just reviews and pushes.
func publishRice(slug, storeDir string) error {
	if !validRiceSlug(slug) {
		return fmt.Errorf("bad rice slug %q", slug)
	}
	r, dir, err := loadRice(slug)
	if err != nil {
		return err
	}
	product := filepath.Join(storeDir, "rices", slug)
	if err := os.MkdirAll(product, 0o755); err != nil {
		return err
	}

	// --- lay out the payload -------------------------------------------------
	// preview: accept preview.webp or preview.png, always stored as the
	// display-art preview at assets/preview.webp.
	previewSrc := ""
	for _, name := range []string{"preview.webp", "preview.png"} {
		if p := filepath.Join(dir, name); isFile(p) {
			previewSrc = p
			break
		}
	}
	if previewSrc != "" {
		if err := copyFile(previewSrc, filepath.Join(product, "assets", "preview.webp")); err != nil {
			return err
		}
	}
	// poster: the legacy 1:1 still, kept when the rice carries a preview.png.
	if p := filepath.Join(dir, "preview.png"); isFile(p) {
		if err := copyFile(p, filepath.Join(product, "poster.png")); err != nil {
			return err
		}
	}

	// every other in-repo asset (palette, decor, fastfetch, brand, screenshots)
	// travels verbatim, except the manifest, the preview sources placed above,
	// authoring docs, and the large release binaries (wallpaper + hero) which
	// ship as GitHub Release assets referenced by URL, not copied in-repo.
	skip := map[string]bool{"rice.json": true, "preview.png": true, "preview.webp": true}
	if r.Assets.Wallpaper != "" {
		skip[r.Assets.Wallpaper] = true
	}
	if r.Assets.Hero != "" {
		skip[r.Assets.Hero] = true
	}
	err = filepath.WalkDir(dir, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if d.IsDir() {
			return nil
		}
		rel, e := filepath.Rel(dir, path)
		if e != nil {
			return e
		}
		rel = filepath.ToSlash(rel)
		if skip[rel] || isRiceDoc(rel) {
			return nil
		}
		return copyFile(path, filepath.Join(product, filepath.FromSlash(rel)))
	})
	if err != nil {
		return err
	}

	// --- files[]: declare every laid-out file bar the manifest ---------------
	var files []productFile
	err = filepath.WalkDir(product, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if d.IsDir() {
			return nil
		}
		rel, e := filepath.Rel(product, path)
		if e != nil {
			return e
		}
		rel = filepath.ToSlash(rel)
		if rel == "rice.json" || isRiceDoc(rel) {
			return nil
		}
		digest, size, e := fileSha256(path)
		if e != nil {
			return e
		}
		mode := "0644"
		if fileHasShebang(path) {
			if e := os.Chmod(path, 0o755); e != nil {
				return e
			}
			mode = "0755"
		}
		files = append(files, productFile{
			Source: rel, Destination: rel, Mode: mode,
			Size: size, Sha256: digest, Install: riceInstall(rel),
		})
		return nil
	})
	if err != nil {
		return err
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Destination < files[j].Destination })

	// --- manifest: augment the source rice with the store envelope -----------
	manifest := riceManifest{
		Schema:      riceSchema,
		ID:          slug,
		Category:    "rices",
		Version:     riceStoreVersion,
		Destination: "ryoku/rices/" + slug,
		Slug:        r.Slug,
		Name:        r.Name,
		Author:      r.Author,
		Blurb:       r.Blurb,
		Tags:        r.Tags,
		CreatedWith: r.CreatedWith,
		Color:       r.Color,
		Assets:      r.Assets,
		Look:        r.Look,
		Layers:      r.Layers,
		Files:       files,
	}
	if manifest.Slug == "" {
		manifest.Slug = slug
	}
	manifestBytes := mustJSON(manifest)
	if err := atomicWrite(filepath.Join(product, "rice.json"), manifestBytes, 0o644); err != nil {
		return err
	}
	sum := sha256.Sum256(manifestBytes)
	manifestHash := hex.EncodeToString(sum[:])

	// --- registry entry ------------------------------------------------------
	pal := readPalette(filepath.Join(dir, "palette.json"))
	accent, surface, rounding := riceColors(r, pal)
	name := r.Name
	if name == "" {
		name = slug
	}
	author := r.Author
	if author == "" {
		author = currentUser()
	}
	summary := shortSummary(r.Blurb, name)
	entry := riceStoreEntry{
		ID:             slug,
		Name:           name,
		Version:        riceStoreVersion,
		Path:           "rices/" + slug,
		Author:         author,
		Summary:        summary,
		Description:    firstNonEmpty(r.Blurb, summary),
		Tags:           r.Tags,
		Accent:         accent,
		Surface:        surface,
		Preview:        "assets/preview.webp",
		Screenshots:    riceScreenshots(product),
		Manifest:       "rice.json",
		ManifestSha256: manifestHash,
		Blurb:          r.Blurb,
		CreatedWith:    r.CreatedWith,
		Color:          r.Color.Mode,
		Rounding:       rounding,
	}
	if entry.Tags == nil {
		entry.Tags = []string{}
	}
	if r.Color.Mode == "fixed" && isFile(filepath.Join(product, "palette.json")) {
		entry.Palette = "rices/" + slug + "/palette.json"
	}
	if r.Assets.Wallpaper != "" {
		entry.Wallpaper = extrasReleaseURL(slug + "-" + r.Assets.Wallpaper)
	}
	if r.Assets.Hero != "" {
		entry.Hero = extrasReleaseURL(slug + "-" + r.Assets.Hero)
	}

	// --- upsert registry -----------------------------------------------------
	regPath := filepath.Join(storeDir, "rices", "registry.json")
	reg := riceRegistry{Schema: 1}
	if b, err := os.ReadFile(regPath); err == nil {
		_ = json.Unmarshal(b, &reg)
	}
	reg.Schema = 1
	replaced := false
	for i := range reg.Rices {
		if reg.Rices[i].ID == slug {
			reg.Rices[i] = entry
			replaced = true
			break
		}
	}
	if !replaced {
		reg.Rices = append(reg.Rices, entry)
	}
	if err := atomicWrite(regPath, mustJSON(reg), 0o644); err != nil {
		return err
	}

	// --- author guidance -----------------------------------------------------
	fmt.Printf("published %q to %s\n", slug, product)
	if r.Assets.Wallpaper != "" || r.Assets.Hero != "" {
		fmt.Println("upload as Release assets under the 'rices' tag:")
		if r.Assets.Wallpaper != "" {
			fmt.Printf("  %s  (from %s)\n", slug+"-"+r.Assets.Wallpaper, filepath.Join(dir, r.Assets.Wallpaper))
		}
		if r.Assets.Hero != "" {
			fmt.Printf("  %s  (from %s)\n", slug+"-"+r.Assets.Hero, filepath.Join(dir, r.Assets.Hero))
		}
	}
	fmt.Printf("add screenshots under rices/%s/screenshots/ and git commit in the store.\n", slug)
	return nil
}

// riceInstall marks store-only display art (the preview under assets/, the 1:1
// poster, and screenshots) install:false; every other payload (palette, decor,
// fastfetch and brand assets) lands on the user's desktop, so install:true.
func riceInstall(dest string) bool {
	if dest == "poster.png" || strings.HasPrefix(dest, "assets/") || strings.HasPrefix(dest, "screenshots/") {
		return false
	}
	return true
}

// riceColors derives the catalogue accent/surface (and rounding) from the look
// (the border and surface the rice actually paints), falling back to the locked
// palette so a wallpaper-mode rice still yields valid six-digit hex colours.
func riceColors(r Rice, pal map[string]string) (accent, surface string, rounding int) {
	if hy, ok := r.Look["hypr"]; ok {
		if ap, ok := hy["appearance"].(map[string]any); ok {
			if v, ok := ap["activeBorder"].(string); ok {
				accent = v
			}
			if v, ok := ap["rounding"].(float64); ok {
				rounding = int(v)
			}
		}
	}
	if sh, ok := r.Look["shell"]; ok {
		if v, ok := sh["surfaceColor"].(string); ok {
			surface = v
		}
	}
	if accent == "" {
		accent = firstNonEmpty(pal["primary"], pal["color1"], pal["accent"])
	}
	if surface == "" {
		surface = firstNonEmpty(pal["surface"], pal["background"], pal["color0"])
	}
	return
}

// shortSummary is the registry summary: a single short line from the blurb,
// trimmed to a word boundary. Empty blurbs fall back to the display name.
func shortSummary(blurb, fallback string) string {
	b := strings.TrimSpace(blurb)
	if b == "" {
		return fallback
	}
	const max = 80
	if len(b) <= max {
		return b
	}
	cut := b[:max]
	if i := strings.LastIndexByte(cut, ' '); i > 0 {
		cut = cut[:i]
	}
	return strings.TrimRight(cut, " .,;:") + "…"
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

// riceScreenshots lists the product's screenshots as product-relative paths,
// sorted for a stable registry entry. Always non-nil so the JSON emits [].
func riceScreenshots(product string) []string {
	shots := []string{}
	entries, err := os.ReadDir(filepath.Join(product, "screenshots"))
	if err != nil {
		return shots
	}
	for _, e := range entries {
		if !e.IsDir() {
			shots = append(shots, "screenshots/"+e.Name())
		}
	}
	sort.Strings(shots)
	return shots
}

// fileSha256 returns the lowercase-hex SHA-256 and byte size of a file. Rice
// payloads are small (large binaries ship as Release assets), so a whole read
// is fine.
func fileSha256(path string) (string, int64, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", 0, err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), int64(len(b)), nil
}

func fileHasShebang(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	buf := make([]byte, 2)
	n, _ := f.Read(buf)
	return n == 2 && buf[0] == '#' && buf[1] == '!'
}

var riceDocNames = []string{"readme", "license", "copying", "notice", "authors"}
var riceDocExts = map[string]bool{"": true, ".md": true, ".txt": true, ".rst": true, ".adoc": true}

// isRiceDoc mirrors the catalogue validator's documentation rule: named docs
// (README/LICENSE/...) and anything under docs/ with a doc extension are
// authoring matter, kept out of the shipped product and its files[].
func isRiceDoc(rel string) bool {
	rel = filepath.ToSlash(rel)
	base := strings.ToLower(filepath.Base(rel))
	ext := strings.ToLower(filepath.Ext(base))
	named := false
	for _, d := range riceDocNames {
		if base == d || strings.HasPrefix(base, d+".") {
			named = true
			break
		}
	}
	parts := strings.Split(rel, "/")
	inDocs := len(parts) > 0 && (parts[0] == "docs" || parts[0] == "documentation")
	if ext == "" {
		return named
	}
	return (named || inDocs) && riceDocExts[ext]
}
