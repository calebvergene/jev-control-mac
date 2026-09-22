#!/bin/zsh
# Forget every permission granted to Jev Control.
#
# Useful after a rebuild changes the code signature and macOS starts ignoring a
# tick that is still showing in System Settings.
for svc in Accessibility ListenEvent Microphone ScreenCapture; do
  tccutil reset "$svc" ai.jev.control 2>/dev/null || true
done
echo "Permissions reset. Relaunch Jev Control and grant them again."
