#!/bin/zsh
# Build and move the app into /Applications, then launch it.
#
# TCC is much better behaved when the app lives in a stable location: running
# the bundle from a build directory means a new path, and often a new prompt,
# on every rebuild.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build.sh"

osascript -e 'tell application "Jev Control" to quit' 2>/dev/null || true
pkill -x JevControl 2>/dev/null || true
sleep 1

rm -rf "/Applications/Jev Control.app"
cp -R "$ROOT/build/JevControl.app" "/Applications/Jev Control.app"
echo "✔ /Applications/Jev Control.app"
open "/Applications/Jev Control.app"
