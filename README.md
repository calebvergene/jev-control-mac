# Jev Control

Voice control for macOS. Hold a key, say what you want, it happens.

## Install

```bash
git clone https://github.com/calebvergene/jev-control-mac.git
cd jev-control-mac
./Scripts/install.sh
```

Builds the app, installs it to `/Applications`, and launches it.

The first build offers to create a local signing certificate — say yes. Without
one, macOS revokes the app's permissions on every rebuild.

Then, in the Setup window:

1. Grant **Accessibility** and **Input Monitoring**.
2. Paste a [TypeSafe API key](https://console.typesafe.ai) under Jev.
3. Wait for Speech to say "Model ready" — the first launch downloads ~150 MB.

Hold **Left Option** and talk.

## What you can say

### Apps and websites

| Say | Does |
| --- | --- |
| "open cursor", "switch to chrome" | Opens or focuses the app |
| "go to youtube", "go to stripe dot com" | Opens the site |
| "search youtube for lofi hip hop" | Site-specific search |
| "google best ramen near me" | Web search |

### Typing and keys

| Say | Does |
| --- | --- |
| "type hello world and hit enter" | Types into the focused field, then submits |
| "select all and copy" | Keyboard shortcuts |
| "close this tab", "undo", "go back", "reload" | Keyboard shortcuts |
| "new note called groceries" | Creates and titles it |
| "in notes, type buy milk" | Focuses the app first, then types |

### System

| Say | Does |
| --- | --- |
| "scroll down a lot", "go to the top" | Scrolls |
| "volume up", "mute" | System volume |
| "pause the music", "next song" | Media keys |
| "take a screenshot" | Saves to Desktop |
| "open my downloads" | Opens the folder |
| "lock the screen", "toggle dark mode" | System |

### Compound commands

| Say | Does |
| --- | --- |
| "open chrome and go to youtube" | Runs both, in order |
| "open notes and type buy milk and press enter" | Runs both, in order |

## Settings

Menu bar icon → **Setup** for the push-to-talk key, microphone, speech model,
and API key. **Decisions** shows what it heard, what it chose, and why.

Push-to-talk is Left Option by default. Right Option and Caps Lock are also
available — Caps Lock needs a system-wide remap, the other two don't.

A short tap latches recording on; tap again to stop.

## Requirements

macOS 13 or later. Xcode is not needed — the Command Line Tools are enough.

## License

MIT
