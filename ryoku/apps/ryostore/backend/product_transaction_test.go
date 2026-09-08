package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type transactionFixture struct {
	cache   *Cache
	entry   ProductEntry
	content []byte
}

func newTransactionFixture(t *testing.T, version string, declared, served []byte) transactionFixture {
	t.Helper()
	fileHash := fmt.Sprintf("%x", sha256.Sum256(declared))
	runtimeManifest := []byte(fmt.Sprintf(`{"id":"demo","version":%q}`, version))
	runtimeHash := fmt.Sprintf("%x", sha256.Sum256(runtimeManifest))
	manifest := ProductManifest{
		Schema:      1,
		ID:          "demo",
		Category:    "plugins",
		Version:     version,
		Destination: "ryoku/plugins/demo",
		Files: []ProductFile{
			{
				Source:      "content/Plugin.qml",
				Destination: "content/Plugin.qml",
				Mode:        "0644",
				Size:        int64(len(declared)),
				SHA256:      fileHash,
				Install:     true,
			},
			{
				Source:      "manifest.json",
				Destination: "manifest.json",
				Mode:        "0644",
				Size:        int64(len(runtimeManifest)),
				SHA256:      runtimeHash,
				Install:     true,
			},
			{
				Source:      "assets/preview.png",
				Destination: "assets/preview.png",
				Mode:        "0644",
				Size:        7,
				SHA256:      strings.Repeat("0", 64),
				Install:     false,
			},
		},
	}
	manifestRaw, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	entry := ProductEntry{
		ID:             "demo",
		Name:           "Demo",
		Version:        version,
		Path:           "plugins/demo",
		Author:         "Ryoku Team",
		Summary:        "Transaction fixture",
		Description:    "Transaction fixture product.",
		Tags:           []string{"fixture"},
		Accent:         "#cdc4ba",
		Surface:        "#101010",
		Screenshots:    []string{},
		Preview:        "assets/preview.png",
		Manifest:       "product-manifest.json",
		ManifestSHA256: fmt.Sprintf("%x", sha256.Sum256(manifestRaw)),
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/plugins/demo/product-manifest.json":
			_, _ = w.Write(manifestRaw)
		case "/plugins/demo/content/Plugin.qml":
			_, _ = w.Write(served)
		case "/plugins/demo/manifest.json":
			_, _ = w.Write(runtimeManifest)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(server.Close)
	return transactionFixture{
		cache: &Cache{
			client: server.Client(),
			base:   server.URL,
			dir:    t.TempDir(),
			memo:   map[string]memoEntry{},
		},
		entry:   entry,
		content: declared,
	}
}

func installedPluginPath() string {
	return filepath.Join(dataHome(), "ryoku", "plugins", "demo")
}

func TestProductTransactionLifecycle(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()

	first := newTransactionFixture(t, "1.0.0", []byte("version one\n"), []byte("version one\n"))
	staleStage := filepath.Join(filepath.Dir(installedPluginPath()), ".ryostore-stage-demo-interrupted")
	if err := os.MkdirAll(staleStage, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := installProduct(ctx, first.cache, "plugins", first.entry); err != nil {
		t.Fatalf("initial install: %v", err)
	}
	if _, err := os.Stat(staleStage); !os.IsNotExist(err) {
		t.Fatalf("interrupted stage remains: %v", err)
	}
	installedFile := filepath.Join(installedPluginPath(), "content", "Plugin.qml")
	if raw, err := os.ReadFile(installedFile); err != nil || string(raw) != "version one\n" {
		t.Fatalf("installed file = %q, err=%v", raw, err)
	}
	if mode, err := os.Stat(installedFile); err != nil || mode.Mode().Perm() != 0o644 {
		t.Fatalf("installed mode = %v, err=%v", mode, err)
	}
	receipt, err := readReceipt("plugins", "demo")
	if err != nil {
		t.Fatal(err)
	}
	if receipt.Version != "1.0.0" || len(receipt.Files) != 2 || receipt.Files[0].Destination != "content/Plugin.qml" || receipt.Files[1].Destination != "manifest.json" {
		t.Fatalf("initial receipt = %#v", receipt)
	}
	if revision := readRevisionForTest(t); revision.Revision != 1 || revision.Operation != "install" {
		t.Fatalf("initial revision = %#v", revision)
	}

	reinstall := newTransactionFixture(t, "1.0.0", []byte("replacement\n"), []byte("replacement\n"))
	if err := installProduct(ctx, reinstall.cache, "plugins", reinstall.entry); err != nil {
		t.Fatalf("identical-version replacement: %v", err)
	}
	if raw, _ := os.ReadFile(installedFile); string(raw) != "replacement\n" {
		t.Fatalf("replacement file = %q", raw)
	}
	if revision := readRevisionForTest(t); revision.Revision != 2 || revision.Operation != "update" || revision.Version != "1.0.0" {
		t.Fatalf("replacement revision = %#v", revision)
	}

	update := newTransactionFixture(t, "2.0.0", []byte("version two\n"), []byte("version two\n"))
	if err := installProduct(ctx, update.cache, "plugins", update.entry); err != nil {
		t.Fatalf("version update: %v", err)
	}
	if raw, _ := os.ReadFile(installedFile); string(raw) != "version two\n" {
		t.Fatalf("updated file = %q", raw)
	}
	if receipt, err = readReceipt("plugins", "demo"); err != nil || receipt.Version != "2.0.0" {
		t.Fatalf("updated receipt = %#v, err=%v", receipt, err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 3 || revision.Operation != "update" || revision.Version != "2.0.0" {
		t.Fatalf("update revision = %#v", revision)
	}

	unrelated := filepath.Join(installedPluginPath(), "notes.txt")
	if err := os.WriteFile(unrelated, []byte("keep\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := removeProduct(ctx, "plugins", "demo"); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if _, err := os.Stat(installedFile); !os.IsNotExist(err) {
		t.Fatalf("owned file remains: %v", err)
	}
	if raw, err := os.ReadFile(unrelated); err != nil || string(raw) != "keep\n" {
		t.Fatalf("unrelated file = %q, err=%v", raw, err)
	}
	if _, err := readReceipt("plugins", "demo"); !os.IsNotExist(err) {
		t.Fatalf("receipt remains: %v", err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 4 || revision.Operation != "remove" || revision.Version != "2.0.0" {
		t.Fatalf("remove revision = %#v", revision)
	}
}

func TestProductTransactionHashFailureRollsBack(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	first := newTransactionFixture(t, "1.0.0", []byte("known good!!\n"), []byte("known good!!\n"))
	if err := installProduct(ctx, first.cache, "plugins", first.entry); err != nil {
		t.Fatal(err)
	}
	bad := newTransactionFixture(t, "2.0.0", []byte("version two!\n"), []byte("tampered two\n"))
	cachedPayload := filepath.Join(bad.cache.dir, "plugins", "demo", "content", "Plugin.qml")
	if err := os.MkdirAll(filepath.Dir(cachedPayload), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cachedPayload, []byte("version two!\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := installProduct(ctx, bad.cache, "plugins", bad.entry); err == nil || !strings.Contains(err.Error(), "hash") {
		t.Fatalf("bad update error = %v, want hash failure", err)
	}
	installedFile := filepath.Join(installedPluginPath(), "content", "Plugin.qml")
	if raw, err := os.ReadFile(installedFile); err != nil || string(raw) != "known good!!\n" {
		t.Fatalf("prior file after failed update = %q, err=%v", raw, err)
	}
	receipt, err := readReceipt("plugins", "demo")
	if err != nil || receipt.Version != "1.0.0" {
		t.Fatalf("receipt after failed update = %#v, err=%v", receipt, err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 1 || revision.Operation != "install" {
		t.Fatalf("revision advanced after failed update: %#v", revision)
	}
	if raw, err := os.ReadFile(cachedPayload); err != nil || string(raw) != "version two!\n" {
		t.Fatalf("valid payload cache was replaced by rejected bytes: %q, err=%v", raw, err)
	}
}

func TestProductTransactionRollsBackAfterPublication(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	first := newTransactionFixture(t, "1.0.0", []byte("version one\n"), []byte("version one\n"))
	if err := installProduct(ctx, first.cache, "plugins", first.entry); err != nil {
		t.Fatal(err)
	}
	previousCheckpoint := productTransactionCheckpoint
	productTransactionCheckpoint = func(phase string) error {
		if phase == "install-published" {
			return errors.New("injected publication failure")
		}
		return nil
	}
	defer func() { productTransactionCheckpoint = previousCheckpoint }()
	update := newTransactionFixture(t, "2.0.0", []byte("version two\n"), []byte("version two\n"))
	if err := installProduct(ctx, update.cache, "plugins", update.entry); err == nil {
		t.Fatal("installProduct accepted injected post-publication failure")
	}
	installed := filepath.Join(installedPluginPath(), "content", "Plugin.qml")
	if raw, err := os.ReadFile(installed); err != nil || string(raw) != "version one\n" {
		t.Fatalf("published failure did not restore prior file: %q, err=%v", raw, err)
	}
	receipt, err := readReceipt("plugins", "demo")
	if err != nil || receipt.Version != "1.0.0" {
		t.Fatalf("published failure did not restore receipt: %#v, err=%v", receipt, err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 1 {
		t.Fatalf("published failure advanced revision: %#v", revision)
	}
}
func TestProductTransactionRollsBackAfterReceiptPublication(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	first := newTransactionFixture(t, "1.0.0", []byte("version one\n"), []byte("version one\n"))
	if err := installProduct(ctx, first.cache, "plugins", first.entry); err != nil {
		t.Fatal(err)
	}
	previousCheckpoint := productTransactionCheckpoint
	productTransactionCheckpoint = func(phase string) error {
		if phase == "install-receipt" {
			return errors.New("injected receipt publication failure")
		}
		return nil
	}
	defer func() { productTransactionCheckpoint = previousCheckpoint }()
	update := newTransactionFixture(t, "2.0.0", []byte("version two\n"), []byte("version two\n"))
	if err := installProduct(ctx, update.cache, "plugins", update.entry); err == nil {
		t.Fatal("installProduct accepted injected post-receipt failure")
	}
	installed := filepath.Join(installedPluginPath(), "content", "Plugin.qml")
	if raw, err := os.ReadFile(installed); err != nil || string(raw) != "version one\n" {
		t.Fatalf("receipt failure did not restore prior file: %q, err=%v", raw, err)
	}
	receipt, err := readReceipt("plugins", "demo")
	if err != nil || receipt.Version != "1.0.0" {
		t.Fatalf("receipt failure did not restore prior receipt: %#v, err=%v", receipt, err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 1 {
		t.Fatalf("receipt failure advanced revision: %#v", revision)
	}
}

func TestProductTransactionRollsBackRevisionFailure(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	first := newTransactionFixture(t, "1.0.0", []byte("version one\n"), []byte("version one\n"))
	if err := installProduct(ctx, first.cache, "plugins", first.entry); err != nil {
		t.Fatal(err)
	}
	previousWriter := writeProductRevision
	writeProductRevision = func(StoreRevision) error { return errors.New("injected revision failure") }
	defer func() { writeProductRevision = previousWriter }()
	update := newTransactionFixture(t, "2.0.0", []byte("version two\n"), []byte("version two\n"))
	if err := installProduct(ctx, update.cache, "plugins", update.entry); err == nil {
		t.Fatal("installProduct accepted revision failure")
	}
	installed := filepath.Join(installedPluginPath(), "content", "Plugin.qml")
	if raw, err := os.ReadFile(installed); err != nil || string(raw) != "version one\n" {
		t.Fatalf("revision failure did not restore prior file: %q, err=%v", raw, err)
	}
	receipt, err := readReceipt("plugins", "demo")
	if err != nil || receipt.Version != "1.0.0" {
		t.Fatalf("revision failure did not restore prior receipt: %#v, err=%v", receipt, err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 1 {
		t.Fatalf("revision failure advanced revision: %#v", revision)
	}
}

func TestProductTransactionRecoversInterruptedPublication(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	fixture := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	previousCheckpoint := productTransactionCheckpoint
	interrupted := true
	productTransactionCheckpoint = func(phase string) error {
		if interrupted && phase == "install-published" {
			interrupted = false
			return errProductTransactionInterrupted
		}
		return nil
	}
	if err := installProduct(ctx, fixture.cache, "plugins", fixture.entry); !errors.Is(err, errProductTransactionInterrupted) {
		t.Fatalf("interrupted install error = %v", err)
	}
	productTransactionCheckpoint = previousCheckpoint
	defer func() { productTransactionCheckpoint = previousCheckpoint }()
	retry := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	if err := installProduct(ctx, retry.cache, "plugins", retry.entry); err != nil {
		t.Fatalf("retry after interruption: %v", err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 1 || revision.Operation != "install" {
		t.Fatalf("interrupted install committed more than once: %#v", revision)
	}
}

func TestProductTransactionRecoversInterruptedRemoval(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	fixture := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	if err := installProduct(ctx, fixture.cache, "plugins", fixture.entry); err != nil {
		t.Fatal(err)
	}
	previousCheckpoint := productTransactionCheckpoint
	productTransactionCheckpoint = func(phase string) error {
		if phase == "remove-files-moved" {
			return errProductTransactionInterrupted
		}
		return nil
	}
	if err := removeProduct(ctx, "plugins", "demo"); !errors.Is(err, errProductTransactionInterrupted) {
		t.Fatalf("interrupted removal error = %v", err)
	}
	productTransactionCheckpoint = previousCheckpoint
	defer func() { productTransactionCheckpoint = previousCheckpoint }()
	if err := removeProduct(ctx, "plugins", "demo"); err != nil {
		t.Fatalf("retry after interrupted removal: %v", err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 2 || revision.Operation != "remove" {
		t.Fatalf("interrupted removal committed incorrectly: %#v", revision)
	}
}
func TestProductTransactionReadyRecoveryUsesRevisionBaseline(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	for _, content := range []string{"version one\n", "version two\n"} {
		fixture := newTransactionFixture(t, "1.0.0", []byte(content), []byte(content))
		if err := installProduct(ctx, fixture.cache, "plugins", fixture.entry); err != nil {
			t.Fatal(err)
		}
	}
	previousCheckpoint := productTransactionCheckpoint
	productTransactionCheckpoint = func(phase string) error {
		if phase == "ready" {
			return errProductTransactionInterrupted
		}
		return nil
	}
	third := newTransactionFixture(t, "1.0.0", []byte("version three\n"), []byte("version three\n"))
	if err := installProduct(ctx, third.cache, "plugins", third.entry); !errors.Is(err, errProductTransactionInterrupted) {
		t.Fatalf("ready interruption error = %v", err)
	}
	productTransactionCheckpoint = previousCheckpoint
	defer func() { productTransactionCheckpoint = previousCheckpoint }()
	if err := recoverStoreTransactions(); err != nil {
		t.Fatal(err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 3 || revision.Operation != "update" {
		t.Fatalf("same-version ready recovery revision = %#v", revision)
	}
	installed := filepath.Join(installedPluginPath(), "content", "Plugin.qml")
	if raw, err := os.ReadFile(installed); err != nil || string(raw) != "version three\n" {
		t.Fatalf("ready recovery payload = %q, err=%v", raw, err)
	}
}

func TestProductTransactionRecoversInterruptedRollbackIntent(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	first := newTransactionFixture(t, "1.0.0", []byte("version one\n"), []byte("version one\n"))
	if err := installProduct(ctx, first.cache, "plugins", first.entry); err != nil {
		t.Fatal(err)
	}
	previousWriter := writeProductRevision
	previousCheckpoint := productTransactionCheckpoint
	writeProductRevision = func(StoreRevision) error { return errors.New("injected revision failure") }
	productTransactionCheckpoint = func(phase string) error {
		if phase == "install-rollback" {
			return errProductTransactionInterrupted
		}
		return nil
	}
	update := newTransactionFixture(t, "2.0.0", []byte("version two\n"), []byte("version two\n"))
	if err := installProduct(ctx, update.cache, "plugins", update.entry); !errors.Is(err, errProductTransactionInterrupted) {
		t.Fatalf("rollback interruption error = %v", err)
	}
	writeProductRevision = previousWriter
	productTransactionCheckpoint = previousCheckpoint
	defer func() {
		writeProductRevision = previousWriter
		productTransactionCheckpoint = previousCheckpoint
	}()
	if err := recoverStoreTransactions(); err != nil {
		t.Fatal(err)
	}
	installed := filepath.Join(installedPluginPath(), "content", "Plugin.qml")
	if raw, err := os.ReadFile(installed); err != nil || string(raw) != "version one\n" {
		t.Fatalf("rollback recovery payload = %q, err=%v", raw, err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 1 {
		t.Fatalf("rollback recovery advanced revision: %#v", revision)
	}
}

func TestProductTransactionScavengesJournalTempFiles(t *testing.T) {
	setTransactionXDG(t)
	temp := filepath.Join(storeTransactionsDir(), "plugins", ".tmp-orphan")
	if err := os.MkdirAll(filepath.Dir(temp), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(temp, []byte("partial"), 0o600); err != nil {
		t.Fatal(err)
	}
	fixture := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	if err := installProduct(context.Background(), fixture.cache, "plugins", fixture.entry); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(temp); !os.IsNotExist(err) {
		t.Fatalf("journal temp remains: %v", err)
	}
}

func TestProductTransactionRejectsNonRegularJournal(t *testing.T) {
	setTransactionXDG(t)
	shortState, err := os.MkdirTemp("", "rj")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(shortState) })
	t.Setenv("XDG_STATE_HOME", shortState)
	journal := filepath.Join(storeTransactionsDir(), "plugins", "demo.json")
	if err := os.MkdirAll(filepath.Dir(journal), 0o755); err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("unix", journal)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	if err := recoverStoreTransactions(); err == nil || !strings.Contains(err.Error(), "invalid Store transaction journal") {
		t.Fatalf("non-regular journal error = %v", err)
	}
}

func TestProductTransactionRejectsSymlinkInRemovalHold(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	fixture := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	if err := installProduct(ctx, fixture.cache, "plugins", fixture.entry); err != nil {
		t.Fatal(err)
	}
	previousCheckpoint := productTransactionCheckpoint
	productTransactionCheckpoint = func(phase string) error {
		if phase == "remove-files-moved" {
			return errProductTransactionInterrupted
		}
		return nil
	}
	if err := removeProduct(ctx, "plugins", "demo"); !errors.Is(err, errProductTransactionInterrupted) {
		t.Fatalf("removal interruption error = %v", err)
	}
	productTransactionCheckpoint = previousCheckpoint
	defer func() { productTransactionCheckpoint = previousCheckpoint }()
	hold := productRemovalHoldPath(installedPluginPath())
	if err := os.Rename(filepath.Join(hold, "content"), filepath.Join(hold, "held-content")); err != nil {
		t.Fatal(err)
	}
	trap := t.TempDir()
	if err := os.Symlink(trap, filepath.Join(hold, "content")); err != nil {
		t.Fatal(err)
	}
	if err := recoverStoreTransactions(); err == nil || !strings.Contains(err.Error(), "symlink") {
		t.Fatalf("removal recovery error = %v, want symlink refusal", err)
	}
	if entries, err := os.ReadDir(trap); err != nil || len(entries) != 0 {
		t.Fatalf("removal recovery mutated symlink target: %v, err=%v", entries, err)
	}
}

func TestLockscreenProductDestinationUsesDataHome(t *testing.T) {
	setTransactionXDG(t)
	destination, relative, err := productDestination("lockscreens", "demo")
	if err != nil {
		t.Fatal(err)
	}
	if relative != "qylock/themes/demo" {
		t.Fatalf("lockscreen relative destination = %q", relative)
	}
	want := filepath.Join(dataHome(), "qylock", "themes", "demo")
	if destination != want {
		t.Fatalf("lockscreen destination = %q, want %q", destination, want)
	}
}

func TestProductTransactionIgnoresPostCommitCleanupFailure(t *testing.T) {
	setTransactionXDG(t)
	ctx := context.Background()
	fixture := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	if err := installProduct(ctx, fixture.cache, "plugins", fixture.entry); err != nil {
		t.Fatal(err)
	}
	previousCleanup := removeProductArtifact
	removeProductArtifact = func(string) error { return errors.New("injected cleanup failure") }
	defer func() { removeProductArtifact = previousCleanup }()
	if err := removeProduct(ctx, "plugins", "demo"); err != nil {
		t.Fatalf("committed removal reported cleanup failure: %v", err)
	}
	if revision := readRevisionForTest(t); revision.Revision != 2 || revision.Operation != "remove" {
		t.Fatalf("cleanup failure prevented committed revision: %#v", revision)
	}
}

func TestProductTransactionRejectsSymlinkAncestorBeforeCleanup(t *testing.T) {
	setTransactionXDG(t)
	target := t.TempDir()
	ancestor := filepath.Join(dataHome(), "ryoku", "plugins")
	if err := os.MkdirAll(filepath.Dir(ancestor), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, ancestor); err != nil {
		t.Fatal(err)
	}
	trap := filepath.Join(target, ".ryostore-stage-demo-trap")
	if err := os.MkdirAll(trap, 0o755); err != nil {
		t.Fatal(err)
	}
	fixture := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	if err := installProduct(context.Background(), fixture.cache, "plugins", fixture.entry); err == nil || !strings.Contains(err.Error(), "symlink") {
		t.Fatalf("install error = %v, want symlink ancestor refusal", err)
	}
	if _, err := os.Stat(trap); err != nil {
		t.Fatalf("symlink target was mutated before refusal: %v", err)
	}
}

func TestProductTransactionRefusesUntrackedDestination(t *testing.T) {
	setTransactionXDG(t)
	if err := os.MkdirAll(installedPluginPath(), 0o755); err != nil {
		t.Fatal(err)
	}
	fixture := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	if err := installProduct(context.Background(), fixture.cache, "plugins", fixture.entry); err == nil || !strings.Contains(err.Error(), "untracked") {
		t.Fatalf("install error = %v, want untracked destination refusal", err)
	}
}

func TestProductTransactionAdoptsManifestDestination(t *testing.T) {
	setTransactionXDG(t)
	if err := os.MkdirAll(installedPluginPath(), 0o755); err != nil {
		t.Fatal(err)
	}
	// A pre-receipt install: the directory carries a product manifest but has no
	// receipt (installed before receipts existed). Installing must adopt it and
	// write a receipt, not refuse it as an untracked destination.
	if err := os.WriteFile(filepath.Join(installedPluginPath(), "manifest.json"), []byte("{\"id\":\"demo\"}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	fixture := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	if err := installProduct(context.Background(), fixture.cache, "plugins", fixture.entry); err != nil {
		t.Fatalf("adopt install failed: %v", err)
	}
	if _, err := readReceipt("plugins", "demo"); err != nil {
		t.Fatalf("adopt did not write a receipt: %v", err)
	}
}

func TestProductTransactionRefusesSymlink(t *testing.T) {
	setTransactionXDG(t)
	if err := os.MkdirAll(filepath.Dir(installedPluginPath()), 0o755); err != nil {
		t.Fatal(err)
	}
	target := t.TempDir()
	if err := os.Symlink(target, installedPluginPath()); err != nil {
		t.Fatal(err)
	}
	fixture := newTransactionFixture(t, "1.0.0", []byte("content\n"), []byte("content\n"))
	if err := installProduct(context.Background(), fixture.cache, "plugins", fixture.entry); err == nil || !strings.Contains(err.Error(), "symlink") {
		t.Fatalf("install error = %v, want symlink refusal", err)
	}
}

type removeDispatchProvider struct {
	removed string
}

func (removeDispatchProvider) Category() Category {
	return Category{ID: "plugins"}
}
func (removeDispatchProvider) Load(context.Context, bool) ([]Item, SourceState, error) {
	return nil, SourceState{}, nil
}
func (removeDispatchProvider) Install(context.Context, string) error { return nil }
func (provider *removeDispatchProvider) Remove(_ context.Context, id string) error {
	provider.removed = id
	return nil
}

func TestRemoveDispatch(t *testing.T) {
	provider := &removeDispatchProvider{}
	if err := runRemove([]Provider{provider}, []string{"plugins", "demo"}); err != nil {
		t.Fatal(err)
	}
	if provider.removed != "demo" {
		t.Fatalf("removed id = %q", provider.removed)
	}
	if err := runRemove([]Provider{provider}, []string{"unknown", "demo"}); err == nil {
		t.Fatal("runRemove accepted unknown category")
	}
	if err := runRemove([]Provider{provider}, []string{"plugins"}); err == nil {
		t.Fatal("runRemove accepted missing id")
	}
}

// Settings' REMOVE button calls `internal remove-guest plugins <id>`. A
// Store-installed plugin owns a receipt, so that call has to run the whole
// transaction: files, receipt, index row. Deleting only the directory left the
// Store badging a plugin INSTALLED that no longer existed, with its install
// button disabled, so it could never be recovered.
func TestRemoveGuestRetiresReceiptOwnedPlugin(t *testing.T) {
	setTransactionXDG(t)
	fixture := newTransactionFixture(t, "1.0.0", []byte("version one\n"), []byte("version one\n"))
	if err := installProduct(context.Background(), fixture.cache, "plugins", fixture.entry); err != nil {
		t.Fatalf("install: %v", err)
	}
	if _, err := readReceipt("plugins", "demo"); err != nil {
		t.Fatalf("receipt after install: %v", err)
	}

	if err := removeGuest("plugins", "demo"); err != nil {
		t.Fatalf("remove-guest: %v", err)
	}

	if _, err := os.Stat(installedPluginPath()); !os.IsNotExist(err) {
		t.Fatalf("plugin directory remains: %v", err)
	}
	if _, err := readReceipt("plugins", "demo"); !os.IsNotExist(err) {
		t.Fatalf("receipt remains: %v", err)
	}
	if revision := readRevisionForTest(t); revision.Operation != "remove" {
		t.Fatalf("revision = %#v", revision)
	}
}

// A dev plugin (RYOSTORE_PLUGINS_DIR, or a symlink into a checkout) has no
// receipt; remove-guest must still unlink it and must not fail looking for one.
func TestRemoveGuestUnlinksReceiptlessPlugin(t *testing.T) {
	setTransactionXDG(t)
	dir := pluginDataDir("demo")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "manifest.json"), []byte("{}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := removeGuest("plugins", "demo"); err != nil {
		t.Fatalf("remove-guest: %v", err)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatalf("plugin directory remains: %v", err)
	}
}
