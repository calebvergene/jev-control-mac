import Foundation

/// Every decision the app has made this session, with the raw probabilities
/// behind it.
///
/// The point is being able to answer "why did it do that" without a debugger:
/// a wrong action is almost always a specific question answered a specific way,
/// and this is where you see which one.
@MainActor
final class DecisionLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let at: Date
        let utterance: String
        let plan: Plan?
        let outcome: String
        let failed: Bool

        /// Answers sorted most-confident first, as `(question, answer, certainty)`.
        var judgements: [(String, String, Double)] {
            guard let plan else { return [] }
            return plan.answers
                .map { key, answer in
                    (key, answer.choice ?? String(format: "%.2f", answer.noul ?? 0), answer.certainty)
                }
                .sorted { $0.2 > $1.2 }
        }
    }

    static let shared = DecisionLog()

    @Published private(set) var entries: [Entry] = []

    private static let limit = 100

    private init() {}

    func record(utterance: String, plan: Plan?, outcome: String, failed: Bool) {
        entries.insert(
            Entry(at: Date(), utterance: utterance, plan: plan, outcome: outcome, failed: failed),
            at: 0
        )
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    func clear() { entries.removeAll() }
}
