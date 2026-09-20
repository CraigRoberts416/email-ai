import SwiftUI

/// A reachable home for work that can outlive the screen where it began.
struct ActivityToolbarButton: View {
    @Environment(FeedStore.self) private var store
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            Image(systemName: "clock.arrow.circlepath").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Activity")
        .accessibilityValue("\(store.receipts.count + store.unsubscribeRuns.count + store.visibleSendJobs.count) records")
        .sheet(isPresented: $presented) { ActivityView() }
    }
}

struct ActivityView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var hasDrafts = false
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.lg) {
                    if store.receipts.isEmpty && store.unsubscribeRuns.isEmpty && store.visibleSendJobs.isEmpty && !hasDrafts {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Nothing in progress").typeStyle(Style.navAction)
                            Text("Sending, filing and unsubscribe attempts stay accessible here.")
                                .typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary)
                        }.padding(Metric.gutter)
                    }
                    SendActivityView().padding(.horizontal, Metric.gutter)
                    if !store.receipts.isEmpty {
                        Text("RECENT ACTIONS").typeStyle(Style.sectionHeader).padding(.horizontal, Metric.gutter)
                        ForEach(store.receipts.reversed()) { receipt in
                            VStack(alignment: .leading, spacing: Space.sm) {
                                Text(receipt.message).typeStyle(Style.body)
                                if let detail = receipt.detail { Text(detail).typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary) }
                                HStack {
                                    if let undo = receipt.undo {
                                        Button("Undo") { perform(undo) }.frame(minHeight: 44)
                                    }
                                    Spacer()
                                    Button("Dismiss") { store.dismissReceipt(id: receipt.id) }.frame(minHeight: 44)
                                }
                            }.padding(.horizontal, Metric.gutter)
                            Rule()
                        }
                    }
                    if !store.unsubscribeRuns.isEmpty {
                        Text("UNSUBSCRIBE").typeStyle(Style.sectionHeader).padding(.horizontal, Metric.gutter)
                        if let failure = store.activitySyncFailure {
                            Text(failure).typeStyle(Style.bodySmall).padding(.horizontal, Metric.gutter)
                        }
                        ForEach(store.unsubscribeRuns) { run in UnsubscribeTaskRow(run: run); Rule() }
                    }
                }.padding(.vertical, Space.lg)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Ink.surface)
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .refreshable { await store.refreshUnsubscribeActivity() }
            .task {
                hasDrafts = !MailDraftStore.drafts(for: Set(store.auth.accounts.map(\.id))).isEmpty
                await store.refreshUnsubscribeActivity()
            }
        }
        #if DEBUG
        // Presented content owns its environment separately from the root.
        // Keep the synthetic accessibility fixture consistent across the sheet.
        .transformEnvironment(\.dynamicTypeSize) { value in
            if ProcessInfo.processInfo.arguments.contains("-sampleLargeText") { value = .accessibility5 }
        }
        #endif
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    private func perform(_ undo: FeedStore.Receipt.Undo) {
        switch undo {
        case .send(let id): store.undoSend(id)
        case .archive(let message, let index): store.undoArchive(message, at: index)
        }
    }
}

struct GlobalActivityTray: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0
    private var count: Int { store.receipts.count + store.unsubscribeRuns.count + store.visibleSendJobs.count }
    private var title: String {
        if let job = store.visibleSendJobs.first { return job.isRunning ? "Sending activity" : "Send result available" }
        return store.receipt?.message ?? "Activity"
    }
    var body: some View {
        Group {
            if store.isActivityTrayVisible && count > 0 {
                Group {
                    if !store.unsubscribeRuns.isEmpty && store.receipts.isEmpty && store.visibleSendJobs.isEmpty {
                        UnsubscribeTray(runs: store.unsubscribeRuns, onOpenLog: { store.activityPresented = true }, onClose: hide)
                    } else {
                        HStack(spacing: Space.sm) {
                            Button { store.activityPresented = true } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(title).typeStyle(Style.navAction)
                                    Text(count == 1 ? "View result and available actions" : "\(count) actions · View activity")
                                        .typeStyle(Style.bodySmall).foregroundStyle(Ink.onInverseSecondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                            }.buttonStyle(.plain)
                            if let undo = store.receipt?.undo, store.visibleSendJobs.isEmpty {
                                Button("Undo") {
                                    switch undo {
                                    case .send(let id): store.undoSend(id)
                                    case .archive(let message, let index): store.undoArchive(message, at: index)
                                    }
                                }.frame(minWidth: 44, minHeight: 44)
                            }
                            Button(action: hide) {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Hide activity summary")
                        }
                        .foregroundStyle(Ink.onSheet)
                        .padding(.leading, Space.lg).padding(.trailing, 4).padding(.vertical, Space.sm)
                        .background(Ink.inverse, in: RoundedRectangle(cornerRadius: Corner.xl, style: .continuous))
                        .frame(maxWidth: 520)
                    }
                }
                .offset(y: reduceMotion ? 0 : drag)
                .gesture(DragGesture(minimumDistance: 12).onChanged { value in
                    drag = max(0, value.translation.height)
                }.onEnded { value in
                    if value.translation.height > 55 || value.predictedEndTranslation.height > 100 { hide() }
                    withAnimation(Move.resolved(Move.settle, reduceMotion)) { drag = 0 }
                })
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, Space.sm)
                .accessibilityAction(.escape, hide)
            }
        }
        .animation(Move.resolved(Move.crisp, reduceMotion), value: store.isActivityTrayVisible)
        .onChange(of: store.visibleSendJobs.map(\.id)) { old, new in
            if new.contains(where: { !old.contains($0) }) { store.isActivityTrayVisible = true }
        }
    }
    private func hide() { store.isActivityTrayVisible = false }
}
