import SwiftUI

struct FeedView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bumped by the root when the already-selected Feed tab is tapped again.
    /// Status-bar tap is free from UIKit while one scroll view is on screen and
    /// is deliberately not reimplemented here.
    var scrollTopSignal: Int = 0

    /// A `ScrollPosition` binding re-applies its last requested position on
    /// re-render, so once anything asked it for `.top` the feed was pinned
    /// there and could not be scrolled at all. An anchor id is a one-shot
    /// request and cannot latch.
    @State private var scroller: ScrollViewProxy?
    private static let topAnchor = "feed.top"
    @State private var open: Message?
    @State private var profile: Sender?
    @State private var compose: ComposeView.Intent?
    @State private var showRunLog = false

    /// Hysteresis state for the pill. A `Bool` rather than a scroll offset, so
    /// the action fires on the crossing and not on every frame.
    @State private var pillVisible = false
    /// A new object entering the frame under an active gesture competes with
    /// the dominant event.
    @State private var swiping = false
    /// The batch the pill just admitted, held only long enough for one opacity
    /// pass over the whole block.
    @State private var admitted: Set<String> = []

    // Pull to refresh, driven from the scroll offset. See `pullStrip`.
    @State private var pull: CGFloat = 0
    @State private var armed = false
    @State private var refreshing = false
    @State private var stripHold: CGFloat = 0
    @State private var settled: String?

    /// Post → Thread is parent → child of the *same* entity, so it is a zoom
    /// shared container rather than a push. Nothing else in the feed is a
    /// shared element: not the hero image (the post's media and the thread's
    /// hero come from different inputs, so morphing them would be a false
    /// identity claim), not the avatar (one source, two destinations), and not
    /// the pill's faces.
    @Namespace private var feedZoom

    private var showsPill: Bool { !store.pending.isEmpty && pillVisible && !swiping }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // The space the pull strip holds open while it works.
                        Color.clear.frame(height: stripHold)

                        Masthead(
                            recap: store.recap,
                            waiting: store.waitingCount,
                            total: store.messages.count,
                            isReading: store.isFirstSync
                        )
                        .accessibilityElement(children: .contain)
                        // `.refreshable` supplied the VoiceOver rotor's Refresh
                        // action for free. Driving the pull by hand removes
                        // that, so it is put back explicitly rather than lost.
                        .accessibilityAction(named: "Refresh") { Task { await refreshNow() } }
                        .id(Self.topAnchor)

                        ForEach(store.messages(), id: \.0) { section, items in
                            Section {
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
                                    onArchive: { store.archive(message) },
                                    onUnsubscribe: { store.unsubscribe(from: message) },
                                    onProfile: { profile = message.sender },
                                    onReact: { store.react(message, $0) },
                                    onSwiping: { swiping = $0 }
                                )
                                .opacity(admitted.contains(message.id) ? 0 : 1)
                                .matchedTransitionSource(id: message.id, in: feedZoom)
                            }
                            } header: {
                                // Sticky, because a date band that scrolls away
                                // is decoration; one that stays is the landmark
                                // you navigate a long feed by.
                                Dateline(section)
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
                                action: { Task { await refreshNow() } }
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
                }
                .scrollIndicators(.hidden)
                // Content used to run straight under the clock and under the
                // floating tab bar with nothing between them, so a post's CTA
                // could sit in the notch and the dateline had bare white above
                // it. Both edges dissolve now.
                .feedEdges()
                .onAppear { scroller = proxy }
                // Two geometry observers, both of which return a value that is
                // CONSTANT during ordinary scrolling, so `body` is not
                // re-evaluated on scroll frames. The old
                // `onGeometryChange(for: CGFloat.self)` emitted a new offset on
                // every frame of every scroll and re-evaluated this whole tree
                // at 120Hz.
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let y = geometry.contentOffset.y + geometry.contentInsets.top
                    // Two thresholds, not one: a single line makes the pill
                    // flicker on a slow scroll across it.
                    return pillVisible
                        ? y > Move.Pill.hideBelowScrollY
                        : y > Move.Pill.showBelowScrollY
                } action: { _, show in
                    pillVisible = show
                }
                // Zero except during an overscroll at the very top, which is
                // exactly when the strip has to track the finger 1 : 1.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
                } action: { _, distance in
                    // Nothing is drawn below `showAt`, so every frame of the
                    // ordinary top bounce collapses to one write of zero and
                    // the feed is not re-evaluated for it. Above the line the
                    // user is deliberately pulling and the strip has to track.
                    let next = distance > Move.Pull.showAt ? distance : 0
                    if next != pull { pull = next }

                    let nowArmed = next >= Move.Pull.armAt
                    guard nowArmed != armed, !refreshing else { return }
                    armed = nowArmed
                    // H2 — identical physical meaning to the swipe threshold,
                    // so identical cue. Arming is news; disarming is not.
                    if nowArmed { Haptics.threshold() }
                }
                }
                .onScrollPhaseChange { old, phase in
                    // No cue on release: H2 already reported the decision, and
                    // a second cue re-reports one decision.
                    guard old == .interacting, phase != .interacting,
                          armed, !refreshing else { return }
                    startRefresh()
                }
                .onChange(of: scrollTopSignal) { _, _ in scrollToTop() }

                // Both live on the top edge, so they stack rather than
                // overlapping when a pull happens during a degraded state.
                //
                // Hidden while a refresh is running. The strip tracks the
                // finger, which is right during a pull and wrong afterwards:
                // once released it kept drawing at the top of the ZStack and
                // "READING YOUR MAILBOX…" landed directly on top of the
                // greeting. The masthead says it is reading — the count holds
                // an em dash and the kicker reads READING — so the strip has
                // nothing left to add.
                VStack(spacing: 0) {
                    if !refreshing { pullStrip }
                    condition
                }

                pill
            }
            .background(Ink.surface)
            .navigationBarHidden(true)
            // The sender. `profile` was being set by every avatar tap and
            // observed by nothing — the screen existed, was built, was styled,
            // and could not be reached from the feed at all. Search had this
            // destination; the feed never did.
            .navigationDestination(item: $profile) { SenderProfileView(sender: $0) }
            // An actual sheet, not a push dressed as one.
            //
            // The corners, the drag-to-dismiss, the feed scaling back behind
            // it and the rubber-banding all come from the system here. Drawn
            // by hand on a pushed view they were a costume: the shape of a
            // sheet with none of the behaviour, which is exactly what reads as
            // wrong even when the radius is right.
            .sheet(item: $open) { message in
                ThreadView(message: message)
                    .presentationDetents([.large])
                    // No grabber. The gesture exists either way, and the
                    // handle is the system's way of advertising a *resize*
                    // between detents — there is only one detent here.
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(.clear)
                    // Delivers the post lifting and expanding into the sheet,
                    // and the system's own fallback when the source row has
                    // been recycled out of the LazyVStack.
                    .navigationTransition(.zoom(sourceID: message.id, in: feedZoom))
            }
            // Agent progress and receipts stack at the bottom, above the tab
            // bar. Neither ever takes the screen.
            .safeAreaInset(edge: .bottom) { overlays }
            .sheet(item: $compose) { intent in
                ComposeView(intent: intent, message: open)
                    .presentationDetents([.large])
                    // Cancel already exists; two dismissals with different
                    // consequences is one too many.
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showRunLog) {
                UnsubscribeRunLog(
                    runs: store.unsubscribes.values.sorted { ($0.index ?? 0) < ($1.index ?? 0) },
                    onClear: { withAnimation(Move.crisp) { store.unsubscribes.removeAll() } }
                )
            }
            // Hardware keyboard and Full Keyboard Access, which `.refreshable`
            // also used to cover.
            .background {
                Button("Refresh") { Task { await refreshNow() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .hidden()
            }
        }
    }

    // MARK: Scroll to top

    private func scrollToTop() {
        // A 2000pt animated camera move is the clearest vestibular trigger in
        // this app, and the destination is what matters, not the journey.
        guard !reduceMotion else { scroller?.scrollTo(Self.topAnchor, anchor: .top); return }
        withAnimation(Move.layout) { scroller?.scrollTo(Self.topAnchor, anchor: .top) }
    }

    // MARK: The new-posts pill

    @ViewBuilder private var pill: some View {
        Group {
            if showsPill {
                NewPostsPill(
                    senders: store.pending.map(\.sender),
                    count: store.pending.count,
                    action: admitPending
                )
                .padding(.top, Space.sm)
                .transition(
                    // T9 — a top-edge overlay arrives from the edge new content
                    // comes from. Under Reduce Motion it fades instead.
                    reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
                )
            }
        }
        // The transition was declared before and never played: the condition
        // changed outside any animation and the container carried none.
        .animation(Move.resolved(Move.crisp, reduceMotion), value: showsPill)
    }

    /// The pill's own tap used to shove the feed — it inserted at index 0 while
    /// the reader was 260pt down, which is the exact failure the component
    /// exists to prevent. The order below is the fix, and scrolling to an
    /// **edge** rather than an ID is what makes it non-fragile: the target is
    /// valid regardless of how much content was just inserted, so no delayed
    /// callback is needed.
    private func admitPending() {
        let batch = Set(store.pending.map(\.id))

        let land = {
            scroller?.scrollTo(Self.topAnchor, anchor: .top)
            store.admitPending()
            pillVisible = false
        }
        // Reduce Motion takes the un-animated jump.
        if reduceMotion { land() } else { withAnimation(Move.layout) { land() } }

        // ONE opacity pass over the whole admitted block — not per post. A
        // stagger over an unbounded batch is the waterfall tax. Deferred by a
        // hop so the inserted rows commit at 0 before they animate to 1.
        admitted = batch
        Task { @MainActor in
            withAnimation(Move.resolved(Move.reveal, reduceMotion)) { admitted = [] }
        }
        // The tree under VoiceOver just changed wholesale and the viewport
        // moved; without this the cursor stays on an element that is no longer
        // where it was.
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    // MARK: Pull to refresh
    //
    // Driven from the scroll offset rather than `.refreshable`, because the
    // system's grey indeterminate ring is the one loading idiom this design
    // rejected outright — and it would appear at the highest-frequency moment
    // in the product, the moment someone asks for their mail. The cost of
    // taking it over is the accessibility contract `.refreshable` supplied for
    // free, which is re-supplied by hand above.

    @ViewBuilder private var pullStrip: some View {
        if pull > Move.Pull.showAt || stripHold > 0 {
            HStack(spacing: Space.sm) {
                if refreshing {
                    Caret(height: 20)
                } else if settled == nil {
                    Rectangle()
                        .fill(Ink.primary)
                        .frame(width: Metric.unreadBar, height: 20)
                        .opacity(armingProgress)
                }
                Text(pullLabel)
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metric.gutter)
            // Height tracks the pull 1 : 1 — the scroll view is already
            // rubber-banding and banding twice reads as lag.
            .frame(height: max(pull, stripHold), alignment: .center)
            .clipped()
            .accessibilityHidden(true)
        }
    }

    private var armingProgress: CGFloat {
        let span = Move.Pull.armAt - Move.Pull.showAt
        return min(1, max(0, (pull - Move.Pull.showAt) / span))
    }

    private var pullLabel: String {
        if let settled { return settled }
        if refreshing { return "READING YOUR MAILBOX\u{2026}" }
        return armed ? "RELEASE TO REFRESH" : "PULL TO REFRESH"
    }

    private func startRefresh() {
        refreshing = true
        armed = false
        withAnimation(Move.resolved(Move.crisp, reduceMotion)) {
            stripHold = Move.Pull.holdOpen
        }
        Task { await runRefresh() }
    }

    private func runRefresh() async {
        let began = ContinuousClock.now
        await refreshNow()

        // Once the caret shows it holds for at least this long even if the
        // network answers in 80ms, or the strip flickers. `Move.loadingDelay`
        // deliberately does NOT apply — the user pulled, so the acknowledgement
        // is immediate.
        let elapsed = began.duration(to: .now)
        let floor = Duration.seconds(Move.skeletonMinHold)
        if elapsed < floor { try? await Task.sleep(for: floor - elapsed) }

        let failure = store.loadFailure != nil
        // H7 — one of the only two outcomes a user walks away from believing
        // the opposite of. No cue on success: it is the common case and the
        // freshness stamp says so.
        if failure { Haptics.failed() }

        withAnimation(Move.resolved(Move.crisp, reduceMotion)) {
            refreshing = false
            settled = failure
                ? "COULDN\u{2019}T REACH YOUR MAILBOX"
                : "CURRENT AS OF \(Date.now.formatted(date: .omitted, time: .shortened).uppercased())"
        }

        try? await Task.sleep(
            for: .seconds(failure ? Move.Pull.failureHold : Move.Pull.stampHold)
        )
        withAnimation(Move.resolved(Move.crisp, reduceMotion)) {
            settled = nil
            stripHold = 0
        }
    }

    /// A user-initiated refresh admits the pending batch first. Holding mail
    /// behind a pill after the user has explicitly asked for mail is
    /// incoherent, and the insertion is safe because a pull only happens at the
    /// top.
    private func refreshNow() async {
        if !store.pending.isEmpty {
            withAnimation(Move.resolved(Move.layout, reduceMotion)) { store.admitPending() }
        }
        await store.refresh()
    }

    private func undo(_ receipt: FeedStore.Receipt) -> (() -> Void)? {
        switch receipt.undo {
        case .none: return nil
        case .send: return { store.undoSend() }
        case .archive(let message, let index):
            // Reinsertion at the ORIGINAL index, so the post returns to where
            // it was rather than to the top.
            return {
                withAnimation(Move.resolved(Move.layout, reduceMotion)) {
                    store.undoArchive(message, at: index)
                }
            }
        }
    }

    // MARK: Overlays

    /// T8 — a bottom-edge overlay arrives from the bottom edge and leaves
    /// decisively. Under Reduce Motion neither travels; both crossfade.
    private var bottomOverlay: AnyTransition {
        .asymmetric(
            insertion: reduceMotion
                ? .opacity.animation(Move.crossfade)
                : .move(edge: .bottom).combined(with: .opacity).animation(Move.crisp),
            // Exits are faster than entries. The user has moved on.
            removal: .opacity.animation(Move.resolved(Move.exit, reduceMotion))
        )
    }

    @ViewBuilder private var overlays: some View {
        VStack(spacing: Space.sm) {
            if !store.unsubscribes.isEmpty {
                UnsubscribeTray(
                    runs: store.unsubscribes.values.sorted { ($0.index ?? 0) < ($1.index ?? 0) },
                    onOpenLog: { showRunLog = true }
                )
                .transition(bottomOverlay)
            }

            if let receipt = store.receipt {
                ToastView(
                    message: receipt.message,
                    detail: receipt.detail,
                    actionLabel: receipt.undo != nil ? "Undo" : nil,
                    action: undo(receipt),
                    onDismiss: { store.dismissReceipt() }
                )
                .transition(bottomOverlay)
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
                    withAnimation(Move.resolved(Move.exit, reduceMotion)) {
                        store.dismissReceipt()
                    }
                }
            }
        }
        .padding(.bottom, store.unsubscribes.isEmpty && store.receipt == nil ? 0 : Space.sm)
        .animation(Move.resolved(Move.crisp, reduceMotion), value: store.unsubscribes.count)
        .animation(Move.resolved(Move.crisp, reduceMotion), value: store.receipt?.id)
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
    /// The mailbox has not been read yet, so there is no count to print.
    var isReading = false

    var body: some View {
        // The greeting leads, at display size, in the human face.
        //
        // It had been demoted to a 12pt grey label with the counts at 24pt,
        // on the reasoning that counts are the actionable thing. That reads as
        // a dashboard, and the spec's own risk section says the failure mode
        // of this product is that the feed model leaves people DISORIENTED —
        // which a number cannot fix. Asana, Withings, Fiverr and Future Pro
        // all open the same way: date, then a greeting large enough to be a
        // greeting, then the state of things. The counts still lead the state;
        // they just no longer lead the screen.
        VStack(alignment: .leading, spacing: Space.sm) {
            // Where you are, before anything else. Pure orientation, and the
            // one line here that is never written by a model.
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .uppercased())
                .typeStyle(Style.sectionHeader)
                .foregroundStyle(Ink.tertiary)

            Text(recap?.greeting ?? fallbackGreeting)
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .padding(.bottom, Space.xs)

            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                // A zero here is an assertion about someone's mailbox, and
                // during the first pass it is one the app has not earned — it
                // has not finished looking. An em dash is the honest glyph for
                // a number that does not exist yet, and it holds the same
                // baseline so nothing shifts when the count arrives.
                Text(isReading ? "\u{2014}" : "\(waiting > 0 ? waiting : total)")
                    .typeStyle(Style.tickCount)
                    .foregroundStyle(isReading ? Ink.tertiary : Ink.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(isReading ? "READING" : (waiting > 0 ? "NEED YOU" : "NEW"))
                    .typeStyle(Style.kicker)
                    .foregroundStyle(isReading ? Ink.tertiary : Ink.primary)
                if waiting > 0, !isReading {
                    Text("· \(total) NEW")
                        .typeStyle(Style.kicker)
                        .foregroundStyle(Ink.tertiary)
                        .monospacedDigit()
                }
            }

            if let summary = recap?.summary {
                // Uncapped, for the same reason the card's summary is: this
                // sentence is what orients somebody who has just opened a feed
                // of their own mail, and two lines put an ellipsis in it.
                Text(summary)
                    .typeStyle(Style.gloss)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .padding(.top, Space.xs)
            }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.lg)
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
        // No leading rule: the post above already drew one, and two hairlines
        // 1pt apart read as a rendering fault rather than a boundary.
        VStack(spacing: 0) {
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
