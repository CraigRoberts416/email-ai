import SwiftUI

struct FeedView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bumped by the root when the already-selected Feed tab is tapped again.
    /// Status-bar tap is free from UIKit while one scroll view is on screen and
    /// is deliberately not reimplemented here.
    var scrollTopSignal: Int = 0
    var notificationRequest: NotificationOpenRequest? = nil

    // A one-shot request uses a permanent target outside the lazy rows. Never
    // retain ScrollViewProxy across layout changes or bind the viewport to top.
    @State private var scrollRequest = 0
    @State private var animateScrollRequest = false
    #if DEBUG
    @State private var didRunNavigationProbe = false
    #endif
    private static let topAnchor = "feed.top"
    @State private var open: Message?
    @State private var handledNotificationID: UUID?
    @State private var notificationLoading = false
    @State private var notificationFailure: String?
    @State private var profile: Sender?
    @State private var compose: ComposeView.Intent?
    @State private var initialComposeIntent: ComposeView.Intent?
    @State private var focusDiscussion = false
    @State private var choosingMailboxes = false
    @State private var showingOldPosts = false
    @State private var scrollPass = ScrollPastState()
    @State private var progress = FeedScrollProgress()
    @State private var viewportHeight: CGFloat = 700
    @State private var feedVisible = false
    @State private var footerVisible = false
    @State private var scrollSnapshot: ScrollSnapshot?

    /// Content can finish arriving while a finger or deceleration moves the
    /// feed. This visit's geometry stays fixed until that movement ends.
    private struct ScrollSnapshot {
        let groups: [(String, [Message])]
        let masthead: Masthead
        let footer: AnyView
        let seenFailure: String?
    }

    private var hasSelectedMailboxes: Bool { store.mailboxes.contains(where: \.includeInUnifiedFeed) }
    private var emptyLoading: Bool {
        hasSelectedMailboxes && store.sessionMessages.isEmpty && store.loadFailure == nil
            && (store.isFirstSync || store.checkingCompletion)
    }

    private var currentMasthead: Masthead {
        Masthead(recap: hasSelectedMailboxes ? store.recap : nil, waiting: hasSelectedMailboxes ? store.waitingCount : 0,
                 total: store.remainingInFeed ?? store.activeMessages.count,
                 totalIsComplete: store.remainingInFeed != nil,
                 isReading: hasSelectedMailboxes && (store.isFirstSync || (store.activeMessages.isEmpty && store.checkingCompletion)),
                 isComplete: hasSelectedMailboxes && store.completionVerified, showsActivity: true)
    }
    private var displayedGroups: [(String, [Message])] { scrollSnapshot?.groups ?? store.messages() }
    private var displayedMasthead: Masthead { scrollSnapshot?.masthead ?? currentMasthead }
    private var displayedFooter: AnyView { scrollSnapshot?.footer ?? AnyView(feedFooter) }
    private var displayedSeenFailure: String? {
        if let scrollSnapshot { return scrollSnapshot.seenFailure }
        return store.seenFailure
    }
    private var canCommitScrollReads: Bool {
        feedVisible && scenePhase == .active && open == nil && profile == nil
            && compose == nil && !showingOldPosts && !choosingMailboxes && !swiping && !refreshing && !notificationLoading
    }


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
    @State private var refreshFailed = false
    @State private var refreshWaitStage = 0
    @State private var firstWaitStage = 0
    @State private var refreshID = UUID()
    @State private var refreshTask: Task<Void, Never>?
    @ScaledMetric(relativeTo: .caption) private var refreshHeight: CGFloat = 56

    /// Post → Thread is parent → child of the *same* entity, so it is a zoom
    /// shared container rather than a push. Nothing else in the feed is a
    /// shared element: not the hero image (the post's media and the thread's
    /// hero come from different inputs, so morphing them would be a false
    /// identity claim), not the avatar (one source, two destinations), and not
    /// the pill's faces.
    @Namespace private var feedZoom

    private var showsPill: Bool { !store.eligiblePending.isEmpty && pillVisible && !swiping }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // This target always exists, even thousands of rows down.
                        // Refresh feedback reserves space through the safe-area inset.
                        Color.clear.frame(height: 0).id(Self.topAnchor)

                        displayedMasthead
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { old, new in
                            cancelIfLayoutChanged(from: old, to: new)
                        }
                        .accessibilityElement(children: .contain)
                        // `.refreshable` supplied the VoiceOver rotor's Refresh
                        // action for free. Driving the pull by hand removes
                        // that, so it is put back explicitly rather than lost.
                        .accessibilityAction(named: "Refresh") { startRefresh() }

                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(displayedGroups, id: \.0) { section, items in
                            Section {
                            ForEach(items, id: \.feedKey) { message in
                                PostView(
                                    message: message,
                                    tag: store.showsMailboxTags
                                        ? store.mailbox(message.mailboxID)?.tag : nil,
                                    onOpen: { openMessage(message) },
                                    // Reply and Forward open the thread, where
                                    // the composer belongs — one tap, one
                                    // destination, rather than a push and a
                                    // sheet racing each other.
                                    onReply: { openMessage(message, intent: .reply) },
                                    onDiscuss: { openMessage(message, discuss: true) },
                                    onForward: { openMessage(message, intent: .forward) },
                                    onSave: { store.toggleSaved(message) },
                                    onArchive: { store.archive(message) },
                                    onUnsubscribe: { store.unsubscribe(from: message) },
                                    onProfile: { profile = message.sender },
                                    onReact: { store.react(message, $0) },
                                    onSwiping: { swiping = $0 }
                                )
                                .id(message.feedKey)
                                .onGeometryChange(for: FeedPostGeometry.self) { geometry in
                                    let frame = geometry.frame(in: .scrollView(axis: .vertical))
                                    let region: ScrollPastState.Region = frame.maxY <= 0 ? .above
                                        : (frame.minY >= viewportHeight ? .below : .visible)
                                    return FeedPostGeometry(region: region, height: frame.height)
                                } action: { old, new in
                                    guard canCommitScrollReads else { return }
                                    guard !cancelIfLayoutChanged(from: old.height, to: new.height) else { return }
                                    scrollPass.moved(message.feedKey, from: old.region, to: new.region, at: progress.offset)
                                    enqueueScrollReads(scrollPass.takePassed())
                                }
                                .accessibilityAction(named: "Mark as seen") {
                                    Task { await store.markSeen(message) }
                                }
                                .opacity(admitted.contains(message.feedKey) ? 0 : 1)
                                .matchedTransitionSource(id: message.feedKey, in: feedZoom)
                            }
                            } header: {
                                // Sticky, because a date band that scrolls away
                                // is decoration; one that stays is the landmark
                                // you navigate a long feed by.
                                Dateline(section, remaining: displayedRemaining(in: section), showsCount: true)
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { old, new in
                                        cancelIfLayoutChanged(from: old, to: new)
                                    }
                            }
                        }

                        if let failure = displayedSeenFailure {
                            VStack(alignment: .leading, spacing: Space.sm) {
                                Text(failure).typeStyle(Style.body).foregroundStyle(Ink.secondary)
                                Button("Try again") { Task { await store.retrySeen() } }
                                    .frame(minHeight: Metric.tapTarget)
                            }
                            .padding(Metric.gutter)
                        }

                        displayedFooter
                            .onScrollVisibilityChange(threshold: 0.1) { footerVisible = $0 }
                            .task(id: "\(store.feedSessionID):\(store.sessionMessages.count):\(footerVisible):\(scrollSnapshot == nil)") {
                                if scrollSnapshot == nil && footerVisible && store.hasMoreFeed && store.paginationFailure == nil {
                                    await store.loadMoreFeed()
                                }
                            }

                    }
                    // The tab bar floats over content on iOS 26, so the feed
                    // has to clear it itself or the last post sits underneath.
                    .scrollTargetLayout()
                    .safeAreaPadding(.bottom, Space.xxxl + Space.xl)
                    }
                }
                .scrollIndicators(.hidden)
                .task {
                    #if DEBUG
                    if !didRunNavigationProbe && ProcessInfo.processInfo.arguments.contains("-verifyFeedNavigation") {
                        didRunNavigationProbe = true
                        await verifyNavigation(using: proxy)
                    }
                    #endif
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, value in
                    // This plain reference does not invalidate the view at scroll frequency.
                    progress.offset = Double(value)
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { old, new in
                    if old != .zero && old != new { scrollPass.cancel() }
                    viewportHeight = new.height
                }
                // Content used to run straight under the clock and under the
                // floating tab bar with nothing between them, so a post's CTA
                // could sit in the notch and the dateline had bare white above
                // it. Both edges dissolve now.
                .feedEdges()
                .task(id: scrollRequest) {
                    guard scrollRequest > 0 else { return }
                    // Admission commits first; scroll only against the new tree.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if animateScrollRequest && !reduceMotion {
                        withAnimation(Move.layout) { proxy.scrollTo(Self.topAnchor, anchor: .top) }
                    } else { proxy.scrollTo(Self.topAnchor, anchor: .top) }
                }
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
                    // so identical cue, fired in BOTH directions like the
                    // swipe. "Arming is news; disarming is not" was this call
                    // site's own rule and no other site's: the token is
                    // documented as firing on disarm, the swipe does fire on
                    // disarm, and a user who pulls back short of the line needs
                    // the same confirmation that they escaped the commit.
                    Haptics.threshold()
                }
                }
                .onScrollPhaseChange { old, phase in
                    switch phase {
                    case .tracking:
                        scrollPass.cancel()
                        captureScrollSnapshot()
                    case .interacting:
                        captureScrollSnapshot()
                        store.noteFeedInteraction()
                        if canCommitScrollReads { scrollPass.begin(at: progress.offset) }
                    case .decelerating:
                        // Keep measuring the same layout after finger release.
                        break
                    case .idle:
                        // Finish against the held layout before any newly
                        // completed content is allowed to change its bounds.
                        let ids = scrollPass.finish()
                        releaseScrollSnapshot()
                        enqueueScrollReads(ids)
                    case .animating:
                        // Programmatic scrolling is navigation, never reading.
                        cancelScrollReads()
                    @unknown default:
                        cancelScrollReads()
                    }
                    // No cue on release: H2 already reported the decision, and
                    // a second cue re-reports one decision.
                    guard old == .interacting, phase != .interacting,
                          armed, !refreshing else { return }
                    startRefresh()
                }
                .onChange(of: scrollTopSignal) { _, _ in scrollToTop() }
                .onChange(of: store.feedSessionID) { _, _ in
                    cancelScrollReads()
                    scrollToTop(animated: false)
                }

                // While pulling, the scroll view supplies the overscroll gap.
                // After release a real safe-area inset owns the status space,
                // so it cannot cover mail when the reader scrolls onward.
                if !refreshing && settled == nil { pullStrip }

                pill
            }
            .background(Ink.surface)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if refreshing || settled != nil { pullStrip }
                    condition
                }
            }
            .navigationBarHidden(true)
            .onAppear { feedVisible = true }
            .environment(\.motionIsActive, feedVisible && scenePhase == .active && open == nil && profile == nil && !showingOldPosts)
            .task(id: emptyLoading) {
                firstWaitStage = 0
                guard emptyLoading else { return }
                do {
                    try await Task.sleep(for: .seconds(10))
                    firstWaitStage = 10
                    try await Task.sleep(for: .seconds(20))
                    firstWaitStage = 30
                } catch { }
            }
            .task(id: refreshing) {
                refreshWaitStage = 0
                guard refreshing else { return }
                do {
                    try await Task.sleep(for: .seconds(10))
                    refreshWaitStage = 10
                    try await Task.sleep(for: .seconds(20))
                    refreshWaitStage = 30
                } catch { }
            }
            .onChange(of: notificationRequest, initial: true) { _, _ in
                handledNotificationID = nil
                notificationFailure = nil
                openNotificationIfAvailable()
            }
            .task(id: notificationRequest?.id) {
                guard let request = notificationRequest else { return }
                await loadNotification(request)
            }
            .onChange(of: store.messages.map(\.feedKey)) { openNotificationIfAvailable() }
            .onChange(of: store.pending.map(\.feedKey)) { openNotificationIfAvailable() }
            .overlay(alignment: .top) {
                if notificationLoading {
                    ProgressView("Opening email…")
                        .padding().background(.regularMaterial, in: Capsule())
                        .padding(.top, Space.sm)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .alert("Couldn’t open email", isPresented: Binding(
                get: { notificationFailure != nil }, set: { if !$0 { notificationFailure = nil } }
            )) {
                Button("Try again") {
                    if let request = notificationRequest { Task { await loadNotification(request) } }
                }
                Button("Cancel", role: .cancel) { notificationFailure = nil }
            } message: { Text(notificationFailure ?? "Please try again.") }
            .onDisappear { feedVisible = false; cancelScrollReads() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelScrollReads() }
            }
            .onChange(of: open != nil) { _, presented in
                if presented { store.noteFeedInteraction(); cancelScrollReads() }
            }
            .onChange(of: profile != nil) { _, shown in if shown { cancelScrollReads() } }
            .onChange(of: showingOldPosts) { _, shown in if shown { cancelScrollReads() } }
            .onChange(of: compose != nil) { _, shown in if shown { cancelScrollReads() } }
            .onChange(of: choosingMailboxes) { _, shown in if shown { cancelScrollReads() } }
            .onChange(of: swiping) { _, active in if active { cancelScrollReads() } }
            .sheet(isPresented: $showingOldPosts) { OldPostsView() }
            .sheet(isPresented: $choosingMailboxes) { MailboxFilterSheet() }
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
                ThreadView(message: message, initialComposeIntent: initialComposeIntent, focusDiscussion: focusDiscussion)
                    .id(message.feedKey)
                    .presentationDetents([.large])
                    // No grabber. The gesture exists either way, and the
                    // handle is the system's way of advertising a *resize*
                    // between detents — there is only one detent here.
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(.clear)
                    // Delivers the post lifting and expanding into the sheet,
                    // and the system's own fallback when the source row has
                    // been recycled out of the LazyVStack.
                    .modifier(FeedThreadTransition(sourceID: message.feedKey, namespace: feedZoom, reduceMotion: reduceMotion))
            }
            .sheet(item: $compose) { intent in
                ComposeView(intent: intent, message: open)
                    .presentationDetents([.large])
                    // Cancel already exists; two dismissals with different
                    // consequences is one too many.
                    .presentationDragIndicator(.hidden)
            }
            // Hardware keyboard and Full Keyboard Access, which `.refreshable`
            // also used to cover.
            .background {
                Button("Refresh") { startRefresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .hidden()
            }
        }
    }

    private func openMessage(_ message: Message, intent: ComposeView.Intent? = nil, discuss: Bool = false) {
        store.noteFeedInteraction()
        initialComposeIntent = intent
        focusDiscussion = discuss
        open = message
    }

    private func openNotificationIfAvailable() {
        guard let request = notificationRequest, handledNotificationID != request.id else { return }
        let connected = Set(store.auth.accounts.map(\.id))
        guard let message = (store.messages + store.pending + store.sessionMessages + store.saved).first(where: {
            request.matches(messageID: $0.id, mailboxID: $0.mailboxID, connectedMailboxIDs: connected)
        }) else { return }
        handledNotificationID = request.id
        notificationLoading = false
        notificationFailure = nil
        openMessage(message)
    }

    private func loadNotification(_ request: NotificationOpenRequest) async {
        guard !store.isSample, handledNotificationID != request.id else { return }
        notificationLoading = true
        notificationFailure = nil
        cancelScrollReads()
        defer { if notificationRequest?.id == request.id { notificationLoading = false } }
        do {
            let message = try await store.notificationMessage(request)
            guard !Task.isCancelled, notificationRequest?.id == request.id,
                  handledNotificationID != request.id else { return }
            handledNotificationID = request.id
            open = message
        } catch {
            guard !Task.isCancelled, notificationRequest?.id == request.id,
                  handledNotificationID != request.id else { return }
            notificationFailure = error.localizedDescription
        }
    }

    // MARK: Scroll to top

    private func captureScrollSnapshot() {
        guard scrollSnapshot == nil else { return }
        scrollSnapshot = ScrollSnapshot(groups: store.messages(), masthead: currentMasthead,
                                        footer: AnyView(feedFooter), seenFailure: store.seenFailure)
    }

    private func releaseScrollSnapshot() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { scrollSnapshot = nil }
    }

    private func cancelScrollReads() {
        // Only incomplete gesture evidence is cancelled. Proven reads belong
        // to the store and continue across navigation and session boundaries.
        scrollPass.cancel()
        releaseScrollSnapshot()
    }

    @discardableResult private func cancelIfLayoutChanged(from old: CGFloat, to new: CGFloat) -> Bool {
        guard scrollPass.userScrolling, old > 0, abs(new - old) > 0.5 else { return false }
        // Rotation, Dynamic Type, or an unexpected size change invalidates
        // this gesture's evidence. A later gesture can establish a new pass.
        scrollPass.cancel()
        return true
    }

    private func displayedRemaining(in section: String) -> Int? {
        store.progressRemaining(in: section)
    }

    private func enqueueScrollReads(_ keys: Set<String>) {
        guard canCommitScrollReads, !keys.isEmpty else { return }
        store.recordSeen(store.sessionMessages.filter { keys.contains($0.feedKey) && !$0.isRead })
    }

    private func scrollToTop(animated: Bool = true) {
        cancelScrollReads()
        animateScrollRequest = animated
        scrollRequest += 1
    }

    // MARK: The new-posts pill

    @ViewBuilder private var pill: some View {
        Group {
            if showsPill {
                NewPostsPill(
                    senders: store.eligiblePending.map(\.sender),
                    count: store.eligiblePending.count,
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

    /// Both new-mail entry points admit the batch before requesting its new
    /// layout's top. The target cannot disappear when lazy rows are recycled.
    private func admitPending() {
        cancelScrollReads()
        admitted = Set(store.eligiblePending.map(\.feedKey))
        store.admitPending()
        pillVisible = false
        scrollToTop()
        Task { @MainActor in
            await Task.yield()
            withAnimation(Move.resolved(Move.reveal, reduceMotion)) { admitted = [] }
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
    }

    #if DEBUG
    /// Exercises actual SwiftUI layout with the signed-in cache. It deliberately
    /// performs no user-scroll simulation and cannot establish gesture coverage.
    private func verifyNavigation(using proxy: ScrollViewProxy) async {
        for _ in 0..<60 where store.sessionMessages.count < 20 {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
        }
        guard store.sessionMessages.count >= 20 else {
            print("[navigation-probe] unavailable: fewer than 20 cached cards")
            return
        }
        cancelScrollReads()
        let incoming = store.stageNavigationProbeArrival()
        let unseenBefore = store.sessionMessages.filter { !$0.isRead }.count + incoming.count
        try? await Task.sleep(for: .milliseconds(300))
        proxy.scrollTo(store.sessionMessages[15].feedKey, anchor: .top)
        try? await Task.sleep(for: .seconds(1))
        let reachedDepth = progress.offset > 500
        let pendingBefore = store.hasPendingInFeed
        admitPending()
        try? await Task.sleep(for: .seconds(1))
        let reachedTop = progress.offset < 10
        let admittedCorrectly = Array(store.sessionMessages.prefix(incoming.count).map(\.feedKey)) == incoming
        let noFalseReads = store.sessionMessages.filter { !$0.isRead }.count == unseenBefore
        proxy.scrollTo(store.sessionMessages[10].feedKey, anchor: .top)
        try? await Task.sleep(for: .seconds(1))
        let canMoveAgain = progress.offset > 500
        scrollToTop(animated: false)
        try? await Task.sleep(for: .seconds(1))
        print("[navigation-probe] depth=\(reachedDepth) pending=\(pendingBefore) top=\(reachedTop) admitted=\(admittedCorrectly) noFalseReads=\(noFalseReads) movable=\(canMoveAgain) returned=\(progress.offset < 10)")
    }
    #endif

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
            HStack(alignment: .center, spacing: Space.md) {
                if refreshing {
                    Caret(height: 20)
                } else if settled == nil {
                    RefreshMargin(tension: reduceMotion ? 0 : armingProgress)
                        .stroke(Ink.primary, style: StrokeStyle(lineWidth: Metric.unreadBar, lineCap: .round))
                        .frame(width: 10, height: 22)
                        .opacity(0.3 + 0.7 * armingProgress)
                        .accessibilityHidden(true)
                }
                Text(pullLabel)
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if refreshFailed && !refreshing {
                    Button("Retry") { startRefresh() }
                        .typeStyle(Style.bodySmall)
                        .frame(minWidth: Metric.tapTarget, minHeight: Metric.tapTarget)
                        .buttonStyle(TapStyle())
                    Button { dismissRefreshStatus() } label: {
                        Image(systemName: "xmark").frame(width: Metric.tapTarget, height: Metric.tapTarget)
                    }
                    .buttonStyle(TapStyle()).accessibilityLabel("Dismiss refresh status")
                }
            }
            .padding(.horizontal, Metric.gutter)
            .frame(height: refreshing || settled != nil ? stripHold : pull, alignment: .center)
            .background(Ink.surface)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.refresh.status")
        }
    }

    private var armingProgress: CGFloat {
        let span = Move.Pull.armAt - Move.Pull.showAt
        return min(1, max(0, (pull - Move.Pull.showAt) / span))
    }

    private var pullLabel: String {
        if let settled, !refreshing { return settled }
        if refreshing {
            if refreshWaitStage >= 30 { return "STILL CHECKING. YOU CAN KEEP READING." }
            if refreshWaitStage >= 10 { return "YOUR MAILBOX IS TAKING LONGER TO RESPOND…" }
            return "CHECKING YOUR MAILBOX…"
        }
        return armed ? "RELEASE TO REFRESH" : "PULL TO REFRESH"
    }

    private func startRefresh() {
        guard hasSelectedMailboxes else { choosingMailboxes = true; return }
        guard !refreshing else { return }
        cancelScrollReads()
        refreshTask?.cancel()
        let id = UUID()
        refreshID = id
        refreshing = true
        refreshFailed = false
        refreshWaitStage = 0
        settled = nil
        armed = false
        withAnimation(Move.resolved(Move.crisp, reduceMotion)) { stripHold = refreshHeight }
        refreshTask = Task { await runRefresh(id: id) }
    }

    private func runRefresh(id: UUID) async {
        let began = ContinuousClock.now
        await refreshNow()
        guard !Task.isCancelled, id == refreshID else { return }
        let elapsed = began.duration(to: .now)
        let floor = Duration.seconds(Move.skeletonMinHold)
        if elapsed < floor {
            do { try await Task.sleep(for: floor - elapsed) } catch { return }
        }
        guard !Task.isCancelled, id == refreshID else { return }
        let failure = store.loadFailure != nil
        if failure && feedVisible { Haptics.needsYou() }
        withAnimation(Move.resolved(Move.crisp, reduceMotion)) {
            refreshing = false
            refreshFailed = failure
            settled = failure ? "COULDN’T REACH YOUR MAILBOX"
                : "CURRENT AS OF \(Date.now.formatted(date: .omitted, time: .shortened).uppercased())"
        }
        if feedVisible { UIAccessibility.post(notification: .announcement, argument: settled) }
        // Failure is actionable and stays until dismissed or retried.
        guard !failure else { return }
        do { try await Task.sleep(for: .seconds(Move.Pull.stampHold)) } catch { return }
        guard id == refreshID, !Task.isCancelled else { return }
        dismissRefreshStatus()
    }

    private func dismissRefreshStatus() {
        withAnimation(Move.resolved(Move.settle, reduceMotion)) {
            settled = nil
            refreshFailed = false
            stripHold = 0
        }
    }

    /// A user-initiated refresh admits the pending batch first. Holding mail
    /// behind a pill after the user has explicitly asked for mail is
    /// incoherent, and the insertion is safe because a pull only happens at the
    /// top.
    private func refreshNow() async {
        cancelScrollReads()
        store.beginFeedSession()
        await store.refresh()
    }

    @ViewBuilder private var feedFooter: some View {
        if !hasSelectedMailboxes {
            EmptyStateView(headline: "No mailboxes selected.", detail: "YOUR MAILBOXES ARE STILL CONNECTED.",
                           actionLabel: "Choose mailboxes", action: { choosingMailboxes = true })
        } else if store.sessionMessages.isEmpty, let failure = store.loadFailure {
            EmptyStateView(headline: "Couldn’t load your mail.", detail: failure,
                           actionLabel: "Try again", action: { startRefresh() })
        } else if store.isFirstSync && store.sessionMessages.isEmpty {
            initialLoading
        } else if store.hasMoreFeed {
            VStack(spacing: Space.md) {
                if let failure = store.paginationFailure {
                    Text(failure).typeStyle(Style.body).foregroundStyle(Ink.secondary)
                    Button("Try again") { Task { await store.loadMoreFeed() } }
                        .frame(minHeight: Metric.tapTarget)
                } else {
                    ProgressView("Loading older emails…")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100)
        } else if store.checkingCompletion && store.sessionMessages.isEmpty {
            initialLoading
        } else if store.feedEndVerified {
            VStack(spacing: Space.md) {
                CompletionPunctuation(verified: store.completionVerified)
                Text("No more emails.")
                    .typeStyle(Style.body).foregroundStyle(Ink.secondary)
                if store.hasPendingInFeed {
                    Button("See new posts", action: admitPending).frame(minHeight: Metric.tapTarget)
                } else if store.completionVerified && store.showOldPosts {
                    Button("See old posts") { showingOldPosts = true }.frame(minHeight: Metric.tapTarget)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Space.xl)
            .frame(minHeight: store.sessionMessages.isEmpty ? 180 : viewportHeight, alignment: .top)
            .accessibilityIdentifier("feed.end")
        } else {
            VStack(spacing: Space.md) {
                Text(store.completionFailure ?? "Checking for older emails…")
                    .typeStyle(Style.body).foregroundStyle(Ink.secondary)
                Button("Check again") { Task { await store.verifyCompletion() } }
                    .frame(minHeight: Metric.tapTarget)
            }
            .frame(maxWidth: .infinity).padding(Metric.gutter)
        }
    }

    private var initialLoading: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            CaretLine(label: store.isFirstSync ? "Reading your mailbox…" : "Checking your inbox…")
            Text(firstWaitStage >= 30
                 ? "This is taking longer than expected. You can leave this screen; your mail will appear as it loads."
                 : (firstWaitStage >= 10 ? "Still waiting for your mailbox to respond."
                    : "Your emails will appear here as they load."))
                .typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.gutter).padding(.top, Space.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed.initialLoading")
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
    var totalIsComplete = true
    /// The mailbox has not been read yet, so there is no count to print.
    var isReading = false
    var isComplete = false
    var showsActivity = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        VStack(alignment: .leading, spacing: 0) {
            // Where you are, before anything else. Pure orientation, and the
            // one line here that is never written by a model.
            Text(dateline)
                .typeStyle(Style.sectionHeader)
                .foregroundStyle(Ink.secondary)
                .padding(.trailing, showsActivity ? Metric.tapTarget + Space.sm : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if showsActivity { ActivityToolbarButton() }
                }
                .padding(.bottom, Space.md + 2)

            headline
                .padding(.bottom, Space.lg + 2)

            counts
        }
        .padding(.horizontal, Metric.gutter)
        // Keep the greeting, while letting the first message share the first
        // screen. A returning reader should not scroll through a title page.
        .padding(.top, Metric.mastheadTop)
        .padding(.bottom, Space.xl)
        // The masthead has to claim the full width before anything is drawn
        // behind it. `LazyVStack(alignment: .leading)` sizes a child to its
        // own content, so the masthead was as wide as its longest line — 236pt
        // — and the atmosphere inherited that, which drew a grey rectangle
        // with a hard edge two thirds of the way across the screen. The text
        // is left-aligned either way, so nothing about the type moves.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            MastheadAtmosphere(weather: weather)
                // Taller than the text so the washes are already fading by the
                // time the first post's hairline arrives.
                .frame(height: 340)
        }
        .animation(Move.crossfade, value: recap)
    }

    /// What the washes behind the greeting are saying.
    private var weather: MastheadAtmosphere.Weather {
        if isReading { return .reading }
        return isComplete ? .clear : .needsYou
    }

    /// The sentence somebody lands on.
    ///
    /// The model already writes a read of this particular mailbox every
    /// morning, and it used to sit under the counts in 12pt grey — the most
    /// orienting thing on the screen set smaller than the number it explains.
    /// It leads now, because it is the only line here that is different today
    /// than it was yesterday, and the spec's own risk section says this
    /// product fails by leaving people disoriented rather than uninformed.
    ///
    /// When there is no read, the greeting and the count take the slot as one
    /// sentence rather than leaving a headline-shaped hole. Nothing is ever
    /// invented to fill it.
    @ViewBuilder private var headline: some View {
        if let read = recap?.summary, !read.isEmpty, !isReading {
            Text(read)
                .typeStyle(Style.headline)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(recap?.greeting ?? fallbackGreeting)
                    .typeStyle(Style.headline)
                    .foregroundStyle(Ink.secondary)
                if !isReading && (total > 0 || isComplete) {
                    Text(waiting > 0
                         ? "\(waiting) request\(waiting == 1 ? "" : "s") to review."
                         : (isComplete ? "You’re caught up." : "Your latest mail."))
                        .typeStyle(Style.headline)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentTransition(.opacity)
        }
    }

    /// The counts, as a footer under the read.
    ///
    /// Still mono, still instrumentation, and still the first thing in the
    /// state — they simply no longer lead the screen. The figure steps up from
    /// its label so the line carries its own small ladder instead of being one
    /// weight all the way across.
    @ViewBuilder private var counts: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs + 2) {
            if isReading {
                // A zero here is an assertion about someone's mailbox, and
                // during the first pass it is one the app has not earned — it
                // has not finished looking.
                Rectangle()
                    .fill(Ink.tertiary)
                    .frame(width: Metric.unreadBar, height: 13)
                Text("STILL READING YOUR MAIL")
                    .typeStyle(Style.kicker)
                    .foregroundStyle(Ink.secondary)
            } else if waiting > 0 {
                Text("\(waiting)")
                    .typeStyle(Style.countInline)
                    .foregroundStyle(Ink.primary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                Text("NEED YOU")
                    .typeStyle(Style.kicker)
                    .foregroundStyle(Ink.primary)
                Text("·")
                    .typeStyle(Style.kicker)
                    .foregroundStyle(Ink.secondary)
                Text("\(total) \(totalIsComplete ? "NEW" : "LOADED")")
                    .typeStyle(Style.kicker)
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
            } else {
                // Nothing waiting is the good morning, and it does not need a
                // zero printed at size to say so.
                Text(total > 0 ? "\(total) \(totalIsComplete ? "NEW POSTS" : "LOADED")" : (isComplete ? "NO UNREAD POSTS" : "NO POSTS TO SHOW"))
                    .typeStyle(Style.kicker)
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var dateline: String {
        let day = Date.now
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .uppercased()
        // The greeting moves into the dateline once the read has taken the
        // headline, so it is still said — just not twice at size.
        guard let read = recap?.summary, !read.isEmpty, !isReading else { return day }
        return "\(day) · \((recap?.greeting ?? fallbackGreeting).uppercased())"
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
    var remaining: Int?
    var showsCount: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ label: String, remaining: Int? = nil, showsCount: Bool = false) {
        self.label = label
        self.remaining = remaining
        self.showsCount = showsCount
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased()).typeStyle(Style.dateline)
            Spacer(minLength: Space.md)
            if showsCount {
                Text(remaining.map { $0.formatted() + " LEFT" } ?? "…")
                    .typeStyle(Style.dateline)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(remaining ?? 0)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: remaining)
                    .accessibilityIdentifier("feed.count." + label.lowercased())
            }
        }
        .foregroundStyle(Ink.secondary)
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.sm)
        .background(Ink.surfaceTertiary)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsCount
            ? label.capitalized + (remaining.map { ", \($0) unread emails remaining" } ?? ", unread count syncing")
            : label)
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

/// Scroll position is sampled for gesture eligibility, never rendered.
private final class FeedScrollProgress { var offset: Double = 0 }

/// Changes only when a card changes region or size, not on every scroll frame.
private struct FeedPostGeometry: Equatable {
    let region: ScrollPastState.Region
    let height: CGFloat
}


/// The margin gathers tension under the finger; text never deforms.
private struct RefreshMargin: Shape {
    var tension: CGFloat
    var animatableData: CGFloat { get { tension } set { tension = newValue } }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                         control: CGPoint(x: rect.midX + (1 - tension) * 5, y: rect.midY))
        return path
    }
}

/// A confirmed endpoint settles quietly. First appearance does not replay a reward.
private struct CompletionPunctuation: View {
    let verified: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            Capsule().frame(width: verified ? 20 : 36, height: 2)
            Circle().frame(width: 3, height: 3).opacity(verified ? 1 : 0)
        }
        .foregroundStyle(Ink.secondary)
        .frame(width: 44, height: 16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.65), value: verified)
        .accessibilityHidden(true)
    }
}

private struct FeedThreadTransition: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID
    let reduceMotion: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion { content }
        else { content.navigationTransition(.zoom(sourceID: sourceID, in: namespace)) }
    }
}
