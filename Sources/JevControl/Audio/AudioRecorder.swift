import AVFoundation
import Foundation

/// Captures microphone audio as 16 kHz mono Float32 — the format Whisper wants —
/// for as long as the push-to-talk key is held.
///
/// The engine is configured once and only started and stopped per utterance, so
/// the macOS microphone indicator is lit only while you are actually talking,
/// and the first syllable is not lost to engine setup.
final class AudioRecorder {
    static let sampleRate: Double = 16_000
    /// Above this, a held key is assumed to be forgotten rather than spoken into.
    static let maxSeconds: Double = 120

    enum RecorderError: LocalizedError {
        case noInputAvailable
        case converterUnavailable
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .noInputAvailable:
                return "No microphone input is available."
            case .converterUnavailable:
                return "Could not convert the microphone format to 16 kHz mono."
            case .engineFailed(let message):
                return "Audio engine failed: \(message)"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioRecorder.sampleRate,
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?
    private var configuredDeviceUID: String?
    private var isConfigured = false

    /// Written from the realtime audio thread, read from the main thread.
    private let lock = NSLock()
    private var samples: [Float] = []

    private(set) var isRecording = false

    // MARK: - Configuration

    /// Binds the engine to a device and installs the tap. Safe to call again;
    /// it rebuilds only when the device actually changed.
    func configure(deviceUID: String?) throws {
        guard !isRecording else { return }
        if isConfigured && configuredDeviceUID == deviceUID { return }

        if isConfigured {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }

        let input = engine.inputNode

        // On macOS the input node follows the system default until told
        // otherwise, so an explicit choice has to be pushed down to the AU.
        if let deviceUID, let device = AudioDevices.device(uid: deviceUID) {
            do {
                try input.auAudioUnit.setDeviceID(device.id)
            } catch {
                throw RecorderError.engineFailed(
                    "Could not select \(device.name): \(error.localizedDescription)"
                )
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            // This is what a missing microphone permission looks like from here.
            throw RecorderError.noInputAvailable
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterUnavailable
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        configuredDeviceUID = deviceUID
        isConfigured = true
    }

    // MARK: - Recording

    func start(deviceUID: String?) throws {
        guard !isRecording else { return }
        try configure(deviceUID: deviceUID)

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(Self.sampleRate * 8))
        lock.unlock()

        converter?.reset()
        do {
            try engine.start()
        } catch {
            throw RecorderError.engineFailed(error.localizedDescription)
        }
        isRecording = true
    }

    /// Stops capture and hands back everything recorded.
    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.stop()
        isRecording = false

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        return captured
    }

    // MARK: - Realtime callback

    /// Runs on the audio thread. No allocation beyond the append, no logging,
    /// no main-thread hops.
    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter, buffer.frameLength > 0 else { return }

        let ratio = Self.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        // The converter pulls; hand it this buffer exactly once, then report
        // starvation so it returns what it has rather than blocking.
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, output.frameLength > 0,
              let channel = output.floatChannelData?[0]
        else { return }

        let incoming = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))

        lock.lock()
        if samples.count < Int(Self.sampleRate * Self.maxSeconds) {
            samples.append(contentsOf: incoming)
        }
        lock.unlock()
    }
}
