#!/bin/zsh
# Build JevControl.app.
#
# Xcode is not required: SwiftPM compiles the binary and this script assembles
# the bundle around it. Set JEV_SIGN_IDENTITY to a Developer ID for a
# distributable build; otherwise the bundle is ad-hoc signed, which is enough
# to run locally and to appear by name in System Settings.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${JEV_CONFIG:-release}"
APP="$ROOT/build/JevControl.app"

echo "▸ swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/JevControl"

echo "▸ bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/JevControl"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -n "$JEV_SIGN_IDENTITY" ]; then
  echo "▸ codesign (Developer ID: $JEV_SIGN_IDENTITY)"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ROOT/Resources/JevControl.entitlements" \
    --sign "$JEV_SIGN_IDENTITY" "$APP"
else
  echo "▸ codesign (ad-hoc — no JEV_SIGN_IDENTITY set)"
  # No hardened runtime: it requires a real identity to be useful, and an
  # ad-hoc hardened binary is rejected at launch on some systems.
  codesign --force --deep \
    --entitlements "$ROOT/Resources/JevControl.entitlements" \
    --sign - "$APP"
fi

codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/  /'
echo "✔ $APP"
