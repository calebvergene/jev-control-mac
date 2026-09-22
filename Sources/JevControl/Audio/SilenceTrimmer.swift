import Accelerate
import Foundation

/// Trims dead air from the ends of an utterance.
///
/// Push-to-talk reliably captures silence at both ends — the gap between
/// pressing and speaking, and between finishing and releasing. Whisper spends
/// real time on those frames and sometimes hallucinates words into them, so
/// they are worth removing before transcription rather than after.
enum SilenceTrimmer {
    /// 20 ms at 16 kHz.
    private static let frameLength = 320
    private static let frameSeconds: TimeInterval = 0.02
    /// Keep a little context so trimming never clips a soft consonant.
    private static let paddingFrames = 5
    /// Nothing quieter than this counts as speech, however quiet the recording.
    private static let absoluteFloor: Float = 0.004
    /// Speech is taken to be this much louder than the loudest frame's fraction.
    private static let relativeFactor: Float = 0.08

    /// Returns the trimmed audio, or an empty array when it is silence throughout.
    static func trim(_ samples: [Float]) -> [Float] {
        guard samples.count >= frameLength else { return [] }

        let energies = frameEnergies(samples)
        guard let peak = energies.max(), peak > absoluteFloor else { return [] }

        let threshold = max(absoluteFloor, peak * relativeFactor)
        guard let firstLoud = energies.firstIndex(where: { $0 >= threshold }),
              let lastLoud = energies.lastIndex(where: { $0 >= threshold })
        else { return [] }

        let start = max(0, firstLoud - paddingFrames) * frameLength
        let end = min(energies.count, lastLoud + 1 + paddingFrames) * frameLength
        guard start < end, end <= samples.count else { return [] }
        return Array(samples[start..<end])
    }

    /// A point at which speech can be considered finished.
    struct CommitPoint {
        /// End of the speech to transcribe and freeze, in samples.
        let speechEnd: Int
        /// Where the next, still-changeable region begins, in samples.
        let resumeAt: Int
    }

    /// Finds the last pause long enough to treat what precedes it as settled.
    ///
    /// A live transcript that re-decodes the whole utterance can rewrite words
    /// spoken ten seconds ago, because each pass is an independent decode.
    /// Splitting at pauses means committed audio is never looked at again, so
    /// committed text cannot change — and the cost of each pass stops growing
    /// with how long you have been talking.
    static func commitBoundary(
        _ samples: [Float],
        minSilence: TimeInterval,
        minSpeech: TimeInterval
    ) -> CommitPoint? {
        let energies = frameEnergies(samples)
        guard let peak = energies.max(), peak > absoluteFloor else { return nil }

        let threshold = max(absoluteFloor, peak * relativeFactor)
        let minSilenceFrames = max(1, Int(minSilence / frameSeconds))
        let minSpeechFrames = max(1, Int(minSpeech / frameSeconds))

        var best: CommitPoint?
        var runStart: Int?
        var speechBefore = 0

        func consider(runStart: Int, runEnd: Int) {
            guard runEnd - runStart >= minSilenceFrames, speechBefore >= minSpeechFrames else {
                return
            }
            // A couple of frames of padding so a trailing consonant is not cut.
            let end = min(energies.count, runStart + 2) * frameLength
            best = CommitPoint(
                speechEnd: min(end, samples.count),
                resumeAt: min(runEnd * frameLength, samples.count)
            )
        }

        for (index, energy) in energies.enumerated() {
            if energy < threshold {
                if runStart == nil { runStart = index }
            } else {
                if let start = runStart {
                    consider(runStart: start, runEnd: index)
                    runStart = nil
                }
                speechBefore += 1
            }
        }
        // A pause still in progress: the speaker has stopped, so commit.
        if let start = runStart {
            consider(runStart: start, runEnd: energies.count)
        }
        return best
    }

    /// Root-mean-square per frame.
    private static func frameEnergies(_ samples: [Float]) -> [Float] {
        let count = samples.count / frameLength
        guard count > 0 else { return [] }

        var energies = [Float](repeating: 0, count: count)
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for index in 0..<count {
                var rms: Float = 0
                vDSP_rmsqv(base + index * frameLength, 1, &rms, vDSP_Length(frameLength))
                energies[index] = rms
            }
        }
        return energies
    }
}
