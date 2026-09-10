package main

import (
	"fmt"
	"path/filepath"
	"strings"
)

// manifest.go answers the question "how do I make MY coding agent Ryoku-aware?"
// for any agent, supported or not. It lists every path Rashin exposes -- the
// skill, the generated vault maps, prowl-agent for code intelligence, the MCP
// server config -- plus a ready-to-paste instruction snippet. The supported
// agents get all of this in one click (Wire); an unsupported one gets the same
// power by pasting the snippet into its own instructions file.

// ManifestItem is one resource an agent can be pointed at.
type ManifestItem struct {
	Label  string `json:"label"`
	Path   string `json:"path"` // tilde-abbreviated for display
	Kind   string `json:"kind"` // skill | map | dir | tool | mcp
	Desc   string `json:"desc"`
	Exists bool   `json:"exists"`
}

// ChatBackendInfo is a chat-capable agent and whether it can/does drive the
// Super+S session right now.
type ChatBackendInfo struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Available   bool   `json:"available"`
	Recommended bool   `json:"recommended"`
	Active      bool   `json:"active"`
}

// Manifest is the whole agent-facing surface: what to read, what to run, who is
// wired, who can drive the chat, and the paste snippet for anything else.
type Manifest struct {
	Skill        ManifestItem      `json:"skill"`
	Prowl        ManifestItem      `json:"prowl"`
	Vault        []ManifestItem    `json:"vault"`
	MCP          []any             `json:"mcp"`
	Agents       []Agent           `json:"agents"`
	ChatBackends []ChatBackendInfo `json:"chatBackends"`
	Pointer      string            `json:"pointer"`
	Snippet      string            `json:"snippet"`
}

// vaultManifest lists the generated vault docs and note dirs with a one-line
// gloss each, in read order (index first).
func vaultManifest() []ManifestItem {
	root := VaultDir()
	docs := []struct{ name, desc, kind string }{
		{"AGENTS.md", "index: where every config lives, the binary that owns it, how to reload", "map"},
		{"desktop.md", "the desktop map: bar, dock, widgets, launcher, Hub", "map"},
		{"system.md", "hardware, kernel, GPU, disks, displays", "map"},
		{"packages.md", "installed packages and pending updates", "map"},
		{"repo.md", "the Ryoku source map", "map"},
		{"user.md", "your own config changes over the shipped base", "map"},
		{"habits.md", "learned usage patterns on this machine", "map"},
		{"memory", "durable notes the agent keeps across sessions", "dir"},
		{"journal", "dated notes (journal/YYYY-MM-DD.md)", "dir"},
	}
	out := make([]ManifestItem, 0, len(docs))
	for _, d := range docs {
		p := filepath.Join(root, d.name)
		exists := fileExists(p) || dirExists(p)
		out = append(out, ManifestItem{
			Label: d.name, Path: tildeAbbrev(p), Kind: d.kind, Desc: d.desc, Exists: exists,
		})
	}
	return out
}

// chatBackendInfos reports each chat-capable agent's availability and which one
// is active for the given config.
func chatBackendInfos(cfg Config) []ChatBackendInfo {
	active, _ := resolveChatBackend(cfg)
	out := make([]ChatBackendInfo, 0, len(chatBackends()))
	for _, b := range chatBackends() {
		out = append(out, ChatBackendInfo{
			ID: b.ID, Name: b.Name,
			Available:   chatBackendAvailable(b),
			Recommended: b.Recommended,
			Active:      b.ID == active.ID,
		})
	}
	return out
}

// BuildManifest assembles the agent-facing surface for the given config.
func BuildManifest(cfg Config) Manifest {
	skillDir := skillSourceDir()
	skill := ManifestItem{
		Label: "ryoku skill", Kind: "skill",
		Desc:   "safety rules, the bar/dock/plugins/themes guide, and the command catalogue",
		Exists: skillDir != "",
	}
	if skillDir != "" {
		skill.Path = tildeAbbrev(filepath.Join(skillDir, "SKILL.md"))
	}

	prowl := ManifestItem{Label: "prowl-agent", Kind: "tool",
		Desc: "cited code intelligence, reindexed each run: search/find/def/references/outline/impact"}
	if bin, ok := findProwl(); ok {
		prowl.Path = tildeAbbrev(bin)
		prowl.Exists = true
	}

	return Manifest{
		Skill:        skill,
		Prowl:        prowl,
		Vault:        vaultManifest(),
		MCP:          prowlMCPServers(),
		Agents:       DetectAgents(),
		ChatBackends: chatBackendInfos(cfg),
		Pointer:      PointerBlock,
		Snippet:      manifestSnippet(skillDir),
	}
}

// manifestSnippet is the plain-language block a user pastes into any coding
// agent's instructions file so it works like the supported ones. Paths are
// resolved and tilde-abbreviated.
func manifestSnippet(skillDir string) string {
	vault := tildeAbbrev(VaultDir())
	skill := "the ryoku skill"
	if skillDir != "" {
		skill = tildeAbbrev(filepath.Join(skillDir, "SKILL.md"))
	}
	var b strings.Builder
	b.WriteString("You are working on a Ryoku machine (Arch Linux + Hyprland + Quickshell).\n\n")
	fmt.Fprintf(&b, "- Read the Ryoku vault first, at %s/ -- start with AGENTS.md (where every\n", vault)
	b.WriteString("  config lives, the binary that owns it, and how to reload it), then desktop.md,\n")
	b.WriteString("  system.md, packages.md, repo.md, user.md.\n")
	b.WriteString("- For code questions prefer prowl-agent (cited, reindexed each run) over grep:\n")
	b.WriteString("  `prowl-agent search \"<question>\"`, `find`, `def`, `references`, `outline`, `impact`.\n")
	fmt.Fprintf(&b, "- Read the Ryoku desktop skill for safe how-tos and the command catalogue: %s\n", skill)
	b.WriteString("- Act through the ryoku commands (ryoku, ryoku-shell, ryoku-hub, ryogami,\n")
	b.WriteString("  ryoku-rashin); never edit shipped files. Keep durable notes under the vault's\n")
	b.WriteString("  memory/ and dated notes under journal/.\n")
	return b.String()
}
