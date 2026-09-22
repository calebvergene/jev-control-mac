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

    /// macOS caches some TCC answers per-process — Input Monitoring in
    /// particular — so a grant can be live in System Settings while this
    /// process still sees the old value. Surfaced as a Relaunch button rather
    /// than left as a mystery.
    @Published private(set) var needsRelaunch = false
    private var staleTicks = 0

    @Published var showPill: Bool = UserDefaults.standard.object(forKey: Keys.showPill) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showPill, forKey: Keys.showPill)
            pill.isEnabled = showPill
        }
    }

    @Published var playSounds: Bool = UserDefaults.standard.object(forKey: Keys.playSounds) as? Bool ?? true {
        didSet { UserDefaults.standard.set(playSounds, forKey: Keys.playSounds) }
    }

    @Published var trigger: HotkeyTrigger = {
        let stored = UserDefaults.standard.string(forKey: Keys.trigger) ?? ""
        return HotkeyTrigger(rawValue: stored) ?? .default
    }() {
        didSet {
            UserDefaults.standard.set(trigger.rawValue, forKey: Keys.trigger)
            hotkey.trigger = trigger
            refresh()
        }
    }

    @Published var model: WhisperModel = {
        let stored = UserDefaults.standard.string(forKey: Keys.model) ?? ""
        return WhisperModel(rawValue: stored) ?? .default
    }() {
        didSet {
            guard model != oldValue else { return }
            UserDefaults.standard.set(model.rawValue, forKey: Keys.model)
            loadModel()
        }
    }

    /// nil means "follow the system default input".
    @Published var microphoneUID: String? = UserDefaults.standard.string(forKey: Keys.microphone) {
        didSet {
            UserDefaults.standard.set(microphoneUID, forKey: Keys.microphone)
        }
    }

    @Published private(set) var speechStatus: Transcriber.Status = .idle
    /// The last thing heard, kept for the Setup window.
    @Published private(set) var lastTranscript: String?

    /// True when the chosen trigger needs a remap that is not installed.
    var needsRemap: Bool { trigger.needsCapsLockRemap && !remapActive }

    let pill = PillController()
    let hotkey = HotkeyManager()

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    /// Guards against a second utterance landing while the first is transcribing.
    private var transcriptionTask: Task<Void, Never>?

    private var pollTimer: Timer?

    private enum Keys {
        static let showPill = "ai.jev.control.showPill"
        static let playSounds = "ai.jev.control.playSounds"
        static let trigger = "ai.jev.control.trigger"
        static let model = "ai.jev.control.model"
        static let microphone = "ai.jev.control.microphone"
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
        hotkey.trigger = trigger
        refresh()
        pill.isEnabled = showPill
        pill.set(.idle, "Idle")
        hotkey.start()
        startPolling()
        loadModel()
    }

    func shutDown() {
        pollTimer?.invalidate()
        pollTimer = nil
        transcriptionTask?.cancel()
        recorder.stop()
        hotkey.stop()
        pill.hide()
    }

    // MARK: - Speech model

    /// Downloads if needed, loads, and prewarms. First run pulls the weights
    /// from Hugging Face, which is why the pill says so rather than just
    /// failing to hear anything.
    private func loadModel() {
        let model = self.model
        Task { [weak self] in
            guard let self else { return }
            await self.transcriber.prepare(model: model) { status in
                Task { @MainActor [weak self] in
                    self?.apply(speechStatus: status)
                }
            }
        }
    }

    private func apply(speechStatus status: Transcriber.Status) {
        speechStatus = status
        switch status {
        case .failed(let message):
            lastError = "Speech model: \(message)"
            pill.set(.error, "Speech model failed to load", revertAfter: 6)
        case .downloading(let fraction) where fraction > 0 && fraction < 1:
            // Only while idle: a download finishing mid-utterance must not
            // stomp on the transcript.
            if !isListening {
                pill.set(.thinking, "Downloading \(model.title) model… \(Int(fraction * 100))%")
            }
        case .ready:
            if !isListening { pill.set(.idle, "Idle") }
        default:
            break
        }
    }

    /// TCC grants land asynchronously and without a notification, so the only
    /// reliable way to notice one is to keep asking.
    ///
    /// The timer is added to `.common` modes by hand: `scheduledTimer` installs
    /// into `.default` only, which stalls the moment the run loop switches to a
    /// tracking mode — exactly what happens while the menu bar menu is open.
    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // Coming back from System Settings is the moment a grant usually lands.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        permissions = Permissions.snapshot()
        remapActive = CapsLockRemap.isActive()
        remapPersisted = CapsLockRemap.isPersisted()
        isTapActive = hotkey.isTapActive

        // The tap is ground truth: if it installed, the OS is honouring the
        // grant whatever the cached read says. Only the opposite case — boxes
        // ticked but the tap still refused — means a stale in-process value.
        if !isTapActive && permissions.requiredAreGranted {
            staleTicks += 1
        } else {
            staleTicks = 0
        }
        needsRelaunch = staleTicks > 10 // ~5s at the current poll interval
    }

    /// Launch a fresh copy and exit, so the new process picks up the grant.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
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
        // A new utterance supersedes one still being transcribed.
        transcriptionTask?.cancel()

        do {
            try recorder.start(deviceUID: microphoneUID)
        } catch {
            pill.set(.error, error.localizedDescription, revertAfter: 4)
            lastError = error.localizedDescription
            if case AudioRecorder.RecorderError.noInputAvailable = error,
               !permissions[.microphone].isGranted {
                Permissions.openSettings(.microphone)
            }
            return
        }

        isListening = true
        isLatched = false
        lastError = nil
        play(.start)
        pill.set(.listening, "Listening…")
    }

    private func endListening(wasLatched: Bool) {
        isListening = false
        isLatched = false
        play(.stop)

        let samples = recorder.stop()
        let speech = SilenceTrimmer.trim(samples)

        guard !speech.isEmpty else {
            pill.set(.idle, "Heard nothing", revertAfter: 1.5)
            return
        }

        guard speechStatus.isReady else {
            pill.set(.thinking, "Still loading the speech model…", revertAfter: 3)
            return
        }

        let seconds = Double(speech.count) / AudioRecorder.sampleRate
        pill.set(.thinking, "Transcribing…")

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            do {
                let text = try await self.transcriber.transcribe(speech)
                guard !Task.isCancelled else { return }
                let elapsed = Date().timeIntervalSince(started)
                self.lastTranscript = text
                self.pill.set(.heard, text, revertAfter: 5)
                Log.debug(String(format: "heard %.1fs of speech in %.0f ms: %@",
                                 seconds, elapsed * 1000, text))
            } catch Transcriber.TranscriberError.empty {
                guard !Task.isCancelled else { return }
                self.pill.set(.idle, "Heard nothing", revertAfter: 1.5)
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                self.pill.set(.error, error.localizedDescription, revertAfter: 4)
            }
        }
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
