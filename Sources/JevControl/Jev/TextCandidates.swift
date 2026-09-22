import Foundation

/// Cuts candidate payload spans out of a transcript.
///
/// The model is never asked to write the text to type or search for — code
/// proposes spans and Jev picks the right one. A selection can only ever be
/// something the user actually said.
enum TextCandidates {
    private static let patterns = [
        #"^(?:please\s+)?(?:can you\s+|could you\s+)?(?:type|write|enter|dictate|input|put|insert|say|send|text|paste)(?:\s+in|\s+out|\s+the\s+words?|\s+the\s+text|\s+this|\s+that)?[:,]?\s+(?<t>.+)$"#,
        #"^(?:please\s+)?(?:can you\s+|could you\s+)?(?:search|google|look\s*up|find|look\s+for|show\s+me|pull\s+up)(?:\s+(?:on|in)\s+\w+(?:\s+\w+)?)?(?:\s+for)?[:,]?\s+(?<t>.+)$"#,
        #"^.*?\b(?:for|about|of|on)\s+(?<t>.+)$"#,
        #"["“'](?<t>[^"”']+)["”']"#,
    ]

    private static let title =
        #"\b(?:called|titled|named|labeled|that says|saying|with the title)\s+(?<t>.+)$"#
    private static let trailingInApp =
        #"\s+(?:in|into|inside|on)\s+(?:the\s+)?(?:[A-Z][\w.]*|notes|chrome|cursor|safari|slack|mail|messages|terminal|finder)(?:\s+app)?\s*[.!?]?$"#
    private static let trailingSubmit =
        #"[\s,.]*(?:and|then)?\s*(?:hit|press|and)\s+(?:enter|return|send|submit)\s*[.!]?$"#

    /// Keyed `c0`, `c1`… because that is what becomes the criteria set Jev
    /// chooses between.
    static func candidates(for utterance: String) -> [String: String] {
        var ordered: [String] = []

        func add(_ raw: String) {
            let cleaned = clean(raw)
            guard !cleaned.isEmpty, !ordered.contains(cleaned) else { return }
            ordered.append(cleaned)
        }

        if let titled = firstMatch(title, in: utterance) { add(titled) }
        for pattern in patterns {
            guard let match = firstMatch(pattern, in: utterance) else { continue }
            add(match)
            add(replacing(trailingInApp, in: match, with: ""))
        }
        add(utterance)

        if ordered.isEmpty {
            ordered.append(utterance.trimmingCharacters(in: .whitespaces))
        }

        var result: [String: String] = [:]
        for (index, value) in ordered.prefix(6).enumerated() {
            result["c\(index)"] = value
        }
        return result
    }

    private static func clean(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespaces)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
        text = replacing(trailingSubmit, in: text, with: "")
        return text
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Domains

    private static let domainPattern = #"\b([a-z0-9-]+(?:\.[a-z0-9-]+)+)\b"#
    private static let siteWordPattern =
        #"\b(?:go to|open|visit|pull up|bring up|load|navigate to|take me to)\s+(?:the\s+)?(?:website\s+|site\s+)?([a-z0-9][a-z0-9 .-]*?)(?:\s+(?:website|site|dot com|\.com|page|homepage))?\s*[.!?]?$"#

    /// Best guess at a domain when the site is not one of the known ones.
    static func domain(in utterance: String) -> String? {
        if let match = firstMatch(domainPattern, in: utterance, group: 1) {
            return match.lowercased()
        }
        guard let word = firstMatch(siteWordPattern, in: utterance, group: 1) else { return nil }
        let cleaned = word
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " dot ", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty, !["it", "that", "this"].contains(cleaned) else { return nil }
        return cleaned.contains(".") ? cleaned : cleaned + ".com"
    }

    // MARK: - Compound splitting

    private static let splitCompound = #"\s*(?:,\s*)?\b(?:and then|then|and also|and)\b\s*"#
    private static let submitOnly =
        #"^(?:then\s+)?(?:hit|press|and)?\s*(?:enter|return|send|submit)(?:\s+it)?$"#

    /// Splits "A and then B" into steps.
    ///
    /// A trailing "hit enter" is not a step of its own — the `type_text` plan
    /// already carries `submit`, so it is folded back into the previous part.
    static func splitCompound(_ utterance: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: splitCompound, options: [.caseInsensitive]) else {
            return [utterance]
        }
        let range = NSRange(utterance.startIndex..., in: utterance)
        let pieces = regex.stringByReplacingMatches(
            in: utterance, range: range, withTemplate: "\u{0}"
        )
        .components(separatedBy: "\u{0}")
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ,.")) }
        .filter { $0.count > 1 }

        guard pieces.count > 1 else { return [utterance] }

        var parts = pieces
        if let last = parts.last, matches(submitOnly, last) {
            parts.removeLast()
            if parts.count == 1 { return [utterance] }
            parts[parts.count - 1] += " and hit enter"
        }
        return parts
    }

    // MARK: - Regex helpers

    private static func firstMatch(_ pattern: String, in text: String, group: Int? = nil) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let matched = group.map { match.range(at: $0) } ?? match.range(withName: "t")
        guard matched.location != NSNotFound, let converted = Range(matched, in: text) else {
            return nil
        }
        return String(text[converted])
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
