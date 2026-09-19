import Foundation
import Observation

/// A profile owns its history independently of the unread feed. Exact totals
/// arrive only after Gmail's entire matching history has been enumerated.
@MainActor @Observable
final class SenderHistoryStore {
    private struct Snapshot: Codable { let cards: [APIClient.Card] }
    private let auth: AuthService
    private let sender: Sender
    private let sample: Bool
    private let disk: IdentityDiskCache
    private let pollingInterval: Duration
    private var cards: [String: [APIClient.Card]] = [:]
    private var cursors: [String: String] = [:]
    private var totals: [String: Int] = [:]
    private var complete: Set<String> = []
    private var received: Set<String> = []
    private var loading: Set<String> = []
    private var failures: [String: String] = [:]
    private var sampleMessages: [Message] = []
    private var generation = 0
    private var replacementPending: Set<String> = []
    var scope: String?
    var scopeKey: String?
    var isLoading: Bool { !loading.isEmpty }
    var failure: String? { failures.values.first }
    var hasReceivedHistory: Bool { sample || !received.isEmpty }
    private var accountIDs: Set<String> { Set(auth.accounts.map(\.id)) }
    var countComplete: Bool { sample || (!accountIDs.isEmpty && accountIDs.isSubset(of: complete)) }
    var totalCount: Int? {
        if sample { return sampleMessages.count }
        guard countComplete else { return nil }
        return accountIDs.reduce(0) { $0 + (totals[$1] ?? 0) }
    }
    var hasMore: Bool { !Set(cursors.keys).isDisjoint(with: accountIDs) }
    var isExhausted: Bool { countComplete && !hasMore && !isLoading && failure == nil && totalCount == messages.count }
    var sourcesComplete: Bool {
        sample || (isExhausted && accountIDs.allSatisfy { account in
            (cards[account] ?? []).allSatisfy { $0.sourceInspected == true }
        })
    }
    var messages: [Message] {
        if sample { return sampleMessages }
        return accountIDs.flatMap { account in
            (cards[account] ?? []).map { card in
                var message = card.asMessage(mailboxID: account)
                if message.isInterpreting {
                    message.isInterpreting = false
                    message.kicker = .original
                    message.quote = nil
                    message.summary = nil
                    message.snippet = card.originalText ?? card.snippet ?? ""
                    message.shape = message.imageURL.map { .media([$0]) } ?? .text
                }
                return message
            }
        }.sorted(by: FeedSession.newer)
    }

    init(auth: AuthService, sender: Sender, sample: Bool, seed: [Message], cache: IdentityDiskCache = IdentityDiskCache(), pollingInterval: Duration = .seconds(3)) {
        self.auth = auth
        self.sender = sender
        self.sample = sample
        self.disk = cache
        self.pollingInterval = pollingInterval
        if sample {
            sampleMessages = seed
        } else {
            for account in auth.accounts {
                if let saved = disk.load(Snapshot.self, key: cacheKey(account.id)) {
                    cards[account.id] = saved.cards
                }
            }
        }
    }

    private func cacheKey(_ account: String) -> String {
        "sender-history:\(account):\(sender.kind == .brand ? "brand" : "person"):\(sender.address.lowercased())"
    }

    func start() async {
        guard !sample else { return }
        generation += 1
        let version = generation
        complete.removeAll()
        cursors.removeAll()
        failures.removeAll()
        replacementPending = Set(accountIDs)
        await heads(version: version, replace: true)
        while !Task.isCancelled, generation == version, !countComplete, failure == nil {
            try? await Task.sleep(for: pollingInterval)
            guard !Task.isCancelled, generation == version else { return }
            await heads(version: version, replace: false)
        }
    }

    private func heads(version: Int, replace: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for account in accountIDs where replace || !complete.contains(account) {
                group.addTask { await self.load(account, cursor: nil, version: version, replace: replace) }
            }
        }
    }

    func loadMore() async {
        guard !sample else { return }
        let version = generation
        await withTaskGroup(of: Void.self) { group in
            for account in accountIDs {
                if let cursor = cursors[account] {
                    group.addTask { await self.load(account, cursor: cursor, version: version, replace: false) }
                }
            }
        }
    }

    private func load(_ account: String, cursor: String?, version: Int, replace: Bool) async {
        guard loading.insert(account).inserted else { return }
        defer { loading.remove(account) }
        do {
            var replacePage = replace || replacementPending.contains(account)
            var inspectionPasses = 0
            var previousPendingSources: Int?
            repeat {
            let response = try await APIClient(auth: auth, accountID: account).senderHistory(
                address: sender.address, kind: sender.kind == .brand ? "brand" : "person", cursor: cursor)
            guard !Task.isCancelled, version == generation, accountIDs.contains(account) else { return }
            #if DEBUG
            print("[sender-history] cards=\(response.cards.count) total=\(response.totalCount.map(String.init) ?? "unknown") complete=\(response.countComplete) sync=\(response.syncState) sourcesPending=\(response.sourcePendingCount ?? 0)")
            #endif
            guard response.syncState != "error" else { throw APIError.transport }
            if let cursor, response.nextCursor == cursor { throw APIError.transport }
            scope = response.scope
            scopeKey = response.scopeKey
            // Enumeration starts with an empty working set. That is not a
            // replacement for cached history; preserve it in memory/on disk
            // until a usable head or a verified empty result arrives.
            if response.cards.isEmpty && !response.countComplete {
                failures.removeValue(forKey: account)
                return
            }
            var byID = Dictionary((replacePage ? [] : (cards[account] ?? [])).map { ($0.messageId, $0) }, uniquingKeysWith: { first, _ in first })
            for card in response.cards { byID[card.messageId] = card }
            cards[account] = Array(byID.values).sorted { ($0.internalDate ?? 0) > ($1.internalDate ?? 0) }
            // Polling a growing first page must not rewind an active cursor.
            // Once its current end grows, a new head cursor safely fills gaps;
            // duplicate cards are merged by provider ID.
            if replacePage || cursor != nil || cursors[account] == nil {
                cursors[account] = response.nextCursor
            }
            if response.countComplete, let total = response.totalCount, total >= 0 {
                totals[account] = total
                complete.insert(account)
                if total == 0 { cards[account] = [] }
            } else { complete.remove(account) }
            // An empty page during enumeration is not proof that this sender
            // has no mail. Keep the already-visible feed/cache fallback until
            // history arrives or Gmail has verified an actual empty result.
            if !response.cards.isEmpty || response.countComplete { received.insert(account) }
            failures.removeValue(forKey: account)
            SenderIdentityStore.shared.remember(messages: response.cards.map { $0.asMessage(mailboxID: account) })
            disk.save(Snapshot(cards: Array((cards[account] ?? []).prefix(200))), key: cacheKey(account))
            replacementPending.remove(account)
            let pendingSources = response.sourcePendingCount ?? 0
            guard pendingSources > 0 else { return }
            if let previousPendingSources, pendingSources < previousPendingSources { inspectionPasses = 0 }
            previousPendingSources = pendingSources
            inspectionPasses += 1
            if inspectionPasses >= 10 {
                failures[account] = "Couldn’t finish loading email images and files. Try again."
                return
            }
            replacePage = false
            try? await Task.sleep(for: pollingInterval)
            } while !Task.isCancelled && version == generation
        } catch {
            guard !Task.isCancelled, version == generation else { return }
            failures[account] = "Couldn’t load email history. Try again."
            complete.remove(account)
        }
    }
}
