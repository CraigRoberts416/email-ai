import Foundation
import Observation
import UserNotifications

/// One feed over any number of mailboxes.
///
/// Each mailbox is its own server session with its own token, so the store
/// fans requests out and unions the results. Nothing downstream knows how many
/// mailboxes there are — a post carries its `mailboxID`, and the feed sorts by
/// time like it always did. That is the whole multi-account design: the merge
/// happens here and nowhere else.
@MainActor
@Observable
final class FeedStore {
    var mailboxes: [Mailbox] = []
    var messages: [Message] = []
    private var retained: [Message] = []
    var condition: FeedCondition = .normal
    var showOldPosts = UserDefaults.standard.object(forKey: "feed.showOldPosts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showOldPosts, forKey: "feed.showOldPosts") }
    }
    private var seenKeys = Set(UserDefaults.standard.stringArray(forKey: "feed.seenMessages") ?? [])
    private var markingSeen: Set<String> = []
    private var failedSeen: [String: FeedReadIntent] = [:]
    private var recordedReads: [String: FeedReadIntent] = [:]
    private var readDrain: Task<Void, Never>?
    private var readVersions: [String: Int] = [:]
    private var mailboxVersions: [String: Int] = [:]
    private var feedVersions: [String: Int] = [:]
    private var confirmedFeeds: Set<String> = []
    private var loadingFeeds: Set<String> = []
    private var feedFailures: [String: String] = [:]
    private var verifyingCompletion = false
    private var cacheVersion = 0
    private var cacheWasCleared = false
    private var unreadCounts: [String: Int] = [:]
    private var badgeVersion = 0
    private var badgeRefresh: Task<Void, Never>?
    private var countsRefresh: Task<Void, Never>?
    var seenFailure: String?
    private var session = FeedSession()
    private var sectionCounts: [String: FeedSectionCounts] = [:] {
        didSet { persistProgress() }
    }
    private var completeCounts: Set<String> = []
    private var pageLoaded: Set<String> = []
    private var nextCursors: [String: String] = [:]
    private var pageFrontiers: [String: Date] = [:]
    private var pagination = FeedPaginationLifecycle()
    private var incompleteCards: Set<String> = []
    var loadingMore: Bool { pagination.isLoading(generation: session.generation) }
    var paginationFailure: String?

    var feedSessionID: Int { session.generation }
    var sessionMessages: [Message] { session.cards.filter { feedingIDs.contains($0.mailboxID) } }
    func noteFeedInteraction() { session.interacted() }

    func remaining(in section: String) -> Int? {
        if isSample { return activeMessages.filter { session.section(for: $0.receivedAt) == section }.count }
        guard !feedingIDs.isEmpty, feedingIDs.isSubset(of: completeCounts) else { return nil }
        return feedingIDs.reduce(0) { $0 + (sectionCounts[$1]?[section] ?? 0) }
    }
    /// Display-only progress keeps the last verified baseline while counts
    /// revalidate. Completion and badges must continue using confirmed state.
    func progressRemaining(in section: String) -> Int? {
        if isSample { return remaining(in: section) }
        guard !feedingIDs.isEmpty, feedingIDs.allSatisfy({ sectionCounts[$0] != nil }) else { return nil }
        let baseline = feedingIDs.reduce(0) { $0 + (sectionCounts[$1]?[section] ?? 0) }
        let saving = recordedReads.values.filter {
            feedingIDs.contains($0.mailboxID) && $0.isFeedEligible && failedSeen[$0.key] == nil
                && !seenKeys.contains($0.key) && session.section(for: $0.receivedAt) == section
        }.count
        return max(0, baseline - saving)
    }
    var remainingInFeed: Int? {
        guard let today = remaining(in: "TODAY"), let yesterday = remaining(in: "YESTERDAY"),
              let earlier = remaining(in: "EARLIER") else { return nil }
        return today + yesterday + earlier
    }
    var hasMoreFeed: Bool { !Set(nextCursors.keys).isDisjoint(with: feedingIDs) }
    var feedEndVerified: Bool {
        if isSample { return true }
        return !feedingIDs.isEmpty && feedingIDs.isSubset(of: pageLoaded)
            && feedingIDs.isSubset(of: completeCounts) && !hasMoreFeed
            && loadingFeeds.isDisjoint(with: feedingIDs) && incompleteCards.isDisjoint(with: feedingIDs)
            && feedingIDs.allSatisfy { feedFailures[$0] == nil }
            && remainingInFeed == knownEligibleUnread.count
    }

    private var knownEligibleUnread: [Message] {
        var keys: Set<String> = []
        return (messages + pending).filter {
            feedingIDs.contains($0.mailboxID) && $0.isFeedEligible && !$0.isRead
                && !hasSeen($0) && keys.insert(seenKey($0)).inserted
        }
    }

    var eligiblePending: [Message] {
        pending.filter { feedingIDs.contains($0.mailboxID) && $0.isFeedEligible && !$0.isRead && !hasSeen($0) && !hasRecordedRead($0) }
    }

    private func applyKnownReads(_ ids: [String], accountID: String) {
        let keys = Set(ids.map { accountID + ":" + $0 })
        for message in messages + pending where keys.contains(seenKey(message)) {
            confirmRead(message, decrement: false)
        }
    }

    /// App/tab re-entry and an explicit refresh are the only session resets.
    /// Cached unread cards are available synchronously while the network catches up.
    func beginFeedSession(at date: Date = .now, calendar: Calendar = .current) {
        countsRefresh?.cancel()
        completeCounts.removeAll()
        let baseline = FeedProgressSnapshot(date: session.startedAt, timeZone: session.timeZone.identifier,
                                            sections: sectionCounts).rebased(at: date, calendar: calendar)
        let read = messages.filter { $0.isRead || hasSeen($0) || hasRecordedRead($0) }
        var known = Set(retained.map(seenKey))
        retained.append(contentsOf: read.filter { known.insert(seenKey($0)).inserted })
        messages = (messages + pending).filter { !$0.isRead && !hasSeen($0) && !hasRecordedRead($0) }
        pending.removeAll()
        session.restart(with: messages.filter { archiving[seenKey($0)] == nil }, at: date, calendar: calendar)
        sectionCounts = baseline
        pageLoaded.removeAll()
        nextCursors.removeAll()
        pageFrontiers.removeAll()
        pagination.reset()
        incompleteCards.removeAll()
        paginationFailure = nil
        for id in auth.accounts.map(\.id) { feedVersions[id, default: 0] += 1 }
        loadingFeeds.removeAll()
    }

    /// A page from a second mailbox must not land below older mail from the
    /// first. Hold older candidates until every mailbox has crossed that date.
    private func revealAvailablePage() {
        guard isSample || feedingIDs.isSubset(of: pageLoaded) else { return }
        let frontier = feedingIDs.compactMap { nextCursors[$0] == nil ? nil : pageFrontiers[$0] }.max()
        let visible = Set(session.cards.map(seenKey))
        let candidates = activeMessages.filter {
            !visible.contains(seenKey($0)) && (frontier == nil || $0.receivedAt >= frontier!)
        }.sorted(by: FeedSession.newer)
        if let last = session.cards.last, session.hasInteracted {
            let later = candidates.filter { $0.receivedAt > last.receivedAt }
            let laterKeys = Set(later.map(seenKey))
            messages.removeAll { laterKeys.contains(seenKey($0)) }
            pending.append(contentsOf: later)
            session.append(candidates.filter { !laterKeys.contains(seenKey($0)) })
        } else if session.cards.isEmpty {
            session.append(candidates)
        } else {
            // Startup reconciliation may discover newer mail after cached
            // cards are already on screen. It uses the same deliberate pill.
            let later = candidates.filter { $0.receivedAt > session.cards.last!.receivedAt }
            let laterKeys = Set(later.map(seenKey))
            messages.removeAll { laterKeys.contains(seenKey($0)) }
            pending.append(contentsOf: later)
            session.append(candidates.filter { !laterKeys.contains(seenKey($0)) })
        }
    }

    func loadMoreFeed() async {
        guard !isSample, !Task.isCancelled, hasMoreFeed,
              let ticket = pagination.beginRun(generation: session.generation) else { return }
        defer { pagination.finishRun(ticket) }
        paginationFailure = nil
        let visibleBefore = session.cards.count
        let generation = ticket.generation
        repeat {
            let cursorsBefore = nextCursors
            let frontier = feedingIDs.compactMap { nextCursors[$0] == nil ? nil : pageFrontiers[$0] }.max()
            let accounts = feedingIDs.filter { nextCursors[$0] != nil && (frontier == nil || pageFrontiers[$0] == frontier) }
            await withTaskGroup(of: Void.self) { group in
                for accountID in accounts {
                    guard let cursor = nextCursors[accountID] else { continue }
                    group.addTask {
                        await self.load(accountID, admitDirectly: true, cursor: cursor, expectedGeneration: generation)
                    }
                }
            }
            guard !Task.isCancelled, generation == session.generation else { return }
            revealAvailablePage()
            if nextCursors == cursorsBefore {
                paginationFailure = "Couldn’t load older emails. Try again."
                return
            }
        } while hasMoreFeed && session.cards.count == visibleBefore && paginationFailure == nil
    }

    private func confirmRead(_ message: Message, decrement: Bool = true) {
        confirmRead(FeedReadIntent(message), decrement: decrement)
    }

    private func confirmRead(_ message: FeedReadIntent, decrement: Bool = true) {
        let key = message.key
        let alreadyRead = seenKeys.contains(key) || (messages + pending + retained).first { $0.feedKey == key }?.isRead == true
        if decrement && !alreadyRead && message.isFeedEligible, sectionCounts[message.mailboxID] != nil {
            let name = session.section(for: message.receivedAt)
            sectionCounts[message.mailboxID]![name] -= 1
        }
        seenKeys.insert(key)
        persistSeen()
        mutate(message.id, accountID: message.mailboxID) { $0.isRead = true }
        failedSeen.removeValue(forKey: key)
        recordedReads.removeValue(forKey: key)
        persistRecordedReads()
        seenFailure = failedSeen.isEmpty ? nil : "Some posts couldn’t be marked as read. Try again."
    }

    private func seenKey(_ message: Message) -> String { message.mailboxID + ":" + message.id }
    func hasSeen(_ message: Message) -> Bool { seenKeys.contains(seenKey(message)) }
    var activeMessages: [Message] {
        let included = feedingIDs
        return messages.filter { included.contains($0.mailboxID) && $0.isFeedEligible && !$0.isRead && !hasSeen($0) && !hasRecordedRead($0) && archiving[seenKey($0)] == nil }
    }
    var hasPendingInFeed: Bool {
        !eligiblePending.isEmpty
    }

    var checkingCompletion: Bool {
        guard !isSample else { return false }
        let included = feedingIDs
        return verifyingCompletion || !markingSeen.isEmpty || !loadingFeeds.isDisjoint(with: included)
            || (!cacheWasCleared && included.contains { !confirmedFeeds.contains($0) && feedFailures[$0] == nil })
    }

    var completionVerified: Bool {
        guard !recordedReads.values.contains(where: { feedingIDs.contains($0.mailboxID) }), !hasPendingInFeed, !failedSeen.values.contains(where: { feedingIDs.contains($0.mailboxID) }) else { return false }
        return remainingInFeed == 0 && (isSample || feedEndVerified)
    }

    var completionFailure: String? {
        if let failure = feedingIDs.compactMap({ feedFailures[$0] }).first { return failure }
        if !incompleteCards.isDisjoint(with: feedingIDs) { return "Some emails couldn’t be displayed. Try again." }
        if !feedingIDs.isSubset(of: completeCounts) { return "Still checking the rest of your mailbox." }
        return nil
    }

    func verifyCompletion() async { await refresh() }

    func retrySeen() async {
        for message in Array(failedSeen.values) {
            guard !Task.isCancelled else { return }
            await markSeen(message)
        }
    }

    private func persistSeen() {
        if !isSample { UserDefaults.standard.set(Array(seenKeys), forKey: "feed.seenMessages") }
    }

    private func hasRecordedRead(_ message: Message) -> Bool {
        recordedReads[message.feedKey] != nil && failedSeen[message.feedKey] == nil
    }

    private func persistRecordedReads() {
        guard !isSample else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(recordedReads), forKey: "feed.recordedReads")
    }

    private func persistProgress() {
        guard !isSample else { return }
        let snapshot = FeedProgressSnapshot(date: session.startedAt, timeZone: session.timeZone.identifier,
                                            sections: sectionCounts)
        UserDefaults.standard.set(try? JSONEncoder().encode(snapshot), forKey: "feed.progressSnapshot")
    }

    /// Record proven passes synchronously. The view only measures gestures;
    /// the store owns their delivery, independent of the visible screen.
    func recordSeen(_ messages: [Message]) {
        for message in messages where !message.isRead && !hasSeen(message) {
            recordedReads[message.feedKey] = FeedReadIntent(message)
            failedSeen.removeValue(forKey: message.feedKey)
        }
        persistRecordedReads()
        drainRecordedReads()
    }

    private func drainRecordedReads() {
        guard readDrain == nil else { return }
        recordedReads = recordedReads.filter { !seenKeys.contains($0.key) }
        persistRecordedReads()
        readDrain = Task { @MainActor in
            while let intent = recordedReads.values.sorted(by: { $0.receivedAt > $1.receivedAt }).first(where: { intent in
                failedSeen[intent.key] == nil && !markingSeen.contains(intent.key)
                    && (isSample || auth.accounts.contains { $0.id == intent.mailboxID })
            }) {
                await markSeen(intent)
            }
            readDrain = nil
        }
    }

    /// A confirmed read changes progress, never this session’s membership.
    func markSeen(_ message: Message) async { await markSeen(FeedReadIntent(message)) }

    private func markSeen(_ intent: FeedReadIntent) async {
        let key = intent.key, accountID = intent.mailboxID
        guard isSample || auth.accounts.contains(where: { $0.id == accountID }) else { return }
        guard !seenKeys.contains(key), markingSeen.insert(key).inserted else { return }
        recordedReads[key] = intent
        failedSeen.removeValue(forKey: key)
        persistRecordedReads()
        readVersions[key, default: 0] += 1
        mailboxVersions[accountID, default: 0] += 1
        do {
            let wasUnread: Bool?
            if isSample { wasUnread = true } else { wasUnread = try await client(accountID).markRead(intent.id) }
            markingSeen.remove(key)
            guard isSample || auth.accounts.contains(where: { $0.id == accountID }) else { return }
            readVersions[key, default: 0] += 1
            mailboxVersions[accountID, default: 0] += 1
            confirmRead(intent, decrement: wasUnread == true)
            if wasUnread == nil { completeCounts.remove(accountID) }
            unreadCounts[accountID] = nil
            scheduleBadgeRefresh()
            scheduleCountsRefresh()
        } catch {
            readVersions[key, default: 0] += 1
            markingSeen.remove(key)
            if seenKeys.contains(key) { failedSeen.removeValue(forKey: key); return }
            guard isSample || auth.accounts.contains(where: { $0.id == accountID }) else { return }
            // Keep the intent on disk for retry, but restore its displayed count.
            failedSeen[key] = intent
            if let held = retained.first(where: { $0.feedKey == key }), !messages.contains(where: { $0.feedKey == key }) {
                messages.append(held)
            }
            seenFailure = "Couldn’t save some read emails. Try again."
        }
    }

    /// One provider total per connected mailbox, independent of the 200-post
    /// feed window. Unknown totals preserve the badge instead of inventing zero.
    func refreshUnreadBadge() async {
        guard !isSample else { return }
        badgeVersion += 1
        let version = badgeVersion
        let accounts = auth.accounts
        let mailboxAtStart = mailboxVersions
        var counts: [String: Int] = [:]
        for account in accounts {
            if let count = try? await GmailClient(auth: auth, accountID: account.id).unreadCount() {
                counts[account.id] = count
            } else { return }
        }
        guard !Task.isCancelled, version == badgeVersion,
              Set(accounts.map(\.id)) == Set(auth.accounts.map(\.id)),
              accounts.allSatisfy({ mailboxAtStart[$0.id] == mailboxVersions[$0.id] }) else { return }
        unreadCounts.merge(counts) { _, new in new }
        let total = counts.values.reduce(0, +)
        try? await UNUserNotificationCenter.current().setBadgeCount(total)
    }

    private func scheduleBadgeRefresh() {
        badgeRefresh?.cancel()
        badgeRefresh = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await loadConversations(preservingLoaded: true)
            await refreshUnreadBadge()
        }
    }

    private func scheduleCountsRefresh() {
        guard !isSample else { return }
        countsRefresh?.cancel()
        let generation = session.generation
        countsRefresh = Task {
            var attempt = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(attempt == 0 ? 1 : 15))
                attempt += 1
                guard !Task.isCancelled, session.generation == generation else { return }
                for accountID in feedingIDs {
                    // Every loaded ID is reconciled. Repeating only the first
                    // page could leave a card read elsewhere stranded forever.
                    let known = knownEligibleUnread.filter { $0.mailboxID == accountID }.map(\.id)
                    let batches = known.isEmpty ? [[]] : stride(from: 0, to: known.count, by: 200).map {
                        Array(known[$0..<min($0 + 200, known.count)])
                    }
                    for batch in batches {
                        let version = mailboxVersions[accountID, default: 0]
                        let wasSaving = markingSeen.contains { $0.hasPrefix(accountID + ":") }
                        let response = try? await client(accountID).feedCounts(sectionDate: session.startedAt, knownMessageIDs: batch)
                        guard !Task.isCancelled, session.generation == generation else { return }
                        guard let response, feedingIDs.contains(accountID), !wasSaving,
                              !markingSeen.contains(where: { $0.hasPrefix(accountID + ":") }),
                              version == mailboxVersions[accountID, default: 0] else {
                            completeCounts.remove(accountID)
                            break
                        }
                        guard response.countsComplete && response.sections.isValid else {
                            completeCounts.remove(accountID)
                            break
                        }
                        sectionCounts[accountID] = response.sections
                        completeCounts.insert(accountID)
                        if response.knownStateComplete == true {
                            applyKnownReads(response.knownReadMessageIds ?? [], accountID: accountID)
                        }
                        if response.sections.total == 0 {
                            for message in messages + pending where message.mailboxID == accountID {
                                confirmRead(message, decrement: false)
                            }
                        }
                    }
                    guard !Task.isCancelled, session.generation == generation else { return }
                    let knownCount = knownEligibleUnread.filter { $0.mailboxID == accountID }.count
                    if completeCounts.contains(accountID), (sectionCounts[accountID]?.total ?? 0) > knownCount,
                       nextCursors[accountID] == nil && !loadingFeeds.contains(accountID) {
                        // A complete sync can add older mail after an early
                        // snapshot ended. Refresh its cursor without replacing
                        // the session, or cancelling this reconciliation task.
                        pageLoaded.remove(accountID)
                        await load(accountID, admitDirectly: true, scheduleCountCheck: false)
                    }
                }
                if feedingIDs.isSubset(of: completeCounts)
                    && (hasMoreFeed || remainingInFeed == knownEligibleUnread.count) { return }
            }
        }
    }


    /// Messages that arrived while the user was scrolled away. The feed set is
    /// frozen at load and this is the only path anything joins it by — which
    /// is what makes the list stable under the thumb.
    var pending: [Message] = []

    /// Live unsubscribe runs, keyed by message. The enum is fixed; the sentence
    /// is written by the model each step, so the UI shows what it is told.
    var unsubscribes: [String: SSEClient.UnsubscribeStatus] = [:]

    /// P5 — the action receipt. One at a time; a new one replaces the old.
    var receipt: Receipt?

    /// Mail from people, grouped by who is in it. Loaded separately from the
    /// feed because it answers a different question — the feed asks what
    /// arrived, this asks who you are talking to.
    var conversations: [Conversation] = []
    var conversationsLoaded = false
    var conversationsFailure: String?
    var conversationsNextCursor: String?
    var conversationsTotal: Int?
    var conversationsUnreadTotal: Int?
    /// The tab and People masthead describe the same unit: conversations.
    /// During indexing only known loaded unread rows can be counted honestly.
    var peopleUnreadCount: Int {
        if conversationsHistoryComplete, let total = conversationsUnreadTotal {
            return max(0, total)
        }
        return conversations.count { $0.unread }
    }
    var conversationsHistoryComplete = false
    var conversationsSyncState = "pending"
    var conversationsLoading = false
    private var conversationsRequestID = UUID()
    private var conversationsLoadedOlderPages = false


    /// The masthead, written by the model rather than assembled from a
    /// template. Nil until it lands — the feed does not wait on it.
    var recap: APIClient.Recap?

    /// What this session actually did. Counted here rather than inferred at
    /// render time, because the caught-up receipt is the one place the product
    /// makes a claim about the user's own work — and a claim like that has to
    /// be a count, not an estimate.
    struct Tally {
        var archived = 0
        var replied = 0
        var unsubscribed = 0
        var saved = 0

        var isEmpty: Bool { archived + replied + unsubscribed + saved == 0 }
        var handled: Int { archived + replied + unsubscribed }
    }

    var tally = Tally()

    struct Receipt: Identifiable {
        enum Undo {
            case send
            case archive(Message, Int)
        }
        let id = UUID()
        var message: String
        var detail: String?
        var undo: Undo?
    }

    let auth: AuthService
    private var streams: [String: SSEClient] = [:]
    private var loaded: Set<String> = []
    private var syncing: Set<String> = []
    private var outgoing: Task<Void, Never>?
    private var archiving: [String: Task<Void, Never>] = [:]
    private var reconcile: [String: Task<Void, Never>] = [:]

    init(auth: AuthService) {
        self.auth = auth
        SenderIdentityStore.shared.configure(auth: auth, isSample: false)
        syncMailboxes()
        if let data = UserDefaults.standard.object(forKey: "feed.recordedReads") as? Data,
           let saved = try? JSONDecoder().decode([String: FeedReadIntent].self, from: data) {
            recordedReads = saved.filter { entry in auth.accounts.contains { $0.id == entry.value.mailboxID } }
        }
        var restored: [Message] = []
        for account in auth.accounts {
            guard let cached = FeedCache.load(for: account.id) else { continue }
            restored += cached.cards.map { $0.asMessage(mailboxID: account.id) }
            if recap == nil { recap = cached.recap }
        }
        var keys: Set<String> = []
        messages = restored.filter { keys.insert(seenKey($0)).inserted }
            .map { message in
                var message = message
                if seenKeys.contains(seenKey(message)) { message.isRead = true }
                return message
            }
            .sorted { $0.receivedAt > $1.receivedAt }
        session.restart(with: messages.filter { !hasRecordedRead($0) })
        if let data = UserDefaults.standard.object(forKey: "feed.progressSnapshot") as? Data,
           let snapshot = try? JSONDecoder().decode(FeedProgressSnapshot.self, from: data) {
            sectionCounts = snapshot.rebased(at: session.startedAt).filter { entry in
                auth.accounts.contains { $0.id == entry.key }
            }
        }
        SenderIdentityStore.shared.remember(messages: messages)
        if let first = auth.accounts.first, let cached = FeedCache.loadConversations(for: first.id) {
            conversations = cached.map(Self.conversation(from:))
            conversationsLoaded = true
        }
    }

    /// True only for the design-time store.
    private(set) var isSample = false

    /// Preview / design-time store. Never used by the running app.
    init(sample: Bool) {
        self.isSample = true
        self.auth = AuthService()
        self.mailboxes = Sample.mailboxes
        self.messages = Sample.messages
        self.seenKeys = []
        SenderIdentityStore.shared.configure(auth: auth, isSample: true)
        SenderIdentityStore.shared.remember(messages: messages)
        session.restart(with: messages)
    }

    private func client(_ accountID: String) -> APIClient {
        APIClient(auth: auth, accountID: accountID, timeZone: session.timeZone)
    }

    /// Clearing local storage leaves account access and the inbox-zero habit
    /// intact. Old requests may finish, but may not restore the cleared cache.
    func clearCachedContent() {
        cacheVersion += 1
        cacheWasCleared = true
        for accountID in Array(feedVersions.keys) { feedVersions[accountID, default: 0] += 1 }
        loadingFeeds.removeAll()
        confirmedFeeds.removeAll()
        feedFailures.removeAll()
        FeedCache.clearAll()
        SenderIdentityStore.shared.clearCache()
        RemoteImageStore.shared.clearCache()
        messages.removeAll()
        pending.removeAll()
        retained.removeAll()
        conversations.removeAll()
        conversationsLoaded = false
        conversationsRequestID = UUID()
        conversationsLoadedOlderPages = false
        conversationsNextCursor = nil
        conversationsTotal = nil
        conversationsUnreadTotal = nil
        conversationsHistoryComplete = false
        conversationsSyncState = "pending"
        conversationsLoading = false
        conversationsFailure = nil
        unsubscribes.removeAll()
        recap = nil
        tally = Tally()
        receipt = nil
        failedSeen.removeAll()
        seenFailure = nil
        loadFailure = nil
        session.restart(with: [])
        pageLoaded.removeAll()
        nextCursors.removeAll()
        pageFrontiers.removeAll()
        pagination.reset()
        sectionCounts.removeAll()
        completeCounts.removeAll()
    }

    // MARK: Derived

    var saved: [Message] { (messages + retained).filter(\.isSaved) }

    var needsReconnect: [Mailbox] { mailboxes.filter { !$0.isHealthy } }

    var waitingCount: Int { activeMessages.count { $0.kicker == .needsYou } }

    /// Things you answered that have not come back yet. The one honest
    /// version of "still open": we know we sent, and we know nothing landed.
    var stillOpen: [Message] { messages.filter { $0.kicker == .waitingOnThem } }

    /// Only mailboxes the user has left in the unified feed. Excluding one
    /// hides its mail here without disconnecting it — the distinction matters
    /// for a work address you do not want in your evening.
    private var feedingIDs: Set<String> {
        Set(mailboxes.filter(\.includeInUnifiedFeed).map(\.id))
    }

    func mailbox(_ id: String) -> Mailbox? { mailboxes.first { $0.id == id } }

    /// Everything one sender has said, newest first. Drawn from what is
    /// already loaded — a profile is a lens on the feed, not a second fetch.
    func messages(from address: String) -> [Message] {
        (messages + pending + retained)
            .filter { $0.sender.address.caseInsensitiveCompare(address) == .orderedSame }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    /// The one-to-one conversation with this person, if there is one.
    ///
    /// A sender profile reads `messages(from:)`, which is the feed — and the
    /// feed is what arrived since you got here. Somebody you have a live
    /// thread with is usually not in it, so their profile said "Nothing from
    /// them" about a conversation you were in the middle of. Conversations
    /// come from the archive and have to be asked for separately.
    func conversation(with address: String) -> Conversation? {
        conversations.first { conversation in
            !conversation.isGroup && conversation.participants.contains {
                $0.address.caseInsensitiveCompare(address) == .orderedSame
            }
        }
    }

    /// The tag is shown on a post only when there is more than one mailbox to
    /// tell apart. With one, it is noise on every single row.
    var showsMailboxTags: Bool { mailboxes.count > 1 }

    // MARK: Lifecycle

    /// Brings every connected mailbox up. Safe to call repeatedly — each
    /// mailbox is only started once, so adding a fourth does not re-sync three.
    func start() async {
        if isSample { return }
        syncMailboxes()
        failedSeen.removeAll()
        drainRecordedReads()
        await withTaskGroup(of: Void.self) { group in
            for account in auth.accounts where !loaded.contains(account.id) {
                loaded.insert(account.id)
                group.addTask { await self.bring(up: account.id) }
            }
        }
    }

    private func bring(up accountID: String) async {
        #if DEBUG
        print("[feed] starting mailbox")
        #endif
        // Disk first. The feed you were reading a minute ago is still true,
        // and showing it immediately is the difference between opening a mail
        // app and watching one boot.
        if messages.isEmpty, let cached = FeedCache.load(for: accountID) {
            messages = cached.cards
                .map { $0.asMessage(mailboxID: accountID) }
                .sorted { $0.receivedAt > $1.receivedAt }
            recap = cached.recap
        }

        // A mailbox with nothing to show is *reading*, and it is reading from
        // the moment it is brought up — not from the moment `settle` is
        // finally reached. Registering and opening the stream take seconds on
        // a cold server, and for that entire window the feed was rendering
        // "Nothing waiting" over a mailbox it had not yet looked at. That is
        // the exact claim `settle` exists to prevent, made earlier in the same
        // function.
        if messages.isEmpty { syncing.insert(accountID) }
        defer { syncing.remove(accountID) }

        // Registering hands the server a refresh token so it can keep syncing
        // while the app is closed. It also kicks off the first backlog pull,
        // so it has to happen before the feed is worth reading.
        try? await client(accountID).register()
        #if DEBUG
        print("[feed] registration finished")
        #endif

        // The stream goes up first: the backlog pull is already running, and
        // anything it produces should have somewhere to land.
        let stream = SSEClient(baseURL: client(accountID).baseURL, auth: auth, accountID: accountID)
        streams[accountID] = stream
        await stream.connect { [weak self] event in
            await self?.apply(event, from: accountID)
        }

        await load(accountID, admitDirectly: true)
        await settle(accountID)
    }

    /// Waits out the first sync of a new mailbox.
    ///
    /// `/auth/register` only *starts* the backlog pull, and that pull emits no
    /// events of its own — so a mailbox connected ten seconds ago answers
    /// `/feed` with an empty list that is not the same thing as an empty inbox.
    /// Saying "nothing waiting" then would be a lie, and the kind that makes
    /// someone delete the app.
    private func settle(_ accountID: String) async {
        // A hydrated feed already gave the user something true to read, so the
        // "reading your mailbox" state is only for a genuinely cold start.
        // `bring(up:)` owns the flag — it is raised before the first network
        // call rather than after three of them.
        guard messages.isEmpty else { return }

        for delay in [2, 3, 5, 8, 12, 20, 30] {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await load(accountID, admitDirectly: true)
            if !messages.isEmpty { return }
        }
    }

    /// True while a mailbox is doing its first sync and has produced nothing
    /// yet. The distinction the feed has to draw is "not yet" versus "none".
    var isFirstSync: Bool { !syncing.isEmpty && messages.isEmpty }

    /// Why the last fetch failed, if it did. "Nothing waiting" is a claim
    /// about someone's mailbox, and the app must never make it on the strength
    /// of a request that did not come back.
    var loadFailure: String?

    /// Pulls the conversation list. Cheap enough to call on every appearance:
    /// it is one request and the result is small.
    ///
    /// Reads the cache first, so the list is on screen before the request goes
    /// out. The people who wrote to you a minute ago are still the people who
    /// wrote to you, and a headline saying otherwise while the network answers
    /// is the app narrating its own plumbing.
    func loadConversations(preservingLoaded: Bool = false) async {
        guard !isSample else { conversationsLoaded = true; conversationsHistoryComplete = true; return }
        guard let account = auth.accounts.first else { return }
        guard !preservingLoaded || !conversationsLoading else { return }
        let version = cacheVersion
        let requestID = UUID()
        conversationsRequestID = requestID
        conversationsLoading = true
        defer { if conversationsRequestID == requestID { conversationsLoading = false } }
        if conversations.isEmpty, let cached = FeedCache.loadConversations(for: account.id) {
            conversations = cached.map(Self.conversation(from:))
            conversationsLoaded = true
        }
        do {
            let page = try await client(account.id).conversationsPage()
            guard !Task.isCancelled, version == cacheVersion, conversationsRequestID == requestID else { return }
            let incoming = page.conversations.map(Self.conversation(from:))
            if (preservingLoaded || page.historyComplete != true)
                && !(page.historyComplete == true && page.totalConversations == 0) {
                // A background directory begins with partial data. Keep both
                // cached rows and older pages already requested while it fills.
                var merged = Dictionary(conversations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for row in incoming { merged[row.id] = row }
                conversations = merged.values.sorted {
                    $0.lastAt == $1.lastAt ? $0.id > $1.id : $0.lastAt > $1.lastAt
                }
                if !conversationsLoadedOlderPages || conversationsNextCursor == nil {
                    conversationsNextCursor = page.nextCursor
                }
            } else {
                conversations = incoming
                conversationsNextCursor = page.nextCursor
                conversationsLoadedOlderPages = false
            }
            conversationsTotal = page.totalConversations
            conversationsUnreadTotal = page.unreadConversations
            conversationsHistoryComplete = page.historyComplete == true
            conversationsSyncState = page.historySyncState ?? "pending"
            if !page.conversations.isEmpty || page.historyComplete == true {
                FeedCache.saveConversations(page.conversations, for: account.id)
            }
            conversationsFailure = nil
            conversationsLoaded = true
        } catch {
            guard !Task.isCancelled, version == cacheVersion, conversationsRequestID == requestID else { return }
            conversationsFailure = "Couldn’t refresh conversations. Try again."
        }
    }

    func loadMoreConversations() async {
        guard !isSample, !conversationsLoading, let startingCursor = conversationsNextCursor,
              let account = auth.accounts.first else { return }
        let version = cacheVersion
        let requestID = conversationsRequestID
        conversationsLoading = true
        defer { if conversationsRequestID == requestID { conversationsLoading = false } }
        var cursor = startingCursor
        do {
            // A refreshed directory may overlap pages already visited. Walk
            // duplicate-only pages automatically, retaining a retryable cursor.
            for _ in 0..<20 {
                let page = try await client(account.id).conversationsPage(cursor: cursor)
                guard !Task.isCancelled, version == cacheVersion, conversationsRequestID == requestID else { return }
                let existing = Set(conversations.map(\.id))
                let fresh = page.conversations.map(Self.conversation(from:)).filter { !existing.contains($0.id) }
                conversations.append(contentsOf: fresh)
                conversationsLoadedOlderPages = true
                conversationsNextCursor = page.nextCursor
                conversationsTotal = page.totalConversations
                conversationsUnreadTotal = page.unreadConversations
                conversationsHistoryComplete = page.historyComplete == true
                conversationsSyncState = page.historySyncState ?? "pending"
                conversationsFailure = nil
                guard fresh.isEmpty, let next = page.nextCursor, next != cursor else { break }
                cursor = next
            }
        } catch {
            guard !Task.isCancelled, version == cacheVersion, conversationsRequestID == requestID else { return }
            conversationsFailure = "Couldn’t load older conversations. Try again."
        }
    }

    private static func conversation(from c: APIClient.ConversationWire) -> Conversation {
        Conversation(
            id: c.id,
            participants: c.participants.map { p in
                Sender(
                    name: p.name ?? "",
                    address: p.email,
                    // Everyone in here is a person by construction — the
                    // server refuses to build a conversation that contains an
                    // automated address.
                    kind: .person,
                    // This was hardcoded to nil, and it is why nobody in
                    // People or in a thread header had a picture. The server
                    // sends `avatarUri` on every participant and always has;
                    // the thread's own message mapping reads it correctly.
                    // This one path threw it away, so every row fell back to a
                    // grey monogram and the whole screen looked like the
                    // feature had never been built.
                    logoURL: p.avatarUri.flatMap(URL.init(string:))
                )
            },
            preview: c.preview ?? "",
            lastAt: Date(timeIntervalSince1970: c.lastAt / 1000),
            lastFromMe: c.lastFromMe ?? false,
            unread: c.unread ?? false,
            messageCount: c.messageCount ?? 0
        )
    }

    /// What this thread said last time, straight off disk.
    ///
    /// Synchronous and on purpose: it is read before the view's first frame, so
    /// a thread you have opened before is simply already there. Removing the
    /// Gmail fetch made the request fast, which is not the same as there being
    /// nothing to wait for — the round trip was still a cold wait on every
    /// single open, and on a sleeping instance a long one.
    func cachedMessages(in conversation: Conversation) -> [ConversationMessage] {
        guard !isSample else { return [] }
        guard let account = auth.accounts.first,
              let wire = FeedCache.loadMessages(account: account.id, conversation: conversation.id)
        else { return [] }
        return wire.map(Self.message(from:))
    }

    struct ConversationPage {
        let messages: [ConversationMessage]
        let nextCursor: String?
        let totalMessages: Int?
        let historyComplete: Bool
        let historySyncState: String
        let sourcesPending: Bool
    }

    func messagesPage(in conversation: Conversation, cursor: String? = nil) async throws -> ConversationPage {
        guard !isSample else {
            return ConversationPage(messages: [], nextCursor: nil, totalMessages: 0,
                                    historyComplete: true, historySyncState: "complete", sourcesPending: false)
        }
        guard let account = auth.accounts.first else { throw AuthError.signedOut }
        let version = cacheVersion
        let page = try await client(account.id).conversationMessagesPage(conversation.id, cursor: cursor)
        guard version == cacheVersion else { throw CancellationError() }
        // Keep the newest page for the next first frame. Loading older mail
        // never replaces that useful cached page with the oldest one visited.
        if cursor == nil { FeedCache.saveMessages(page.messages, account: account.id, conversation: conversation.id) }
        return ConversationPage(messages: page.messages.map(Self.message(from:)), nextCursor: page.nextCursor,
                                totalMessages: page.totalMessages, historyComplete: page.historyComplete == true,
                                historySyncState: page.historySyncState ?? "pending", sourcesPending: page.sourcesPending == true)
    }

    func messages(in conversation: Conversation) async -> [ConversationMessage] {
        (try? await messagesPage(in: conversation).messages) ?? []
    }

    private static func message(from m: APIClient.ConversationMessageWire) -> ConversationMessage {
        let subject = (m.subject ?? "").trimmingCharacters(in: .whitespaces)
        // A bare reply prefix is not a subject, it is punctuation left over
        // from a mail client. Showing "RE:" above a bubble would add a line
        // that says nothing.
        let meaningful = subject
            .replacingOccurrences(of: #"^((re|fwd|fw)\s*:\s*)+"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return ConversationMessage(
            id: m.messageId,
            sender: Sender(
                name: m.fromName ?? "",
                address: m.fromEmail ?? "",
                kind: .person,
                logoURL: m.avatarUri.flatMap(URL.init(string:))
            ),
            mine: m.mine,
            body: m.body ?? "",
            subject: meaningful.isEmpty ? nil : meaningful,
            receivedAt: Date(timeIntervalSince1970: m.internalDate / 1000),
            attachments: (m.attachments ?? []).map { wire in
                Attachment(
                    id: wire.id,
                    filename: wire.filename,
                    byteCount: wire.byteCount ?? 0,
                    preview: (wire.isImage == true)
                        ? (wire.previewUrl.flatMap(URL.init(string:)).map(Attachment.Preview.image)
                            ?? .document(pages: 0))
                        : .document(pages: wire.pages ?? 0),
                    fileURL: wire.fileUrl.flatMap(URL.init(string:)),
                    mimeType: wire.mimeType
                )
            }
        )
    }

    func refresh() async {
        guard !isSample else { return }
        syncMailboxes()
        failedSeen.removeAll()
        drainRecordedReads()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadConversations(preservingLoaded: true) }
            for account in auth.accounts {
                group.addTask { await self.load(account.id, admitDirectly: false) }
            }
        }
        await loadRecap()
        await refreshUnreadBadge()
    }

    /// The app came back to the foreground.
    ///
    /// Nothing called this before, and the cost was the whole reason this app
    /// felt slower than every other mail client on the phone. Two things go
    /// wrong while the app is off screen and neither fixes itself:
    ///
    /// 1. iOS suspends the event stream's connection. A suspended stream does
    ///    not report itself as dead — it just stops delivering. The feed then
    ///    sits open, looking live, showing mail from whenever the app was last
    ///    in front.
    /// 2. `start()` is idempotent by account, so re-entering the app ran no
    ///    fetch at all. The only way to see new mail was to pull to refresh.
    ///
    /// So the stream is torn down and rebuilt rather than trusted, and the
    /// feed is re-fetched from the server, which is authoritative.
    func resume() async {
        guard !isSample else { return }
        guard !loaded.isEmpty else { return await start() }

        await withTaskGroup(of: Void.self) { group in
            for accountID in loaded {
                group.addTask { await self.reopen(accountID) }
            }
        }
        await refresh()
    }

    /// Replaces one mailbox's event stream with a live one.
    private func reopen(_ accountID: String) async {
        await streams[accountID]?.disconnect()
        let stream = SSEClient(baseURL: client(accountID).baseURL, auth: auth, accountID: accountID)
        streams[accountID] = stream
        await stream.connect { [weak self] event in
            await self?.apply(event, from: accountID)
        }
    }

    /// Pulls one mailbox's feed and merges it in place, keeping every other
    /// mailbox's posts untouched.
    private func load(_ accountID: String, admitDirectly: Bool, cursor: String? = nil, expectedGeneration: Int? = nil, scheduleCountCheck: Bool = true) async {
        guard !isSample, !Task.isCancelled else { return }
        let generation = session.generation
        var pageTicket: FeedPaginationLifecycle.Ticket?
        if cursor != nil {
            guard let ticket = pagination.beginPage(account: accountID, generation: generation,
                                                    expectedGeneration: expectedGeneration) else { return }
            pageTicket = ticket
        }
        cacheWasCleared = false
        let version = (feedVersions[accountID] ?? 0) + 1
        feedVersions[accountID] = version
        let firstPage = cursor == nil && !pageLoaded.contains(accountID)
        loadingFeeds.insert(accountID)
        let readsAtStart = readVersions
        let markingAtStart = markingSeen
        let mailboxAtStart = mailboxVersions[accountID, default: 0]
        defer {
            if feedVersions[accountID] == version { loadingFeeds.remove(accountID) }
            if let pageTicket { pagination.finishPage(account: accountID, ticket: pageTicket) }
        }
        do {
            let knownIDs = knownEligibleUnread.filter { $0.mailboxID == accountID }.map(\.id)
            let response = try await client(accountID).feed(cursor: cursor, sectionDate: session.startedAt, knownMessageIDs: Array(knownIDs.prefix(200)))
            #if DEBUG
            print("[feed] response cards=\(response.cards.count) total=\(response.sections?.total ?? -1) provider=\(response.unreadCount ?? -1) complete=\(response.countsComplete) more=\(response.nextCursor != nil) sync=\(response.syncState ?? "unknown")")
            #endif
            guard !Task.isCancelled, feedVersions[accountID] == version,
                  generation == session.generation,
                  auth.accounts.contains(where: { $0.id == accountID }) else { return }
            let existing = Dictionary((messages + pending + retained).map { (seenKey($0), $0) },
                                      uniquingKeysWith: { first, _ in first })
            let incoming = response.cards.map { card -> Message in
                var updated = card.asMessage(mailboxID: accountID)
                let key = seenKey(updated)
                let previous = existing[key]
                updated.isSaved = previous?.isSaved ?? false
                updated.reaction = previous?.reaction
                let readChanged = readsAtStart[key] != readVersions[key]
                    || markingAtStart.contains(key) || markingSeen.contains(key)
                if readChanged {
                    updated.isRead = updated.isRead || previous?.isRead == true || seenKeys.contains(key)
                } else if !updated.isRead {
                    seenKeys.remove(key)
                }
                return updated
            }
            let byKey = Dictionary(incoming.map { (seenKey($0), $0) }, uniquingKeysWith: { first, _ in first })
            SenderIdentityStore.shared.remember(messages: incoming)
            let known = Set((messages + pending).map(seenKey))
            let fresh = incoming.filter { !known.contains(seenKey($0)) }
            // Refresh the backing records for the next visit. This visit
            // retains its membership, order and finished card contents.
            messages = messages.map { byKey[seenKey($0)] ?? $0 }
            pending = pending.map { byKey[seenKey($0)] ?? $0 }
            for message in incoming {
                session.update(seenKey(message)) { current in
                    if current.isInterpreting {
                        // Recover missed SSE progress/completion without
                        // replacing the row or moving its session date band.
                        let anchoredDate = current.receivedAt
                        current = message
                        current.receivedAt = anchoredDate
                    }
                    // Finished content stays still for this visit. Read state
                    // and the reader's actions remain live independently.
                    current.isRead = message.isRead
                    current.isSaved = message.isSaved
                    current.reaction = message.reaction
                }
            }
            if firstPage || cursor != nil || admitDirectly {
                messages.append(contentsOf: fresh)
            } else {
                pending.append(contentsOf: fresh.filter { !$0.isRead })
            }
            let displayedKeys = Set((messages + pending).map(seenKey))
            retained.removeAll { displayedKeys.contains(seenKey($0)) }
            if firstPage || cursor != nil {
                pageLoaded.insert(accountID)
                nextCursors[accountID] = response.nextCursor
                pageFrontiers[accountID] = incoming.last?.receivedAt ?? pageFrontiers[accountID]
                if response.droppedCards > 0 { incompleteCards.insert(accountID) }
            }
            if mailboxVersions[accountID, default: 0] == mailboxAtStart,
               !markingAtStart.contains(where: { $0.hasPrefix(accountID + ":") }),
               !markingSeen.contains(where: { $0.hasPrefix(accountID + ":") }) {
                unreadCounts[accountID] = response.unreadCount
                if let counts = response.sections, response.countsComplete {
                    sectionCounts[accountID] = counts
                    completeCounts.insert(accountID)
                    if response.knownStateComplete { applyKnownReads(response.knownReadMessageIds, accountID: accountID) }
                    if counts.total == 0 {
                        for message in messages + pending where message.mailboxID == accountID { confirmRead(message, decrement: false) }
                    }
                } else {
                    completeCounts.remove(accountID)
                }
            }
            persistSeen()
            confirmedFeeds.insert(accountID)
            feedFailures.removeValue(forKey: accountID)
            mark(accountID, healthy: true)
            lastSynced = .now
            loadFailure = nil
            if cursor == nil { FeedCache.save(response.cards, recap: recap, for: accountID) }
            revealAvailablePage()
            scheduleBadgeRefresh()
            if scheduleCountCheck && (!feedingIDs.isSubset(of: completeCounts) || remainingInFeed != knownEligibleUnread.count) { scheduleCountsRefresh() }
        } catch APIError.unauthorized, AuthError.signedOut {
            guard feedVersions[accountID] == version else { return }
            mark(accountID, healthy: false, reason: "needs reconnecting")
            loadFailure = "That mailbox needs reconnecting."
            feedFailures[accountID] = loadFailure
        } catch {
            guard !Task.isCancelled, feedVersions[accountID] == version else { return }
            #if DEBUG
            print("[feed] load failed: \(error.localizedDescription)")
            #endif
            loadFailure = error.localizedDescription
            feedFailures[accountID] = loadFailure
            if cursor != nil { paginationFailure = "Couldn’t load older emails. Try again." }
            if let urlError = error as? URLError, Self.unresolved.contains(urlError.code) {
                condition = .statusStrip(state: "OFFLINE", freshness: freshness)
            }
        }
        resolveCondition()
    }

    /// The briefing is a nicety, so it never blocks or reports failure — a
    /// missing recap just means the masthead shows counts and nothing else.
    private func loadRecap() async {
        guard !isSample, let first = auth.accounts.first, !activeMessages.isEmpty else { recap = nil; return }
        let hour = Calendar.current.component(.hour, from: .now)
        let timeOfDay = hour < 12 ? "morning" : (hour < 17 ? "afternoon" : "evening")
        let keys = activeMessages.map(seenKey)
        let cards = activeMessages.prefix(40).map(\.asRecapCard)
        let received = try? await client(first.id).sessionRecap(cards: cards, timeOfDay: timeOfDay)
        if keys == activeMessages.map(seenKey), !session.hasInteracted { recap = received }
    }

    func oldPosts(accountID: String, cursor: Int? = nil) async throws -> (posts: [Message], cursor: Int?) {
        if isSample {
            return ((messages + retained).filter { $0.mailboxID == accountID && ($0.isRead || hasSeen($0)) }, nil)
        }
        let response = try await client(accountID).allMail(cursor: cursor)
        return (response.cards.map { $0.asMessage(mailboxID: accountID) }
            .filter(\.isRead), response.nextCursor)
    }

    func notificationMessage(_ request: NotificationOpenRequest) async throws -> Message {
        guard !isSample else { throw APIError.sampleUnavailable }
        guard let messageID = request.messageID else { throw NotificationOpenError.unavailableEmail }
        let accountID = try request.connectedMailboxID(in: Set(auth.accounts.map(\.id)))
        if let cached = (messages + pending + retained).first(where: { $0.id == messageID && $0.mailboxID == accountID }) {
            return currentVersion(of: cached)
        }
        let card: APIClient.Card
        do { card = try await client(accountID).messageCard(messageID) }
        catch APIError.server(404) { throw NotificationOpenError.unavailableEmail }
        try Task.checkCancellation()
        guard auth.accounts.contains(where: { $0.id == accountID }) else { throw NotificationOpenError.disconnectedMailbox }
        guard card.messageId == messageID else { throw APIError.transport }
        let message = card.asMessage(mailboxID: accountID)
        retainIfNeeded(message)
        return currentVersion(of: message)
    }

    func body(of message: Message) async throws -> APIClient.Body {
        if isSample { return APIClient.Body(plainText: message.snippet, htmlRaw: "") }
        let version = cacheVersion
        let body = try await client(message.mailboxID).body(of: message.id)
        if version == cacheVersion, !Task.isCancelled,
           auth.accounts.contains(where: { $0.id == message.mailboxID }) {
            FeedCache.saveBody(body, account: message.mailboxID, message: message.id)
        }
        return body
    }

    func suggestReply(to message: Message) async throws -> String {
        guard !isSample else { throw APIError.sampleUnavailable }
        return try await client(message.mailboxID).suggestReply(messageID: message.id)
    }

    func discuss(question: String, about message: Message) async throws -> String {
        guard !isSample else { throw APIError.sampleUnavailable }
        return try await client(message.mailboxID).discuss(messageID: message.id, question: question)
    }

    // MARK: Mailboxes

    /// Mirrors the auth account list into feed-facing mailboxes, preserving
    /// per-mailbox preferences the user has already set.
    private func syncMailboxes() {
        mailboxes = auth.accounts.map { account in
            if var existing = mailboxes.first(where: { $0.id == account.id }) {
                existing.tag = account.tag
                return existing
            }
            return Mailbox(
                id: account.id, address: account.id, provider: "Gmail",
                status: .active(lastSynced: .now), tag: account.tag,
                includeInUnifiedFeed: true
            )
        }
    }

    func add() async {
        guard !isSample else { return }
        guard let account = await auth.connect() else { return }
        syncMailboxes()
        guard !loaded.contains(account.id) else { return }
        loaded.insert(account.id)
        await bring(up: account.id)
    }

    func remove(_ mailboxID: String) {
        Task {
            // The account must still authenticate while unregistering its push
            // token; otherwise a disconnected inbox keeps inflating the badge.
            if !isSample { try? await client(mailboxID).unregisterPushToken() }
            FeedCache.clear(for: mailboxID)
            await streams[mailboxID]?.disconnect()
            streams[mailboxID] = nil
            loaded.remove(mailboxID)
            messages.removeAll { $0.mailboxID == mailboxID }
            pending.removeAll { $0.mailboxID == mailboxID }
            retained.removeAll { $0.mailboxID == mailboxID }
            failedSeen = failedSeen.filter { $0.value.mailboxID != mailboxID }
            recordedReads = recordedReads.filter { $0.value.mailboxID != mailboxID }
            persistRecordedReads()
            confirmedFeeds.remove(mailboxID)
            loadingFeeds.remove(mailboxID)
            feedFailures.removeValue(forKey: mailboxID)
            unreadCounts.removeValue(forKey: mailboxID)
            sectionCounts.removeValue(forKey: mailboxID)
            completeCounts.remove(mailboxID)
            auth.disconnect(mailboxID)
            SenderIdentityStore.shared.clearCache()
            RemoteImageStore.shared.clearCache()
            SenderIdentityStore.shared.remember(messages: messages + pending + retained)
            syncMailboxes()
            resolveCondition()
            await refreshUnreadBadge()
        }
    }

    func rename(_ mailboxID: String, tag: String) {
        auth.rename(mailboxID, tag: tag)
        syncMailboxes()
    }

    func setIncluded(_ mailboxID: String, _ included: Bool) {
        guard let i = mailboxes.firstIndex(where: { $0.id == mailboxID }) else { return }
        mailboxes[i].includeInUnifiedFeed = included
        beginFeedSession()
    }


    /// Re-consent for one mailbox. Every other mailbox keeps working through it.
    func reconnect(_ mailboxID: String? = nil) async {
        guard !isSample else { return }
        let target = mailboxID ?? needsReconnect.first?.id ?? auth.accounts.first?.id
        guard let target, await auth.connect() != nil else { return }
        syncMailboxes()
        try? await client(target).register()
        await load(target, admitDirectly: true)
    }

    private func mark(_ mailboxID: String, healthy: Bool, reason: String = "") {
        guard let i = mailboxes.firstIndex(where: { $0.id == mailboxID }) else { return }
        mailboxes[i].status = healthy ? .active(lastSynced: .now) : .needsReconnect(reason: reason)
    }

    // MARK: Condition
    //
    // Degraded states are ranked: a mailbox the user must fix outranks a
    // network blip, and with several mailboxes the message names how many are
    // fine — "one is stale" is very different from "nothing works".

    private func resolveCondition() {
        let broken = needsReconnect
        if broken.isEmpty {
            condition = .normal
        } else if mailboxes.count == 1 {
            condition = .actionBar(message: "That mailbox needs reconnecting.", verb: "Reconnect")
        } else {
            let rest = mailboxes.count - broken.count
            condition = .actionBar(
                message: "\(broken.map(\.tag).joined(separator: ", ")) needs reconnecting. The other \(rest) are fine.",
                verb: "Reconnect"
            )
        }
    }

    /// When we last heard from the server — not when the newest email was
    /// sent. Reading it off the mail meant a mailbox synced two seconds ago
    /// reported "current as of 360 min ago", and one that had not synced since
    /// yesterday reported "up to date".
    private var lastSynced: Date?

    private var freshness: String {
        guard let lastSynced else { return "Not synced yet" }
        let minutes = Int(Date().timeIntervalSince(lastSynced) / 60)
        return minutes < 1 ? "Up to date" : "Last synced \(minutes) min ago"
    }

    /// URLError codes that mean "we never got an answer", as opposed to an
    /// answer we did not like.
    private static let unresolved: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet,
    ]

    // MARK: Live events

    private func apply(_ event: SSEClient.Event, from accountID: String) {
        switch event {
        case .messageAdded(let card):
            guard !(card.labelIds ?? []).contains(where: { $0 == "SPAM" || $0 == "TRASH" }) else { return }
            let message = card.asMessage(mailboxID: accountID)
            SenderIdentityStore.shared.remember(messages: [message])
            guard !(messages + pending + retained).contains(where: { seenKey($0) == seenKey(message) }) else { return }
            mailboxVersions[accountID, default: 0] += 1
            unreadCounts[accountID] = nil
            if !message.isRead, sectionCounts[accountID] != nil {
                let section = session.section(for: message.receivedAt)
                sectionCounts[accountID]![section] += 1
            }
            pending.append(message)
            scheduleBadgeRefresh()
            scheduleCountsRefresh()

        case .messageRead(let id, let wasUnread):
            let key = accountID + ":" + id
            readVersions[key, default: 0] += 1
            mailboxVersions[accountID, default: 0] += 1
            if let message = (messages + pending + retained).first(where: { seenKey($0) == key }) {
                confirmRead(message, decrement: wasUnread == true)
                if wasUnread == nil { completeCounts.remove(accountID) }
            } else if let intent = recordedReads[key] {
                confirmRead(intent, decrement: wasUnread == true)
                if wasUnread == nil { completeCounts.remove(accountID) }
            } else {
                seenKeys.insert(key)
                persistSeen()
                completeCounts.remove(accountID)
                found(false, else: accountID)
            }
            unreadCounts[accountID] = nil
            scheduleBadgeRefresh()
            scheduleCountsRefresh()

        case .processing(let id):
            found(mutate(id, accountID: accountID) { $0.isInterpreting = true; $0.reinterpret() }, else: accountID)

        case .chunk(let id, let field, let text):
            // Appending as tokens land is what makes the caret honest — it sits
            // at the end of real text rather than animating over a placeholder.
            found(mutate(id, accountID: accountID) { message in
                switch field {
                case "quote": message.quote = (message.quote ?? "") + text
                case "summary": message.summary = (message.summary ?? "") + text
                case "action": message.actionLabel = (message.actionLabel ?? "") + text
                default: break
                }
            }, else: accountID)

        case .fieldComplete(let id, let field, let value):
            found(mutate(id, accountID: accountID) { message in
                switch field {
                case "quote": message.quote = value
                case "summary": message.summary = value
                case "action": message.actionLabel = value
                case "actionUrl": message.actionURL = value.flatMap(URL.init(string:))
                case "unsubscribeUrl": message.unsubscribeURL = value.flatMap(URL.init(string:))
                // The worker finds the email's picture before the model has
                // finished writing about it, so the card can fill in while it
                // is still being interpreted. The raw sender URL never reaches
                // here — what arrives is already the proxy's.
                case "imageUrl": message.imageURL = value.flatMap(URL.init(string:))
                case "requiresAttention": message.requiresAttention = (value == "true")
                case "riskLevel": message.isAtRisk = (value == "possible_scam")
                default: break
                }
                message.reinterpret()
            }, else: accountID)

        case .messageReady(let id):
            found(mutate(id, accountID: accountID) { $0.isInterpreting = false; $0.reinterpret() }, else: accountID)

        case .unsubscribeStatus(let status):
            unsubscribes[status.messageId] = status
            if status.step == .done {
                messages.removeAll { $0.id == status.messageId }
                tally.unsubscribed += 1
            }
        }
    }

    /// Applies an edit wherever the message currently lives, and reports
    /// whether it landed anywhere. A message being interpreted while it sits
    /// behind the pill still has to update.
    @discardableResult
    private func mutate(_ id: String, accountID: String? = nil, _ change: (inout Message) -> Void) -> Bool {
        let matches: (Message) -> Bool = { $0.id == id && (accountID == nil || $0.mailboxID == accountID) }
        for message in session.cards.filter(matches) {
            session.update(seenKey(message), change)
        }
        if let i = messages.firstIndex(where: matches) {
            change(&messages[i])
            return true
        }
        if let i = pending.firstIndex(where: matches) {
            change(&pending[i])
            return true
        }
        if let i = retained.firstIndex(where: matches) {
            change(&retained[i])
            return true
        }
        return false
    }

    /// Historical posts remain actionable without entering the unread feed.
    func currentVersion(of message: Message) -> Message {
        (messages + pending + retained).first { seenKey($0) == seenKey(message) } ?? message
    }

    private func retainIfNeeded(_ message: Message) {
        if !(messages + pending + retained).contains(where: { seenKey($0) == seenKey(message) }) {
            retained.append(message)
        }
    }

    /// An event about a message we have never heard of means the server knows
    /// about mail we do not — the first sync of a mailbox announces itself no
    /// other way. Debounced, because a backlog arrives as a burst and one
    /// fetch answers all of it.
    private func found(_ landed: Bool, else accountID: String) {
        guard !landed, reconcile[accountID] == nil else { return }
        let generation = session.generation
        reconcile[accountID] = Task {
            defer { reconcile[accountID] = nil }
            try? await Task.sleep(for: .seconds(2))
            // Backlog events can keep arriving for minutes. Coalesce them
            // without cancelling a fetch already carrying the user's mail.
            guard !Task.isCancelled, generation == session.generation,
                  !loadingFeeds.contains(accountID) else { return }
            await load(accountID, admitDirectly: messages.isEmpty)
        }
    }

    // MARK: Actions — optimistic, with undo. No confirmation dialogs.

    /// Optimistic with a real undo — which the doc comment claimed and the
    /// code did not do. The row leaves immediately, the mailbox is not touched
    /// until the window closes, and undo puts the post back where it was
    /// rather than at the top.
    func archive(_ message: Message) {
        let key = seenKey(message)
        let index = session.cards.firstIndex { seenKey($0) == key } ?? -1
        let removed = currentVersion(of: message)
        session.remove(key)
        messages.removeAll { seenKey($0) == key }
        pending.removeAll { seenKey($0) == key }
        retained.removeAll { seenKey($0) == key }
        retained.append(removed)
        archiving[key]?.cancel()

        receipt = Receipt(
            message: "Archived.",
            detail: removed.sender.displayName.uppercased(),
            undo: .archive(removed, index)
        )

        archiving[key] = Task {
            try? await Task.sleep(for: .seconds(Move.undoWindow))
            guard !Task.isCancelled else { return }
            readVersions[key, default: 0] += 1
            mailboxVersions[removed.mailboxID, default: 0] += 1
            markingSeen.insert(key)
            do {
                // Read first so the server reports the real unread transition.
                // Its SSE event and HTTP reply may arrive in either order;
                // confirmRead applies the counter change just once.
                let wasUnread = isSample ? true : try await client(removed.mailboxID).markRead(removed.id)
                confirmRead(removed, decrement: wasUnread == true)
                if wasUnread == nil { completeCounts.remove(removed.mailboxID) }
                if !isSample {
                    try await GmailClient(auth: auth, accountID: removed.mailboxID).archive(messageID: removed.id)
                }
                tally.archived += 1
                scheduleBadgeRefresh()
            } catch {
                if index >= 0 {
                    let restored = currentVersion(of: removed)
                    messages.removeAll { seenKey($0) == key }
                    messages.insert(restored, at: min(index, messages.count))
                    session.restore(restored, at: index)
                }
                receipt = Receipt(message: "Couldn’t archive. Your post is still here.")
            }
            readVersions[key, default: 0] += 1
            mailboxVersions[removed.mailboxID, default: 0] += 1
            markingSeen.remove(key)
            archiving[key] = nil
            scheduleCountsRefresh()
        }
    }

    func undoArchive(_ message: Message, at index: Int) {
        let key = seenKey(message)
        archiving[key]?.cancel()
        archiving[key] = nil
        if index >= 0 {
            messages.removeAll { seenKey($0) == key }
            retained.removeAll { seenKey($0) == key }
            messages.insert(message, at: min(index, messages.count))
            session.restore(message, at: index)
        }
        receipt = nil
    }

    func markRead(_ message: Message) {
        guard !currentVersion(of: message).isRead else { return }
        recordSeen([message])
    }

    /// Marks a message with an emoji, or clears it. Nothing leaves the device.
    func react(_ message: Message, _ emoji: String?) {
        retainIfNeeded(message)
        mutate(message.id) { $0.reaction = emoji }
        // A reaction is an accepted value change, so it earns a cue — but only
        // on setting one. Clearing is a correction, and a correction that
        // announces itself as loudly as the decision reads as an error.
        //
        // `commit()`, not `detent()`. The picker fires a detent for every item
        // the finger crosses, so committing with the same cue made the chosen
        // reaction indistinguishable from passing over one more. Landing on a
        // value and choosing it are different events and need different cues.
        if emoji != nil { Haptics.commit() }
    }

    func toggleSaved(_ message: Message) {
        retainIfNeeded(message)
        mutate(message.id) { $0.isSaved.toggle() }
        if currentVersion(of: message).isSaved { tally.saved += 1 }
    }

    func unsubscribe(from message: Message) {
        guard !isSample else { receipt = Receipt(message: "Connect a mailbox to unsubscribe."); return }
        guard let url = message.unsubscribeURL else { return }
        // Seed the local status so the row reacts on tap rather than on the
        // server's first event — the round trip is not the user's problem.
        unsubscribes[message.id] = .init(
            messageId: message.id,
            senderName: message.sender.displayName,
            status: "queued",
            message: nil,
            index: unsubscribes.count + 1,
            total: unsubscribes.count + 1,
            fieldIndex: nil, fieldTotal: nil
        )
        Task {
            do {
                try await client(message.mailboxID).unsubscribe(
                    messageID: message.id,
                    url: url.absoluteString,
                    senderName: message.sender.displayName
                )
            } catch {
                Haptics.needsYou()
                unsubscribes[message.id] = .init(
                    messageId: message.id,
                    senderName: message.sender.displayName,
                    status: "failed",
                    message: error.localizedDescription,
                    index: unsubscribes[message.id]?.index,
                    total: unsubscribes[message.id]?.total,
                    fieldIndex: nil, fieldTotal: nil
                )
            }
        }
    }

    // MARK: Sending
    //
    // Sending is immediate with an undo window rather than a "Send?" dialog.
    // A dialog taxes everybody every time to catch the few who change their
    // mind; an undo charges nothing until you actually use it.

    func queueSend(_ draft: GmailClient.Draft, from mailboxID: String? = nil) {
        guard !isSample else { receipt = Receipt(message: "Connect a mailbox to send email."); return }
        let from = mailboxID ?? auth.accounts.first?.id
        guard let from else { return }
        outgoing?.cancel()
        receipt = Receipt(message: "Sending\u{2026}", detail: draft.to.first?.uppercased(), undo: .send)
        outgoing = Task {
            try? await Task.sleep(for: .seconds(Move.sendUndoWindow))
            guard !Task.isCancelled else { return }
            do {
                try await GmailClient(auth: auth, accountID: from).send(draft)
                tally.replied += 1
                receipt = Receipt(message: "Sent.", detail: draft.to.first?.uppercased())
            } catch let error as URLError where Self.unresolved.contains(error.code) {
                // The request never came back. That is not the same as a
                // refusal — the message may well be in their inbox already,
                // and saying "didn't send" would send it twice.
                Haptics.needsYou()
                receipt = Receipt(
                    message: "We couldn\u{2019}t confirm that send.",
                    detail: "CHECK YOUR SENT MAIL BEFORE WRITING IT AGAIN"
                )
            } catch {
                // Gmail answered and refused. No retry offered: a duplicate
                // send is worse than ambiguity.
                Haptics.needsYou()
                receipt = Receipt(
                    message: "Gmail wouldn\u{2019}t take that one.",
                    detail: error.localizedDescription.uppercased()
                )
            }
            outgoing = nil
        }
    }

    func undoSend() {
        outgoing?.cancel()
        outgoing = nil
        receipt = Receipt(message: "Held. Nothing was sent.")
    }

    func dismissReceipt() { receipt = nil }

    /// Admits the pending batch at the top. Called only from the new-posts pill.
    func admitPending() {
        guard !pending.isEmpty else { return }
        let eligible = eligiblePending
        session.admit(eligible)
        let keys = Set(eligible.map(seenKey))
        messages.insert(contentsOf: eligible.sorted(by: FeedSession.newer), at: 0)
        pending.removeAll { keys.contains(seenKey($0)) }
    }

    #if DEBUG
    /// Stages existing unread cards as a deterministic arrival for a navigation
    /// check. This changes only the current in-memory visit, never Gmail.
    func stageNavigationProbeArrival() -> [String] {
        let batch = Array(sessionMessages.filter { !$0.isRead && !hasSeen($0) }.prefix(2))
        let keys = Set(batch.map(\.feedKey))
        for key in keys { session.remove(key) }
        messages.removeAll { keys.contains($0.feedKey) }
        pending.removeAll { keys.contains($0.feedKey) }
        pending.insert(contentsOf: batch, at: 0)
        return batch.map(\.feedKey)
    }
    #endif

    func messages(groupedBy calendar: Calendar = .current) -> [(String, [Message])] {
        session.groups(included: feedingIDs)
    }

}

private extension Message {
    /// The shape `/session-recap` reads. Only what the briefing needs — the
    /// body never leaves the device for this.
    var asRecapCard: APIClient.Card {
        APIClient.Card(
            messageId: id, threadId: threadID, labelIds: nil,
            subject: subject, fromName: sender.name, fromEmail: sender.address,
            snippet: snippet, internalDate: receivedAt.timeIntervalSince1970 * 1000,
            aiStatus: isInterpreting ? "pending" : "done",
            quote: quote, summary: summary, action: actionLabel,
            actionUrl: actionURL?.absoluteString, requiresAttention: requiresAttention,
            unsubscribeUrl: unsubscribeURL?.absoluteString,
            avatarUri: nil, avatarFallbackText: nil,
            // No pictures in a briefing: the recap is text the model writes
            // about text, and an image URL is one more thing to send for
            // nothing.
            heroImageUrl: nil, heroImageBgColor: nil, senderDescription: nil,
            imageUrl: nil, attachments: nil, riskLevel: nil
        )
    }
}

// MARK: - Sample data
//
// Design-time only. The running app never reaches this — every field here has
// a real counterpart in the `/feed` payload.

enum Sample {
    static let mailboxes: [Mailbox] = [
        Mailbox(id: "mb1", address: "craig@gmail.com", provider: "Gmail",
                status: .active(lastSynced: .now), tag: "GM",
                includeInUnifiedFeed: true),
        Mailbox(id: "mb2", address: "craig@northwind.co", provider: "Outlook",
                status: .active(lastSynced: .now), tag: "WORK",
                includeInUnifiedFeed: true),
    ]

    static let priya = Sender(name: "Priya Raman", address: "priya@northwind.co", kind: .person, logoURL: nil)
    static let delta = Sender(name: "Delta Air Lines SkyMiles", address: "no-reply@delta.com", kind: .brand, logoURL: nil)
    static let marcus = Sender(name: "Marcus Hill", address: "marcus@acme.io", kind: .person, logoURL: nil)
    static let figma = Sender(name: "Figma", address: "news@figma.com", kind: .brand, logoURL: nil)
    static let chase = Sender(name: "Chase Security", address: "alerts@chase-secure-verify.net", kind: .brand, logoURL: nil)
    static let nike = Sender(name: "Nike", address: "news@nike.com", kind: .brand, logoURL: nil)
    static let ramp = Sender(name: "Ramp", address: "alerts@ramp.com", kind: .brand, logoURL: nil)

    static let messages: [Message] = [
        Message(
            id: "m1", threadID: "t1", mailboxID: "mb2", sender: priya,
            subject: "Design review moved",
            snippet: "Hey — had to shuffle things around this week.",
            receivedAt: .now.addingTimeInterval(-12 * 60),
            quote: "Can you do Thursday at 2?",
            summary: "She needs a yes or no before she books the room.",
            actionLabel: nil, actionURL: nil,
            kicker: .needsYou, shape: .text,
            isRead: false, threadCount: 4, unsubscribeURL: nil,
            requiresAttention: true, isInterpreting: false
        ),
        Message(
            id: "m2", threadID: "t2", mailboxID: "mb1", sender: ramp,
            subject: "Card declined",
            snippet: "A vendor charge failed this morning.",
            receivedAt: .now.addingTimeInterval(-40 * 60),
            quote: "Card ending 4417 was declined",
            summary: "A vendor charge failed this morning. Nothing retries on its own.",
            actionLabel: "Update payment method",
            actionURL: URL(string: "https://ramp.com/settings/billing"),
            kicker: .needsYou, shape: .text,
            isRead: false, threadCount: 1, unsubscribeURL: nil,
            requiresAttention: true, isInterpreting: false
        ),
        Message(
            id: "m3", threadID: "t3", mailboxID: "mb1", sender: delta,
            subject: "Your upcoming flight to Miami",
            snippet: "This is an important reminder that your upcoming flight DL204…",
            receivedAt: .now.addingTimeInterval(-2 * 3600),
            quote: "Departure moved to 8:15 AM",
            summary: "DL204 now leaves 55 minutes earlier than booked.",
            actionLabel: "Add ticket to Apple Wallet", actionURL: nil,
            kicker: .fyi, shape: .text,
            isRead: false, threadCount: 2, unsubscribeURL: nil, isInterpreting: false
        ),
        Message(
            id: "m4", threadID: "t4", mailboxID: "mb1", sender: chase,
            subject: "Urgent: verify your account",
            snippet: "Your account will be locked.",
            receivedAt: .now.addingTimeInterval(-3 * 3600),
            quote: "Your account will be locked in 24 hours",
            summary: "The domain is not chase.com. Real banks never ask you to verify through a link.",
            actionLabel: nil, actionURL: nil,
            kicker: .possibleScam, shape: .text,
            isRead: false, threadCount: 1, unsubscribeURL: nil, isInterpreting: false
        ),
        Message(
            // The promotion-with-a-picture shape, which nothing in this set
            // covered before and which therefore could not be looked at
            // without a real mailbox. The image URL is not expected to
            // resolve — `heroGround` stands in, which is also what ships when
            // a sender's CDN is slow.
            id: "m5", threadID: "t5", mailboxID: "mb1", sender: nike,
            subject: "Members get early access",
            snippet: "48 hours of early access.",
            receivedAt: .now.addingTimeInterval(-5 * 3600),
            quote: "Members get 48 hours of early access to the Pegasus 41.",
            summary: "Sale ends Sunday. Nothing needed from you.",
            actionLabel: "Shop early access",
            actionURL: URL(string: "https://nike.com/early-access"),
            kicker: .promotion,
            shape: .media([URL(string: "https://example.invalid/pegasus.jpg")!]),
            isRead: false, threadCount: 1,
            unsubscribeURL: URL(string: "https://nike.com/unsubscribe"), isInterpreting: false
        ),
        Message(
            id: "m6", threadID: "t6", mailboxID: "mb1", sender: figma,
            subject: "Config 2026",
            snippet: "Tickets go on sale Tuesday.",
            receivedAt: .now.addingTimeInterval(-6 * 3600),
            quote: nil, summary: nil, actionLabel: nil, actionURL: nil,
            kicker: .promotion, shape: .text,
            isRead: false, threadCount: 1,
            unsubscribeURL: URL(string: "https://figma.com/unsubscribe"), isInterpreting: true
        ),
        Message(
            id: "m7", threadID: "t7", mailboxID: "mb2", sender: marcus,
            subject: "Signed contract",
            snippet: "Sent the signed contract over.",
            receivedAt: .now.addingTimeInterval(-3 * 86400),
            quote: "Sent the signed contract over",
            summary: "Contract is done. Forward to legal when you get a minute.",
            actionLabel: nil, actionURL: nil,
            kicker: .handled,
            shape: .carousel([
                Attachment(id: "a1", filename: "Contract-final.pdf", byteCount: 2_400_000,
                           preview: .document(pages: 11)),
                Attachment(id: "a2", filename: "Schedule-4.pdf", byteCount: 380_000,
                           preview: .document(pages: 2)),
            ]),
            isRead: true, threadCount: 6, unsubscribeURL: nil, isInterpreting: false
        ),
    ]
}
