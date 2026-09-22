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

# Prefer an explicit Developer ID, then the local dev certificate, then ad-hoc.
# Ad-hoc is a trap for anything permission-related: its designated requirement
# is the binary's own hash, so every rebuild invalidates TCC grants.
if [ -z "$JEV_SIGN_IDENTITY" ]; then
  DEV_CERT="${JEV_CERT_NAME:-Jev Control Dev}"
  if security find-identity -v -p codesigning | grep -q "$DEV_CERT"; then
    JEV_SIGN_IDENTITY="$DEV_CERT"
  fi
fi

if [ -n "$JEV_SIGN_IDENTITY" ]; then
  echo "▸ codesign ($JEV_SIGN_IDENTITY)"
  RUNTIME=""
  case "$JEV_SIGN_IDENTITY" in
    "Developer ID"*) RUNTIME="--options runtime --timestamp" ;;
  esac
  codesign --force --deep $RUNTIME \
    --entitlements "$ROOT/Resources/JevControl.entitlements" \
    --sign "$JEV_SIGN_IDENTITY" "$APP"
else
  echo "▸ codesign (ad-hoc)"
  echo "  ⚠ TCC grants will not survive a rebuild. Run Scripts/create-signing-cert.sh once."
  # No hardened runtime: it requires a real identity to be useful, and an
  # ad-hoc hardened binary is rejected at launch on some systems.
  codesign --force --deep \
    --entitlements "$ROOT/Resources/JevControl.entitlements" \
    --sign - "$APP"
fi

codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/  /'
echo "✔ $APP"
