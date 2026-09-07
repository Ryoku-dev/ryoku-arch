package main

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

// icons.go resolves desktop icon names to concrete SVG/PNG files, without going
// through Qt's icon engine. The shell used to load app and theme icons as
// image://icon/<name> URLs, which routed every icon through libqsvgicon under
// QIcon and re-rasterised on a fractional-scale change -- a path that raced the
// dock icon warm-up and segfaulted the surface. Handing QML a plain file:// path
// to the theme's own SVG/PNG keeps the ordinary image plugin in the loop, which
// is size-stable across DPR changes.
//
// `ryoku-shell icons` prints one JSON object indexing every icon name reachable
// through the current theme's inheritance chain; `ryoku-shell icons <name>...`
// prints one resolved absolute path per line ("" for none). Both are served
// client-side (main.go), like `theme catalog`: the index is far larger than the
// daemon socket's reply and needs no running daemon, so it is built on demand in
// the calling process (a few thousand readdir/stat, well under 100 ms).

// iconIndex is the whole answer: the active theme, its resolved inheritance
// chain (ending in hicolor), and every icon name mapped to an absolute path.
type iconIndex struct {
	Theme string            `json:"theme"`
	Chain []string          `json:"chain"`
	Icons map[string]string `json:"icons"`
}

// iconCand is one candidate file for a name within a single theme, scored so the
// preferred one wins: a scalable SVG beats the largest sized raster, which beats
// a symbolic variant; ties break toward the larger size, then toward SVG.
type iconCand struct {
	path string
	tier int // 3 scalable svg, 2 sized, 1 symbolic
	size int
	svg  bool
}

// better reports whether a is the preferred candidate over b.
func better(a, b iconCand) bool {
	if a.tier != b.tier {
		return a.tier > b.tier
	}
	if a.size != b.size {
		return a.size > b.size
	}
	if a.svg != b.svg {
		return a.svg
	}
	return false
}

// runIcons is the CLI entry. With no names it prints the whole index as JSON;
// with names it prints one resolved path per line.
func runIcons(args []string) int {
	idx := buildIconIndex()
	if len(args) == 0 {
		b, err := json.Marshal(idx)
		if err != nil {
			fmt.Fprintln(os.Stderr, "ryoku-shell: icons:", err)
			return 1
		}
		fmt.Println(string(b))
		return 0
	}
	for _, name := range args {
		fmt.Println(resolveIconName(name, idx))
	}
	return 0
}

// resolveIconName answers one spot-check lookup: an absolute path passes through
// when it exists, otherwise the name is looked up in the index ("" for none).
func resolveIconName(name string, idx iconIndex) string {
	if name == "" {
		return ""
	}
	if strings.HasPrefix(name, "/") {
		if fileExists(name) {
			return name
		}
		return ""
	}
	return idx.Icons[name]
}

// buildIconIndex builds the index for the live system: the active theme, the
// real icon roots, and /usr/share/pixmaps as the final fallback.
func buildIconIndex() iconIndex {
	return buildIndex(currentIconTheme(), iconRoots(), "/usr/share/pixmaps")
}

// buildIndex is the pure core (theme, roots, and pixmaps dir injected) so the
// lookup order is unit-testable without touching gsettings or /usr.
func buildIndex(theme string, roots []string, pixmapsDir string) iconIndex {
	chain := iconThemeChain(theme, roots)
	icons := make(map[string]string, 4096)
	for _, t := range chain {
		// Best candidate per name within this theme (across every root), then
		// merge: the first theme in the chain that has a name keeps it.
		best := map[string]iconCand{}
		for _, root := range roots {
			scanThemeDir(filepath.Join(root, t), best)
		}
		for name, c := range best {
			if _, ok := icons[name]; !ok {
				icons[name] = c.path
			}
		}
	}
	scanPixmaps(pixmapsDir, icons)
	return iconIndex{Theme: theme, Chain: chain, Icons: icons}
}

// currentIconTheme reads the active icon theme: the GNOME interface setting
// first, then the GTK 3 settings.ini, then hicolor as the universal fallback.
func currentIconTheme() string {
	if out, err := exec.Command("gsettings", "get", "org.gnome.desktop.interface", "icon-theme").Output(); err == nil {
		if s := strings.Trim(strings.TrimSpace(string(out)), "'\""); s != "" {
			return s
		}
	}
	if s := gtkIconThemeName(); s != "" {
		return s
	}
	return "hicolor"
}

// gtkIconThemeName reads gtk-icon-theme-name from ~/.config/gtk-3.0/settings.ini.
func gtkIconThemeName() string {
	cfg := os.Getenv("XDG_CONFIG_HOME")
	if cfg == "" {
		cfg = filepath.Join(os.Getenv("HOME"), ".config")
	}
	data, err := os.ReadFile(filepath.Join(cfg, "gtk-3.0", "settings.ini"))
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if v, ok := strings.CutPrefix(line, "gtk-icon-theme-name"); ok {
			v = strings.TrimSpace(v)
			if v, ok := strings.CutPrefix(v, "="); ok {
				return strings.Trim(strings.TrimSpace(v), "'\"")
			}
		}
	}
	return ""
}

// iconRoots are the icon search roots in preference order: the user's data dir,
// ~/.icons, then each system data dir (XDG spec defaults when unset).
func iconRoots() []string {
	home := os.Getenv("HOME")
	dataHome := os.Getenv("XDG_DATA_HOME")
	if dataHome == "" {
		dataHome = filepath.Join(home, ".local", "share")
	}
	dataDirs := os.Getenv("XDG_DATA_DIRS")
	if dataDirs == "" {
		dataDirs = "/usr/local/share:/usr/share"
	}
	roots := []string{
		filepath.Join(dataHome, "icons"),
		filepath.Join(home, ".icons"),
	}
	for _, d := range strings.Split(dataDirs, ":") {
		if d != "" {
			roots = append(roots, filepath.Join(d, "icons"))
		}
	}
	return roots
}

// iconThemeChain resolves the theme's inheritance chain: the theme, then its
// Inherits parents (depth-first, deduped), with hicolor guaranteed last.
func iconThemeChain(theme string, roots []string) []string {
	var chain []string
	seen := map[string]bool{}
	var visit func(t string)
	visit = func(t string) {
		if t == "" || seen[t] {
			return
		}
		seen[t] = true
		chain = append(chain, t)
		for _, parent := range themeInherits(t, roots) {
			visit(parent)
		}
	}
	visit(theme)
	if !seen["hicolor"] {
		chain = append(chain, "hicolor")
	}
	return chain
}

// themeInherits reads the Inherits= list from a theme's index.theme, taking the
// first root that has one.
func themeInherits(theme string, roots []string) []string {
	for _, root := range roots {
		data, err := os.ReadFile(filepath.Join(root, theme, "index.theme"))
		if err != nil {
			continue
		}
		return parseInherits(data)
	}
	return nil
}

// parseInherits pulls the comma-separated Inherits= value out of the
// [Icon Theme] section of an index.theme.
func parseInherits(data []byte) []string {
	section := ""
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = strings.TrimSuffix(strings.TrimPrefix(line, "["), "]")
			continue
		}
		if section != "Icon Theme" {
			continue
		}
		if v, ok := strings.CutPrefix(line, "Inherits"); ok {
			v = strings.TrimSpace(v)
			if v, ok := strings.CutPrefix(v, "="); ok {
				var out []string
				for _, p := range strings.Split(v, ",") {
					if p = strings.TrimSpace(p); p != "" {
						out = append(out, p)
					}
				}
				return out
			}
		}
	}
	return nil
}

// scanThemeDir walks one theme directory (one root) and merges the best
// candidate per icon name into best. It follows directory symlinks -- Papirus
// and its dark/light variants build whole size trees out of them
// (Papirus-Dark/128x128 -> ../Papirus/128x128), which filepath.WalkDir skips --
// deduping by resolved path so an aliased tree is walked once and a symlink
// cycle cannot loop.
func scanThemeDir(dir string, best map[string]iconCand) {
	seen := map[string]bool{}
	var walk func(cur string)
	walk = func(cur string) {
		key := cur
		if real, err := filepath.EvalSymlinks(cur); err == nil {
			key = real
		}
		if seen[key] {
			return
		}
		seen[key] = true
		entries, err := os.ReadDir(cur)
		if err != nil {
			return
		}
		for _, e := range entries {
			name := e.Name()
			p := filepath.Join(cur, name)
			// An icon-extension entry is a file (a real file or a symlink to one);
			// classify it straight away. classifyIcon only records the path, which
			// resolves through the symlink on open, so no stat is needed here -- the
			// win that keeps a symlink-heavy theme (Papirus) well under budget.
			if c, iname, ok := classifyIcon(dir, p, name); ok {
				if prev, exists := best[iname]; !exists || better(c, prev) {
					best[iname] = c
				}
				continue
			}
			// Otherwise it may be a directory: recurse into real dirs, and stat
			// only extension-less symlinks (the size-tree aliases) to follow them.
			isDir := e.IsDir()
			if e.Type()&fs.ModeSymlink != 0 {
				info, err := os.Stat(p)
				if err != nil {
					continue
				}
				isDir = info.IsDir()
			}
			if isDir {
				walk(p)
			}
		}
	}
	walk(dir)
}

// classifyIcon scores one file under a theme directory. It returns the candidate
// and the icon name (the file stem), or ok=false for a non-icon file.
func classifyIcon(themeDir, p, base string) (iconCand, string, bool) {
	ext := strings.ToLower(filepath.Ext(base))
	if ext != ".svg" && ext != ".png" && ext != ".xpm" {
		return iconCand{}, "", false
	}
	name := strings.TrimSuffix(base, filepath.Ext(base))
	rel, err := filepath.Rel(themeDir, p)
	if err != nil {
		return iconCand{}, "", false
	}
	comps := strings.Split(filepath.ToSlash(rel), "/")
	svg := ext == ".svg"
	isScalable := false
	isSymbolic := strings.HasSuffix(name, "-symbolic")
	size := 0
	for _, c := range comps[:len(comps)-1] { // skip the file component
		switch c {
		case "scalable":
			isScalable = true
		case "symbolic":
			isSymbolic = true
		}
		if s := parseSizeDir(c); s > size {
			size = s
		}
	}
	var tier int
	switch {
	case isSymbolic:
		tier = 1
	case isScalable && svg:
		tier = 3
	default:
		tier = 2
	}
	// A scalable directory with no numeric size still beats any fixed raster.
	if isScalable && size == 0 {
		size = 1 << 20
	}
	return iconCand{path: p, tier: tier, size: size, svg: svg}, name, true
}

// parseSizeDir reads the pixel size out of a size directory name: the leading
// integer of forms like "48", "48x48", "256x256", doubled for an "@2x" suffix.
// It returns 0 for a non-size directory (scalable, symbolic, apps, ...).
func parseSizeDir(name string) int {
	mult := 1
	if i := strings.Index(name, "@"); i >= 0 {
		suffix := name[i+1:]
		name = name[:i]
		if m := strings.TrimSuffix(suffix, "x"); m != suffix {
			if n, err := strconv.Atoi(m); err == nil && n > 0 {
				mult = n
			}
		}
	}
	end := 0
	for end < len(name) && name[end] >= '0' && name[end] <= '9' {
		end++
	}
	if end == 0 {
		return 0
	}
	n, err := strconv.Atoi(name[:end])
	if err != nil {
		return 0
	}
	return n * mult
}

// scanPixmaps fills any name still missing from /usr/share/pixmaps top level,
// preferring svg over png over xpm.
func scanPixmaps(dir string, icons map[string]string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	rank := func(ext string) int {
		switch ext {
		case ".svg":
			return 3
		case ".png":
			return 2
		case ".xpm":
			return 1
		}
		return 0
	}
	best := map[string]iconCand{}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		r := rank(strings.ToLower(filepath.Ext(e.Name())))
		if r == 0 {
			continue
		}
		name := strings.TrimSuffix(e.Name(), filepath.Ext(e.Name()))
		if cur, ok := best[name]; !ok || r > cur.size {
			best[name] = iconCand{path: filepath.Join(dir, e.Name()), size: r}
		}
	}
	for name, c := range best {
		if _, ok := icons[name]; !ok {
			icons[name] = c.path
		}
	}
}
