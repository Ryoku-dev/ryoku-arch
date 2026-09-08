package updater

import (
	"reflect"
	"testing"
)

// The set decides what `ryoku update` is allowed to touch, so every property
// here is load-bearing: only packages the [ryoku] repo serves, only ones the
// box actually has, and every target repo-qualified so pacman resolves it from
// our repo even for a name that also exists in core/extra (an unqualified
// target would silently install the Arch build, or fail to downgrade onto a
// frozen release).
func TestRyokuSet(t *testing.T) {
	for _, c := range []struct {
		name            string
		repo, installed []string
		want            []string
	}{
		{
			name:      "installed and served, repo-qualified and sorted",
			repo:      []string{"ryoku-shell", "ryoku-desktop", "ryotunes"},
			installed: []string{"linux", "ryoku-desktop", "ryoku-shell", "firefox"},
			want:      []string{"ryoku/ryoku-desktop", "ryoku/ryoku-shell"},
		},
		{
			name:      "a package the repo serves but the box lacks is not installed by an update",
			repo:      []string{"ryoku-desktop", "asusctl"},
			installed: []string{"ryoku-desktop"},
			want:      []string{"ryoku/ryoku-desktop"},
		},
		{
			name:      "a kernel is never in the set, because the repo never serves one",
			repo:      []string{"ryoku-desktop"},
			installed: []string{"linux", "linux-cachyos", "linux-firmware", "ryoku-desktop"},
			want:      []string{"ryoku/ryoku-desktop"},
		},
		{
			name:      "nothing served: empty, never a bare pacman target",
			repo:      nil,
			installed: []string{"ryoku-desktop"},
			want:      []string{},
		},
		{
			name:      "duplicate repo lines collapse",
			repo:      []string{"ryoku-desktop", "ryoku-desktop"},
			installed: []string{"ryoku-desktop"},
			want:      []string{"ryoku/ryoku-desktop"},
		},
		{
			name:      "an external-release package the repo serves is never in the update set (no downgrade of a newer external build)",
			repo:      []string{"ryoku-desktop", "ryotunes"},
			installed: []string{"ryoku-desktop", "ryotunes"},
			want:      []string{"ryoku/ryoku-desktop"},
		},
	} {
		t.Run(c.name, func(t *testing.T) {
			got := ryokuSet(c.repo, c.installed)
			if !reflect.DeepEqual(got, c.want) {
				t.Errorf("ryokuSet = %v, want %v", got, c.want)
			}
		})
	}
}
