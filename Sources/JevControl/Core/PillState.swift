import SwiftUI

/// What the floating pill is showing. Chunk 1 only drives `idle` and
/// `listening`; the rest are the states the later chunks fill in, kept here so
/// the palette is decided once.
enum PillState: String {
    case idle
    case listening
    case heard
    case thinking
    case acting
    case done
    case error

    var color: Color {
        switch self {
        case .idle: return Color(red: 0.55, green: 0.55, blue: 0.58)
        case .listening: return Color(red: 0.95, green: 0.30, blue: 0.30)
        case .heard: return Color(red: 0.98, green: 0.78, blue: 0.25)
        case .thinking: return Color(red: 0.35, green: 0.60, blue: 1.00)
        case .acting: return Color(red: 0.60, green: 0.45, blue: 0.95)
        case .done: return Color(red: 0.30, green: 0.85, blue: 0.45)
        case .error: return Color(red: 1.00, green: 0.45, blue: 0.20)
        }
    }

    /// States where a pulsing dot reads as "something is happening".
    var isAnimated: Bool {
        self == .listening || self == .thinking || self == .acting
    }
}
