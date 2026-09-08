package updater

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
	"strings"
	"time"
)

// A packaged install has no checkout, so it cannot run gitLog to list what is
// incoming. It still knows the commit it runs (the installed ryoku-desktop) and
// the commit the [ryoku] repo offers (the latest), so it asks the public GitHub
// repo for the commits between them: the same origin/main history a dev box
// reads locally, so the Hub's Updates list is the real commit subjects on both,
// not bare package names.
//
// The lookup is cached by the base..head pair (both shas move only across an
// actual release, so a polled `ryoku status` fetches once and reuses it) and is
// best-effort: any failure returns nil so the caller degrades to a single
// package row, and a status poll never hangs or errors.

// ryokuRepoSlug is the canonical GitHub repo (owner/name) the update channel
// tracks. Every Ryoku machine follows it; RYOKU_REPO_SLUG overrides it for a
// fork or a test.
func ryokuRepoSlug() string {
	if s := strings.TrimSpace(os.Getenv("RYOKU_REPO_SLUG")); s != "" {
		return s
	}
	return "ryoku-dev/ryoku-arch"
}

// githubAPI is the API root. RYOKU_GITHUB_API points a test at a stub server.
func githubAPI() string {
	if s := strings.TrimSpace(os.Getenv("RYOKU_GITHUB_API")); s != "" {
		return s
	}
	return "https://api.github.com"
}

func commitCacheFile() string {
	return filepath.Join(sys.Xdg("XDG_CACHE_HOME", ".cache"), "ryoku", "commits.json")
}

// commitCache is the last resolved compare, keyed by the sha pair it was fetched
// for. A hit (same base and head) short-circuits the network call, so repeated
// status polls between two releases cost nothing.
type commitCache struct {
	Base    string       `json:"base"`
	Head    string       `json:"head"`
	Behind  int          `json:"behind"`
	Updates []updateItem `json:"updates"`
}

// incomingCommits returns the commits head has that base lacks, newest first, as
// display rows (subject in Name, short hash in New), plus the true count. An
// empty base or head, or base == head, means nothing is incoming and no lookup
// runs. Best-effort: (nil, 0) on any failure, so the caller can degrade without
// ever blocking the status query.
func incomingCommits(base, head string) ([]updateItem, int) {
	if base == "" || head == "" || base == head {
		return nil, 0
	}
	if c, ok := readCommitCache(base, head); ok {
		return c.Updates, c.Behind
	}
	ups, total, ok := fetchCompare(base, head)
	if !ok {
		return nil, 0
	}
	writeCommitCache(commitCache{Base: base, Head: head, Behind: total, Updates: ups})
	return ups, total
}

func readCommitCache(base, head string) (commitCache, bool) {
	b, err := os.ReadFile(commitCacheFile())
	if err != nil {
		return commitCache{}, false
	}
	var c commitCache
	if json.Unmarshal(b, &c) != nil {
		return commitCache{}, false
	}
	if c.Base != base || c.Head != head {
		return commitCache{}, false
	}
	return c, true
}

func writeCommitCache(c commitCache) {
	b, err := json.Marshal(c)
	if err != nil {
		return
	}
	if os.MkdirAll(filepath.Dir(commitCacheFile()), 0o755) != nil {
		return
	}
	_ = os.WriteFile(commitCacheFile(), b, 0o644)
}

// compareResponse is the slice of GitHub's compare payload we read.
type compareResponse struct {
	TotalCommits int `json:"total_commits"`
	Commits      []struct {
		SHA    string `json:"sha"`
		Commit struct {
			Message string `json:"message"`
		} `json:"commit"`
	} `json:"commits"`
}

// fetchCompare asks the GitHub compare API for base...head. GitHub returns those
// commits oldest first; the Hub rail reads newest first (matching gitLog), so
// they are reversed. Bounded and best-effort: ok=false on any error, so status
// stays responsive when GitHub is offline or rate-limited.
func fetchCompare(base, head string) ([]updateItem, int, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	url := githubAPI() + "/repos/" + ryokuRepoSlug() + "/compare/" + base + "..." + head
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, 0, false
	}
	// GitHub 403s an API request with no User-Agent; the media type pins the
	// response shape.
	req.Header.Set("User-Agent", "ryoku-cli")
	req.Header.Set("Accept", "application/vnd.github+json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, 0, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, 0, false
	}

	var cr compareResponse
	if json.NewDecoder(resp.Body).Decode(&cr) != nil {
		return nil, 0, false
	}

	ups := make([]updateItem, 0, len(cr.Commits))
	for i := len(cr.Commits) - 1; i >= 0; i-- { // newest first, to match git log
		c := cr.Commits[i]
		subject := c.Commit.Message
		if nl := strings.IndexByte(subject, '\n'); nl >= 0 {
			subject = subject[:nl]
		}
		sha := c.SHA
		if len(sha) > 7 {
			sha = sha[:7]
		}
		ups = append(ups, updateItem{Name: subject, New: sha})
	}
	total := cr.TotalCommits
	if total == 0 {
		total = len(ups)
	}
	return ups, total, true
}

// An up-to-date packaged box has nothing incoming, so the compare view above is
// empty. It still runs a known commit (the installed ryoku-desktop), so it asks
// the public GitHub repo for the recent history that commit contains: the last
// handful of commit subjects, newest first, so the Hub's Updates page shows
// "what you're running" instead of a blank section. Same best-effort + cached
// contract as incomingCommits, keyed by the head sha (which only moves across a
// release).

func recentCacheFile() string {
	return filepath.Join(sys.Xdg("XDG_CACHE_HOME", ".cache"), "ryoku", "recent.json")
}

// recentCache is the last resolved recent history, keyed by the head sha it was
// fetched for. A hit (same head) short-circuits the network call, so repeated
// status polls on an up-to-date box cost nothing.
type recentCache struct {
	Head    string       `json:"head"`
	Updates []updateItem `json:"updates"`
}

// recentCommits returns the last commits reachable from head, newest first, as
// display rows (subject in Name, short hash in New). An empty head means no
// lookup runs. Best-effort: nil on any failure, so the status query never hangs
// or errors when GitHub is offline or rate-limited.
func recentCommits(head string) []updateItem {
	if head == "" {
		return nil
	}
	if c, ok := readRecentCache(head); ok {
		return c.Updates
	}
	ups, ok := fetchRecent(head)
	if !ok {
		return nil
	}
	writeRecentCache(recentCache{Head: head, Updates: ups})
	return ups
}

func readRecentCache(head string) (recentCache, bool) {
	b, err := os.ReadFile(recentCacheFile())
	if err != nil {
		return recentCache{}, false
	}
	var c recentCache
	if json.Unmarshal(b, &c) != nil {
		return recentCache{}, false
	}
	if c.Head != head {
		return recentCache{}, false
	}
	return c, true
}

func writeRecentCache(c recentCache) {
	b, err := json.Marshal(c)
	if err != nil {
		return
	}
	if os.MkdirAll(filepath.Dir(recentCacheFile()), 0o755) != nil {
		return
	}
	_ = os.WriteFile(recentCacheFile(), b, 0o644)
}

// listResponse is the slice of GitHub's list-commits payload we read. That
// endpoint returns a bare array, newest first already, so no reversal is needed.
type listResponse []struct {
	SHA    string `json:"sha"`
	Commit struct {
		Message string `json:"message"`
	} `json:"commit"`
}

// fetchRecent asks the GitHub list-commits API for the last commits reachable
// from head (newest first, capped at per_page). Bounded and best-effort:
// ok=false on any error, so status stays responsive when GitHub is offline or
// rate-limited.
func fetchRecent(head string) ([]updateItem, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	url := githubAPI() + "/repos/" + ryokuRepoSlug() + "/commits?sha=" + head + "&per_page=10"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, false
	}
	// GitHub 403s an API request with no User-Agent; the media type pins the
	// response shape.
	req.Header.Set("User-Agent", "ryoku-cli")
	req.Header.Set("Accept", "application/vnd.github+json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, false
	}

	var lr listResponse
	if json.NewDecoder(resp.Body).Decode(&lr) != nil {
		return nil, false
	}

	ups := make([]updateItem, 0, len(lr))
	for _, c := range lr { // GitHub lists newest first already
		subject := c.Commit.Message
		if nl := strings.IndexByte(subject, '\n'); nl >= 0 {
			subject = subject[:nl]
		}
		sha := c.SHA
		if len(sha) > 7 {
			sha = sha[:7]
		}
		ups = append(ups, updateItem{Name: subject, New: sha})
	}
	return ups, true
}
