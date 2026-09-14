import SwiftUI

struct FeedView: View {
    @Environment(FeedStore.self) private var store
    @State private var scrollY: CGFloat = 0
    @State private var open: Message?
    @State private var compose: ComposeView.Intent?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Masthead(
                            recap: store.recap,
                            waiting: store.waitingCount,
                            total: store.messages.count
                        )

                        ForEach(store.messages(), id: \.0) { section, items in
                            Dateline(section)
                            ForEach(items) { message in
                                PostView(
                                    message: message,
                                    tag: store.showsMailboxTags
                                        ? store.mailbox(message.mailboxID)?.tag : nil,
                                    onOpen: { open = message },
                                    onReply: { open = message; compose = .reply },
                                    onForward: { open = message; compose = .forward },
                                    onSave: { store.toggleSaved(message) },
                                    onArchive: { withAnimation(Move.layout) { store.archive(message) } },
                                    onUnsubscribe: { store.unsubscribe(from: message) }
                                )
                            }
                        }

                        if store.isFirstSync {
                            // "Nothing waiting" would be a lie here: the mail
                            // exists, we just have not been handed it yet.
                            EmptyStateView(
                                headline: "Reading your mailbox\u{2026}",
                                detail: "THE FIRST PASS TAKES A MINUTE. POSTS APPEAR AS THEY ARE UNDERSTOOD."
                            )
                        } else if store.messages.isEmpty {
                            EmptyStateView(
                                headline: "Nothing waiting.",
                                detail: "NEW MAIL APPEARS HERE AS IT LANDS \u{2014} ALREADY READ."
                            )
                        } else {
                            CaughtUp(handled: store.messages.count)
                        }
                    }
                    // The tab bar floats over content on iOS 26, so the feed
                    // has to clear it itself or the last post sits underneath.
                    .safeAreaPadding(.bottom, Space.xxxl + Space.xl)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        -proxy.frame(in: .scrollView).origin.y
                    } action: { scrollY = $0 }
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refresh() }

                condition

                if !store.pending.isEmpty, scrollY > Move.Pill.showBelowScrollY {
                    NewPostsPill(senders: store.pending.map(\.sender), count: store.pending.count) {
                        withAnimation(Move.enter) { store.admitPending() }
                    }
                    .padding(.top, Space.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(Ink.surface)
            .navigationBarHidden(true)
            .navigationDestination(item: $open) { message in
                ThreadView(message: message)
            }
            // Agent progress and receipts stack at the bottom, above the tab
            // bar. Neither ever takes the screen.
            .safeAreaInset(edge: .bottom) { overlays }
            .sheet(item: $compose) { intent in
                ComposeView(intent: intent, message: open)
            }
        }
    }

    // MARK: Overlays

    @ViewBuilder private var overlays: some View {
        VStack(spacing: Space.sm) {
            if !store.unsubscribes.isEmpty {
                UnsubscribeTray(
                    runs: store.unsubscribes.values.sorted { $0.messageId < $1.messageId },
                    onDismiss: { withAnimation(Move.crisp) { store.unsubscribes.removeAll() } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let receipt = store.receipt {
                ToastView(
                    message: receipt.message,
                    detail: receipt.detail,
                    actionLabel: receipt.undo != nil ? "Undo" : nil,
                    action: receipt.undo != nil ? { store.undoSend() } : nil
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: receipt.id) {
                    // Failures hold longer than successes — six seconds is the
                    // floor for anything the user may need to act on.
                    let hold: Duration = receipt.undo == nil ? .seconds(6) : .seconds(Move.sendUndoWindow)
                    try? await Task.sleep(for: hold)
                    withAnimation(Move.crisp) { store.dismissReceipt() }
                }
            }
        }
        .padding(.bottom, store.unsubscribes.isEmpty && store.receipt == nil ? 0 : Space.sm)
        .animation(Move.crisp, value: store.unsubscribes.count)
        .animation(Move.crisp, value: store.receipt?.id)
    }

    /// Degraded states never take the screen. They sit above the feed and the
    /// feed keeps working underneath.
    @ViewBuilder private var condition: some View {
        switch store.condition {
        case .normal:
            EmptyView()
        case .statusStrip(let state, let freshness):
            StatusStrip(state: state, freshness: freshness)
        case .actionBar(let message, let verb):
            ActionBarView(message: message, verb: verb) {
                Task { await store.reconnect() }
            }
        case .fallback(let freshness):
            StatusStrip(state: "NOT INTERPRETING", freshness: freshness)
        }
    }
}

// MARK: - Masthead
//
// The greeting and the line under it are written by the model against this
// particular inbox. Counts are ours — a number is not a sentence, and the
// model has no business rounding it.

struct Masthead: View {
    let recap: APIClient.Recap?
    let waiting: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(recap?.greeting ?? fallbackGreeting)
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .contentTransition(.opacity)

            if let summary = recap?.summary {
                Text(summary)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }

            HStack(spacing: Space.xs + 2) {
                Text("\(total) NEW").typeStyle(Style.kicker).foregroundStyle(Ink.secondary)
                if waiting > 0 {
                    Text("·").typeStyle(Style.meta).foregroundStyle(Ink.tertiary)
                    Text("\(waiting) NEED YOU").typeStyle(Style.kicker).foregroundStyle(Ink.primary)
                }
            }
            .monospacedDigit()
            .padding(.top, Space.xs)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, Space.xxl)
        .padding(.bottom, Space.xl)
        .animation(Move.crossfade, value: recap)
    }

    private var fallbackGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<12: return "Good morning"
        case ..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Dateline
//
// 40pt above a band and nowhere else, so the spacing itself means "new day".

struct Dateline: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            Text(label)
                .typeStyle(Style.kicker)
                .foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, Space.sm)
                .background(Ink.surfaceTertiary)
            Rule()
        }
    }
}

// MARK: - Caught up
//
// A receipt, not a trophy. The feed is finite on purpose.

struct CaughtUp: View {
    let handled: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("That\u{2019}s the lot.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
            Text("Nothing left is waiting on you.")
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.xxxl + Space.xl)
    }
}
