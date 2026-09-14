import SwiftUI

/// `04 · Run log` — the agent thinking out loud, one tap away from the tray.
///
/// A feed is not the place to watch a machine work, but somewhere has to be:
/// a confirmed unsubscribe that did not hold is the most useful thing this
/// feature can tell you, and that is only legible as a sequence.
struct UnsubscribeRunLog: View {
    let runs: [SSEClient.UnsubscribeStatus]
    var onClear: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(runs, id: \.messageId) { run in
                        VStack(alignment: .leading, spacing: Space.sm) {
                            HStack(spacing: Space.sm) {
                                Text(run.senderName?.uppercased() ?? "SENDER")
                                    .typeStyle(Style.sectionHeader)
                                    .foregroundStyle(Ink.tertiary)
                                Spacer(minLength: Space.sm)
                                Text(run.step.label.uppercased())
                                    .typeStyle(Style.monoAction)
                                    .foregroundStyle(run.isTerminal ? Ink.primary : Ink.tertiary)
                            }

                            // "Now" is marked by weight and colour, not by a
                            // spinner: the live line is the black one.
                            Text(run.message ?? run.step.fallback(sender: run.senderName))
                                .typeStyle(run.isTerminal ? Style.monoSmall : Style.ai)
                                .foregroundStyle(run.isTerminal ? Ink.tertiary : Ink.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metric.gutter)
                        .padding(.vertical, Space.lg)
                        Rule()
                    }

                    Text("THE AGENT KEEPS WATCHING AFTER IT FINISHES. A CONFIRMED UNSUBSCRIBE THAT DOES NOT HOLD IS THE MOST USEFUL THING THIS CAN TELL YOU.")
                        .typeStyle(Style.monoMicro)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metric.gutter)
                        .padding(.vertical, Space.xl)
                }
            }
            .scrollIndicators(.hidden)
            .background(Ink.surface)
            .navigationTitle("Unsubscribing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClear(); dismiss() }
                        .typeStyle(Style.navAction)
                        .foregroundStyle(Ink.primary)
                }
            }
        }
    }
}
