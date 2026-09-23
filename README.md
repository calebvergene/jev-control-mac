# Jev Control — Voice Control for Mac That Actually Does Things

**Talk to your Mac and it works.** Open apps, write emails, click buttons, fill
forms, reply to messages — by voice, on macOS, with speech recognition that runs
entirely on your machine.

[![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](https://github.com/calebvergene/jev-control-mac/releases)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-black?logo=apple)](https://github.com/calebvergene/jev-control-mac/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)

Hold a key. Say what you want. It happens.

```
⌥  "reply to the last email from Sam saying I'll be there"
⌥  "open chrome and go to youtube"
⌥  "find the cheapest flight to London on google flights"
⌥  "in notes, make a new note called groceries and type milk, eggs, bread"
```

Jev Control is an **open-source voice assistant for macOS** — a hands-free Mac
automation tool that understands ordinary speech and drives real applications.
Not a chatbot. Not dictation. It reads your screen and clicks things.

---

## Why this is different from Siri, Voice Control, and dictation apps

| | Siri | macOS Voice Control | Dictation apps | **Jev Control** |
| --- | --- | --- | --- | --- |
| Works in any app | Partly | Yes | Typing only | **Yes** |
| Understands intent | Some | No — fixed grammar | No | **Yes** |
| Multi-step tasks | No | No | No | **Yes** |
| Speech stays on device | No | Yes | Varies | **Yes** |
| Reads the screen | No | Labels only | No | **Yes** |
| Scriptable / open source | No | No | Rarely | **MIT** |

Apple's Voice Control needs the exact phrase. Siri needs Apple to have built
the integration. Jev Control works out what you meant, then operates the app
the way you would.

---

## What you can say

### Apps and websites

| Say | It does |
| --- | --- |
| "open cursor", "switch to chrome" | Launches or focuses the matching installed app |
| "go to youtube", "pull up stripe dot com" | Opens the site |
| "search youtube for lofi hip hop" | Site-specific search |
| "google best ramen near me" | Web search |

### Typing and keys

| Say | It does |
| --- | --- |
| "type hello world and hit enter" | Types into the focused field, then submits |
| "select all and copy" | ~45 keyboard shortcuts |
| "close this tab", "undo", "go back", "reload" | The obvious thing |
| "new note called groceries" | Creates it and titles it |

### System

| Say | It does |
| --- | --- |
| "scroll down a lot", "go to the top" | Real scroll-wheel events |
| "volume up", "mute", "pause the music", "next song" | Volume and media keys |
| "take a screenshot", "open my downloads", "lock the screen" | Misc |
| "toggle dark mode" | Appearance |

### Things that need looking at the screen

This is the part other voice assistants can't do:

| Say | It does |
| --- | --- |
| "reply to this email saying yes, Tuesday works" | Finds Reply, focuses the body, writes, stops before sending |
| "mark everything in my inbox as read" | Walks the message list |
| "in system settings, turn on night shift" | Navigates the settings tree |
| "find the cheapest flight to London on google flights" | Fills the form, reads the results |
| "add milk to my shopping list in reminders" | Finds the list, adds the item |
| "unmute myself in zoom" | Finds the control even when it's an unlabelled icon |

It shows you each step in the pill as it goes — `step 3/12: clicking Reply` —
and stops and asks before anything destructive.

---

## Install

Download the latest `.dmg` from
[Releases](https://github.com/calebvergene/jev-control-mac/releases), drag it to
Applications, and open it. It's signed and notarized, so it just opens.

Or build from source:

```bash
git clone https://github.com/calebvergene/jev-control-mac.git
cd jev-control-mac
./Scripts/install.sh
```

Grant **Accessibility** and **Input Monitoring** when asked. Both are required:
the first lets it read and drive on-screen controls, the second lets it see the
push-to-talk key without the app you're controlling seeing it.

On first launch it downloads a Whisper speech model (~150 MB) from Hugging Face.

---

## How it works

```
mic ─► push-to-talk ─► Whisper (on device, ~90 ms) ─► Jev (~250 ms) ─► macOS
                                                          │
                                       needs the screen? ──┴─► agent loop
                                                               │
                              accessibility tree ─► Jev ─► click / type / key
                                      │
                              empty tree? ─► screen capture + OCR
```

**Speech never leaves your Mac.** Transcription runs locally with
[WhisperKit](https://github.com/argmaxinc/WhisperKit) on the Neural Engine.

**The model never writes commands.** This is the important part. Jev
([TypeSafe System One](https://console.typesafe.ai)) doesn't generate text — it
*selects* from options that code produced. The app to open comes from the list
of apps actually installed on your Mac. The button to click is an
`AXUIElement` the app is already showing. The text to type is a span cut out of
your own words.

It cannot invent a shell command, because it is never asked to write one.

**It verifies its own work.** After each step it re-reads the screen and checks
the thing it claimed to do actually happened. "Done" is a claim that has to
survive a second look at fresh state, not something it can simply assert.

---

## Safety

- **Nothing destructive without asking.** Send, delete, purchase, and "empty
  trash" trigger a spoken confirmation you have to answer out loud.
- **Password fields are off limits.** macOS secure input is detected and the
  agent refuses to act.
- **Bounded runs.** 12 steps, 20 seconds, Escape aborts instantly.
- **No loops.** Repeating an action that changed nothing stops the run.
- **App allowlist.** Restrict it to apps you choose, or block ones you don't.
- **Everything is logged.** Every decision, every probability, replayable
  offline.

---

## The Decisions window

Open it from the menu bar to see exactly why it did what it did:

```
"open chrome and go to youtube"         Open Google Chrome · 94% · 212 ms
  action        open_app          ████████████████░░  0.94
  app           Google Chrome     ██████████████████  0.97
  compound      0.91              █████████████████░  0.91
  addressed     0.98              ██████████████████  0.98
  text          c0                ████████░░░░░░░░░░  0.44
```

When it gets something wrong, you can see which judgement caused it.

---

## Requirements

- macOS 13 Ventura or later
- Apple Silicon recommended (Intel works, transcription is slower)
- A [TypeSafe API key](https://console.typesafe.ai) for the intent layer
- About 150 MB for the speech model

---

## FAQ

**Does my voice get sent anywhere?**
No. Transcription is local. Only the resulting *text* goes to Jev, and only
when you hold the key.

**Does it work offline?**
Speech recognition does. Deciding what to do needs a network call.

**Can it run without an API key?**
Speech to text works. Acting on it doesn't.

**Will it work in my app?**
If your app is accessible to VoiceOver, yes. If not, it falls back to screen
capture and OCR, which handles canvas apps, PDFs and games.

**Is it safe to leave running?**
It only listens while you hold the key. There's no wake word unless you turn
one on.

**Why Left Option and not Caps Lock?**
Option gives a clean press and release with nothing to install. Caps Lock is a
latching toggle and needs a system-wide remap — it's available if you want it.

**How is this different from a Claude/GPT computer-use agent?**
Those generate actions as text, then something executes the text. Here the
model only picks from actions code already validated. It's faster, cheaper, and
it can't emit something that wasn't on the list.

---

## Keywords

macOS voice control · Mac voice assistant · control your Mac with your voice ·
open source Siri alternative · hands-free Mac · voice automation macOS ·
offline speech recognition Mac · Whisper macOS app · push to talk dictation ·
accessibility automation · AI agent for macOS · computer use agent Mac ·
Swift menu bar app · voice-driven GUI automation

---

## Credits

A macOS-native descendant of [jev-voice](https://github.com/kevinbadi/jev-voice),
whose intent layer and select-don't-generate approach this follows. Speech by
[WhisperKit](https://github.com/argmaxinc/WhisperKit). Intent by
[TypeSafe](https://console.typesafe.ai).

## License

MIT — see [LICENSE](LICENSE).
