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
