import Foundation
import os

/// Minimal logging. `log stream --predicate 'subsystem == "ai.jev.control"'`
/// shows it live without attaching a debugger.
enum Log {
    private static let logger = Logger(subsystem: "ai.jev.control", category: "app")

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
