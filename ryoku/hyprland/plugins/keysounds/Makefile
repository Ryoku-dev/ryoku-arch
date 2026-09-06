# keysounds: build the plugin against the installed Hyprland headers and lay the
# shipped sample profiles into sounds/. `make all` is what hyprpm.toml runs, on
# a checkout, a packaged box and in the [ryoku] build alike.
#
# The profiles are real switch recordings from the MIT-licensed Mechvibes
# repository, one profile per line of profiles.txt, cut into the plugin's
# layout by ryoku-keysounds-import (the same tool a user runs on any pack).
# MECHVIBES names a checkout of that repository; unset, one is cloned at the
# pinned commit. IMPORTER names the importer; unset, the installed one on PATH,
# else the repo copy beside this plugin.

ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wall

MECHVIBES_URL    = https://github.com/hainguyents13/mechvibes.git
MECHVIBES_COMMIT = 326252a13e7bef4f1c35d08ef0189b5af6f8ba02
MECHVIBES ?= $(or $(XDG_CACHE_HOME),$(HOME)/.cache)/ryoku/mechvibes
IMPORTER ?= $(shell command -v ryoku-keysounds-import 2>/dev/null || echo $(CURDIR)/../../scripts/ryoku-keysounds-import)

all: keysounds.so sounds

keysounds.so: main.cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) main.cpp -o keysounds.so `pkg-config --cflags --libs hyprland pixman-1 libdrm libcanberra`

$(MECHVIBES)/src/audio:
	git init -q "$(MECHVIBES)"
	git -C "$(MECHVIBES)" fetch -q --depth 1 "$(MECHVIBES_URL)" "$(MECHVIBES_COMMIT)"
	git -C "$(MECHVIBES)" checkout -q FETCH_HEAD

sounds: profiles.txt $(MECHVIBES)/src/audio
	rm -rf sounds
	grep -vE '^[[:space:]]*(#|$$)' profiles.txt | while read -r name pack; do \
	  "$(IMPORTER)" "$(MECHVIBES)/src/audio/$$pack" --name "$$name" --to sounds || exit 1; \
	done
	cp "$(MECHVIBES)/LICENSE" sounds/LICENSE.mechvibes

clean:
	rm -rf keysounds.so sounds

.PHONY: all clean
