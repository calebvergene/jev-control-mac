# Jev Control

Hold Caps Lock, talk to your Mac.

This is the macOS app port of [jev-voice](https://github.com/kevinbadi/jev-voice) —
a real signed `.app` instead of a Python process borrowing your terminal's
permissions.

**Status: Chunk 1 of 8.** The app shell, permissions, the Caps Lock hotkey and
the floating pill. No microphone, no transcription, no actions yet.

## What works today

- Menu bar app, no Dock icon, never takes keyboard focus.
- Setup window that requests and live-polls Microphone, Accessibility, Input
  Monitoring and Screen Recording, and deep-links to the right System Settings
  pane when macOS has already made up its mind.
- Caps Lock → F18 remap via `hidutil`, persisted with a LaunchAgent, with an
  Undo button.
- A `CGEvent` tap on F18 that swallows the key, so the app you are controlling
  never sees it.
- Push-to-talk: hold to listen, release to stop. A press under 250 ms latches
  instead, and the next press unlatches — the same rule jev-voice uses.
- A floating pill at the top of the screen: gray idle, red listening, with a
  lock glyph when latched.

## Requirements

macOS 13 or later, Apple Silicon or Intel. Xcode is **not** required — the
Command Line Tools are enough.

## Build and run

```bash
./Scripts/install.sh
```

That builds `JevControl.app`, copies it to `/Applications/Jev Control.app` and
launches it. Installing to `/Applications` matters: macOS ties permissions to a
path and a code signature, and an app that moves loses its grants.

To build without installing:

```bash
./Scripts/build.sh
```

The result is `build/JevControl.app`, ad-hoc signed. For a distributable build,
set a Developer ID first:

```bash
JEV_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build.sh
```

## Testing Chunk 1

1. Launch the app. The Setup window opens because nothing is granted yet.
2. Grant **Accessibility** and **Input Monitoring**. The window polls once a
   second, so the dots go green without a relaunch, and the key tap installs
   itself on the next retry — also without a relaunch.
3. Click **Remap Caps Lock**. Caps Lock stops toggling capitals.
4. Hold Caps Lock. The pill turns red and says "Listening…", and a Tink plays.
   Release it: gray, and a Pop.
5. Tap Caps Lock quickly instead. The pill stays red with a padlock. Press
   again to stop.
6. While holding Caps Lock, confirm the focused app never receives the key and
   never loses focus — type in TextEdit, hold Caps Lock mid-word, keep typing.
7. Check System Settings › Privacy & Security. The entries say **Jev Control**,
   not Terminal.

## If permissions misbehave

An ad-hoc signature changes on every rebuild, so macOS can keep showing a
ticked box it no longer honours. Forget them and grant again:

```bash
./Scripts/reset-permissions.sh
```

A Developer ID signature is stable across rebuilds and does not have this
problem.

## If Caps Lock is stuck as F18

The app's Undo button restores it. If the app will not launch:

```bash
./Scripts/uninstall-capslock.sh
```

## Layout

```
Sources/JevControl/
  JevControlApp.swift          @main, AppDelegate, menu bar
  Core/AppState.swift          observable state, permission polling, feedback
  Core/PillState.swift         pill states and their palette
  Permissions/Permissions.swift  the four TCC checks, requests and deep links
  Hotkey/CapsLockRemap.swift   hidutil mapping + LaunchAgent persistence
  Hotkey/HotkeyTap.swift       CGEvent tap on F18, swallows the key
  Hotkey/HotkeyManager.swift   hold / tap-to-latch state machine
  UI/PillPanel.swift           non-activating NSPanel, sizing and placement
  UI/PillView.swift            the pill itself
  UI/OnboardingView.swift      setup checklist
  UI/OnboardingWindow.swift    plain NSWindow host for it
Scripts/
  build.sh                     swift build + bundle + codesign
  install.sh                   build, install to /Applications, launch
  uninstall-capslock.sh        restore Caps Lock without the app
  reset-permissions.sh         tccutil reset for this bundle
```

## Why Caps Lock becomes F18

Caps Lock is a latching modifier: macOS reports a state change, not a press and
a release, so it cannot drive push-to-talk. `hidutil` remaps it at the HID layer
to F18 — a key no Mac keyboard has and no app binds — which turns it into an
ordinary key with a clean down/up pair. The mapping does not survive a reboot,
so the same command is installed as a LaunchAgent.

## License

MIT
