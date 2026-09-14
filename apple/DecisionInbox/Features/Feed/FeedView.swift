import SwiftUI

struct FeedView: View {
    private static let topAnchor = "feed.top"

    @Environment(FeedStore.self) private var store
    @State private var scrollY: CGFloat = 0
    @State private var open: Message?
    @State private var compose: ComposeView.Intent?
    @State private var showRunLog = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Masthead(
                            recap: store.recap,
                            waiting: store.waitingCount,
                            total: store.messages.count
                        )
                        .id(Self.topAnchor)

                        ForEach(store.messages(), id: \.0) { section, items in
                            Dateline(section)
                            ForEach(items) { message in
                                PostView(
                                    message: message,
                                    tag: store.showsMailboxTags
                                        ? store.mailbox(message.mailboxID)?.tag : nil,
                                    onOpen: { open = message },
                                    // Reply and Forward open the thread, where
                                    // the composer belongs — one tap, one
                                    // destination, rather than a push and a
                                    // sheet racing each other.
                                    onReply: { open = message },
                                    onDiscuss: { open = message },
                                    onForward: { open = message },
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
                        } else if store.messages.isEmpty, let failure = store.loadFailure {
                            // An empty feed we could not fetch is not an empty
                            // mailbox, and must never be reported as one.
                            EmptyStateView(
                                headline: "Couldn\u{2019}t load your mail.",
                                detail: failure.uppercased(),
                                actionLabel: "Try again",
                                action: { Task { await store.refresh() } }
                            )
                        } else if store.messages.isEmpty {
                            EmptyStateView(
                                headline: "Nothing waiting.",
                                detail: "NEW MAIL APPEARS HERE AS IT LANDS \u{2014} ALREADY READ."
                            )
                        } else {
                            CaughtUp(
                                tally: store.tally,
                                waiting: store.waitingCount,
                                stillOpen: store.stillOpen
                            )
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
                        // Admitting and scrolling must happen in one
                        // transaction. Inserting at index 0 while the reader
                        // is 260pt down shoves the viewport — which is the
                        // exact failure the pill exists to prevent.
                        withAnimation(Move.layout) {
                            store.admitPending()
                            scroller.scrollTo(Self.topAnchor, anchor: .top)
                        }
                    }
                    .padding(.top, Space.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
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
            .sheet(isPresented: $showRunLog) {
                UnsubscribeRunLog(
                    runs: store.unsubscribes.values.sorted { ($0.index ?? 0) < ($1.index ?? 0) },
                    onClear: { withAnimation(Move.crisp) { store.unsubscribes.removeAll() } }
                )
            }
        }
    }

    private func undo(_ receipt: FeedStore.Receipt) -> (() -> Void)? {
        switch receipt.undo {
        case .none: return nil
        case .send: return { store.undoSend() }
        case .archive(let message, let index):
            return { withAnimation(Move.layout) { store.undoArchive(message, at: index) } }
        }
    }

    // MARK: Overlays

    @ViewBuilder private var overlays: some View {
        VStack(spacing: Space.sm) {
            if !store.unsubscribes.isEmpty {
                UnsubscribeTray(
                    runs: store.unsubscribes.values.sorted { ($0.index ?? 0) < ($1.index ?? 0) },
                    onOpenLog: { showRunLog = true }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let receipt = store.receipt {
                ToastView(
                    message: receipt.message,
                    detail: receipt.detail,
                    actionLabel: receipt.undo != nil ? "Undo" : nil,
                    action: undo(receipt)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: receipt.id) {
                    // Failures hold longer than successes — six seconds is the
                    // floor for anything the user may need to act on.
                    let hold: Duration
                    switch receipt.undo {
                    case .none: hold = .seconds(6)
                    case .send: hold = .seconds(Move.sendUndoWindow)
                    case .archive: hold = .seconds(Move.undoWindow)
                    }
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
                    Text("·").typeStyle(Style.separator).foregroundStyle(Ink.tertiary)
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
                .typeStyle(Style.dateline)
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
// A receipt, not a trophy. The feed is finite on purpose, and the end of it
// is a statement of what you did rather than a congratulation for doing it —
// no streak, no score, nothing that would make tomorrow's empty feed feel
// like a loss. The tallies are counted, never estimated: this is the only
// place the product makes a claim about the user's own work.

struct CaughtUp: View {
    let tally: FeedStore.Tally
    var waiting: Int = 0
    var stillOpen: [Message] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(waiting > 0 ? "That\u{2019}s everything." : "That\u{2019}s the lot.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)

            // Never claim the feed is clear while posts above it still ask
            // for something. The end of the list is not the end of the work.
            Text(caption)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !tally.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    row(tally.archived, "ARCHIVED")
                    row(tally.replied, "REPLIED")
                    row(tally.unsubscribed, "UNSUBSCRIBED")
                    row(tally.saved, "SAVED")
                }
                .padding(.top, Space.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.xxxl + Space.xl)
    }

    private var caption: String {
        if waiting > 0 {
            return waiting == 1
                ? "One thing above still needs you."
                : "\(waiting) things above still need you."
        }
        if stillOpen.isEmpty { return "Nothing left is waiting on you." }
        return stillOpen.count == 1
            ? "Nothing needs you. One thing is waiting on them."
            : "Nothing needs you. \(stillOpen.count) things are waiting on them."
    }

    /// A zero is left out rather than shown. "0 UNSUBSCRIBED" is not a fact
    /// anybody needs, and a column of zeroes reads as a scorecard.
    @ViewBuilder private func row(_ count: Int, _ label: String) -> some View {
        if count > 0 {
            HStack(spacing: Space.md) {
                Text("\(count)")
                    .typeStyle(Style.tally)
                    .foregroundStyle(Ink.primary)
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
                Text(label)
                    .typeStyle(Style.tally)
                    .foregroundStyle(Ink.secondary)
            }
        }
    }
}
