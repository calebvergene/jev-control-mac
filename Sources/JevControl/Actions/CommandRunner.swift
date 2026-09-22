import AppKit
import Foundation

/// Executes a `Plan`. The only place in the app that causes side effects.
@MainActor
enum CommandRunner {
    enum Outcome {
        case done(String)
        case unsure(String)
        case notACommand
        case unsupported(String)
        case stop

        var isFailure: Bool {
            if case .done = self { return false }
            if case .stop = self { return false }
            return true
        }
    }

    static func run(_ plan: Plan) async -> Outcome {
        guard plan.confidence >= Brain.minimumConfidence else {
            return .unsure("Not sure — \(Int(plan.confidence * 100))%")
        }
        if case .none = plan.action { return .notACommand }
        if case .stop = plan.action { return .stop }

        // "type this in notes": focus first, so keystrokes land in the right app.
        if let app = plan.inApp {
            _ = await AppCatalog.focus(app: app)
        }

        switch plan.action {
        case .openApp(let app):
            guard AppCatalog.open(app: app) else {
                return .unsupported("Could not find \(app)")
            }
            return .done("Opening \(app)")

        case .openWebsite(let url, let label):
            Executor.open(url: url)
            return .done("Opening \(label)")

        case .webSearch(let engine, let query):
            Executor.search(engine: engine, query: query)
            return .done("Searching \(engine)")

        case .typeText(let text, let submit):
            Keyboard.type(text)
            if submit {
                try? await Task.sleep(nanoseconds: 120_000_000)
                Keyboard.press(.enterKey)
            }
            return .done("Typed")

        case .newItem(let kind, let title):
            switch kind {
            case "tab": Keyboard.press(.newTab)
            case "window": Keyboard.post(keyCode: 45, flags: [.maskCommand, .maskShift]) // ⇧⌘N
            default: Keyboard.press(.new)
            }
            if let title, !title.isEmpty {
                try? await Task.sleep(nanoseconds: 350_000_000)
                Keyboard.type(title)
            }
            return .done("New \(kind)")

        case .shortcut(let shortcut):
            Keyboard.press(shortcut)
            return .done(shortcut.rawValue.replacingOccurrences(of: "_", with: " "))

        case .scroll(let direction, let amount):
            Keyboard.scroll(direction: direction, amount: amount)
            return .done("Scrolled \(direction)")

        case .volume(let op):
            return .done(Executor.volume(op))

        case .media(let op):
            Executor.media(op)
            return .done(op.replacingOccurrences(of: "_", with: "/"))

        case .screenshot:
            return .done(Executor.screenshot())

        case .openFolder(let folder):
            Executor.open(folder: folder)
            return .done("Opening \(folder)")

        case .system(let op):
            return .done(Executor.system(op))

        case .task:
            // The GUI agent loop is not built yet; saying so beats pretending.
            return .unsupported("On-screen tasks are not supported yet")

        case .stop:
            return .stop

        case .none:
            return .notACommand
        }
    }
}
