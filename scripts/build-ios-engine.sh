#!/usr/bin/env bash
# Builds the prebuilt engine: PSO.app for iOS without the game module, plus the
# Mac DolRecomp that turns a PsoV3.dol into the module. It contains no game
# code, so it can be shared; build-ios-game.sh adds a user's own game to it.
#
# Writes build/pso-engine-<commit>.tar.gz containing:
#   PSO.app/        the app, runtime and resources (Frameworks/ is empty)
#   bin/dolrecomp   the recompiler (macOS arm64)
#   engine.json     the pso-ios commit it was built from
# Run through `make ios-engine`. Needs Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
. scripts/ios-lib.sh

JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
DOLRECOMP="lib/ModernGekko/build/dolrecomp"
OUT="build/ios-engine"
CMAKE_BUILD="$OUT/cmake"

COMMIT="$(git rev-parse HEAD)"
SHORT="$(git rev-parse --short=12 HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no -- . ':!lib')" ]; then
  echo "warning: the working tree has uncommitted changes; the engine won't match commit $SHORT" >&2
fi

check_xcode

step "Configuring the engine for iOS"
PKG_CONFIG_LIBDIR=/var/empty PKG_CONFIG_PATH= \
  cmake -S ios -B "$CMAKE_BUILD" $(ios_cmake_args) -DPSO_ENGINE_ONLY=ON

step "Building the engine"
cmake --build "$CMAKE_BUILD" --target PSO -j"$JOBS" -- -k 0

KIT="$OUT/kit"
rm -rf "$KIT"
mkdir -p "$KIT/bin"
cp -R "$CMAKE_BUILD/PSO.app" "$KIT/PSO.app"
rm -f "$KIT/PSO.app/Frameworks/"*.dylib
add_resources "$KIT/PSO.app" "$OUT"
cp "$DOLRECOMP" "$KIT/bin/dolrecomp"
cat > "$KIT/engine.json" <<EOF
{
  "format": 1,
  "commit": "$COMMIT",
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployment_target": "$DEPLOYMENT_TARGET"
}
EOF

step "Packaging the engine"
TARBALL="build/pso-engine-$SHORT.tar.gz"
tar -C "$KIT" -czf "$TARBALL" .
ls -lh "$TARBALL"
echo
echo "Done: $TARBALL"
