#!/usr/bin/env bash
# Builds PSO.app for iOS (arm64), engine and game module together, and packages
# build/PSO-unsigned-<time>.ipa. Run through `make ios`, which first builds the
# Mac host tools and extracts the disc. Needs Xcode (for the iOS SDK).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
. scripts/ios-lib.sh

JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
DOLRECOMP="lib/ModernGekko/build/dolrecomp"
GAME_DIR="extracted/pso"
OUT="build/ios"
GEN_OUT="$OUT/dolrecomp-output"
CMAKE_BUILD="$OUT/cmake"

check_xcode
recompile_dol "$DOLRECOMP" "$GAME_DIR/sys/main.dol" "$GEN_OUT"

step "Configuring for iOS"
PKG_CONFIG_LIBDIR=/var/empty PKG_CONFIG_PATH= \
  cmake -S ios -B "$CMAKE_BUILD" $(ios_cmake_args) \
  -DPSO_ENGINE_ONLY=OFF \
  -DPSO_GENERATED_DIR="$ROOT/$GEN_OUT/generated"

step "Building"
# -k 0 keeps going past errors so one run reports all of them.
cmake --build "$CMAKE_BUILD" --target PSO -j"$JOBS" -- -k 0

APP="$CMAKE_BUILD/PSO.app"
add_resources "$APP" "$OUT"
package_ipa "$APP" "$OUT"
