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
# Each new ipa is also copied here (iCloud Drive/pso-ios), if the folder
# exists. Set IPA_COPY_DIR= (empty) to skip, or to another folder.
IPA_COPY_DIR="${IPA_COPY_DIR-$HOME/Library/Mobile Documents/com~apple~CloudDocs/pso-ios}"

step() { printf '\n==> %s\n' "$*"; }

step "Checking Xcode"
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo "error: the iOS SDK wasn't found. Install Xcode from the App Store, open it once," >&2
  echo "       then run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi
xcodebuild -version | sed -n 1p
echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"

step "Recompiling PsoV3.dol"
if [ ! -f "$GEN_OUT/generated/generated.h" ] || [ "$GAME_DIR/sys/main.dol" -nt "$GEN_OUT/generated/generated.h" ]; then
  rm -rf "$GEN_OUT"
  "$DOLRECOMP" -j"$JOBS" --backend=c --cpu gekko --gamecube "$GAME_DIR/sys/main.dol" "$GEN_OUT"
else
  echo "up to date"
fi
# The module template also wants the DOL and an SMC table next to the
# generated code (ModernGekko's port tool sets these up the same way).
# Copy only when it differs: a fresh mtime rebuilds the whole game module.
cmp -s "$GAME_DIR/sys/main.dol" "$GEN_OUT/generated/main.dol" ||
  cp "$GAME_DIR/sys/main.dol" "$GEN_OUT/generated/main.dol"
[ -f "$GEN_OUT/generated/generated_smc.txt" ] || : > "$GEN_OUT/generated/generated_smc.txt"

step "Configuring for iOS"
# PKG_CONFIG_LIBDIR hides Homebrew's (macOS) libraries from pkg-config.
PKG_CONFIG_LIBDIR=/var/empty PKG_CONFIG_PATH= \
cmake -S ios -B "$CMAKE_BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_BUILD_TYPE=Release \
  -DPSO_GENERATED_DIR="$ROOT/$GEN_OUT/generated"

step "Building"
# -k 0 keeps going past errors so one run reports all of them.
cmake --build "$CMAKE_BUILD" --target PSO -j"$JOBS" -- -k 0

APP="$CMAKE_BUILD/PSO.app"
step "Resources"
# Menu font (SIL OFL, license alongside) and the app icon (ios/icon/AppIcon.png;
# `make icon ICON=your.png` replaces it).
mkdir -p "$APP/fonts"
cp ios/resources/fonts/* "$APP/fonts/"
# PSO's network settings file, installed on the memory card at boot when it's missing (see
# InstallNetworkSettings in PlatformIOS.mm).
mkdir -p "$APP/network"
cp ios/resources/network/*.gci "$APP/network/"
scripts/ios-icon.sh ios/icon/AppIcon.png "$APP" "$OUT/icon"

step "Packaging"
# Ad-hoc signatures only; sign for your device with your usual sideloading tool.
codesign --force --sign - "$APP"/Frameworks/*.dylib
codesign --force --sign - "$APP"
# Each build gets a timestamped name; build/PSO-unsigned.ipa links to the latest.
IPA="PSO-unsigned-$(date +%Y%m%d-%H%M%S).ipa"
rm -rf "$OUT/Payload"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && zip -qry "../$IPA" Payload)
rm -rf "$OUT/Payload"
ln -sf "$IPA" build/PSO-unsigned.ipa
ls -lh "build/$IPA"
if [ -n "$IPA_COPY_DIR" ] && [ -d "$IPA_COPY_DIR" ]; then
  cp "build/$IPA" "$IPA_COPY_DIR/"
  echo "Copied to $IPA_COPY_DIR/$IPA"
fi
echo
echo "Done: build/$IPA"
