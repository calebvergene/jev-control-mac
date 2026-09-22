import AppKit
import Foundation

/// The installed applications, which become the choice set Jev picks from.
///
/// The model is never asked to name an app freely — it selects from what is
/// actually on this Mac, so an executable name can't be invented.
enum AppCatalog {
    private static let searchPaths = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    /// Names people say aloud that may not be in /Applications.
    private static let always = [
        "Finder", "Safari", "Terminal", "System Settings", "Notes", "Messages",
        "Mail", "Calendar", "Music", "Reminders", "Photos", "Calculator",
        "TextEdit", "Preview", "Activity Monitor", "FaceTime", "Maps",
    ]

    private static var cached: [String]?

    static func installedApps() -> [String] {
        if let cached { return cached }

        var names = Set(always)
        for path in searchPaths {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".app") {
                names.insert(String(entry.dropLast(4)))
            }
        }
        let sorted = names.sorted { $0.lowercased() < $1.lowercased() }
        cached = sorted
        return sorted
    }

    static func invalidate() { cached = nil }

    static func frontmostApp() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }

    static func url(forApp name: String) -> URL? {
        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
    }

    @discardableResult
    static func open(app name: String) -> Bool {
        guard let url = url(forApp: name) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        return true
    }

    /// Brings an app to the front and waits until it really is frontmost, so a
    /// keystroke sent straight afterwards lands in it rather than in whatever
    /// was focused before.
    static func focus(app name: String, timeout: TimeInterval = 2.0) async -> Bool {
        if frontmostApp().lowercased() == name.lowercased() { return true }

        let running = NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.lowercased() == name.lowercased()
        }
        if let running {
            running.activate(options: [])
        } else {
            guard open(app: name) else { return false }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if frontmostApp().lowercased() == name.lowercased() {
                // Let the window actually take key focus.
                try? await Task.sleep(nanoseconds: 150_000_000)
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
}
