# Jev Control

Hold a key, talk to your Mac.

This is the macOS app port of [jev-voice](https://github.com/kevinbadi/jev-voice) —
a real signed `.app` instead of a Python process borrowing your terminal's
permissions.

**Early.** The app shell, permissions, the push-to-talk hotkey and the floating
pill are in. No microphone, no transcription, no actions yet.

## What works today

- Menu bar app, no Dock icon, never takes keyboard focus.
- Setup window that requests and live-polls Microphone, Accessibility, Input
  Monitoring and Screen Recording, and deep-links to the right System Settings
  pane when macOS has already made up its mind.
- Push-to-talk on **Left Option** by default, switchable to Right Option or
  Caps Lock.
- A `CGEvent` tap that swallows the key, so the app you are controlling never
  sees it — including the modifier flag on anything you type while holding it.
- Hold to listen, release to stop. A press under 250 ms latches instead, and
  the next press unlatches — the same rule jev-voice uses.
- A floating pill at the top of the screen: gray idle, red listening, with a
  lock glyph when latched.
- Optional Caps Lock → F18 remap via `hidutil`, persisted with a LaunchAgent,
  with an Undo button.

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

## Testing it

1. Launch the app. The Setup window opens because nothing is granted yet.
2. Grant **Accessibility** and **Input Monitoring**. The window polls once a
   second, so the dots go green without a relaunch, and the key tap installs
   itself on the next retry — also without a relaunch.
3. Hold **Left Option**. The pill turns red and says "Listening…", and a Tink
   plays. Release it: gray, and a Pop.
4. Tap Left Option quickly instead. The pill stays red with a padlock. Press
   again to stop.
5. Type in TextEdit, hold Left Option mid-word, keep typing. Focus must not
   move, and the letters must come out unaccented — no `å` for `⌥a`.
6. Check System Settings › Privacy & Security. The entries say **Jev Control**,
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

## Why Left Option, and why Caps Lock is awkward

Push-to-talk needs a key you can hold for seconds with one hand, that emits a
clean press *and* release, and that costs nothing to swallow.

Option qualifies on all three. Modifiers report through `flagsChanged` on both
press and release, and left and right are told apart by the device-dependent
flag bits (`0x20` / `0x40`) rather than the shared `maskAlternate`, which both
set. Nothing has to be installed, and nothing is left behind if the app dies.

One wrinkle: the window server stamps modifier flags onto key events from
hardware state, not from the tap, so swallowing the Option press is not enough
— `⌥a` would still arrive as `å`. The tap also scrubs the Option bits off any
key pressed while the trigger is held.

Caps Lock cannot work this way. It is a latching toggle: macOS reports a state
change, not a press and a release, and the HID driver adds an activation delay.
The only way to get hold semantics is to remap it to F18 — a key no Mac
keyboard has — at the HID layer with `hidutil`. That works, but it is a
system-wide change affecting every app and every user on the machine, it does
not survive a reboot without a LaunchAgent, and it outlives the app if it
crashes. Hence Option by default, Caps Lock by choice.

## License

MIT
