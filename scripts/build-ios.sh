#!/usr/bin/env bash
# Builds PSO.app for iOS (arm64) and packages build/PSO-unsigned.ipa.
# Run through `make ios`, which first builds the Mac host tools and extracts
# the disc. Needs Xcode (for the iOS SDK) and the host tools in lib/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
DOLRECOMP="lib/ModernGekko/build/dolrecomp"
GAME_DIR="extracted/pso"
OUT="build/ios"
GEN_OUT="$OUT/dolrecomp-output"
CMAKE_BUILD="$OUT/cmake"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-16.0}"

step() { printf '\n==> %s\n' "$*"; }

step "Checking Xcode"
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo "error: the iOS SDK wasn't found. Install Xcode from the App Store, open it once," >&2
  echo "       then run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi
xcodebuild -version | head -1
echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"

step "Recompiling PsoV3.dol"
if [ ! -f "$GEN_OUT/generated/generated.h" ] || [ "$GAME_DIR/sys/main.dol" -nt "$GEN_OUT/generated/generated.h" ]; then
  rm -rf "$GEN_OUT"
  "$DOLRECOMP" -j"$JOBS" --backend=c --cpu gekko --gamecube "$GAME_DIR/sys/main.dol" "$GEN_OUT"
else
  echo "up to date"
fi

step "Configuring for iOS"
cmake -S ios -B "$CMAKE_BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_BUILD_TYPE=Release \
  -DPSO_GENERATED_DIR="$ROOT/$GEN_OUT/generated"

step "Building"
# -k 0 keeps going past errors so one run reports all of them.
cmake --build "$CMAKE_BUILD" --target PSO -j"$JOBS" -- -k 0

APP="$CMAKE_BUILD/PSO.app"
step "Packaging"
# Ad-hoc signatures only; sign for your device with your usual sideloading tool.
codesign --force --sign - "$APP"/Frameworks/*.dylib
codesign --force --sign - "$APP"
rm -rf "$OUT/Payload" build/PSO-unsigned.ipa
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && zip -qry ../PSO-unsigned.ipa Payload)
rm -rf "$OUT/Payload"
ls -lh build/PSO-unsigned.ipa
echo
echo "Done: build/PSO-unsigned.ipa"
