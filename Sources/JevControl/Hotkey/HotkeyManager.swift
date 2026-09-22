import Foundation
import QuartzCore

/// Push-to-talk semantics on top of the raw F18 tap.
///
/// Hold to talk, release to send. A press shorter than `tapThreshold` latches
/// instead, so you can start a long utterance without holding the key; the next
/// press unlatches and sends. This mirrors jev-voice's `run_capslock`.
@MainActor
final class HotkeyManager {
    static let tapThreshold: TimeInterval = 0.25

    /// Called when recording should begin.
    var onStart: (() -> Void)?
    /// Called when recording should end. `latched` says whether the run was
    /// hands-free, which later chunks use to pick a different end-of-speech rule.
    var onStop: ((_ wasLatched: Bool) -> Void)?
    /// Called whenever the tap's availability changes.
    var onTapStateChange: ((Bool) -> Void)?
    /// Called when a short tap latches recording on (hands-free).
    var onLatch: (() -> Void)?

    private(set) var isListening = false
    private(set) var isLatched = false
    var isTapActive: Bool { tap.isRunning }

    /// Switching keys mid-run cancels anything in flight, so a half-held key
    /// cannot leave the app stuck listening.
    var trigger: HotkeyTrigger {
        get { tap.trigger }
        set {
            guard newValue != tap.trigger else { return }
            if isListening { finish(latched: isLatched) }
            tap.trigger = newValue
        }
    }

    private let tap = HotkeyTap()
    private var pressedAt: CFTimeInterval = 0
    private var retryTimer: Timer?

    init() {
        tap.onKeyDown = { [weak self] in self?.handlePress() }
        tap.onKeyUp = { [weak self] in self?.handleRelease() }
    }

    // MARK: - Lifecycle

    /// Tries to install the tap. On refusal, retries every 2s so the app comes
    /// alive the moment the user ticks the boxes in System Settings — without a
    /// relaunch.
    @discardableResult
    func start() -> Bool {
        let ok = tap.start()
        onTapStateChange?(ok)
        if ok {
            retryTimer?.invalidate()
            retryTimer = nil
        } else {
            scheduleRetry()
        }
        return ok
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if isListening { finish(latched: isLatched) }
        tap.stop()
        onTapStateChange?(false)
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.tap.start() else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.onTapStateChange?(true)
            }
        }
    }

    // MARK: - State machine

    private func handlePress() {
        pressedAt = CACurrentMediaTime()

        // A press while latched ends the hands-free run.
        if isLatched {
            isLatched = false
            finish(latched: true)
            return
        }

        guard !isListening else { return }
        isListening = true
        onStart?()
    }

    private func handleRelease() {
        guard isListening else { return }

        if CACurrentMediaTime() - pressedAt < Self.tapThreshold {
            // Short tap: keep recording, hands-free, until the next press.
            isLatched = true
            onLatch?()
            return
        }
        finish(latched: false)
    }

    private func finish(latched: Bool) {
        isListening = false
        isLatched = false
        onStop?(latched)
    }
}
