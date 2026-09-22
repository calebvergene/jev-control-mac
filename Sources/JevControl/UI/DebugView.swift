import SwiftUI

/// Every decision, with the probabilities behind it.
///
/// A wrong action almost always traces to one question answered one way, so
/// the judgements are listed in full rather than summarised.
struct DebugView: View {
    @ObservedObject var log: DecisionLog
    @State private var selected: DecisionLog.Entry.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Decisions").font(.headline)
                Spacer()
                Text("\(log.entries.count)").foregroundStyle(.secondary).font(.caption)
                Button("Clear") { log.clear() }.controlSize(.small)
            }
            .padding(10)

            Divider()

            if log.entries.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing yet").foregroundStyle(.secondary)
                    Text("Hold the push-to-talk key and say a command.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(log.entries) { entry in
                            EntryRow(entry: entry, isExpanded: selected == entry.id) {
                                selected = selected == entry.id ? nil : entry.id
                            }
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

private struct EntryRow: View {
    let entry: DecisionLog.Entry
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(entry.utterance)”").font(.callout)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(entry.failed ? Color.orange : Color.green)
                                .frame(width: 7, height: 7)
                            Text(entry.plan?.summary ?? entry.outcome)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(entry.at, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let plan = entry.plan {
                    VStack(alignment: .leading, spacing: 3) {
                        LabeledLine("action", plan.action.label)
                        LabeledLine("confidence", String(format: "%.2f", plan.confidence))
                        if let app = plan.inApp { LabeledLine("in app", app) }
                        LabeledLine("compound", plan.isCompound ? "yes" : "no")
                        LabeledLine("latency", "\(plan.latencyMs) ms")
                        LabeledLine("outcome", entry.outcome)
                    }
                    .padding(.leading, 20)

                    Text("Judgements").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary).padding(.leading, 20).padding(.top, 4)

                    VStack(spacing: 2) {
                        ForEach(entry.judgements, id: \.0) { question, answer, certainty in
                            HStack(spacing: 8) {
                                Text(question)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 110, alignment: .leading)
                                Text(answer)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                ProgressView(value: certainty)
                                    .frame(width: 70)
                                Text(String(format: "%.2f", certainty))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.leading, 20)
                } else {
                    Text(entry.outcome).font(.caption).foregroundStyle(.orange).padding(.leading, 20)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct LabeledLine: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value).font(.system(size: 11))
            Spacer()
        }
    }
}
