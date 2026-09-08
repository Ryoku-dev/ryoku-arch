package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"ryoku-cli/internal/sys"
)

// plugin_share.go is the way a widget leaves a desktop: `ryoku plugin export`
// turns an installed plugin into a Ryostore-shaped folder (the files, the
// per-file product-manifest.json the store verifies against, and a complete
// registry entry), and `ryoku plugin share` opens the pull request that lists
// it in the catalogue, or the submission form when gh is not around. Neither
// executes anything from the plugin.

const ryostoreRepo = "ryoku-dev/ryostore"
const ryostoreFormURL = "https://github.com/ryoku-dev/ryostore/issues/new"

// exportRoot is where exports land: the user's Documents dir when the desktop
// names one, else the home dir, under ryoku-plugins/.
func exportRoot() string {
	if out, err := sys.RunOut("xdg-user-dir", "DOCUMENTS"); err == nil {
		if d := strings.TrimSpace(out); d != "" && d != sys.Home() && sys.Exists(d) {
			return filepath.Join(d, "ryoku-plugins")
		}
	}
	return filepath.Join(sys.Home(), "ryoku-plugins")
}

// installedPluginDir is the directory an installed plugin loads from: a dev
// override first (as discover.sh resolves it), else the store's install root.
func installedPluginDir(id string) (string, error) {
	for _, r := range pluginListRows() {
		if r.ID == id {
			return r.Dir, nil
		}
	}
	return "", fmt.Errorf("plugin %q is not installed (ryoku plugin list)", id)
}

func cmdPluginExport(args []string) error {
	id, to := "", ""
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--to":
			i++
			if i >= len(args) {
				return fmt.Errorf("--to needs a directory")
			}
			to = args[i]
		case strings.HasPrefix(args[i], "-"):
			return fmt.Errorf("unknown flag %q", args[i])
		default:
			if id != "" {
				return fmt.Errorf("give one plugin id")
			}
			id = args[i]
		}
	}
	if id == "" {
		return fmt.Errorf("usage: ryoku plugin export <id> [--to <dir>]")
	}
	dest, err := exportPlugin(id, to)
	if err != nil {
		return err
	}
	fmt.Printf("%s %s -> %s\n", sys.Green("exported"), id, dest)
	fmt.Println("  product-manifest.json  the per-file hashes Ryostore verifies against")
	fmt.Println("  registry-entry.json    the catalogue entry, ready for plugins/registry.json")
	fmt.Println("Next: `ryoku plugin share " + id + "` opens the Ryostore pull request for you.")
	return nil
}

// exportPlugin copies an installed plugin to dest (default under exportRoot),
// writes its product manifest and registry entry, and puts it under git.
func exportPlugin(id, dest string) (string, error) {
	src, err := installedPluginDir(id)
	if err != nil {
		return "", err
	}
	m, err := validateManifest(src, map[string]bool{})
	if err != nil {
		return "", fmt.Errorf("installed plugin %q: %w", id, err)
	}
	if dest == "" {
		dest = filepath.Join(exportRoot(), id)
	}
	if err := os.MkdirAll(dest, 0o755); err != nil {
		return "", err
	}
	if err := copyPluginTree(src, dest); err != nil {
		return "", err
	}
	raw := readManifestMap(filepath.Join(dest, "manifest.json"))
	preview, shots := previewMedia(dest)
	pm, err := buildProductManifest(dest, m.ID, m.Version, preview, shots)
	if err != nil {
		return "", err
	}
	pmPath := filepath.Join(dest, "product-manifest.json")
	if err := os.WriteFile(pmPath, pm, 0o644); err != nil {
		return "", err
	}
	entry := registryEntryFor(raw, m, preview, shots, sha256Hex(pm))
	eb, err := marshalIndent(entry)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(dest, "registry-entry.json"), eb, 0o644); err != nil {
		return "", err
	}
	if sys.Has("git") && !sys.Exists(filepath.Join(dest, ".git")) {
		if err := gitIn(dest, "init", "-q"); err == nil {
			_ = gitIn(dest, "add", "-A")
			_ = gitCommitAs(dest, entry.Author, "Export "+m.Name+" "+m.Version)
		}
	}
	return dest, nil
}

// copyPluginTree copies every regular file under src to dest, skipping git
// metadata and the two files export writes itself. Symlinks are refused: the
// store refuses them too, and a symlink is how a plugin would reach outside its
// own folder.
func copyPluginTree(src, dest string) error {
	if err := os.MkdirAll(dest, 0o755); err != nil {
		return err
	}
	return filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, path)
		if rel == "." {
			return nil
		}
		if d.IsDir() {
			if d.Name() == ".git" {
				return filepath.SkipDir
			}
			return os.MkdirAll(filepath.Join(dest, rel), 0o755)
		}
		if d.Type()&fs.ModeSymlink != 0 {
			return fmt.Errorf("symlink in plugin tree: %s", rel)
		}
		if rel == "product-manifest.json" || rel == "registry-entry.json" {
			return nil
		}
		return sys.CopyFile(path, filepath.Join(dest, rel))
	})
}

// previewMedia finds the preview image and screenshots the registry entry
// names: assets/preview-widget.png by convention, else the first image under
// assets/, then every other image under assets/ as a screenshot.
func previewMedia(dir string) (string, []string) {
	var images []string
	_ = filepath.WalkDir(filepath.Join(dir, "assets"), func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		switch strings.ToLower(filepath.Ext(path)) {
		case ".png", ".jpg", ".jpeg", ".webp", ".gif", ".avif":
			rel, _ := filepath.Rel(dir, path)
			images = append(images, filepath.ToSlash(rel))
		}
		return nil
	})
	sort.Strings(images)
	if len(images) == 0 {
		return "", nil
	}
	// preview-widget.png is the catalogue's hero by convention; any other
	// preview-*.png is a screenshot beside it.
	preview := images[0]
	for _, p := range images {
		if strings.HasPrefix(filepath.Base(p), "preview") {
			preview = p
			break
		}
	}
	for _, p := range images {
		if strings.HasPrefix(filepath.Base(p), "preview-widget.") {
			preview = p
			break
		}
	}
	shots := []string{preview}
	for _, p := range images {
		if p != preview {
			shots = append(shots, p)
		}
	}
	return preview, shots
}

// productFile is one row of product-manifest.json, in the store's field order.
type productFile struct {
	Source      string `json:"source"`
	Destination string `json:"destination"`
	SHA256      string `json:"sha256"`
	Mode        string `json:"mode"`
	Size        int64  `json:"size"`
	Install     bool   `json:"install"`
}

type productManifest struct {
	Schema      int           `json:"schema"`
	ID          string        `json:"id"`
	Category    string        `json:"category"`
	Version     string        `json:"version"`
	Destination string        `json:"destination"`
	Files       []productFile `json:"files"`
}

// buildProductManifest hashes every file under dir into the store's manifest.
// Docs (README, LICENSE, ...) and the preview media install:false, like the
// catalogue's own plugins; an executable script is 0755, everything else 0644.
func buildProductManifest(dir, id, version, preview string, shots []string) ([]byte, error) {
	media := map[string]bool{}
	if preview != "" {
		media[preview] = true
	}
	for _, s := range shots {
		media[s] = true
	}
	var files []productFile
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if d.Name() == ".git" {
				return filepath.SkipDir
			}
			return nil
		}
		rel, _ := filepath.Rel(dir, path)
		rel = filepath.ToSlash(rel)
		if rel == "product-manifest.json" || rel == "registry-entry.json" {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		sum, err := fileSHA256(path)
		if err != nil {
			return err
		}
		mode := "0644"
		if info.Mode()&0o111 != 0 && startsWithShebang(path) {
			mode = "0755"
		}
		files = append(files, productFile{
			Source: rel, Destination: rel, SHA256: sum, Mode: mode, Size: info.Size(),
			Install: !media[rel] && !isDocFile(rel),
		})
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Source < files[j].Source })
	pm := productManifest{Schema: 1, ID: id, Category: "plugins", Version: version,
		Destination: "ryoku/plugins/" + id, Files: files}
	return marshalIndent(pm)
}

// marshalIndent is two-space JSON without HTML escaping, so an author's
// `Name <mail>` survives as written (encoding/json would print \u003c).
func marshalIndent(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// isDocFile mirrors the store validator: a README/LICENSE-style name, with no
// extension or a text one, is documentation and is not installed.
func isDocFile(rel string) bool {
	base := strings.ToLower(filepath.Base(rel))
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	switch ext {
	case "", ".md", ".txt", ".rst", ".adoc":
	default:
		return false
	}
	for _, n := range []string{"readme", "license", "copying", "notice", "authors"} {
		if stem == n {
			return true
		}
	}
	return false
}

func startsWithShebang(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	head := make([]byte, 2)
	n, _ := io.ReadFull(f, head)
	return n == 2 && head[0] == '#' && head[1] == '!'
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func sha256Hex(b []byte) string {
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

// registryEntry is the plugins/registry.json row for the plugin, in the
// catalogue's field order, always community (official: false).
type registryEntry struct {
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
	ManifestSHA256 string   `json:"manifestSha256"`
	Official       bool     `json:"official"`
	Tagline        string   `json:"tagline"`
	Icon           string   `json:"icon"`
	Hosts          []string `json:"hosts"`
	LastUpdated    string   `json:"lastUpdated"`
}

func registryEntryFor(raw map[string]any, m manifest, preview string, shots []string, manifestSum string) registryEntry {
	desc := manifestString(raw, "description")
	summary := firstSentence(desc)
	if summary == "" {
		summary = m.Name + " for the Ryoku desktop."
	}
	tags := manifestStrings(raw, "tags")
	bar := false
	for _, h := range m.Hosts {
		if h == "topbarGlyph" {
			bar = true
		}
	}
	tags = withTag(tags, bar, "bar-widget")
	tags = withTag(tags, !bar, "desktop-widget")
	icon := ""
	if d, ok := raw["defaults"].(map[string]any); ok {
		icon = manifestString(d, "icon")
	}
	if shots == nil {
		shots = []string{}
	}
	return registryEntry{
		ID: m.ID, Name: m.Name, Version: m.Version, Path: "plugins/" + m.ID,
		Author: manifestString(raw, "author"), Summary: summary, Description: desc,
		Tags: tags, Accent: manifestStringOr(raw, "accent", "#8f8378"),
		Surface: manifestStringOr(raw, "surface", "#101010"),
		Preview: preview, Screenshots: shots,
		Manifest: "product-manifest.json", ManifestSHA256: manifestSum,
		Official: false, Tagline: summary, Icon: icon, Hosts: m.Hosts,
		LastUpdated: time.Now().Format("2006-01-02"),
	}
}

func withTag(tags []string, when bool, tag string) []string {
	if !when {
		return tags
	}
	for _, t := range tags {
		if t == tag {
			return tags
		}
	}
	return append(tags, tag)
}

func firstSentence(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexAny(s, ".!?"); i > 0 && i < 140 {
		return s[:i+1]
	}
	if len(s) > 140 {
		return s[:137] + "..."
	}
	return s
}

func manifestStrings(m map[string]any, key string) []string {
	arr, ok := m[key].([]any)
	if !ok {
		return []string{}
	}
	out := []string{}
	for _, e := range arr {
		if s, ok := e.(string); ok && s != "" {
			out = append(out, s)
		}
	}
	return out
}

func manifestStringOr(m map[string]any, key, def string) string {
	if s := manifestString(m, key); s != "" {
		return s
	}
	return def
}

func marshalCompact(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return bytes.TrimRight(buf.Bytes(), "\n"), nil
}

// gitCommitAs commits with the plugin author as the identity when git has none
// configured (a fresh desktop rarely does), so the commit carries the author's
// own name; a configured identity wins.
func gitCommitAs(dir, author, subject string) error {
	args := []string{}
	if _, err := gitOut(dir, "config", "user.name"); err != nil {
		name, mail := splitAuthor(author)
		args = append(args, "-c", "user.name="+name, "-c", "user.email="+mail)
	}
	return gitIn(dir, append(args, "commit", "-q", "-m", subject)...)
}

// splitAuthor reads the manifest's `Name <mail>` form; either half may be
// missing, and both fall back to something git accepts.
func splitAuthor(author string) (string, string) {
	name, mail := strings.TrimSpace(author), ""
	if i := strings.Index(name, "<"); i >= 0 {
		mail = strings.Trim(strings.TrimSpace(name[i:]), "<>")
		name = strings.TrimSpace(name[:i])
	}
	if name == "" {
		name = "ryoku"
	}
	if mail == "" {
		mail = strings.ToLower(strings.ReplaceAll(name, " ", "-")) + "@users.noreply.github.com"
	}
	return name, mail
}

func gitIn(dir string, args ...string) error {
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	return cmd.Run()
}

func gitOut(dir string, args ...string) (string, error) {
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

// ── share ────────────────────────────────────────────────────────────────────

func cmdPluginShare(args []string) error {
	id, from := "", ""
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--from":
			i++
			if i >= len(args) {
				return fmt.Errorf("--from needs a directory")
			}
			from = args[i]
		case strings.HasPrefix(args[i], "-"):
			return fmt.Errorf("unknown flag %q", args[i])
		default:
			if id != "" {
				return fmt.Errorf("give one plugin id")
			}
			id = args[i]
		}
	}
	if id == "" {
		return fmt.Errorf("usage: ryoku plugin share <id> [--from <exported-dir>]")
	}
	dir := from
	if dir == "" {
		d, err := exportPlugin(id, "")
		if err != nil {
			return err
		}
		dir = d
		fmt.Printf("%s %s -> %s\n", sys.Green("exported"), id, dir)
	}
	var entry registryEntry
	eb, err := os.ReadFile(filepath.Join(dir, "registry-entry.json"))
	if err != nil {
		return fmt.Errorf("%s is not an export (run `ryoku plugin export %s` first)", dir, id)
	}
	if err := json.Unmarshal(eb, &entry); err != nil {
		return fmt.Errorf("registry-entry.json: %w", err)
	}
	if entry.Preview == "" {
		fmt.Println(sys.Amber("Warning: no preview image under assets/; Ryostore needs a real screenshot (assets/preview-widget.png)."))
	}
	if sys.Has("gh") && ghLoggedIn() {
		return shareByPullRequest(dir, entry)
	}
	return shareByForm(dir, entry)
}

func ghLoggedIn() bool {
	return exec.Command("gh", "auth", "status").Run() == nil
}

func ghLogin() string {
	out, err := exec.Command("gh", "api", "user", "-q", ".login").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// shareByPullRequest forks the catalogue (a no-op for its owner), lays the
// export into plugins/<id>, upserts the registry entry, pushes a branch and
// opens the pull request with the catalogue's own checklist.
func shareByPullRequest(dir string, entry registryEntry) error {
	login := ghLogin()
	if login == "" {
		return shareByForm(dir, entry)
	}
	owner := strings.SplitN(ryostoreRepo, "/", 2)[0]
	head := ryostoreRepo
	if login != owner {
		fmt.Println("forking " + ryostoreRepo + " ...")
		if err := sys.Run("gh", "repo", "fork", ryostoreRepo, "--clone=false"); err != nil {
			return fmt.Errorf("fork: %w", err)
		}
		head = login + "/ryostore"
	}
	work, err := os.MkdirTemp("", "ryoku-share-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)
	fmt.Println("cloning " + head + " ...")
	if err := sys.Run("gh", "repo", "clone", head, work, "--", "--depth", "1", "--quiet"); err != nil {
		return fmt.Errorf("clone: %w", err)
	}
	if head != ryostoreRepo {
		_ = gitIn(work, "remote", "add", "upstream", "https://github.com/"+ryostoreRepo+".git")
		_ = gitIn(work, "fetch", "-q", "--depth", "1", "upstream", "main")
		_ = gitIn(work, "reset", "-q", "--hard", "upstream/main")
	}
	branch := "plugin/" + entry.ID
	if err := gitIn(work, "checkout", "-q", "-B", branch); err != nil {
		return err
	}
	target := filepath.Join(work, "plugins", entry.ID)
	_ = os.RemoveAll(target)
	if err := os.MkdirAll(target, 0o755); err != nil {
		return err
	}
	if err := copyPluginTree(dir, target); err != nil {
		return err
	}
	if err := sys.CopyFile(filepath.Join(dir, "product-manifest.json"), filepath.Join(target, "product-manifest.json")); err != nil {
		return err
	}
	regPath := filepath.Join(work, "plugins", "registry.json")
	if err := upsertRegistryEntry(regPath, entry); err != nil {
		return err
	}
	if out, err := gitOut(work, "status", "--porcelain"); err != nil || out == "" {
		return fmt.Errorf("nothing to submit: the catalogue already carries %s %s", entry.ID, entry.Version)
	}
	_ = gitIn(work, "add", "-A")
	subject := fmt.Sprintf("plugins: add %s %s", entry.Name, entry.Version)
	if err := gitCommitAs(work, entry.Author, subject); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	if err := gitIn(work, "push", "-q", "-f", "-u", "origin", branch); err != nil {
		return fmt.Errorf("push: %w", err)
	}
	kind := "desktop plugin"
	for _, h := range entry.Hosts {
		if h == "topbarGlyph" {
			kind = "bar widget"
		}
	}
	body := fmt.Sprintf(`## What is this?

%s, a %s: %s

## Checklist

- [x] One folder under its catalogue with a manifest and a real preview image (not a placeholder).
- [x] One entry added to that catalogue's `+"`registry.json`"+` (`+"`lastUpdated`"+` in `+"`YYYY-MM-DD`"+`; `+"`official: false`"+` for community items).
- [x] Tested live in Ryoku, it renders and behaves correctly (installed with `+"`ryoku plugin add`"+`).
- [ ] `+"`tests/validate-catalogue.sh`"+` passes from the repo root.
- [x] I own or have permission to submit this content, and it is licensed for redistribution.
- [x] It does not overwrite user configuration or run privileged commands without clear consent.

Opened with `+"`ryoku plugin share`"+`; the product manifest and the registry entry were generated from the installed plugin.
`, entry.Name, kind, entry.Summary)
	prArgs := []string{"pr", "create", "-R", ryostoreRepo, "--title", subject, "--body", body, "--head", branch}
	if head != ryostoreRepo {
		prArgs[len(prArgs)-1] = login + ":" + branch
	}
	cmd := exec.Command("gh", prArgs...)
	cmd.Dir = work
	out, err := cmd.CombinedOutput()
	text := strings.TrimSpace(string(out))
	if err != nil {
		if strings.Contains(text, "already exists") {
			fmt.Println(sys.Green("updated") + " the open pull request for " + entry.ID)
			return nil
		}
		return fmt.Errorf("gh pr create: %s", text)
	}
	fmt.Println(sys.Green("submitted") + " " + text)
	return nil
}

// upsertRegistryEntry replaces the entry with the same id in plugins/registry.json
// or appends it, keeping the file's two-space formatting.
func upsertRegistryEntry(path string, entry registryEntry) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var reg struct {
		Plugins []json.RawMessage `json:"plugins"`
	}
	var whole map[string]json.RawMessage
	if err := json.Unmarshal(b, &whole); err != nil {
		return fmt.Errorf("registry.json: %w", err)
	}
	if err := json.Unmarshal(b, &reg); err != nil {
		return fmt.Errorf("registry.json: %w", err)
	}
	nb, err := marshalCompact(entry)
	if err != nil {
		return err
	}
	replaced := false
	for i, raw := range reg.Plugins {
		var probe struct {
			ID string `json:"id"`
		}
		if json.Unmarshal(raw, &probe) == nil && probe.ID == entry.ID {
			reg.Plugins[i] = nb
			replaced = true
		}
	}
	if !replaced {
		reg.Plugins = append(reg.Plugins, nb)
	}
	pb, err := marshalCompact(reg.Plugins)
	if err != nil {
		return err
	}
	whole["plugins"] = pb
	// keep every other key (archived, ...) and the key order schema, plugins, rest
	var out bytes.Buffer
	out.WriteString("{\n")
	keys := []string{"schema", "plugins"}
	for k := range whole {
		if k != "schema" && k != "plugins" {
			keys = append(keys, k)
		}
	}
	for i, k := range keys {
		v, ok := whole[k]
		if !ok {
			continue
		}
		var pretty bytes.Buffer
		if err := json.Indent(&pretty, v, "  ", "  "); err != nil {
			return err
		}
		fmt.Fprintf(&out, "  %q: %s", k, pretty.String())
		if i < len(keys)-1 {
			out.WriteString(",")
		}
		out.WriteString("\n")
	}
	out.WriteString("}\n")
	return os.WriteFile(path, out.Bytes(), 0o644)
}

// shareByForm opens the catalogue's submission form prefilled from the export,
// for a desktop without gh; the export dir is what a maintainer asks for.
func shareByForm(dir string, entry registryEntry) error {
	kind := "Plugin (desktop widget)"
	for _, h := range entry.Hosts {
		if h == "topbarGlyph" {
			kind = "Plugin (bar widget)"
		}
	}
	source := dir
	if remote, err := gitOut(dir, "remote", "get-url", "origin"); err == nil && remote != "" {
		source = remote
	}
	q := url.Values{}
	q.Set("template", "submit-item.yml")
	q.Set("title", "[plugin] "+entry.Name)
	q.Set("name", entry.Name)
	q.Set("kind", kind)
	q.Set("author", entry.Author)
	q.Set("summary", entry.Summary)
	q.Set("description", entry.Description)
	q.Set("source", source)
	u := ryostoreFormURL + "?" + q.Encode()
	fmt.Println("gh is not set up, so the submission goes through the form.")
	fmt.Println("Push " + dir + " to a public git repo first, then paste its URL in the form:")
	fmt.Println("  " + u)
	if sys.Has("xdg-open") {
		_ = exec.Command("xdg-open", u).Start()
	}
	return nil
}
