# Shared steps for the iOS build scripts (sourced, not run):
#   build-ios.sh         full build: engine and game module together
#   build-ios-engine.sh  the app without game code (the prebuilt engine)
#   build-ios-game.sh    recompile PsoV3.dol and add it to a prebuilt engine

DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-16.0}"
# Each new ipa is also copied here (iCloud Drive/pso-ios), if the folder
# exists. Set IPA_COPY_DIR= (empty) to skip, or to another folder.
IPA_COPY_DIR="${IPA_COPY_DIR-$HOME/Library/Mobile Documents/com~apple~CloudDocs/pso-ios}"

step() { printf '\n==> %s\n' "$*"; }

check_xcode() {
  step "Checking Xcode"
  if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    echo "error: the iOS SDK wasn't found. Install Xcode from the App Store, open it once," >&2
    echo "       then run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
  fi
  xcodebuild -version | sed -n 1p
  echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
}

# Common CMake arguments for an iOS (arm64) configure. PKG_CONFIG_LIBDIR (set
# by the callers) hides Homebrew's macOS libraries from pkg-config.
ios_cmake_args() {
  printf '%s\n' -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_BUILD_TYPE=Release
}

# recompile_dol <dolrecomp> <main.dol> <output dir>
# Runs DolRecomp unless the output is already current, then puts the DOL and an
# SMC table beside the generated code (the module template wants both, as
# ModernGekko's port tool sets them up).
recompile_dol() {
  local dolrecomp="$1" dol="$2" out="$3"
  step "Recompiling PsoV3.dol"
  if [ ! -f "$out/generated/generated.h" ] || [ "$dol" -nt "$out/generated/generated.h" ]; then
    rm -rf "$out"
    "$dolrecomp" -j"$JOBS" --backend=c --cpu gekko --gamecube "$dol" "$out"
  else
    echo "up to date"
  fi
  # Copy only when it differs: a fresh mtime rebuilds the whole game module.
  cmp -s "$dol" "$out/generated/main.dol" || cp "$dol" "$out/generated/main.dol"
  [ -f "$out/generated/generated_smc.txt" ] || : > "$out/generated/generated_smc.txt"
}

# add_resources <PSO.app> <scratch dir>
add_resources() {
  local app="$1" scratch="$2"
  step "Resources"
  # Menu font (SIL OFL, license alongside) and the app icon (ios/icon/AppIcon.png;
  # `make icon ICON=your.png` replaces it).
  mkdir -p "$app/fonts"
  cp ios/resources/fonts/* "$app/fonts/"
  # PSO's network settings file, installed on the memory card at boot when it's missing (see
  # InstallNetworkSettings in PlatformIOS.mm).
  mkdir -p "$app/network"
  cp ios/resources/network/*.gci "$app/network/"
  scripts/ios-icon.sh ios/icon/AppIcon.png "$app" "$scratch/icon"
}

# package_ipa <PSO.app> <scratch dir>
# Ad-hoc signs the app and its game module and zips build/PSO-unsigned-<time>.ipa;
# build/PSO-unsigned.ipa links to the newest. Sign for your device with your
# usual sideloading tool.
package_ipa() {
  local app="$1" scratch="$2"
  step "Packaging"
  codesign --force --sign - "$app"/Frameworks/*.dylib
  codesign --force --sign - "$app"
  local ipa="PSO-unsigned-$(date +%Y%m%d-%H%M%S).ipa"
  rm -rf "$scratch/Payload"
  mkdir -p "$scratch/Payload"
  cp -R "$app" "$scratch/Payload/"
  (cd "$scratch" && zip -qry "$ROOT/build/$ipa" Payload)
  rm -rf "$scratch/Payload"
  ln -sf "$ipa" build/PSO-unsigned.ipa
  ls -lh "build/$ipa"
  if [ -n "$IPA_COPY_DIR" ] && [ -d "$IPA_COPY_DIR" ]; then
    cp "build/$ipa" "$IPA_COPY_DIR/"
    echo "Copied to $IPA_COPY_DIR/$ipa"
  fi
  echo
  echo "Done: build/$ipa"
}
