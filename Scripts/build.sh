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

# Pick a signing identity: an explicit Developer ID, else the local dev
# certificate, else offer to make one.
#
# Ad-hoc is a trap for anything permission-related. Its designated requirement
# is the binary's own hash, so every rebuild invalidates the Accessibility and
# Input Monitoring grants while System Settings still shows them ticked. A
# certificate — any certificate — keys the requirement to itself instead, and
# survives rebuilds.
DEV_CERT="${JEV_CERT_NAME:-Jev Control Dev}"

if [ -z "$JEV_SIGN_IDENTITY" ]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q "\"$DEV_CERT\""; then
    JEV_SIGN_IDENTITY="$DEV_CERT"
  elif [ "$JEV_ADHOC" != "1" ] && [ -t 0 ]; then
    echo
    echo "No code signing identity found."
    echo
    echo "Without one, this build is ad-hoc signed, and macOS will silently"
    echo "revoke Accessibility and Input Monitoring every time you rebuild."
    echo "A local self-signed certificate fixes that for good."
    echo
    printf "Create one now? It prompts for your login password. [Y/n] "
    read -r reply
    case "$reply" in
      [Nn]*) ;;
      *)
        "$ROOT/Scripts/create-signing-cert.sh"
        if security find-identity -p codesigning 2>/dev/null | grep -q "\"$DEV_CERT\""; then
          JEV_SIGN_IDENTITY="$DEV_CERT"
        fi
        ;;
    esac
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
  echo "  ⚠ TCC grants will not survive a rebuild (JEV_ADHOC=1 or declined)."
  # No hardened runtime: it requires a real identity to be useful, and an
  # ad-hoc hardened binary is rejected at launch on some systems.
  codesign --force --deep \
    --entitlements "$ROOT/Resources/JevControl.entitlements" \
    --sign - "$APP"
fi

codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/  /'
echo "✔ $APP"
