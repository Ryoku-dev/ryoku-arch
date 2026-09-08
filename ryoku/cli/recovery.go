package main

import (
	"fmt"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
)

// where the recovery script lives on the channel, for boxes that have no local
// checkout to run it from (a packaged install that lost its desktop).
const recoveryURL = "https://raw.githubusercontent.com/ryoku-dev/ryoku-arch/main/bin/ryoku-recovery"

// cmdRecovery hands off to bin/ryoku-recovery: prefer the copy in a local
// checkout, otherwise fetch the canonical one. The script does the real work and
// does not lean on this binary, so it still recovers when the build is broken.
func cmdRecovery(args []string) error {
	if repo := sys.ResolveRepo(); repo != "" {
		if script := filepath.Join(repo, "bin", "ryoku-recovery"); sys.Exists(script) {
			return sys.Run("bash", append([]string{script}, args...)...)
		}
	}

	if !sys.Has("curl") {
		return fmt.Errorf("no local recovery script and curl is missing; run it by hand:\n  curl -fsSL %s | bash", recoveryURL)
	}
	tmp, err := os.CreateTemp("", "ryoku-recovery-*.sh")
	if err != nil {
		return err
	}
	tmp.Close()
	defer os.Remove(tmp.Name())
	if err := sys.Run("curl", "-fsSL", recoveryURL, "-o", tmp.Name()); err != nil {
		return fmt.Errorf("fetch recovery script from %s: %w", recoveryURL, err)
	}
	return sys.Run("bash", append([]string{tmp.Name()}, args...)...)
}
