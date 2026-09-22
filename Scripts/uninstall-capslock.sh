#!/bin/zsh
# Restore Caps Lock, in case the app is not around to do it.
hidutil property --set '{"UserKeyMapping":[]}' > /dev/null
launchctl bootout "gui/$(id -u)/ai.jev.control.capslock" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/ai.jev.control.capslock.plist"
echo "Caps Lock restored."
