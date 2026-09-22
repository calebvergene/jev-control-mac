import Foundation

/// Turns a transcript into a `Plan`, with one Jev request per utterance.
///
/// Every question the executor could need is asked speculatively in the same
/// request and evaluated in parallel. Only the answers the chosen action
/// actually uses are read, and the plan's confidence is the *minimum* over
/// those — so a shaky sub-answer drags the whole plan below the threshold
/// rather than being averaged away by confident ones.
struct Brain {
    /// Below this, say "not sure" instead of acting.
    static let minimumConfidence = 0.35

    private let client: JevClient

    init(client: JevClient) {
        self.client = client
    }

    static let actions: [String: String] = [
        "open_app": "Launch, open, switch to, or bring up an application program on the Mac (for example Chrome, Cursor, Slack, Finder, Terminal, Notes)",
        "open_website": "Go to a website or web page by name or domain, with no search query (for example 'go to youtube', 'open reddit', 'pull up gmail')",
        "web_search": "Search for something on the web or on a specific site: Google it, look it up, find videos of, search YouTube for, search Amazon for",
        "type_text": "Type, write, dictate, or enter some text into whatever is currently focused",
        "new_item": "Create something new inside an app: a new note, document, file, tab, window, message, email, or page (for example 'new note', 'make a new note called groceries', 'new document')",
        "shortcut": "Press a single key or keyboard shortcut: enter, escape, tab, copy, paste, undo, save, select all, new tab, close tab, reload, go back, quit the app, switch app, and similar",
        "scroll": "Scroll the current page or document up or down, to the top or bottom",
        "volume": "Change the system sound volume: louder, quieter, mute, unmute, max",
        "media": "Control music or video playback: play, pause, resume, next track, previous track, skip",
        "screenshot": "Take a screenshot of the screen",
        "open_folder": "Open a folder like Downloads, Desktop, Documents, or the home folder in Finder",
        "system": "System-level action: lock the screen, put the display to sleep, show the desktop, toggle dark mode, empty the trash",
        "task": "A multi-step task that needs looking at the screen and doing several things inside an app or website: fill in a form, find and click something specific, reply to a message, search a site and open a result, change a setting, compose and send an email",
        "stop": "Tell the assistant to stop listening, go to sleep, or exit",
        "none": "Not a command for the computer: conversation, thinking aloud, background chatter, or unintelligible",
    ]

    static let shortcutCriteria: [String: String] = [
        "enter": "press enter / return / submit",
        "escape": "press escape / cancel / dismiss",
        "tab": "press the tab key",
        "space": "press the space bar",
        "backspace": "delete the previous character / backspace",
        "arrow_up": "press the up arrow",
        "arrow_down": "press the down arrow",
        "arrow_left": "press the left arrow",
        "arrow_right": "press the right arrow",
        "copy": "copy the selection",
        "paste": "paste from the clipboard",
        "cut": "cut the selection",
        "undo": "undo the last change",
        "redo": "redo",
        "select_all": "select all / select everything",
        "save": "save the file / document",
        "find": "open find / search within the page or document",
        "new": "create a new file, document, note, or message in the current app",
        "new_tab": "open a new browser tab",
        "close_tab_or_window": "close the current tab or window",
        "reopen_closed_tab": "reopen the last closed tab",
        "quit_app": "quit / exit the current application entirely",
        "minimize_window": "minimize the window",
        "hide_app": "hide the current app",
        "fullscreen": "toggle full screen",
        "next_tab": "switch to the next tab",
        "previous_tab": "switch to the previous tab",
        "browser_back": "go back to the previous page",
        "browser_forward": "go forward",
        "reload": "reload / refresh the page",
        "address_bar": "focus the browser address bar / URL bar",
        "spotlight": "open Spotlight search",
        "switch_app": "switch to the previous / next application (command-tab)",
        "next_window": "switch to the next window of the current app",
        "delete_word": "delete the previous word",
        "delete_line": "delete the current line / everything before the cursor on this line",
        "zoom_in": "zoom in / make text bigger",
        "zoom_out": "zoom out / make text smaller",
        "bold": "make the selection bold",
        "italic": "make the selection italic",
        "send_message": "send the message (command-enter)",
        "emoji_picker": "open the emoji picker",
    ]

    // MARK: - Questions

    private func questions(candidates: [String: String], apps: [String]) -> [String: JevQuestion] {
        var appCriteria: [String: String?] = Dictionary(uniqueKeysWithValues: apps.map { ($0, nil) })
        appCriteria["none"] = "No listed application matches what the user said"

        var siteCriteria: [String: String?] = Dictionary(
            uniqueKeysWithValues: Executor.sites.keys.map { ($0, nil) }
        )
        siteCriteria["other"] = "A site not in this list"

        return [
            "action": .choice(
                "The user is speaking a voice command to their Mac. `utterance` is the transcript. Which single kind of action are they asking the computer to perform right now?",
                Self.actions.mapValues { Optional($0) }
            ),
            "addressed": .noul(
                "Is `utterance` an instruction spoken to a voice assistant that controls this computer (open, type, search, scroll, press, play, close, and so on), rather than conversation with another person, a phone call, reading aloud, or thinking out loud?",
                yes: "A direct instruction for the computer to do something now",
                no: "Not directed at the computer, or not an instruction"
            ),
            "compound": .noul(
                "Does `utterance` ask for two or more separate actions to be performed one after another (for example 'open chrome and go to youtube')? A single action with several words is not compound.",
                yes: "Two or more distinct actions are requested",
                no: "Exactly one action is requested"
            ),
            "app": .choice(
                "Assume the user wants to open or switch to an application. Which installed application in `apps` do they mean? Match on meaning: 'chrome' means Google Chrome, 'settings' means System Settings, 'browser' means the default browser. Choose `none` if no listed app matches.",
                appCriteria
            ),
            "site": .choice(
                "Assume the user wants to open a website. Which site do they mean? Choose `other` if it is not one of the listed sites.",
                siteCriteria
            ),
            "engine": .choice(
                "Assume the user wants to search for something. Which site or search engine should the search run on? If the user does not name a site, choose google.",
                keys: Executor.searchEngines.keys.sorted()
            ),
            "text": .choice(
                "Assume the user wants some text typed or searched. `candidates` holds possible payloads cut from the utterance. Which candidate is exactly the payload text the user intends, with no command words (like 'type', 'search for', 'on youtube') and no trailing 'and press enter' included?",
                candidates.mapValues { Optional($0) }
            ),
            "in_app": .noul(
                "Does the user name a specific application that the action should happen inside of (for example 'in the notes app', 'in chrome', 'in cursor')? Naming an app as the thing to open does not count unless the action is something done inside it.",
                yes: "An application is named as the place where the action happens",
                no: "No application is named, or the app is only the thing being opened"
            ),
            "new_kind": .choice(
                "Assume the user wants to create something new. What kind of thing?",
                ["tab": "a new browser tab",
                 "window": "a new window",
                 "item": "a new note, document, file, message, email, page, or anything else created with the app's New command"]
            ),
            "has_title": .noul(
                "Assume the user is creating a new note, document, or file. Do they give it a title or initial text (for example 'called groceries', 'titled ideas', 'that says hello')?",
                yes: "A title or initial text is given",
                no: "No title or text is given"
            ),
            "submit": .noul(
                "After typing the text, does the user also want the enter/return key pressed (they say things like 'and hit enter', 'and send it', 'and search')?",
                yes: "The user explicitly asks to submit, send, or press enter afterwards",
                no: "They only want the text typed"
            ),
            "shortcut": .choice(
                "Assume the user wants a key or keyboard shortcut pressed. Which one?",
                Self.shortcutCriteria.mapValues { Optional($0) }
            ),
            "scroll_dir": .choice(
                "Assume the user wants to scroll. In which direction?",
                ["down": "scroll down / further", "up": "scroll up / back up",
                 "top": "jump to the very top", "bottom": "jump to the very bottom"]
            ),
            "scroll_amount": .choice(
                "Assume the user wants to scroll up or down. How far?",
                ["little": "a little / a bit / a few lines",
                 "page": "a normal amount, about one screen; the default when unspecified",
                 "a_lot": "a lot / way down / far"]
            ),
            "volume_op": .choice(
                "Assume the user wants to change the volume. What change?",
                ["up": "louder / turn it up", "down": "quieter / turn it down",
                 "mute": "mute / silence", "unmute": "unmute / sound back on",
                 "max": "maximum / all the way up", "half": "medium / half volume"]
            ),
            "media_op": .choice(
                "Assume the user wants to control playback. What?",
                ["play_pause": "play, pause, resume, or stop the current track or video",
                 "next": "next track / skip this song",
                 "previous": "previous track / go back a song"]
            ),
            "folder": .choice(
                "Assume the user wants to open a folder in Finder. Which one?",
                keys: Executor.folders.keys.sorted()
            ),
            "system_op": .choice(
                "Assume the user wants a system-level action. Which one?",
                ["lock": "lock the screen", "sleep_display": "put the display / screen to sleep",
                 "show_desktop": "show the desktop",
                 "toggle_dark_mode": "switch between dark and light mode",
                 "empty_trash": "empty the trash"]
            ),
        ]
    }

    // MARK: - Inference

    func evaluate(utterance: String, frontmostApp: String) async throws -> Plan {
        let apps = AppCatalog.installedApps()
        let candidates = TextCandidates.candidates(for: utterance)

        let state: [String: JSONValue] = [
            "utterance": .string(utterance),
            "frontmost_app": .string(frontmostApp),
            "apps": .strings(apps),
            "candidates": .map(candidates),
        ]

        let response = try await client.evaluate(
            state: state,
            questions: questions(candidates: candidates, apps: apps)
        )
        return plan(
            utterance: utterance,
            answers: response.answers,
            candidates: candidates,
            latencyMs: Int(response.latency * 1000)
        )
    }

    /// Reads only the answers the chosen action needs, taking the minimum
    /// confidence across them.
    func plan(
        utterance: String,
        answers: [String: JevAnswer],
        candidates: [String: String],
        latencyMs: Int
    ) -> Plan {
        guard let actionAnswer = answers["action"], let kind = actionAnswer.choice else {
            return Plan(utterance: utterance, action: .none, confidence: 0,
                        answers: answers, latencyMs: latencyMs)
        }

        var confidence = actionAnswer.confidence ?? 0

        func choice(_ key: String) -> (String, Double) {
            guard let answer = answers[key], let value = answer.choice else { return ("", 0) }
            return (value, answer.confidence ?? 0)
        }
        func isYes(_ key: String) -> Bool { answers[key]?.isYes ?? false }
        func narrow(_ value: Double) { confidence = min(confidence, value) }

        var action: PlanAction = .none
        var resolved = kind

        switch kind {
        case "open_app":
            let (app, appConfidence) = choice("app")
            narrow(appConfidence)
            action = app.isEmpty || app == "none" ? .none : .openApp(app)

        case "open_website":
            let (site, siteConfidence) = choice("site")
            if site != "other", let url = Executor.sites[site] {
                narrow(siteConfidence)
                action = .openWebsite(url: url, label: site.replacingOccurrences(of: "_", with: " "))
            } else if let domain = TextCandidates.domain(in: utterance) {
                action = .openWebsite(url: "https://" + domain, label: domain)
            } else {
                // Nothing to navigate to: a search is the useful fallback.
                resolved = "web_search"
            }

        case "type_text":
            let (key, textConfidence) = choice("text")
            narrow(textConfidence)
            action = .typeText(candidates[key] ?? utterance, submit: isYes("submit"))

        case "new_item":
            let (newKind, _) = choice("new_kind")
            var title: String?
            if isYes("has_title") {
                let (key, _) = choice("text")
                title = candidates[key]
            }
            action = .newItem(kind: newKind.isEmpty ? "item" : newKind, title: title)

        case "shortcut":
            let (name, shortcutConfidence) = choice("shortcut")
            narrow(shortcutConfidence)
            action = Keyboard.Shortcut(rawValue: name).map(PlanAction.shortcut) ?? .none

        case "scroll":
            let (direction, directionConfidence) = choice("scroll_dir")
            let (amount, _) = choice("scroll_amount")
            narrow(directionConfidence)
            action = .scroll(direction: direction, amount: amount.isEmpty ? "page" : amount)

        case "volume":
            let (op, opConfidence) = choice("volume_op")
            narrow(opConfidence)
            action = .volume(op)

        case "media":
            let (op, opConfidence) = choice("media_op")
            narrow(opConfidence)
            action = .media(op)

        case "open_folder":
            let (folder, folderConfidence) = choice("folder")
            narrow(folderConfidence)
            action = .openFolder(folder)

        case "system":
            let (op, opConfidence) = choice("system_op")
            narrow(opConfidence)
            action = .system(op)

        case "screenshot": action = .screenshot
        case "task": action = .task(utterance)
        case "stop": action = .stop
        default: action = .none
        }

        // The website branch can fall through to a search.
        if resolved == "web_search" {
            let (engine, _) = choice("engine")
            let (key, textConfidence) = choice("text")
            narrow(textConfidence)
            action = .webSearch(
                engine: engine.isEmpty ? "google" : engine,
                query: candidates[key] ?? utterance
            )
        }

        var inApp: String?
        if ["new_item", "shortcut", "type_text", "scroll"].contains(resolved), isYes("in_app") {
            let (app, _) = choice("app")
            if app != "none", !app.isEmpty { inApp = app }
        }

        return Plan(
            utterance: utterance,
            action: action,
            confidence: confidence,
            inApp: inApp,
            isCompound: isYes("compound"),
            answers: answers,
            latencyMs: latencyMs
        )
    }
}
