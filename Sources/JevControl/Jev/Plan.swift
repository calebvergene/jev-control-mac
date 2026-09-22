import Foundation

/// What the executor should do. Every associated value came from a closed set
/// or a span cut out of the transcript — nothing here was written by the model.
enum PlanAction: Equatable {
    case openApp(String)
    case openWebsite(url: String, label: String)
    case webSearch(engine: String, query: String)
    case typeText(String, submit: Bool)
    case newItem(kind: String, title: String?)
    case shortcut(Keyboard.Shortcut)
    case scroll(direction: String, amount: String)
    case volume(String)
    case media(String)
    case screenshot
    case openFolder(String)
    case system(String)
    /// Needs looking at the screen — the GUI agent loop, not yet built.
    case task(String)
    case stop
    case none

    var label: String {
        switch self {
        case .openApp(let app): return "Open \(app)"
        case .openWebsite(_, let label): return "Go to \(label)"
        case .webSearch(let engine, let query): return "Search \(engine) for “\(query)”"
        case .typeText(let text, let submit):
            return "Type “\(text)”" + (submit ? " and press enter" : "")
        case .newItem(let kind, let title):
            return "New \(kind)" + (title.map { " “\($0)”" } ?? "")
        case .shortcut(let shortcut): return "Press \(shortcut.rawValue.replacingOccurrences(of: "_", with: " "))"
        case .scroll(let direction, let amount): return "Scroll \(direction) (\(amount))"
        case .volume(let op): return "Volume \(op)"
        case .media(let op): return "Media \(op.replacingOccurrences(of: "_", with: "/"))"
        case .screenshot: return "Take a screenshot"
        case .openFolder(let folder): return "Open \(folder)"
        case .system(let op): return "System \(op.replacingOccurrences(of: "_", with: " "))"
        case .task(let goal): return "Task: \(goal)"
        case .stop: return "Stop listening"
        case .none: return "Not a command"
        }
    }
}

struct Plan {
    let utterance: String
    var action: PlanAction
    /// The minimum over every judgement the plan actually relied on — so one
    /// shaky answer drags the whole plan down rather than being averaged away.
    var confidence: Double
    /// An app to focus before acting inside it ("type this in notes").
    var inApp: String?
    var isCompound: Bool = false
    /// Every raw answer, for the debug window.
    var answers: [String: JevAnswer] = [:]
    var latencyMs: Int = 0

    var summary: String {
        String(format: "%@ · %.0f%% · %d ms", action.label, confidence * 100, latencyMs)
    }
}
