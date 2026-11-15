# pso-ios: Phantasy Star Online Episode I & II Plus (GameCube, GPOE8P v1.02)
# static recompilation, built on DolRecomp + ModernGekko.
#
#   make tools                    Build DolRecomp and ModernGekko
#   make extract DISC=path        Extract your disc (ISO or CISO) into extracted/pso
#                                 (or DOL=path/PsoV3.dol: enough for `make ios`)
#   make recompile                Recompile PsoV3.dol and build the native module
#   make run                      Recompile if needed and launch the game
#   make names                    Write build/pso.map (decomp function names)
#   make ios                      Build build/PSO-unsigned.ipa (needs Xcode)

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
DOLPHIN_PATCHES := $(wildcard patches/dolphin-*.patch)
DOLPHIN_DIR := $(MODERNGEKKO_DIR)/vendor/dolphin

.DEFAULT_GOAL := help
.PHONY: help tools dolrecomp moderngekko host-dolrecomp patch-moderngekko user-config submodules decomp extract recompile run names ios icon clean clean-game

help:
	@sed -n '4,11p' Makefile | sed 's/^# //'

# DolRecomp and ModernGekko (with Dolphin and its libraries). Dolphin's
# prebuilt Windows Qt and FFmpeg are large and unused here, so they're skipped.
# pso-decomp is only needed for `make names` (see decomp).
submodules:
	@if [ ! -f "$(DOLRECOMP_DIR)/CMakeLists.txt" ] || [ ! -f "$(DOLPHIN_DIR)/Externals/fmt/fmt/CMakeLists.txt" ]; then \
		git submodule sync --recursive; \
		git submodule update --init --depth 1 $(DOLRECOMP_DIR) $(MODERNGEKKO_DIR); \
		git -C $(DOLRECOMP_DIR) submodule update --init --recursive --depth 1; \
		git -C $(MODERNGEKKO_DIR) submodule update --init --depth 1; \
		git -C $(DOLPHIN_DIR) -c submodule.Externals/Qt.update=none -c submodule.Externals/FFmpeg-bin.update=none \
			submodule update --init --recursive --depth 1; \
	fi

decomp:
	@[ -f "$(DECOMP_DIR)/configure.py" ] || git submodule update --init --depth 1 $(DECOMP_DIR)

dolrecomp: submodules
	cmake -S $(DOLRECOMP_DIR) -B $(DOLRECOMP_BUILD) -G Ninja -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) -DBUILD_TESTING=OFF
	cmake --build $(DOLRECOMP_BUILD) --target dolrecomp -j$(JOBS)

# Local fixes to ModernGekko and its Dolphin (Metal on Apple, iOS support).
# Each patch is applied once; already-applied patches are skipped. The iOS
# changes are behind IOS / DOLPHIN_IOS, so the Mac build is unaffected.
patch-moderngekko: submodules
	@scripts/apply-patches.sh $(MODERNGEKKO_DIR) build/patches/moderngekko $(PATCHES)
	@scripts/apply-patches.sh $(DOLPHIN_DIR) build/patches/dolphin $(DOLPHIN_PATCHES)

moderngekko: patch-moderngekko
	cmake -S $(MODERNGEKKO_DIR) -B $(MODERNGEKKO_BUILD) -G Ninja -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) -DBUILD_TESTING=OFF
	cmake --build $(MODERNGEKKO_BUILD) --target moderngekko-port -j$(JOBS)

# Only the recompiler from ModernGekko's host build: all `make ios` needs
# from the Mac side.
host-dolrecomp: patch-moderngekko
	cmake -S $(MODERNGEKKO_DIR) -B $(MODERNGEKKO_BUILD) -G Ninja -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) -DBUILD_TESTING=OFF
	cmake --build $(MODERNGEKKO_BUILD) --target moderngekko-port-recompiler -j$(JOBS)

tools: dolrecomp moderngekko

# Extract the disc, then make PsoV3.dol the main executable. The disc's own
# sys/main.dol is "switcher", a small launcher that only loads PsoV3.dol;
# it is kept as sys/switcher.dol. DOL=path/PsoV3.dol instead of DISC sets up
# only the executable, which is all the iOS build needs (the app imports the
# rest of the disc on the phone).
ifneq ($(DOL),)
$(GAME_DIR)/sys/main.dol:
	python3 tools/check_sha1.py "$(DOL)" $(PSOV3_SHA1)
	@mkdir -p $(GAME_DIR)/sys $(GAME_DIR)/files
	cp "$(DOL)" $(GAME_DIR)/files/PsoV3.dol
	cp "$(DOL)" $(GAME_DIR)/sys/main.dol
else
$(GAME_DIR)/sys/main.dol:
	@if [ -z "$(DISC)" ]; then echo "error: pass DISC=/path/to/PSO.ciso (or .iso) the first time" >&2; exit 1; fi
	@$(MAKE) --no-print-directory dolrecomp
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
endif

extract: $(GAME_DIR)/sys/main.dol

recompile: moderngekko extract
	$(PORT_BIN) build $(GAME_DIR) --backend $(BACKEND) --toolchain $(TOOLCHAIN) --output $(MODULES_DIR)

# Settings live in build/user so an existing Dolphin/ModernGekko setup on
# the Mac (which may name Vulkan) isn't used.
user-config:
	@mkdir -p $(USER_DIR)
	@test -f $(USER_DIR)/config.ini || printf 'resolution=1920x1080\nbackend=Metal\n' > $(USER_DIR)/config.ini

# Game-side widescreen mod (mods/widescreen). On the Mac it is off unless
# PSO_WIDE is set (screen aspect / (4/3), e.g. PSO_WIDE=1.3333 for 16:9 with
# the Stretch aspect mode); the iOS app links it in and sets it itself.
WIDESCREEN_MOD := $(USER_DIR)/Mods/pso_widescreen.mgm.dylib
$(WIDESCREEN_MOD): mods/widescreen/widescreen.c mods/widescreen/pso_widescreen.h
	@mkdir -p $(dir $@)
	cc -O2 -shared -fvisibility=hidden -DPSO_WIDESCREEN_DYLIB -I $(MODERNGEKKO_DIR)/include $< -o $@

# Cheats mod (mods/cheats). On the Mac, PSO_CHEATS=meseta,hp,mag,exp=4,rare=8
# (any subset) turns cheats on; the iOS app links it in and drives it from
# Settings > Mods.
CHEATS_MOD := $(USER_DIR)/Mods/pso_cheats.mgm.dylib
$(CHEATS_MOD): mods/cheats/cheats.c mods/cheats/pso_cheats.h
	@mkdir -p $(dir $@)
	cc -O2 -Wall -shared -fvisibility=hidden -DPSO_CHEATS_DYLIB -I $(MODERNGEKKO_DIR)/include $< -o $@

run: moderngekko extract user-config $(WIDESCREEN_MOD) $(CHEATS_MOD)
	$(PORT_BIN) run $(GAME_DIR) --backend $(BACKEND) --toolchain $(TOOLCHAIN) --output $(MODULES_DIR) -- --user-dir $(USER_DIR) $(RUN_ARGS)

# iOS app: recompiles PsoV3.dol with the host DolRecomp, then builds the
# runtime, game module and app for the iOS SDK.
ios: host-dolrecomp extract
	JOBS=$(JOBS) scripts/build-ios.sh

# App icon. `make icon` redraws the default; `make icon ICON=path/to/image`
# uses your own picture instead (center-cropped to a square). Rebuild with
# `make ios` afterwards.
icon:
	@if [ -n "$(ICON)" ]; then \
	  w=$$(sips -g pixelWidth "$(ICON)" | awk '/pixelWidth/{print $$2}'); \
	  h=$$(sips -g pixelHeight "$(ICON)" | awk '/pixelHeight/{print $$2}'); \
	  s=$$(( w < h ? w : h )); \
	  sips -s format png -c $$s $$s "$(ICON)" --out ios/icon/AppIcon.png >/dev/null && \
	  sips -z 1024 1024 ios/icon/AppIcon.png >/dev/null && echo "ios/icon/AppIcon.png updated from $(ICON)"; \
	else \
	  swift scripts/make-icon.swift ios/resources/fonts/Baloo2-SemiBold.ttf ios/icon/AppIcon.png; \
	fi

names: decomp
	@mkdir -p build
	python3 tools/make_map.py $(DECOMP_DIR)/config/$(GAME_ID)/psov3/symbols.txt $(MAP_FILE)

clean-game:
	rm -rf extracted $(MODULES_DIR)

clean: clean-game
	rm -rf build $(DOLRECOMP_BUILD) $(MODERNGEKKO_BUILD)
