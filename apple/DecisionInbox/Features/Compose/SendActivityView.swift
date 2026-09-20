import SwiftUI

/// Expanded inside the shared Activity sheet. Each send owns its own Undo.
struct SendActivityView: View {
    @Environment(FeedStore.self) private var store
    @State private var editing: MailDraftRecord?
    @State private var editingJobID: UUID?
    @State private var drafts: [MailDraftRecord] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
        ForEach(store.visibleSendJobs) { job in
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    if job.isRunning { ProgressView().controlSize(.small) }
                    Text(job.phase.title).typeStyle(Style.body)
                    Spacer()
                    if job.canUndo { Button("Undo") { store.undoSend(job.id) }.frame(minWidth: Metric.tapTarget, minHeight: Metric.tapTarget) }
                }
                Text(job.draft.subject.isEmpty ? "No subject" : job.draft.subject)
                    .typeStyle(Style.bodySmall).lineLimit(2)
                Text("\(job.mailboxID) → \(job.draft.to.joined(separator: ", "))")
                    .typeStyle(Style.monoMicro).foregroundStyle(Ink.secondary)
                if let detail = job.detail { Text(detail).typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary) }
                HStack {
                    if job.canEdit {
                        Button("Edit draft") { edit(job) }
                    }
                    if !job.isRunning {
                        Spacer()
                        Button("Dismiss") { store.dismissSendJob(job.id); loadDrafts() }
                    }
                }.frame(minHeight: Metric.tapTarget)
            }
            .padding(.vertical, Space.sm)
            .animation(Move.resolved(Move.crisp, reduceMotion), value: job.phase)
            .accessibilityElement(children: .contain)
        }
        if !drafts.isEmpty {
            Text("DRAFTS ON THIS DEVICE").typeStyle(Style.sectionHeader)
            ForEach(drafts) { draft in
                HStack {
                    Button {
                        editingJobID = nil; editing = draft
                    } label: {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(draft.draft.subject.isEmpty ? "Untitled draft" : draft.draft.subject).typeStyle(Style.body)
                            Text(draft.mailboxID).typeStyle(Style.monoMicro).foregroundStyle(Ink.secondary)
                        }.frame(maxWidth: .infinity, minHeight: Metric.tapTarget, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
        }
        .task { loadDrafts() }
        .sheet(item: $editing, onDismiss: loadDrafts) { ComposeView(intent: ComposeView.Intent(rawValue: $0.composeIntent) ?? .new, message: $0.sourceMessage, restoredDraft: $0, recoveringSendID: editingJobID) }

    }

    private func loadDrafts() {
        drafts = MailDraftStore.drafts(for: Set(store.auth.accounts.map(\.id)))
    }

    private func edit(_ job: SendJob) {
        editingJobID = job.id
        editing = .init(id: job.draftKey, mailboxID: job.mailboxID, draft: job.draft, requiresSentCheck: job.phase == .unknown)
    }
}
