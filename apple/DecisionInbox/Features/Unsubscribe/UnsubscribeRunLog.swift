import SwiftUI

struct UnsubscribeRunLog: View {
    var focusID: String? = nil
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let failure = store.activitySyncFailure {
                        Text(failure).typeStyle(Style.bodySmall).padding(Metric.gutter)
                    }
                    ForEach(store.unsubscribeRuns.filter { focusID == nil || $0.id == focusID }) { run in
                        UnsubscribeTaskRow(run: run)
                        Rule()
                    }
                }.frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Ink.surface)
            .navigationTitle("Unsubscribe activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .refreshable { await store.refreshUnsubscribeActivity() }
            .task { await store.refreshUnsubscribeActivity() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct UnsubscribeTaskRow: View {
    let run: UnsubscribeRun
    @Environment(FeedStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var expanded = false
    @State private var confirmRemoval = false
    @State private var confirmFinished = false
    @State private var confirmRetry = false
    @State private var openFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.senderName ?? "Sender").typeStyle(Style.navAction)
                    if let mailbox = run.mailboxID {
                        Text(mailbox).typeStyle(Style.meta).foregroundStyle(Ink.secondary)
                    }
                }
                Spacer(minLength: Space.sm)
                PaperIllustration(art: .receipt, phase: run.isConfirmed ? 2 : (run.needsAttention ? 3 : (run.isTerminal ? 0 : 1)), pull: 100)
                    .frame(width: 78, height: 52)
            }
            Text(run.title).typeStyle(Style.sectionHeader)
            Text(run.summary).typeStyle(Style.bodySmall).fixedSize(horizontal: false, vertical: true)
            if let url = run.actionURL, run.needsAttention || run.openedByUserAt != nil {
                Button {
                    openURL(url) { accepted in
                        if accepted { store.openedUnsubscribePage(run.id); openFailure = nil }
                        else { openFailure = "Couldn’t open the sender’s page." }
                    }
                } label: { Label("Open sender page", systemImage: "arrow.up.right.square").frame(minHeight: 44) }
                .buttonStyle(.bordered)
                Text("Opens a fresh page in your browser. You may need to repeat steps; it does not continue the agent’s browser session.")
                    .typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary)
                if let openFailure { Text(openFailure).typeStyle(Style.bodySmall) }
            }
            if run.openedByUserAt != nil, run.userReportedComplete != true, !run.isConfirmed {
                Text("Back from the page? Its result is still unverified.")
                    .typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary)
                Button("I completed it on the sender’s page") { confirmFinished = true }
                    .frame(minHeight: 44)
            }
            HStack {
                Button("Refresh status") { Task { await store.refreshUnsubscribeActivity() } }.frame(minHeight: 44)
                Spacer()
                Button(expanded ? "Hide details" : "Details") { expanded.toggle() }.frame(minHeight: 44)
            }
            if expanded {
                if let evidence = run.evidence, !evidence.isEmpty {
                    Text("EVIDENCE").typeStyle(Style.meta)
                    Text(evidence).typeStyle(Style.bodySmall).textSelection(.enabled)
                }
                ForEach(run.history ?? []) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Date(timeIntervalSince1970: event.at / 1000), style: .time)
                            .typeStyle(Style.meta).foregroundStyle(Ink.secondary)
                        Text(event.message ?? UnsubscribeStep(event.status).label)
                            .typeStyle(Style.bodySmall).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("This receipt does not monitor future mail or hide messages from this sender.")
                    .typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary)
                if run.isTerminal && run.sourceURL != nil && !run.isConfirmed && run.userReportedComplete != true {
                    Button("Try another attempt") { confirmRetry = true }.frame(minHeight: 44)
                }
                if run.isTerminal {
                    Button("Remove receipt", role: .destructive) { confirmRemoval = true }.frame(minHeight: 44)
                }
            }
        }
        .foregroundStyle(Ink.primary)
        .padding(Metric.gutter)
        .confirmationDialog("Remove this receipt?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Remove receipt", role: .destructive) { store.removeUnsubscribeReceipt(run.id) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the record. It does not reverse a request sent to the sender.") }
        .confirmationDialog("Start another attempt?", isPresented: $confirmRetry, titleVisibility: .visible) {
            Button("I checked the sender’s page — try again") { store.retryUnsubscribe(run.id) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The previous request may already have been submitted. Check the sender’s page first. This starts again in a fresh browser session.") }
        .confirmationDialog("Mark complete based on your report?", isPresented: $confirmFinished, titleVisibility: .visible) {
            Button("Mark complete") { store.markUnsubscribeComplete(run.id) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The receipt will say you completed it. It will not claim the sender confirmed it.") }
    }
}
