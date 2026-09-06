package main

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// music.go enriches whatever MPRIS player the shell is showing: the highest
// resolution cover image the track's own metadata can reach, and its
// synchronized lyrics. QML owns the player pick (services/Media.qml) and pushes
// the bare track on "music.track"; the daemon resolves art and lyrics, caches
// both under ~/.cache/ryoku/music, and streams the result on the "music" state
// topic, so no QML surface makes an HTTP request itself (docs/conventions.md).
//
// Providers are keyless and public: LRCLIB for lyrics, Deezer then iTunes for a
// cover the player never published. Nothing here needs an account, so Spotify,
// YouTube Music and YouTube all resolve the same way: their MPRIS art URL is
// rewritten to its full-size variant, and a missing one is looked up by title
// and artist.

const (
	musLyricsGetURL    = "https://lrclib.net/api/get"
	musLyricsSearchURL = "https://lrclib.net/api/search"
	musDeezerURL       = "https://api.deezer.com/search"
	musITunesURL       = "https://itunes.apple.com/search"

	musHTTPTimeout = 12 * time.Second
	// A cover under this size is a placeholder or an error page, not art.
	musMinArtBytes = 2048
	musMaxArtBytes = 12 << 20
	musUserAgent   = "ryoku-shell (https://github.com/ryoku-arch)"
)

// Track sources, resolved from the player's bus name and page URL. The frame
// carries it so a surface can label what is playing, and art resolution uses it
// to pick which URL rewrite applies.
const (
	musSrcSpotify    = "spotify"
	musSrcYtMusic    = "ytmusic"
	musSrcYouTube    = "youtube"
	musSrcAppleMusic = "applemusic"
	musSrcBrowser    = "browser"
	musSrcLocal      = "local"
	musSrcOther      = "other"
)

// Lyrics and art states QML binds its placeholders to.
const (
	musIdle    = "idle"
	musLoading = "loading"
	musOK      = "ok"
	musPlain   = "plain" // lyrics found, but unsynced: no timestamps to follow
	musNone    = "none"
	musError   = "error"
)

// musicTrack is the MPRIS metadata QML pushes in. Length is seconds.
type musicTrack struct {
	Title  string  `json:"title"`
	Artist string  `json:"artist"`
	Album  string  `json:"album"`
	URL    string  `json:"url"`
	ArtURL string  `json:"artUrl"`
	Length float64 `json:"length"`
	Player string  `json:"player"`
}

// musicLine is one timed lyric line: T seconds into the track.
type musicLine struct {
	T    float64 `json:"t"`
	Text string  `json:"text"`
}

// musicFrame is the whole state QML renders from.
type musicFrame struct {
	Key          string      `json:"key"`
	Title        string      `json:"title"`
	Artist       string      `json:"artist"`
	Album        string      `json:"album"`
	Source       string      `json:"source"`
	Art          string      `json:"art"`
	ArtStatus    string      `json:"artStatus"`
	Lyrics       []musicLine `json:"lyrics"`
	Plain        []string    `json:"plain"`
	LyricsStatus string      `json:"lyricsStatus"`
	Canvas       string      `json:"canvas"`
}

// musicState holds the resolver: its topic, the track it is resolving, and the
// generation that invalidates in-flight work when the track changes.
type musicState struct {
	topic  *stateTopic
	client *http.Client
	dir    string

	mu    sync.Mutex
	gen   int
	key   string
	frame musicFrame
}

// startMusic registers the music topic and the track push, and publishes the
// empty frame so a surface that loads before anything plays has state to bind.
func (d *daemon) startMusic() {
	s := &musicState{
		topic:  d.registerTopic("music"),
		client: &http.Client{Timeout: musHTTPTimeout},
		dir:    musicCacheDir(),
	}
	s.publish()

	d.registerCall("music.track", func(raw json.RawMessage) (any, error) {
		var t musicTrack
		if err := json.Unmarshal(raw, &t); err != nil {
			return nil, err
		}
		s.setTrack(t)
		return map[string]any{"ok": true}, nil
	})
}

func musicCacheDir() string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".cache")
	}
	return filepath.Join(base, "ryoku", "music")
}

// setTrack adopts a new track: an unchanged key is a no-op (every shell surface
// pushes the same pick, and MPRIS repeats metadata on every property change),
// so one track is resolved once.
func (s *musicState) setTrack(t musicTrack) {
	key := musicTrackKey(t)
	s.mu.Lock()
	if key == s.key {
		s.mu.Unlock()
		return
	}
	s.gen++
	gen := s.gen
	s.key = key
	empty := strings.TrimSpace(t.Title) == ""
	s.frame = musicFrame{
		Key:          key,
		Title:        t.Title,
		Artist:       t.Artist,
		Album:        t.Album,
		Source:       musicSourceOf(t),
		ArtStatus:    musLoading,
		LyricsStatus: musLoading,
	}
	if empty {
		s.frame = musicFrame{Key: key, ArtStatus: musNone, LyricsStatus: musIdle}
	}
	s.mu.Unlock()
	s.publish()
	if empty {
		return
	}
	go s.resolveArt(gen, t)
	go s.resolveLyrics(gen, t)
	go s.resolveCanvas(gen, t)
}

// current reports whether gen is still the live request, so a resolver that
// finished after a track change drops its result instead of painting the wrong
// cover over the new one.
func (s *musicState) current(gen int) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return gen == s.gen
}

// publish ships the frame as it stands. Art and lyrics land independently, so
// each resolver publishes when it finishes and the other's fields stay put.
func (s *musicState) publish() {
	s.mu.Lock()
	frame := s.frame
	s.mu.Unlock()
	if frame.Lyrics == nil {
		frame.Lyrics = []musicLine{}
	}
	if frame.Plain == nil {
		frame.Plain = []string{}
	}
	b, err := json.Marshal(frame)
	if err != nil {
		return
	}
	s.topic.publish(b)
}

// resolveArt walks the candidate covers in descending quality and publishes the
// first that downloads to a real image. A local file is published as-is.
func (s *musicState) resolveArt(gen int, t musicTrack) {
	for _, cand := range musicArtCandidates(t) {
		if !s.current(gen) {
			return
		}
		if path, ok := musicLocalArt(cand); ok {
			s.setArt(gen, path, musOK)
			return
		}
		if path, err := s.cacheArt(cand); err == nil {
			s.setArt(gen, path, musOK)
			return
		}
	}
	if !s.current(gen) {
		return
	}
	// Nothing the track carries resolved: ask the keyless catalogues, which
	// answer by title and artist rather than by URL.
	for _, lookup := range []func(musicTrack) (string, error){s.deezerCover, s.itunesCover} {
		if !s.current(gen) {
			return
		}
		remote, err := lookup(t)
		if err != nil || remote == "" {
			continue
		}
		if path, err := s.cacheArt(remote); err == nil {
			s.setArt(gen, path, musOK)
			return
		}
	}
	s.setArt(gen, "", musNone)
}

func (s *musicState) setArt(gen int, path, status string) {
	s.mu.Lock()
	if gen != s.gen {
		s.mu.Unlock()
		return
	}
	s.frame.Art = path
	s.frame.ArtStatus = status
	s.mu.Unlock()
	s.publish()
}

// resolveCanvas matches the track's Spotify id to a local backdrop the user
// keeps in ~/.config/ryoku/canvas/<id>.<ext> (a downloaded Canvas clip, or any
// loop): the "canvas" backdrop mode plays it per song. No id, or no file,
// leaves the field empty and the surface falls back to the cover.
func (s *musicState) resolveCanvas(gen int, t musicTrack) {
	url := ""
	if p := canvasFileFor(spotifyTrackID(t)); p != "" {
		url = "file://" + p
	}
	s.setCanvas(gen, url)
}

// canvasFileFor returns the local Canvas file for a Spotify id, or "" if the id
// is empty or the library has no clip for it.
func canvasFileFor(id string) string {
	if id == "" {
		return ""
	}
	dir := canvasDir()
	for _, ext := range []string{"mp4", "webm", "mkv", "mov", "m4v", "gif"} {
		p := filepath.Join(dir, id+"."+ext)
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
			return p
		}
	}
	return ""
}

func (s *musicState) setCanvas(gen int, url string) {
	s.mu.Lock()
	if gen != s.gen {
		s.mu.Unlock()
		return
	}
	s.frame.Canvas = url
	s.mu.Unlock()
	s.publish()
}

// canvasDir is the user's Canvas library, beside the other ryoku config.
func canvasDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "canvas")
}

// spotifyTrackID pulls the base62 id out of the track's page URL or MPRIS uri
// (https://open.spotify.com/track/<id> or spotify:track:<id>); "" if neither.
func spotifyTrackID(t musicTrack) string {
	u := strings.TrimSpace(t.URL)
	if i := strings.Index(u, "open.spotify.com/track/"); i >= 0 {
		id := u[i+len("open.spotify.com/track/"):]
		if j := strings.IndexAny(id, "?/#"); j >= 0 {
			id = id[:j]
		}
		return id
	}
	if i := strings.Index(u, "spotify:track:"); i >= 0 {
		return u[i+len("spotify:track:"):]
	}
	return ""
}

// resolveLyrics reads the cache, else queries LRCLIB. Synced lyrics win; a
// plain-text match is published as `plain` so a surface can still show the
// words without a follow-along highlight.
func (s *musicState) resolveLyrics(gen int, t musicTrack) {
	title, artist := musicSearchTerms(t)
	if title == "" {
		s.setLyrics(gen, nil, nil, musNone)
		return
	}
	cache := filepath.Join(s.dir, "lyrics", musicLyricsCacheName(title, artist, t.Album, t.Length))
	if lines, plain, status, ok := musicReadLyricsCache(cache); ok {
		s.setLyrics(gen, lines, plain, status)
		return
	}
	if !s.current(gen) {
		return
	}
	lines, plain, status, err := s.fetchLyrics(title, artist, t.Album, t.Length)
	if err != nil {
		s.setLyrics(gen, nil, nil, musError)
		return
	}
	musicWriteLyricsCache(cache, lines, plain, status)
	s.setLyrics(gen, lines, plain, status)
}

func (s *musicState) setLyrics(gen int, lines []musicLine, plain []string, status string) {
	s.mu.Lock()
	if gen != s.gen {
		s.mu.Unlock()
		return
	}
	s.frame.Lyrics = lines
	s.frame.Plain = plain
	s.frame.LyricsStatus = status
	s.mu.Unlock()
	s.publish()
}

// lrclibTrack is one LRCLIB record (both endpoints return this shape).
type lrclibTrack struct {
	TrackName    string  `json:"trackName"`
	ArtistName   string  `json:"artistName"`
	AlbumName    string  `json:"albumName"`
	Duration     float64 `json:"duration"`
	Instrumental bool    `json:"instrumental"`
	PlainLyrics  string  `json:"plainLyrics"`
	SyncedLyrics string  `json:"syncedLyrics"`
}

func (s *musicState) fetchLyrics(title, artist, album string, length float64) ([]musicLine, []string, string, error) {
	return s.fetchLyricsFrom(musLyricsGetURL, musLyricsSearchURL, title, artist, album, length)
}

// fetchLyricsFrom asks LRCLIB for the exact record first (title, artist, album
// and duration together), then falls back to the searches, taking the best
// scoring candidate. A track with no artist still searches on its title, which
// is how a YouTube video with only a channel name resolves. The endpoints are
// parameters so the ladder is testable against a stub provider.
func (s *musicState) fetchLyricsFrom(getURL, searchURL, title, artist, album string, length float64) ([]musicLine, []string, string, error) {
	var reached bool
	var best *lrclibTrack

	consider := func(cands []lrclibTrack) {
		for i := range cands {
			c := cands[i]
			if !musicLyricsMatch(c, title, artist, length) {
				continue
			}
			if best == nil || musicLyricsScore(c, length) > musicLyricsScore(*best, length) {
				best = &c
			}
		}
	}

	if artist != "" && album != "" && length > 0 {
		q := url.Values{}
		q.Set("track_name", title)
		q.Set("artist_name", artist)
		q.Set("album_name", album)
		q.Set("duration", strconv.Itoa(int(math.Round(length))))
		var one lrclibTrack
		if err := s.getJSON(getURL+"?"+q.Encode(), &one); err == nil {
			reached = true
			consider([]lrclibTrack{one})
		}
	}

	if best == nil || best.SyncedLyrics == "" {
		for _, q := range musicLyricsQueries(title, artist) {
			var list []lrclibTrack
			if err := s.getJSON(searchURL+"?"+q.Encode(), &list); err != nil {
				continue
			}
			reached = true
			consider(list)
			if best != nil && best.SyncedLyrics != "" {
				break
			}
		}
	}

	if best == nil {
		if !reached {
			return nil, nil, musError, fmt.Errorf("lyrics provider unreachable")
		}
		return nil, nil, musNone, nil
	}
	if lines := musicParseLRC(best.SyncedLyrics); len(lines) > 0 {
		return lines, nil, musOK, nil
	}
	if plain := musicPlainLines(best.PlainLyrics); len(plain) > 0 {
		return nil, plain, musPlain, nil
	}
	return nil, nil, musNone, nil
}

// musicLyricsQueries is the search ladder: the structured query first, then the
// whole "title artist" phrase, which catches records filed under a different
// artist spelling.
func musicLyricsQueries(title, artist string) []url.Values {
	out := []url.Values{}
	if artist != "" {
		q := url.Values{}
		q.Set("track_name", title)
		q.Set("artist_name", artist)
		out = append(out, q)
	}
	q := url.Values{}
	q.Set("q", strings.TrimSpace(title+" "+artist))
	out = append(out, q)
	if artist != "" {
		only := url.Values{}
		only.Set("track_name", title)
		out = append(out, only)
	}
	return out
}

// musicLyricsMatch keeps a candidate whose title and artist plausibly name the
// same recording, and whose duration is within ten seconds when both are known.
// LRCLIB search is fuzzy: without this a common title returns someone else's
// song, and a mistimed record scrolls out of sync.
func musicLyricsMatch(c lrclibTrack, title, artist string, length float64) bool {
	if c.Instrumental {
		return false
	}
	if c.SyncedLyrics == "" && strings.TrimSpace(c.PlainLyrics) == "" {
		return false
	}
	if !musicTermsOverlap(title, c.TrackName) {
		return false
	}
	if artist != "" && c.ArtistName != "" && !musicTermsOverlap(artist, c.ArtistName) {
		return false
	}
	if length > 0 && c.Duration > 0 && math.Abs(length-c.Duration) > 10 {
		return false
	}
	return true
}

// musicLyricsScore ranks kept candidates: synced beats plain, and a closer
// duration beats a looser one.
func musicLyricsScore(c lrclibTrack, length float64) float64 {
	score := 0.0
	if c.SyncedLyrics != "" {
		score += 100
	}
	if length > 0 && c.Duration > 0 {
		score += 10 - math.Min(10, math.Abs(length-c.Duration))
	}
	return score
}

// musicTermsOverlap compares two loose names: either contains the other, or
// they share a significant word. Punctuation and case are ignored.
func musicTermsOverlap(want, got string) bool {
	a := musicNormalize(want)
	b := musicNormalize(got)
	if a == "" || b == "" {
		return false
	}
	if strings.Contains(a, b) || strings.Contains(b, a) {
		return true
	}
	seen := map[string]bool{}
	for _, w := range strings.Fields(a) {
		if len(w) > 3 {
			seen[w] = true
		}
	}
	for _, w := range strings.Fields(b) {
		if seen[w] {
			return true
		}
	}
	return false
}

var musicPunct = regexp.MustCompile(`[^\p{L}\p{N}\s]+`)

// musicNormalize lowercases and strips punctuation, so "Don't Stop!" and
// "dont stop" compare equal.
func musicNormalize(s string) string {
	return strings.Join(strings.Fields(musicPunct.ReplaceAllString(strings.ToLower(s), " ")), " ")
}

var (
	// Bracketed decorations a video title carries and a lyrics database does
	// not: "(Official Video)", "[Lyrics]", "(Audio)", "(4K Remaster)".
	musicBrackets = regexp.MustCompile(`(?i)[\(\[][^\)\]]*(official|lyric|audio|video|visuali[sz]er|remaster|explicit|hd|hq|4k|mv|m/v|full album|live session)[^\)\]]*[\)\]]`)
	// Trailing decorations without brackets, after a dash or pipe.
	musicTrailers  = regexp.MustCompile(`(?i)\s*[-|·]\s*(official\s+)?(music\s+)?(video|audio|lyrics?|visuali[sz]er|hd|hq|4k)\s*$`)
	musicFeatures  = regexp.MustCompile(`(?i)\s*[\(\[]?\s*(feat\.?|ft\.?|featuring)\s+[^\)\]]*[\)\]]?\s*$`)
	musicLRCStamp  = regexp.MustCompile(`\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]`)
	musicYouTubeID = regexp.MustCompile(
		`(?:youtube\.com/(?:watch\?(?:[^&]*&)*v=|live/|shorts/|embed/)|youtu\.be/)([A-Za-z0-9_-]{11})`)
	musicSpotifyArt = regexp.MustCompile(`^(https://i\.scdn\.co/image/ab67616d)[0-9a-f]{8}([0-9a-f]+)$`)
	musicYtImg      = regexp.MustCompile(`^https?://i\d?\.ytimg\.com/vi(?:_webp)?/([A-Za-z0-9_-]{11})/`)
	musicGoogleArt  = regexp.MustCompile(`^(https://[a-z0-9]+\.googleusercontent\.com/[^=]+)=.*$`)
	musicTopic      = regexp.MustCompile(`(?i)\s*-\s*topic\s*$`)
)

// musicSearchTerms turns player metadata into the title and artist a lyrics
// database recognises. Browsers publish a video title where a music player
// publishes a track: "Nothing But Thieves - Afterlife (Official Video)" with an
// empty or channel artist becomes "Afterlife" by "Nothing But Thieves".
func musicSearchTerms(t musicTrack) (string, string) {
	title := strings.TrimSpace(t.Title)
	artist := musicTopic.ReplaceAllString(strings.TrimSpace(t.Artist), "")
	title = musicBrackets.ReplaceAllString(title, " ")
	title = musicTrailers.ReplaceAllString(title, "")
	title = strings.TrimSpace(strings.Join(strings.Fields(title), " "))
	title = strings.Trim(title, "-|· ")

	// A "Artist - Title" video title splits only when the artist is unknown or
	// is that same leading name, so a real track called "Song - Live" survives.
	if parts := strings.SplitN(title, " - ", 2); len(parts) == 2 {
		lead := strings.TrimSpace(parts[0])
		rest := strings.TrimSpace(parts[1])
		if rest != "" && (artist == "" || musicNormalize(artist) == musicNormalize(lead)) {
			artist = lead
			title = rest
		}
	}
	title = strings.TrimSpace(musicFeatures.ReplaceAllString(title, ""))
	artist = strings.TrimSpace(musicFeatures.ReplaceAllString(artist, ""))
	// A collaboration credit reaches the database as its first artist.
	for _, sep := range []string{", ", " & ", " x ", " X ", " / ", "; "} {
		if i := strings.Index(artist, sep); i > 0 {
			artist = strings.TrimSpace(artist[:i])
			break
		}
	}
	return title, artist
}

// musicSourceOf names the service behind a player, from its bus name and the
// page URL browsers publish.
func musicSourceOf(t musicTrack) string {
	player := strings.ToLower(t.Player)
	link := strings.ToLower(t.URL)
	switch {
	case strings.Contains(player, "spotify"):
		return musSrcSpotify
	case strings.Contains(player, "sidra"), strings.Contains(player, "cider"),
		strings.Contains(link, "music.apple.com"):
		return musSrcAppleMusic
	case strings.Contains(link, "music.youtube.com"), strings.Contains(player, "ytmusic"),
		strings.Contains(player, "youtube_music"), strings.Contains(player, "youtubemusic"):
		return musSrcYtMusic
	case strings.Contains(link, "youtube.com"), strings.Contains(link, "youtu.be"):
		return musSrcYouTube
	case strings.HasPrefix(link, "file://"):
		return musSrcLocal
	case musicIsBrowser(player):
		return musSrcBrowser
	}
	return musSrcOther
}

func musicIsBrowser(player string) bool {
	for _, name := range []string{"firefox", "chrome", "chromium", "brave", "vivaldi",
		"opera", "zen", "edge", "epiphany", "plasma-browser-integration"} {
		if strings.Contains(player, name) {
			return true
		}
	}
	return false
}

// musicArtCandidates lists cover URLs for a track, best first. A player's own
// art URL is rewritten to its full-size variant, and a YouTube page URL yields
// the video's thumbnails even when the player published no art at all (mpv and
// some browser integrations never do).
func musicArtCandidates(t musicTrack) []string {
	out := []string{}
	seen := map[string]bool{}
	add := func(u string) {
		if u == "" || seen[u] {
			return
		}
		seen[u] = true
		out = append(out, u)
	}
	for _, u := range musicUpgradeArt(strings.TrimSpace(t.ArtURL)) {
		add(u)
	}
	if id := musicYouTubeIDOf(t); id != "" {
		for _, name := range []string{"maxresdefault", "sddefault", "hqdefault"} {
			add("https://i.ytimg.com/vi/" + id + "/" + name + ".jpg")
		}
	}
	return out
}

// musicYouTubeIDOf finds the video id in the page URL, or in a thumbnail URL
// the player did publish.
func musicYouTubeIDOf(t musicTrack) string {
	if m := musicYouTubeID.FindStringSubmatch(t.URL); m != nil {
		return m[1]
	}
	if m := musicYtImg.FindStringSubmatch(t.ArtURL); m != nil {
		return m[1]
	}
	return ""
}

// musicUpgradeArt rewrites a known art URL to its largest variant, keeping the
// original as the fallback. Spotify serves one image id at three sizes and
// clients publish whichever they cached; Google (YouTube Music, YouTube) sizes
// through a URL suffix; a YouTube thumbnail has a fixed ladder of names.
func musicUpgradeArt(raw string) []string {
	if raw == "" {
		return nil
	}
	if strings.HasPrefix(raw, "file://") || strings.HasPrefix(raw, "/") {
		return []string{raw}
	}
	if strings.HasPrefix(raw, "https://open.spotify.com/image/") {
		raw = "https://i.scdn.co/image/" + strings.TrimPrefix(raw, "https://open.spotify.com/image/")
	}
	if m := musicSpotifyArt.FindStringSubmatch(raw); m != nil {
		// ab67616d0000b273 is the 640 px rendition of the same image id.
		full := m[1] + "0000b273" + m[2]
		if full != raw {
			return []string{full, raw}
		}
		return []string{raw}
	}
	if m := musicYtImg.FindStringSubmatch(raw); m != nil {
		id := m[1]
		return []string{
			"https://i.ytimg.com/vi/" + id + "/maxresdefault.jpg",
			"https://i.ytimg.com/vi/" + id + "/sddefault.jpg",
			"https://i.ytimg.com/vi/" + id + "/hqdefault.jpg",
			raw,
		}
	}
	if m := musicGoogleArt.FindStringSubmatch(raw); m != nil {
		return []string{m[1] + "=w1000-h1000-l90-rj", raw}
	}
	return []string{raw}
}

// musicLocalArt turns a local art URL into a path QML can load directly, so an
// embedded cover a player already extracted is never copied or re-downloaded.
func musicLocalArt(raw string) (string, bool) {
	path := ""
	switch {
	case strings.HasPrefix(raw, "file://"):
		if u, err := url.Parse(raw); err == nil {
			path = u.Path
		}
	case strings.HasPrefix(raw, "/"):
		path = raw
	default:
		return "", false
	}
	if path == "" {
		return "", false
	}
	if info, err := os.Stat(path); err != nil || info.IsDir() || info.Size() < musMinArtBytes {
		return "", false
	}
	return path, true
}

// cacheArt downloads a cover into the cache and returns its path. A cover
// already cached is reused, so a replayed track costs no request.
func (s *musicState) cacheArt(remote string) (string, error) {
	dir := filepath.Join(s.dir, "art")
	path := filepath.Join(dir, musicHash(remote)+musicArtExt(remote))
	if info, err := os.Stat(path); err == nil && info.Size() >= musMinArtBytes {
		return path, nil
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(context.Background(), musHTTPTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, remote, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", musUserAgent)
	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("cover status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, musMaxArtBytes))
	if err != nil {
		return "", err
	}
	if len(body) < musMinArtBytes || !musicIsImage(body) {
		return "", fmt.Errorf("cover is not an image")
	}
	tmp := path + ".part"
	if err := os.WriteFile(tmp, body, 0o644); err != nil {
		return "", err
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return "", err
	}
	return path, nil
}

// musicIsImage sniffs the magic bytes: YouTube answers a missing thumbnail size
// with a 404 page, and a proxy can answer with HTML, both of which would cache
// as a broken cover.
func musicIsImage(body []byte) bool {
	switch {
	case len(body) > 3 && body[0] == 0xff && body[1] == 0xd8 && body[2] == 0xff:
		return true // jpeg
	case len(body) > 8 && string(body[:8]) == "\x89PNG\r\n\x1a\n":
		return true
	case len(body) > 12 && string(body[:4]) == "RIFF" && string(body[8:12]) == "WEBP":
		return true
	case len(body) > 6 && string(body[:6]) == "GIF89a":
		return true
	}
	return false
}

func musicArtExt(remote string) string {
	clean := strings.ToLower(remote)
	if i := strings.IndexAny(clean, "?#"); i >= 0 {
		clean = clean[:i]
	}
	for _, ext := range []string{".png", ".webp", ".jpeg", ".jpg", ".gif"} {
		if strings.HasSuffix(clean, ext) {
			return ext
		}
	}
	return ".jpg"
}

// deezerCover looks a cover up by album, else by track: Deezer's keyless search
// carries a 1000 px rendition.
func (s *musicState) deezerCover(t musicTrack) (string, error) {
	title, artist := musicSearchTerms(t)
	q := url.Values{}
	q.Set("q", musicCatalogQuery(title, artist, t.Album))
	q.Set("limit", "1")
	var resp struct {
		Data []struct {
			Album struct {
				CoverXL  string `json:"cover_xl"`
				CoverBig string `json:"cover_big"`
			} `json:"album"`
		} `json:"data"`
	}
	if err := s.getJSON(musDeezerURL+"?"+q.Encode(), &resp); err != nil {
		return "", err
	}
	if len(resp.Data) == 0 {
		return "", nil
	}
	if resp.Data[0].Album.CoverXL != "" {
		return resp.Data[0].Album.CoverXL, nil
	}
	return resp.Data[0].Album.CoverBig, nil
}

// itunesCover is the second catalogue. Its search returns a 100 px thumbnail
// whose path scales to any size, so ask for 1000.
func (s *musicState) itunesCover(t musicTrack) (string, error) {
	title, artist := musicSearchTerms(t)
	q := url.Values{}
	q.Set("term", musicCatalogQuery(title, artist, ""))
	q.Set("media", "music")
	q.Set("limit", "1")
	var resp struct {
		Results []struct {
			ArtworkURL100 string `json:"artworkUrl100"`
		} `json:"results"`
	}
	if err := s.getJSON(musITunesURL+"?"+q.Encode(), &resp); err != nil {
		return "", err
	}
	if len(resp.Results) == 0 {
		return "", nil
	}
	return musicITunesFullSize(resp.Results[0].ArtworkURL100), nil
}

func musicITunesFullSize(raw string) string {
	if raw == "" {
		return ""
	}
	return strings.Replace(raw, "/100x100bb.", "/1000x1000bb.", 1)
}

// musicCatalogQuery is the phrase a cover catalogue is searched with: the album
// names the cover exactly, the track only approximately.
func musicCatalogQuery(title, artist, album string) string {
	parts := []string{}
	if artist != "" {
		parts = append(parts, artist)
	}
	if album != "" {
		parts = append(parts, album)
	} else if title != "" {
		parts = append(parts, title)
	}
	return strings.Join(parts, " ")
}

func (s *musicState) getJSON(rawURL string, out any) error {
	ctx, cancel := context.WithTimeout(context.Background(), musHTTPTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", musUserAgent)
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return fmt.Errorf("not found")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("provider status %d", resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(out)
}

// musicParseLRC turns an LRC document into sorted timed lines. A line can carry
// several timestamps (a repeated chorus), which each become their own entry; an
// empty line keeps its stamp so the sheet holds a pause instead of jumping.
func musicParseLRC(lrc string) []musicLine {
	out := []musicLine{}
	for _, raw := range strings.Split(lrc, "\n") {
		stamps := musicLRCStamp.FindAllStringSubmatchIndex(raw, -1)
		if len(stamps) == 0 {
			continue
		}
		text := strings.TrimSpace(raw[stamps[len(stamps)-1][1]:])
		for _, s := range stamps {
			minutes, err := strconv.Atoi(raw[s[2]:s[3]])
			if err != nil {
				continue
			}
			seconds, err := strconv.ParseFloat(strings.Replace(raw[s[4]:s[5]], ":", ".", 1), 64)
			if err != nil {
				continue
			}
			out = append(out, musicLine{
				T:    math.Round((float64(minutes)*60+seconds)*1000) / 1000,
				Text: text,
			})
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].T < out[j].T })
	return out
}

// musicPlainLines splits unsynced lyrics into display lines, collapsing runs of
// blank lines to a single break.
func musicPlainLines(text string) []string {
	out := []string{}
	blank := false
	for _, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" {
			if blank || len(out) == 0 {
				continue
			}
			blank = true
			out = append(out, "")
			continue
		}
		blank = false
		out = append(out, line)
	}
	for len(out) > 0 && out[len(out)-1] == "" {
		out = out[:len(out)-1]
	}
	return out
}

// musicTrackKey identifies one playing track. The art URL is part of it because
// a player can reuse a title across two recordings, and dropping it would keep
// the previous cover.
func musicTrackKey(t musicTrack) string {
	return musicHash(strings.Join([]string{
		strings.TrimSpace(t.Title),
		strings.TrimSpace(t.Artist),
		strings.TrimSpace(t.Album),
		strings.TrimSpace(t.ArtURL),
		strconv.Itoa(int(math.Round(t.Length))),
	}, "\x1f"))
}

func musicLyricsCacheName(title, artist, album string, length float64) string {
	return musicHash(strings.Join([]string{
		musicNormalize(title),
		musicNormalize(artist),
		musicNormalize(album),
		strconv.Itoa(int(math.Round(length))),
	}, "\x1f")) + ".json"
}

func musicHash(s string) string {
	sum := sha1.Sum([]byte(s))
	return hex.EncodeToString(sum[:])
}

// musicLyricsCache is the on-disk shape. A miss ("none") is cached too, so a
// track with no lyrics anywhere is asked for once per session rather than on
// every replay.
type musicLyricsCache struct {
	Status string      `json:"status"`
	Lines  []musicLine `json:"lines"`
	Plain  []string    `json:"plain"`
	At     int64       `json:"at"`
}

// A negative result is retried after a week: LRCLIB grows, and a track missing
// today may be transcribed tomorrow.
const musicMissTTL = 7 * 24 * time.Hour

func musicReadLyricsCache(path string) ([]musicLine, []string, string, bool) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, "", false
	}
	var c musicLyricsCache
	if json.Unmarshal(raw, &c) != nil {
		return nil, nil, "", false
	}
	switch c.Status {
	case musOK, musPlain:
		return c.Lines, c.Plain, c.Status, true
	case musNone:
		if time.Since(time.Unix(c.At, 0)) < musicMissTTL {
			return nil, nil, musNone, true
		}
	}
	return nil, nil, "", false
}

func musicWriteLyricsCache(path string, lines []musicLine, plain []string, status string) {
	if status != musOK && status != musPlain && status != musNone {
		return
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	body, err := json.Marshal(musicLyricsCache{Status: status, Lines: lines, Plain: plain, At: time.Now().Unix()})
	if err != nil {
		return
	}
	tmp := path + ".part"
	if os.WriteFile(tmp, body, 0o644) != nil {
		return
	}
	if os.Rename(tmp, path) != nil {
		_ = os.Remove(tmp)
	}
}
