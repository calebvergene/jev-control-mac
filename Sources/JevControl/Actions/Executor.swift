import AppKit
import Foundation

/// Everything the assistant can actually do. Plain code — no model involved
/// past the point a `Plan` is produced.
enum Executor {
    static let sites: [String: String] = [
        "youtube": "https://www.youtube.com",
        "google": "https://www.google.com",
        "gmail": "https://mail.google.com",
        "google_calendar": "https://calendar.google.com",
        "google_drive": "https://drive.google.com",
        "google_docs": "https://docs.google.com",
        "google_maps": "https://maps.google.com",
        "github": "https://github.com",
        "twitter_x": "https://x.com",
        "reddit": "https://www.reddit.com",
        "amazon": "https://www.amazon.com",
        "netflix": "https://www.netflix.com",
        "chatgpt": "https://chatgpt.com",
        "claude": "https://claude.ai",
        "notion": "https://www.notion.so",
        "spotify_web": "https://open.spotify.com",
        "linkedin": "https://www.linkedin.com",
        "instagram": "https://www.instagram.com",
        "facebook": "https://www.facebook.com",
        "wikipedia": "https://en.wikipedia.org",
        "hacker_news": "https://news.ycombinator.com",
        "twitch": "https://www.twitch.tv",
        "figma": "https://www.figma.com",
    ]

    static let searchEngines: [String: String] = [
        "google": "https://www.google.com/search?q={q}",
        "youtube": "https://www.youtube.com/results?search_query={q}",
        "amazon": "https://www.amazon.com/s?k={q}",
        "wikipedia": "https://en.wikipedia.org/w/index.php?search={q}",
        "github": "https://github.com/search?q={q}",
        "google_maps": "https://www.google.com/maps/search/{q}",
        "twitter_x": "https://x.com/search?q={q}",
        "reddit": "https://www.reddit.com/search/?q={q}",
        "spotify": "https://open.spotify.com/search/{q}",
        "perplexity": "https://www.perplexity.ai/search?q={q}",
    ]

    static let folders: [String: String] = [
        "home": NSHomeDirectory(),
        "desktop": NSHomeDirectory() + "/Desktop",
        "downloads": NSHomeDirectory() + "/Downloads",
        "documents": NSHomeDirectory() + "/Documents",
        "pictures": NSHomeDirectory() + "/Pictures",
        "movies": NSHomeDirectory() + "/Movies",
        "applications": "/Applications",
    ]

    // MARK: - Web

    static func open(url: String) {
        var text = url
        if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
            text = "https://" + text
        }
        guard let parsed = URL(string: text) else { return }
        NSWorkspace.shared.open(parsed)
    }

    static func search(engine: String, query: String) {
        let template = searchEngines[engine] ?? searchEngines["google"]!
        let escaped = query.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))
        ) ?? query
        open(url: template.replacingOccurrences(of: "{q}", with: escaped))
    }

    static func open(folder: String) {
        let path = folders[folder] ?? NSHomeDirectory()
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Volume

    /// AppleScript for volume specifically: `set volume` is a scripting
    /// addition rather than control of another app, so it needs no Automation
    /// permission, and the CoreAudio equivalent has to handle per-channel
    /// devices to get the same result.
    @discardableResult
    static func volume(_ op: String) -> String {
        switch op {
        case "mute":
            runAppleScript("set volume with output muted")
            return "Muted"
        case "unmute":
            runAppleScript("set volume without output muted")
            return "Unmuted"
        case "max":
            runAppleScript("set volume output volume 100")
            return "Max volume"
        case "half":
            runAppleScript("set volume output volume 50")
            return "Half volume"
        case "up", "down":
            let current = Int(runAppleScript("output volume of (get volume settings)") ?? "50") ?? 50
            let next = max(0, min(100, current + (op == "up" ? 15 : -15)))
            runAppleScript("set volume output volume \(next)")
            return op == "up" ? "Louder" : "Quieter"
        default:
            return ""
        }
    }

    // MARK: - Media keys

    private static let mediaKeys = ["play_pause": 16, "next": 17, "previous": 18]

    /// Posts a system-defined HID event, which Music, Spotify and browser video
    /// all honour — unlike a keyboard shortcut, which only reaches the focused
    /// app.
    static func media(_ op: String) {
        guard let key = mediaKeys[op] else { return }
        for isDown in [true, false] {
            let flags: NSEvent.ModifierFlags = isDown
                ? NSEvent.ModifierFlags(rawValue: 0xA00)
                : NSEvent.ModifierFlags(rawValue: 0xB00)
            let data1 = (key << 16) | ((isDown ? 0xA : 0xB) << 8)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ), let cgEvent = event.cgEvent else { continue }
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - System

    @discardableResult
    static func system(_ op: String) -> String {
        switch op {
        case "lock":
            Keyboard.press(.lockScreen)
            return "Locking"
        case "sleep_display":
            shell("/usr/bin/pmset", ["displaysleepnow"])
            return "Sleeping the display"
        case "show_desktop":
            Keyboard.press(.showDesktop)
            return "Showing desktop"
        case "toggle_dark_mode":
            runAppleScript(
                "tell application \"System Events\" to tell appearance preferences "
                    + "to set dark mode to not dark mode"
            )
            return "Toggled dark mode"
        case "empty_trash":
            runAppleScript("tell application \"Finder\" to empty trash")
            return "Emptied the trash"
        default:
            return ""
        }
    }

    @discardableResult
    static func screenshot() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let path = NSHomeDirectory() + "/Desktop/Screenshot \(formatter.string(from: Date())).png"
        shell("/usr/sbin/screencapture", ["-x", path])
        return "Screenshot saved"
    }

    // MARK: - Process helpers

    @discardableResult
    static func runAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            Log.error("AppleScript failed: \(error)")
            return nil
        }
        return result?.stringValue
    }

    private static func shell(_ path: String, _ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        try? task.run()
    }
}
