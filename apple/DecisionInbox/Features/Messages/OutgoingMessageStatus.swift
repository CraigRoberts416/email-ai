import SwiftUI

/// The user's words keep the same identity while queue, transport and outcome
/// change around them. Provider acceptance is distinct from recipient delivery.
struct OutgoingMessageStatus: View {
    let job: SendJob
    @Environment(FeedStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(job.draft.body).typeStyle(Style.body).lineLimit(4)
            HStack(spacing: Space.sm) {
                if job.isRunning { ProgressView().controlSize(.small) }
                Image(systemName: job.phase == .sent ? "checkmark" : "paperplane")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                Text(job.phase.title).typeStyle(Style.monoMicro)
                Spacer(minLength: 0)
                if job.canUndo { Button("Undo") { store.undoSend(job.id) }.frame(minHeight: Metric.tapTarget) }
                else { ActivityToolbarButton() }
            }
            if let detail = job.detail { Text(detail).typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary) }
        }
        .padding(Space.md)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.lg))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(Move.resolved(Move.crisp, reduceMotion), value: job.phase)
        .accessibilityElement(children: .contain)
    }
}
