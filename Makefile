# pso-ios: Phantasy Star Online Episode I & II Plus (GameCube, GPOE8P v1.02)
# static recompilation, built on DolRecomp + ModernGekko.
#
#   make tools                    Build DolRecomp and ModernGekko
#   make extract DISC=path        Extract your disc (ISO or CISO) into extracted/pso
#   make recompile                Recompile PsoV3.dol and build the native module
#   make run                      Recompile if needed and launch the game
#   make names                    Write build/pso.map (decomp function names)

DOLRECOMP_DIR     := lib/DolRecomp
MODERNGEKKO_DIR   := lib/ModernGekko
DECOMP_DIR        := lib/pso-decomp
DOLRECOMP_BUILD   := $(DOLRECOMP_DIR)/build
MODERNGEKKO_BUILD := $(MODERNGEKKO_DIR)/build
DOLRECOMP_BIN     := $(DOLRECOMP_BUILD)/dolrecomp
PORT_BIN          := $(MODERNGEKKO_BUILD)/moderngekko-port

GAME_DIR    := extracted/pso
MODULES_DIR := build/modules
MAP_FILE    := build/pso.map

# Expected hashes: the DOL is what matters (CISO drops the disc's padding,
# so a converted ISO never matches the full-dump hash).
GAME_ID    := GPOE8P
PSOV3_SHA1 := 0d85744b51d7379efb025a943d0cd5aaae2191a3

JOBS ?= $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
CMAKE_BUILD_TYPE ?= Release
BACKEND   ?= c
TOOLCHAIN ?= auto
USER_DIR  := $(CURDIR)/build/user
RUN_ARGS  ?=
PATCHES   := $(wildcard patches/moderngekko-*.patch)

.DEFAULT_GOAL := help
.PHONY: help tools dolrecomp moderngekko patch-moderngekko user-config submodules extract recompile run names clean clean-game

help:
	@sed -n '4,9p' Makefile | sed 's/^# //'

submodules:
	@if [ ! -f "$(DOLRECOMP_DIR)/CMakeLists.txt" ] || [ ! -f "$(MODERNGEKKO_DIR)/CMakeLists.txt" ] || \
	    [ ! -f "$(DECOMP_DIR)/configure.py" ]; then \
		git submodule sync --recursive; \
		git submodule update --init --recursive --depth 1; \
	fi

dolrecomp: submodules
	cmake -S $(DOLRECOMP_DIR) -B $(DOLRECOMP_BUILD) -G Ninja -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) -DBUILD_TESTING=OFF
	cmake --build $(DOLRECOMP_BUILD) --target dolrecomp -j$(JOBS)

# Local fixes to ModernGekko (e.g. Metal as the Apple video backend). Each
# patch is applied once; already-applied patches are skipped.
patch-moderngekko: submodules
	@for p in $(PATCHES); do \
	  if git -C $(MODERNGEKKO_DIR) apply --reverse --check "$(CURDIR)/$$p" 2>/dev/null; then :; \
	  else echo "Applying $$p"; git -C $(MODERNGEKKO_DIR) apply "$(CURDIR)/$$p" || exit 1; fi; \
	done

moderngekko: patch-moderngekko
	cmake -S $(MODERNGEKKO_DIR) -B $(MODERNGEKKO_BUILD) -G Ninja -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) -DBUILD_TESTING=OFF
	cmake --build $(MODERNGEKKO_BUILD) --target moderngekko-port -j$(JOBS)

tools: dolrecomp moderngekko

# Extract the disc, then make PsoV3.dol the main executable. The disc's own
# sys/main.dol is "switcher", a small launcher that only loads PsoV3.dol;
# it is kept as sys/switcher.dol.
$(GAME_DIR)/sys/main.dol: | dolrecomp
	@if [ -z "$(DISC)" ]; then echo "error: pass DISC=/path/to/PSO.ciso (or .iso) the first time" >&2; exit 1; fi
	@mkdir -p build
	@case "$(DISC)" in \
	  *.ciso|*.CISO) echo "Converting CISO to ISO..."; python3 tools/ciso2iso.py "$(DISC)" build/disc.iso ;; \
	  *) ln -sf "$$(cd "$$(dirname "$(DISC)")" && pwd)/$$(basename "$(DISC)")" build/disc.iso ;; \
	esac
	$(DOLRECOMP_BIN) extract build/disc.iso $(GAME_DIR)
	@test "$$(head -c 6 $(GAME_DIR)/sys/boot.bin)" = "$(GAME_ID)" || { echo "error: disc is not $(GAME_ID)" >&2; exit 1; }
	python3 tools/check_sha1.py $(GAME_DIR)/files/PsoV3.dol $(PSOV3_SHA1)
	mv $(GAME_DIR)/sys/main.dol $(GAME_DIR)/sys/switcher.dol
	cp $(GAME_DIR)/files/PsoV3.dol $(GAME_DIR)/sys/main.dol
	@rm -f build/disc.iso

extract: $(GAME_DIR)/sys/main.dol

recompile: moderngekko extract
	$(PORT_BIN) build $(GAME_DIR) --backend $(BACKEND) --toolchain $(TOOLCHAIN) --output $(MODULES_DIR)

# Settings live in build/user so an existing Dolphin/ModernGekko setup on
# the Mac (which may name Vulkan) isn't used.
user-config:
	@mkdir -p $(USER_DIR)
	@test -f $(USER_DIR)/config.ini || printf 'resolution=1920x1080\nbackend=Metal\n' > $(USER_DIR)/config.ini

run: moderngekko extract user-config
	$(PORT_BIN) run $(GAME_DIR) --backend $(BACKEND) --toolchain $(TOOLCHAIN) --output $(MODULES_DIR) -- --user-dir $(USER_DIR) $(RUN_ARGS)

names: submodules
	@mkdir -p build
	python3 tools/make_map.py $(DECOMP_DIR)/config/$(GAME_ID)/psov3/symbols.txt $(MAP_FILE)

clean-game:
	rm -rf extracted $(MODULES_DIR)

clean: clean-game
	rm -rf build $(DOLRECOMP_BUILD) $(MODERNGEKKO_BUILD)
