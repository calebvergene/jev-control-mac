import Foundation

/// Where Whisper weights live.
///
/// WhisperKit's Hugging Face client defaults to `~/Documents/huggingface`,
/// which drops a few hundred megabytes of cache into a folder the user
/// actually looks at and backs up. Application Support is where this belongs.
enum ModelStorage {
    static var downloadBase: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return support
            .appendingPathComponent("JevControl", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    private static var legacyBase: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    /// Moves a previously downloaded cache out of Documents. Runs before the
    /// model loads, so an existing download is reused rather than fetched again.
    static func migrateLegacyDownloadIfNeeded() {
        let fm = FileManager.default
        let legacyModels = legacyBase.appendingPathComponent("models", isDirectory: true)
        guard fm.fileExists(atPath: legacyModels.path) else { return }

        let target = downloadBase.appendingPathComponent("models", isDirectory: true)
        do {
            if fm.fileExists(atPath: target.path) {
                // Already migrated; the leftover is redundant.
                try fm.removeItem(at: legacyBase)
                return
            }
            try fm.createDirectory(at: downloadBase, withIntermediateDirectories: true)
            try fm.moveItem(at: legacyModels, to: target)
            // Only remove the parent if nothing else of the user's is in it.
            if let rest = try? fm.contentsOfDirectory(atPath: legacyBase.path), rest.isEmpty {
                try? fm.removeItem(at: legacyBase)
            }
            Log.debug("Moved model cache out of Documents into \(target.path)")
        } catch {
            Log.error("Could not migrate the model cache: \(error.localizedDescription)")
        }
    }
}
