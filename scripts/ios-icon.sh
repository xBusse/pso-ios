#!/bin/bash
# Puts the app icon into the built PSO.app: an asset catalog (Assets.car, what
# current iOS reads) plus loose PNGs for older versions.
#   scripts/ios-icon.sh <icon-1024.png> <PSO.app> <scratch dir>
set -euo pipefail
src="$1"; app="$2"; work="$3"

rm -rf "$work"; mkdir -p "$work/Assets.xcassets/AppIcon.appiconset"
# Flatten onto opaque pixels at exactly 1024x1024 (iOS rejects icons with alpha).
sips -s format png -z 1024 1024 "$src" --out "$work/icon.png" >/dev/null
sips -s format jpeg "$work/icon.png" --out "$work/icon.jpg" >/dev/null
sips -s format png "$work/icon.jpg" --out "$work/Assets.xcassets/AppIcon.appiconset/icon-1024.png" >/dev/null
cat > "$work/Assets.xcassets/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
cat > "$work/Assets.xcassets/AppIcon.appiconset/Contents.json" <<'JSON'
{
  "images" : [ { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

if xcrun --sdk iphoneos --find actool >/dev/null 2>&1; then
  xcrun actool "$work/Assets.xcassets" --compile "$app" --platform iphoneos --minimum-deployment-target 16.0 \
    --target-device iphone --target-device ipad --app-icon AppIcon \
    --output-partial-info-plist "$work/partial.plist" --output-format human-readable-text --notices --warnings \
    >"$work/actool.log" 2>&1 || { cat "$work/actool.log" >&2; echo "warning: actool failed; using loose icons only" >&2; }
fi

flat="$work/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
for spec in 60x60@2x:120 60x60@3x:180 76x76@2x~ipad:152 83.5x83.5@2x~ipad:167; do
  name="AppIcon${spec%%:*}.png"; px="${spec##*:}"
  sips -z "$px" "$px" "$flat" --out "$app/$name" >/dev/null
done
