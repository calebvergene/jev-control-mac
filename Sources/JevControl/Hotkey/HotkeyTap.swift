import CoreGraphics
import Foundation

/// A listen-and-swallow `CGEvent` tap on the push-to-talk key.
///
/// The tap sits on the session tap at head-insert, so it sees the key before
/// the focused app does and returns `nil` for it — the app being controlled
/// never learns the key was pressed.
final class HotkeyTap {
    /// Changing this re-arms the tap's internal state; it does not need a restart.
    var trigger: HotkeyTrigger = .default {
        didSet {
            guard trigger != oldValue else { return }
            isDown = false
        }
    }

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

        // Modifier triggers arrive as flagsChanged; key events are still needed
        // so their stale modifier flags can be scrubbed while the key is held.
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
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

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if trigger.isModifier {
            if type == .flagsChanged && keyCode == trigger.keyCode {
                setDown(event.flags.rawValue & trigger.deviceFlagMask != 0)
                return nil // swallow: the focused app never sees the modifier
            }
            // The window server stamps modifier flags from hardware state, not
            // from this tap, so a swallowed Option is still set on every key
            // pressed while it is held — which would turn "a" into "å".
            if isDown && (type == .keyDown || type == .keyUp) {
                scrubTriggerFlags(from: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard keyCode == trigger.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        // Held keys auto-repeat; only the first down and the final up matter.
        // Modifiers never auto-repeat, so this is the key-event path only.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        switch type {
        case .keyDown: setDown(true)
        case .keyUp: setDown(false)
        default: break
        }

        return nil // swallow
    }

    private func setDown(_ down: Bool) {
        guard down != isDown else { return }
        isDown = down
        let handler = down ? onKeyDown : onKeyUp
        DispatchQueue.main.async { handler?() }
    }

    /// Clear the trigger's own Option bit, and the shared `maskAlternate` too
    /// unless the *other* Option key is genuinely held.
    private func scrubTriggerFlags(from event: CGEvent) {
        var raw = event.flags.rawValue
        raw &= ~trigger.deviceFlagMask
        if raw & HotkeyTrigger.anyOptionDeviceMask == 0 {
            raw &= ~CGEventFlags.maskAlternate.rawValue
        }
        event.flags = CGEventFlags(rawValue: raw)
    }
}
