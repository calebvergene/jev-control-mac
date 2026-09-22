import AppKit
import Combine
import Foundation

/// Single source of truth for the menu bar, the onboarding window and the pill.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published state

    @Published private(set) var permissions = PermissionSnapshot()
    @Published private(set) var remapActive = false
    @Published private(set) var remapPersisted = false
    @Published private(set) var isTapActive = false
    @Published private(set) var isListening = false
    @Published private(set) var isLatched = false
    @Published private(set) var lastError: String?

    @Published var showPill: Bool = UserDefaults.standard.object(forKey: Keys.showPill) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showPill, forKey: Keys.showPill)
            pill.isEnabled = showPill
        }
    }

    @Published var playSounds: Bool = UserDefaults.standard.object(forKey: Keys.playSounds) as? Bool ?? true {
        didSet { UserDefaults.standard.set(playSounds, forKey: Keys.playSounds) }
    }

    let pill = PillController()
    let hotkey = HotkeyManager()

    private var pollTimer: Timer?

    private enum Keys {
        static let showPill = "ai.jev.control.showPill"
        static let playSounds = "ai.jev.control.playSounds"
    }

    private init() {
        hotkey.onStart = { [weak self] in self?.beginListening() }
        hotkey.onStop = { [weak self] latched in self?.endListening(wasLatched: latched) }
        hotkey.onLatch = { [weak self] in self?.markLatched() }
        hotkey.onTapStateChange = { [weak self] active in
            guard let self else { return }
            self.isTapActive = active
            if !active { self.pill.set(.idle, "Waiting for permissions") }
        }
    }

    // MARK: - Lifecycle

    func start() {
        refresh()
        pill.isEnabled = showPill
        pill.set(.idle, "Idle")
        hotkey.start()
        startPolling()
    }

    func shutDown() {
        pollTimer?.invalidate()
        pollTimer = nil
        hotkey.stop()
        pill.hide()
    }

    /// TCC grants land asynchronously and without a notification, so the only
    /// reliable way to notice one is to keep asking.
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        permissions = Permissions.snapshot()
        remapActive = CapsLockRemap.isActive()
        remapPersisted = CapsLockRemap.isPersisted()
        if !isTapActive {
            isTapActive = hotkey.isTapActive
        }
    }

    // MARK: - Permissions

    func request(_ kind: PermissionKind) {
        let before = Permissions.check(kind)
        Permissions.request(kind) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                // Already-decided permissions produce no prompt; send the user
                // to the pane instead of leaving them staring at nothing.
                if before == .denied || (before != .granted && self.permissions[kind] == before) {
                    Permissions.openSettings(kind)
                }
            }
        }
    }

    // MARK: - Caps Lock remap

    func installRemap() {
        switch CapsLockRemap.install() {
        case .success:
            lastError = nil
        case .failure(let error):
            lastError = error.errorDescription
        }
        refresh()
    }

    func removeRemap() {
        switch CapsLockRemap.remove() {
        case .success:
            lastError = nil
        case .failure(let error):
            lastError = error.errorDescription
        }
        refresh()
    }

    // MARK: - Push-to-talk

    private func beginListening() {
        isListening = true
        isLatched = false
        play(.start)
        pill.set(.listening, "Listening…")
    }

    private func endListening(wasLatched: Bool) {
        isListening = false
        isLatched = false
        play(.stop)
        // Chunk 2 replaces this with the transcript.
        pill.set(.idle, "Idle")
    }

    /// The press turned out to be a tap: recording stays on until the next press.
    private func markLatched() {
        isLatched = true
        pill.set(.listening, "Listening…", isLatched: true)
    }

    // MARK: - Feedback

    private enum Chime: String {
        case start = "Tink"
        case stop = "Pop"
    }

    private func play(_ chime: Chime) {
        guard playSounds else { return }
        NSSound(named: chime.rawValue)?.play()
    }
}
