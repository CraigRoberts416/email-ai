import SwiftUI

/// `05 · Senders`.
///
/// One group, and every row in it is a receipt the unsubscribe agent actually
/// produced — `FeedStore.unsubscribes`, the same records the run log reads.
///
/// The design also called for `BLOCKED` and `ALWAYS SHOW` groups. Nothing in
/// the app can block a sender or pin one above relevance, so listing either
/// would be a list of senders the app is not treating differently. The rows
/// here are the ones with a fact behind them.
struct SettingsSendersView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var inspecting: Run?

    /// The sheet the run log is shown in wants something identifiable, and a
    /// message id on its own is not.
    private struct Run: Identifiable {
        let id: String
        let status: SSEClient.UnsubscribeStatus
    }

    private var runs: [SSEClient.UnsubscribeStatus] {
        store.unsubscribes.values.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
    }

    private var clearAll: (() -> Void)? {
        guard !runs.isEmpty else { return nil }
        return { withAnimation(Move.layout) { store.unsubscribes.removeAll() } }
    }

    var body: some View {
        SettingsScreen(title: "Senders", onBack: { dismiss() }) {
            SettingsGroup(
                runs.isEmpty ? "UNSUBSCRIBED" : "UNSUBSCRIBED \u{00B7} \(runs.count)",
                caption: "Receipts from the agent. A sender who keeps writing after confirming shows up here as still sending, which is the most useful thing this can tell you.",
                trailing: runs.isEmpty ? nil : "CLEAR",
                onTrailing: clearAll
            )
            Rule()

            if runs.isEmpty {
                Text("Nothing unsubscribed yet.")
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.sm)
                Text("Tap Unsubscribe on a promotion and the agent works through the sender\u{2019}s own page. Whatever it finds lands here.")
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.bottom, Space.xl)
                Rule()
            } else {
                ForEach(runs, id: \.messageId) { run in
                    ListRow(
                        title: run.senderName ?? "This sender",
                        subtitle: run.step.stamp,
                        action: { inspecting = Run(id: run.messageId, status: run) },
                        leading: {
                            AvatarView(
                                sender: run.sender ?? Sender(
                                    name: run.senderName ?? "?", address: run.messageId,
                                    kind: .brand, logoURL: nil
                                ),
                                size: Metric.avatarRow
                            )
                        },
                        trailing: {
                            Text(run.step.label.uppercased())
                                .typeStyle(Style.monoSmall)
                                .foregroundStyle(run.step.wantsAttention ? Ink.primary : Ink.tertiary)
                        }
                    )
                    Rule()
                }
            }

            SettingsGroup("BLOCKING")
            SettingsParagraph("There is no block list yet. Until there is one, this screen doesn\u{2019}t offer a switch that would quietly do nothing \u{2014} unsubscribing is the only thing the app can actually make a sender stop doing.")
        }
        .sheet(item: $inspecting) { run in
            UnsubscribeRunLog(runs: [run.status])
        }
    }
}

// MARK: - Step stamps

extension UnsubscribeStep {
    /// A row sub-label: short, closed-set, and a statement of what happened.
    /// Upper-case mono is right here for the same reason it is right on
    /// `SYNCED 14:02` — it is a stamp, not a sentence.
    var stamp: String {
        switch self {
        case .queued: return "LINED UP"
        case .navigating: return "OPENING THEIR PAGE"
        case .analyzing: return "READING THEIR PAGE"
        case .filling: return "FILLING THEIR FORM"
        case .clicking: return "SUBMITTING"
        case .verifying: return "CHECKING IT TOOK"
        case .done: return "CONFIRMED BY THEM"
        case .noLink: return "NO UNSUBSCRIBE LINK FOUND"
        case .needsYou: return "THEIR PAGE WANTS A PERSON"
        case .failed: return "THEIR PAGE DIDN\u{2019}T ANSWER"
        case .stillSending: return "WROTE AGAIN AFTER CONFIRMING"
        }
    }

    /// The two outcomes that are still the user's problem. Everything else is
    /// inert status, and the only signal between them is ink.
    var wantsAttention: Bool {
        switch self {
        case .needsYou, .stillSending: return true
        default: return false
        }
    }
}

#Preview {
    NavigationStack { SettingsSendersView() }
        .environment(FeedStore(sample: true))
}
