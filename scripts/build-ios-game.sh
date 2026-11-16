#!/usr/bin/env bash
# build-ios-game.sh <engine .tar.gz or unpacked folder> <PsoV3.dol>
#
# Turns a prebuilt engine (build-ios-engine.sh) and your own PsoV3.dol into the
# app: recompiles the DOL with the engine's DolRecomp, builds the game module for
# iOS, puts it in the engine's app and packages build/PSO-unsigned-<time>.ipa.
# Only the game module is compiled (still most of the work: ~17 min on an 8-core Mac).
#
# The module has to come from the same pso-ios commit as the engine (they share
# the runtime ABI), so check out that commit first: engine.json names it.
# Run through `make ios-game ENGINE=... DOL=...`. Needs Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
. scripts/ios-lib.sh

ENGINE="${1:?usage: build-ios-game.sh <engine .tar.gz or folder> <PsoV3.dol>}"
DOL="${2:?usage: build-ios-game.sh <engine .tar.gz or folder> <PsoV3.dol>}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
OUT="build/ios-game"
KIT="$OUT/kit"
GEN_OUT="$OUT/dolrecomp-output"
CMAKE_BUILD="$OUT/cmake"
PSOV3_SHA1=0d85744b51d7379efb025a943d0cd5aaae2191a3

check_xcode

step "Checking PsoV3.dol"
python3 tools/check_sha1.py "$DOL" "$PSOV3_SHA1"

step "Unpacking the engine"
rm -rf "$KIT"
mkdir -p "$KIT"
if [ -d "$ENGINE" ]; then
  cp -R "$ENGINE"/. "$KIT"/
else
  tar -C "$KIT" -xzf "$ENGINE"
fi
# A browser download marks the files as quarantined, which stops dolrecomp from running.
xattr -dr com.apple.quarantine "$KIT" 2>/dev/null || true
if [ ! -f "$KIT/engine.json" ] || [ ! -d "$KIT/PSO.app" ] || [ ! -x "$KIT/bin/dolrecomp" ]; then
  echo "error: $ENGINE isn't a pso-ios engine (engine.json, PSO.app and bin/dolrecomp are expected)" >&2
  exit 1
fi
ENGINE_COMMIT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$KIT/engine.json")"
HERE="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo "Engine built from $ENGINE_COMMIT"
if [ "$ENGINE_COMMIT" != "$HERE" ] && [ -z "${ALLOW_ENGINE_MISMATCH:-}" ]; then
  echo "error: this checkout is at $HERE, but the engine was built from $ENGINE_COMMIT." >&2
  echo "       Check out that commit (git checkout $ENGINE_COMMIT && git submodule update) so the" >&2
  echo "       game module matches the engine, or set ALLOW_ENGINE_MISMATCH=1 if you know they agree." >&2
  exit 1
fi

recompile_dol "$KIT/bin/dolrecomp" "$DOL" "$GEN_OUT"

step "Configuring the game module for iOS"
PKG_CONFIG_LIBDIR=/var/empty PKG_CONFIG_PATH= \
  cmake -S ios/game-module -B "$CMAKE_BUILD" $(ios_cmake_args) \
  -DPSO_GENERATED_DIR="$ROOT/$GEN_OUT/generated"

step "Building the game module"
cmake --build "$CMAKE_BUILD" --target gGPOE8P_recomp -j"$JOBS" -- -k 0

step "Adding the game module to the app"
APP="$OUT/PSO.app"
rm -rf "$APP"
cp -R "$KIT/PSO.app" "$APP"
mkdir -p "$APP/Frameworks"
cp "$CMAKE_BUILD/game-module/gGPOE8P_recomp.dylib" "$APP/Frameworks/"

package_ipa "$APP" "$OUT"
