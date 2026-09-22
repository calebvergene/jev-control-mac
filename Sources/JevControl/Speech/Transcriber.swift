import Foundation
import WhisperKit

/// Whisper models worth offering. Larger is more accurate and slower; the
/// English-only variants are both faster and better than their multilingual
/// counterparts for this use.
enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "tiny.en"
    case base = "base.en"
    case small = "small.en"

    static let `default`: WhisperModel = .base

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        }
    }

    var detail: String {
        switch self {
        case .tiny: return "Fastest, least accurate. ~75 MB."
        case .base: return "The default. Good accuracy at conversational speed. ~145 MB."
        case .small: return "Most accurate, noticeably slower. ~480 MB."
        }
    }
}

/// Wraps WhisperKit behind an actor so model loading and transcription are
/// serialised, and neither ever runs on the main thread.
actor Transcriber {
    enum Status: Equatable {
        case idle
        /// Fetching weights from Hugging Face. 0...1.
        case downloading(Double)
        /// Weights are on disk; compiling and prewarming.
        case loading
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    enum TranscriberError: LocalizedError {
        case notReady
        case empty

        var errorDescription: String? {
            switch self {
            case .notReady: return "The speech model is still loading."
            case .empty: return "Nothing was said."
            }
        }
    }

    private var kit: WhisperKit?
    private var loadedModel: WhisperModel?
    private(set) var status: Status = .idle

    /// Downloads and loads the model, then runs it once on silence so the first
    /// real utterance is not paying for CoreML's lazy setup.
    /// `onStatus` fires on every transition so the UI can show download
    /// progress; the weights are a few hundred megabytes on first run and a
    /// silent wait is indistinguishable from a hang.
    func prepare(model: WhisperModel, onStatus: @escaping @Sendable (Status) -> Void) async {
        if loadedModel == model, status.isReady {
            onStatus(status)
            return
        }

        kit = nil
        loadedModel = nil
        ModelStorage.migrateLegacyDownloadIfNeeded()

        func report(_ new: Status) {
            status = new
            onStatus(new)
        }

        report(.downloading(0))

        do {
            // Downloading explicitly rather than letting the initialiser do it
            // is the only way to get progress out of WhisperKit.
            let folder = try await WhisperKit.download(
                variant: model.rawValue,
                downloadBase: ModelStorage.downloadBase
            ) { progress in
                onStatus(.downloading(progress.fractionCompleted))
            }

            report(.loading)

            let config = WhisperKitConfig(
                model: model.rawValue,
                downloadBase: ModelStorage.downloadBase,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            self.kit = kit
            loadedModel = model
            await warmUpDecoder(kit)
            report(.ready)
        } catch {
            report(.failed(error.localizedDescription))
        }
    }

    /// WhisperKit's own `prewarm` loads and compiles the models but never runs
    /// a decode, so the first real transcription still pays ~750 ms of lazy
    /// CoreML setup. One throwaway pass on silence moves that cost to launch.
    private func warmUpDecoder(_ kit: WhisperKit) async {
        var options = DecodingOptions()
        options.language = "en"
        options.task = .transcribe
        options.temperature = 0
        options.withoutTimestamps = true
        let silence = [Float](repeating: 0, count: Int(AudioRecorder.sampleRate))
        _ = try? await kit.transcribe(audioArray: silence, decodeOptions: options)
    }

    /// Transcribe 16 kHz mono samples. Returns trimmed text, or throws `.empty`
    /// when the model produced nothing usable.
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let kit, status.isReady else { throw TranscriberError.notReady }
        guard !samples.isEmpty else { throw TranscriberError.empty }

        var options = DecodingOptions()
        options.language = "en"
        options.task = .transcribe
        options.temperature = 0
        options.withoutTimestamps = true
        options.skipSpecialTokens = true

        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw TranscriberError.empty }
        return text
    }

    func currentStatus() -> Status { status }
}
