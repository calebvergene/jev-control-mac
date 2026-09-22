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

    /// Live transcript, refreshed while the key is held.
    ///
    /// `committedText` covers audio before `committedSamples` and never
    /// changes again; `liveTail` is the current, still-revisable hypothesis for
    /// everything after it.
    private var liveTimer: Timer?
    private var livePartialTask: Task<Void, Never>?
    private var committedText = ""
    private var committedSamples = 0
    private var liveTail = ""

    private var livePartial: String {
        guard !committedText.isEmpty else { return liveTail }
        guard !liveTail.isEmpty else { return committedText }
        return committedText + " " + liveTail
    }

    /// How often the growing buffer is re-transcribed. Short enough to feel
    /// live, long enough that a pass has comfortably finished before the next
    /// one starts — base.en does ~1.8s of audio in ~90 ms.
    private static let liveInterval: TimeInterval = 0.45
    /// Below this there is not enough audio for a useful hypothesis.
    private static let liveMinimumSeconds: Double = 0.6
    /// A pause this long ends a sentence, and what precedes it is frozen.
    private static let commitSilenceSeconds: TimeInterval = 0.5
    /// Never commit on less speech than this.
    private static let commitMinimumSpeechSeconds: TimeInterval = 0.4
    /// Past this much unsettled audio, commit on a much shorter pause — nobody
    /// should watch a whole paragraph rewrite itself because they did not
    /// breathe.
    private static let forceCommitAfterSeconds: Double = 6.0
    private static let forcedCommitSilenceSeconds: TimeInterval = 0.15

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
        committedText = ""
        committedSamples = 0
        liveTail = ""
        play(.start)
        pill.set(.listening, "Listening…")
        startLiveTranscript()
    }

    // MARK: - Live transcript

    /// Re-transcribes everything captured so far, on a timer, so the pill fills
    /// in while you are still speaking. Each pass is a fresh hypothesis over
    /// the whole utterance rather than an append, so later words can revise
    /// earlier ones — which is what makes the result usable rather than a
    /// stream of first guesses.
    private func startLiveTranscript() {
        liveTimer?.invalidate()
        let timer = Timer(timeInterval: Self.liveInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tickLiveTranscript() }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    private func stopLiveTranscript() {
        liveTimer?.invalidate()
        liveTimer = nil
        livePartialTask?.cancel()
        livePartialTask = nil
    }

    private func tickLiveTranscript() {
        // Skip rather than queue: a backlog of partials would delay the final
        // transcription behind work whose results are already stale.
        guard isListening, livePartialTask == nil, speechStatus.isReady else { return }

        let all = recorder.snapshot()
        guard all.count > committedSamples else { return }
        let tail = Array(all[committedSamples...])

        let tailSeconds = Double(tail.count) / AudioRecorder.sampleRate
        guard tailSeconds >= Self.liveMinimumSeconds else { return }

        // Long unbroken speech gets a far more forgiving pause threshold, so
        // the revisable region stays short even without real sentence breaks.
        let overdue = tailSeconds > Self.forceCommitAfterSeconds
        let boundary = SilenceTrimmer.commitBoundary(
            tail,
            minSilence: overdue ? Self.forcedCommitSilenceSeconds : Self.commitSilenceSeconds,
            minSpeech: Self.commitMinimumSpeechSeconds
        )

        livePartialTask = Task { [weak self] in
            guard let self else { return }
            defer { self.livePartialTask = nil }

            if let boundary {
                await self.commit(tail: tail, upTo: boundary)
            } else {
                await self.refreshTail(tail)
            }
        }
    }

    /// Transcribes a finished sentence and freezes it.
    private func commit(tail: [Float], upTo boundary: SilenceTrimmer.CommitPoint) async {
        let chunk = SilenceTrimmer.trim(Array(tail[0..<boundary.speechEnd]))
        let text = chunk.isEmpty ? nil : await self.transcriber.partial(chunk)

        guard !Task.isCancelled, isListening else { return }

        if let text {
            committedText = committedText.isEmpty ? text : committedText + " " + text
        }
        // Advance regardless: audio that produced nothing is still spent, and
        // leaving it in would make every later pass redo it.
        committedSamples += boundary.resumeAt
        liveTail = ""
        showLiveTranscript()
    }

    /// Re-transcribes only the unsettled tail.
    private func refreshTail(_ tail: [Float]) async {
        let speech = SilenceTrimmer.trim(tail)
        guard !speech.isEmpty else { return }
        let text = await self.transcriber.partial(speech)

        guard !Task.isCancelled, isListening, let text, text != liveTail else { return }
        liveTail = text
        showLiveTranscript()
    }

    private func showLiveTranscript() {
        guard !livePartial.isEmpty else { return }
        pill.set(.listening, livePartial, isLatched: isLatched, isLive: true)
    }

    private func endListening(wasLatched: Bool) {
        isListening = false
        isLatched = false
        stopLiveTranscript()
        play(.stop)

        let samples = recorder.stop()
        let tail = committedSamples < samples.count
            ? Array(samples[committedSamples...])
            : []
        let speech = SilenceTrimmer.trim(tail)
        let committed = committedText

        guard !speech.isEmpty || !committed.isEmpty else {
            pill.set(.idle, "Heard nothing", revertAfter: 1.5)
            return
        }

        guard speechStatus.isReady else {
            pill.set(.thinking, "Still loading the speech model…", revertAfter: 3)
            return
        }

        // Nothing new since the last commit: what is on screen is already final.
        guard !speech.isEmpty else {
            lastTranscript = committed
            pill.set(.heard, committed, revertAfter: 5)
            return
        }

        let seconds = Double(speech.count) / AudioRecorder.sampleRate
        pill.set(.thinking, livePartial.isEmpty ? "Transcribing…" : livePartial, isLive: !livePartial.isEmpty)

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            do {
                let tailText = try await self.transcriber.transcribe(speech)
                guard !Task.isCancelled else { return }
                let elapsed = Date().timeIntervalSince(started)
                let text = committed.isEmpty ? tailText : committed + " " + tailText
                self.lastTranscript = text
                self.pill.set(.heard, text, revertAfter: 5)
                Log.debug(String(format: "heard %.1fs of speech in %.0f ms: %@",
                                 seconds, elapsed * 1000, text))
            } catch Transcriber.TranscriberError.empty {
                guard !Task.isCancelled else { return }
                if committed.isEmpty {
                    self.pill.set(.idle, "Heard nothing", revertAfter: 1.5)
                } else {
                    self.lastTranscript = committed
                    self.pill.set(.heard, committed, revertAfter: 5)
                }
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
        pill.set(.listening, livePartial.isEmpty ? "Listening…" : livePartial,
                 isLatched: true, isLive: !livePartial.isEmpty)
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
