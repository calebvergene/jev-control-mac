import Foundation

/// One speculative question in a Jev fan-out.
///
/// Jev never writes text. Every free value the executor needs — the text to
/// type, the app to open, the search query — is produced as candidates in code,
/// and Jev only *selects* among them. That is what makes the output safe to
/// execute without checking it.
struct JevQuestion {
    enum Kind: String {
        /// Pick one key from `criteria`.
        case choice
        /// A probability that the statement in `instructions` holds.
        case noul
    }

    let kind: Kind
    let instructions: String
    /// Key to description. A null description means the key speaks for itself,
    /// which is how app names are passed without inventing a gloss for each.
    let criteria: [String: String?]

    static func choice(_ instructions: String, _ criteria: [String: String?]) -> JevQuestion {
        JevQuestion(kind: .choice, instructions: instructions, criteria: criteria)
    }

    /// Convenience for the common case of bare keys with no descriptions.
    static func choice(_ instructions: String, keys: [String]) -> JevQuestion {
        JevQuestion(
            kind: .choice,
            instructions: instructions,
            criteria: Dictionary(uniqueKeysWithValues: keys.map { ($0, nil) })
        )
    }

    static func noul(_ instructions: String, yes: String, no: String) -> JevQuestion {
        JevQuestion(
            kind: .noul,
            instructions: instructions,
            criteria: ["true": yes, "false": no]
        )
    }

    var json: JSONValue {
        .object([
            "type": .string(kind.rawValue),
            "instructions": .string(instructions),
            "criteria": .object(criteria.mapValues { $0.map(JSONValue.string) ?? .null }),
        ])
    }
}

/// One answer. A `choice` question returns a key and a confidence; a `noul`
/// returns a single probability.
struct JevAnswer: Decodable {
    let choice: String?
    let confidence: Double?
    let noul: Double?

    /// Probability that a noul is true, or the confidence of a choice.
    var certainty: Double { noul ?? confidence ?? 0 }

    var isYes: Bool { (noul ?? 0) > JevClient.yesThreshold }
}
