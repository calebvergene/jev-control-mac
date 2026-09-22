import CoreGraphics
import Foundation

/// A listen-and-swallow `CGEvent` tap on F18 (what Caps Lock became).
///
/// The tap sits on the session tap at head-insert, so it sees the key before
/// the focused app does and returns `nil` for it — the app being controlled
/// never learns that F18 was pressed.
final class HotkeyTap {
    /// macOS virtual keycode for F18.
    static let f18KeyCode: Int64 = 79

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private(set) var isRunning = false
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    deinit { stop() }

    /// Installs the tap on the current run loop. Returns false when macOS
    /// refuses — which in practice always means Accessibility or Input
    /// Monitoring is not granted to this bundle.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        machPort = port
        runLoopSource = source
        isRunning = true
        return true
    }

    func stop() {
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        machPort = nil
        runLoopSource = nil
        isDown = false
        isRunning = false
    }

    // MARK: - Tap callback

    /// Runs on the main run loop. Must stay cheap: a slow tap callback gets the
    /// tap disabled by timeout.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that took too long, or that raced user input.
        // Re-arming is the documented recovery.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = machPort { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.f18KeyCode else {
            return Unmanaged.passUnretained(event)
        }

        // Held keys auto-repeat; only the first down and the final up matter.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        switch type {
        case .keyDown where !isDown:
            isDown = true
            let handler = onKeyDown
            DispatchQueue.main.async { handler?() }
        case .keyUp where isDown:
            isDown = false
            let handler = onKeyUp
            DispatchQueue.main.async { handler?() }
        default:
            break
        }

        return nil // swallow: the focused app never sees F18
    }
}
