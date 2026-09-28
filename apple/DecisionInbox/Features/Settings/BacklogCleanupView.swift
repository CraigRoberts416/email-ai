import SwiftUI

struct BacklogCleanupView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Set<String> = []
    @State private var olderOnly = false
    @State private var cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var confirming = false
    @State private var stopping = false
    private var cleanup: BacklogCleanup { store.backlogCleanup }

    var body: some View {
        SettingsScreen(title: "Clear unread backlog", onBack: { cleanup.pause(); dismiss() }) {
            if cleanup.hasWork { progress } else { selection }
        }
        .onAppear { if selected.isEmpty { selected = Set(store.mailboxes.map(\.id)) } }
        .onDisappear { cleanup.pause() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cleanup.pause() } }
        .alert("Mark \(cleanup.total.formatted()) emails as read?", isPresented: $confirming) {
            Button("Mark as read") { Task { await cleanup.approve() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes their unread status in Gmail. Emails stay searchable. Only the emails in this preview are included; new arrivals stay unread.")
        }
        .alert("Finish this cleanup here?", isPresented: $stopping) {
            Button("Finish here") { cleanup.reset() }
            Button("Keep cleanup", role: .cancel) {}
        } message: { Text("Completed batches stay read. The remaining emails will stay unread.") }
    }

    private var selection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("A FRESH START", caption: "Clear the unread backlog at your pace. Emails stay in Gmail and remain searchable.")
            Picker("Emails to include", selection: $olderOnly) {
                Text("All unread").tag(false)
                Text("Before a date").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, Space.lg)
            if olderOnly {
                DatePicker("Before", selection: $cutoff, in: ...Date.now, displayedComponents: .date)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.bottom, Space.md)
                SettingsParagraph("Emails received on or after this date stay unread.")
            }
            SettingsGroup("MAILBOXES", caption: "Includes archived unread mail. Spam and Trash are excluded.")
            Rule()
            ForEach(store.mailboxes) { mailbox in
                SettingsToggle(title: mailbox.address, isOn: Binding(
                    get: { selected.contains(mailbox.id) },
                    set: { if $0 { selected.insert(mailbox.id) } else { selected.remove(mailbox.id) } }
                ))
                Rule()
            }
            PrimaryButton(label: "Preview emails") {
                let before = olderOnly ? Calendar.current.startOfDay(for: cutoff) : nil
                Task { await cleanup.preview(mailboxes: store.mailboxes.filter { selected.contains($0.id) }, before: before) }
            }
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("backlog.preview")
            .padding(Metric.gutter)
            SettingsParagraph("Previewing won’t mark anything read. You’ll review the count before applying the change.")
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup(cleanup.done ? "CLEANUP COMPLETE" : cleanup.approved ? "YOUR CLEANUP" : "REVIEW YOUR BACKLOG")
            VStack(alignment: .leading, spacing: Space.md) {
                Text((cleanup.approved ? cleanup.completed : cleanup.total).formatted())
                    .font(.custom(Face.sansMedium, size: 48, relativeTo: .largeTitle))
                    .foregroundStyle(Ink.primary)
                    .contentTransition(.numericText())
                    .animation(Move.resolved(Move.crisp, reduceMotion), value: cleanup.completed)
                    .accessibilityIdentifier("backlog.count")
                Text(status).typeStyle(Style.body).foregroundStyle(Ink.primary)
                    .accessibilityIdentifier("backlog.status")
                if cleanup.busy && !cleanup.approved {
                    ProgressView().accessibilityLabel("Counting matching emails")
                } else if cleanup.approved && !cleanup.done {
                    ProgressView(value: Double(cleanup.completed), total: Double(max(1, cleanup.total)))
                        .tint(Ink.primary)
                        .accessibilityLabel("Cleanup progress")
                }
                if let before = cleanup.journal?.before {
                    Text("Received before \(before.formatted(date: .abbreviated, time: .omitted))")
                        .typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, Space.xl)
            Rule()
            ForEach(cleanup.entries) { entry in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(entry.address).typeStyle(Style.bodyMedium)
                    Text(entryStatus(entry)).typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metric.gutter)
                .accessibilityElement(children: .combine)
                Rule()
            }
            if let failure = cleanup.failure { SettingsParagraph(failure) }
            VStack(spacing: Space.md) {
                if cleanup.busy {
                    Button(cleanup.pauseRequested ? "Pausing…" : "Pause after this step") { cleanup.pause() }
                        .disabled(cleanup.pauseRequested)
                        .frame(minHeight: Metric.tapTarget)
                } else if cleanup.done {
                    PrimaryButton(label: "Done") { dismiss() }
                    Button("New cleanup") { cleanup.reset() }.frame(minHeight: Metric.tapTarget)
                } else if cleanup.ready && !cleanup.approved {
                    if cleanup.total > 0 {
                        PrimaryButton(label: "Mark \(cleanup.total.formatted()) as read") { confirming = true }
                            .accessibilityIdentifier("backlog.confirm")
                    }
                    Button("Change selection") { cleanup.reset() }.frame(minHeight: Metric.tapTarget)
                } else {
                    PrimaryButton(label: cleanup.approved ? "Resume cleanup" : "Resume preview") {
                        Task { await cleanup.resume() }
                    }
                    Button(cleanup.approved ? "Finish here" : "Change selection") {
                        if cleanup.approved { stopping = true } else { cleanup.reset() }
                    }.frame(minHeight: Metric.tapTarget)
                }
            }
            .padding(Metric.gutter)
            SettingsParagraph(cleanup.approved
                ? "Leaving this screen pauses after the current step. Return here to resume. Completed changes stay saved in Gmail."
                : "This preview changes nothing. Marking these emails read will update Gmail, your feed counts, and the app badge. It won’t delete or archive them.")
        }
    }

    private var status: String {
        if cleanup.done { return "Emails processed. New arrivals stay unread." }
        if cleanup.approved { return "of \(cleanup.total.formatted()) emails processed\(cleanup.busy ? "" : " · Paused")" }
        if cleanup.ready { return cleanup.total == 0 ? "No unread emails match this selection." : "emails will be marked as read" }
        return cleanup.busy ? "matching emails found · Still counting…" : "matching emails found · Preview paused"
    }

    private func entryStatus(_ entry: BacklogCleanup.Entry) -> String {
        guard let job = entry.job else { return "Waiting to count" }
        if cleanup.approved { return "\(job.completed.formatted()) of \(job.total.formatted()) processed" }
        return "\(job.total.formatted()) emails\(job.phase == "scanning" ? " · Still counting" : "")"
    }
}
