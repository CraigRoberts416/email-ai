import Foundation

/// Run ./apple/tests/run-feed-store-tests.sh. No account, disk cache, keychain,
/// notification permission, Gmail mutation, or real network is used.
@main @MainActor struct FeedStoreTests {
    static var checks = 0
    static let noon = Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600)

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }

    static func until(_ message: String, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(4)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        check(condition(), "Timed out: \(message)")
    }

    static func card(_ id: String, age: Double = 0, labels: [String] = ["UNREAD", "INBOX"]) -> [String: Any] {
        ["messageId": id, "labelIds": labels, "subject": id, "fromName": "Test Sender",
         "fromEmail": "sender@example.invalid", "snippet": id, "aiStatus": "done",
         "internalDate": noon.addingTimeInterval(-age).timeIntervalSince1970 * 1000]
    }

    static func wire(_ card: [String: Any]) -> APIClient.Card {
        try! JSONDecoder().decode(APIClient.Card.self, from: JSONSerialization.data(withJSONObject: card))
    }

    static func page(_ cards: [[String: Any]], total: Int, next: String? = nil,
                     complete: Bool = true, knownRead: [String] = [],
                     provider: Int? = nil, sections: [String: Int]? = nil) -> HarnessReply {
        var json: [String: Any] = ["cards": cards,
            "sections": sections ?? ["today": total, "yesterday": 0, "earlier": 0],
            "unreadCount": provider ?? total, "countsComplete": complete,
            "knownReadMessageIds": knownRead, "knownStateComplete": complete,
            "syncState": complete ? "complete" : "syncing"]
        if let next { json["nextCursor"] = next }
        return HarnessReply(json: json)
    }

    @MainActor struct Fixture {
        let store: FeedStore
        let ids: [String]
        let accounts: [HarnessAccount]
        func stop() { store.beginFeedSession() }
    }

    static func fixture(_ count: Int = 1, cached: [[String: Any]] = []) -> Fixture {
        let ids = (0..<count).map { "fixture-\(UUID().uuidString)-\($0)" }
        let accounts = ids.map { id -> HarnessAccount in
            let account = HarnessAccount()
            HarnessTransport.accounts[id] = account
            return account
        }
        if !cached.isEmpty { FeedCache.save(cached.map(wire), recap: nil, for: ids[0]) }
        return Fixture(store: FeedStore(auth: AuthService(accounts: ids)), ids: ids, accounts: accounts)
    }

    static func readRaceAndSession() async {
        let f = fixture(), a = f.accounts[0], gate = HarnessGate()
        a.feed = { _, _ in page([card("a"), card("b", age: 60)], total: 2) }
        await f.store.start()
        let original = f.store.sessionMessages
        check(original.map(\.id) == ["a", "b"], "Initial feed uses real response decoding")
        a.read = { id in id == "a" ? await gate.wait() : HarnessReply(json: ["wasUnread": true]) }
        let scroll = Task { await f.store.markSeen(original[0]) }
        await until("read HTTP request", { gate.waiting })
        await a.emit(.messageRead("a", wasUnread: true))
        check(f.store.remainingInFeed == 1, "SSE read decrements before HTTP confirmation")
        gate.finish(HarnessReply(json: ["wasUnread": true]))
        await scroll.value
        check(f.store.remainingInFeed == 1, "HTTP after SSE does not double-decrement")
        check(f.store.sessionMessages.map(\.id) == ["a", "b"], "Scroll-passed card remains in session")
        check(f.store.sessionMessages[0].isRead, "Visible session card records provider-confirmed read")
        f.store.markRead(original[1])
        await until("opening marks second card read", { f.store.hasSeen(original[1]) })
        check(f.store.remainingInFeed == 0, "Opening decrements remaining unread")
        await a.emit(.messageRead("b", wasUnread: true))
        check(f.store.remainingInFeed == 0, "SSE after HTTP does not double-decrement")
        check(f.store.sessionMessages.count == 2 && f.store.completionVerified, "Verified zero keeps both session cards")
        let reads = a.requests.filter { $0.url!.path.hasSuffix("/read") }.count
        await f.store.markSeen(original[0])
        check(a.requests.filter { $0.url!.path.hasSuffix("/read") }.count == reads, "Repeated visibility does not issue duplicate read")
        f.store.beginFeedSession()
        check(f.store.sessionMessages.isEmpty, "Next session removes read cards")
        check(!f.store.completionVerified, "Next visit revalidates counts instead of inheriting zero")
    }

    static func alreadyReadAndFailure() async {
        let f = fixture(), a = f.accounts[0]
        a.feed = { _, _ in page([card("stale"), card("real", age: 60)], total: 1) }
        await f.store.start()
        a.read = { _ in HarnessReply(json: ["wasUnread": false]) }
        await f.store.markSeen(f.store.sessionMessages[0])
        check(f.store.remainingInFeed == 1, "Provider already-read response never decrements another unread email")
        check(f.store.sessionMessages.count == 2, "Already-read confirmation preserves this visit")
        let real = f.store.sessionMessages[1]
        a.read = { _ in HarnessReply(status: 503, json: [:]) }
        await f.store.markSeen(real)
        check(!f.store.hasSeen(real) && f.store.remainingInFeed == 1, "Failed read preserves unread state and count")
        check(f.store.seenFailure != nil && !f.store.completionVerified, "Failed read is retryable and cannot claim completion")
        a.read = { _ in HarnessReply(json: ["wasUnread": true]) }
        await f.store.retrySeen()
        check(f.store.seenFailure == nil && f.store.remainingInFeed == 0, "Retry clears failure only after confirmation")
        f.stop()

        let lost = fixture(), b = lost.accounts[0], gate = HarnessGate()
        b.feed = { _, _ in page([card("mail")], total: 1) }
        await lost.store.start()
        b.read = { _ in await gate.wait() }
        let request = Task { await lost.store.markSeen(lost.store.sessionMessages[0]) }
        await until("lost HTTP request", { gate.waiting })
        await b.emit(.messageRead("mail", wasUnread: true))
        gate.finish(HarnessReply(status: 503, json: [:]))
        await request.value
        check(lost.store.seenFailure == nil && lost.store.remainingInFeed == 0, "Confirmed SSE survives failed HTTP response")
        lost.stop()
    }

    static func cachedCountsAndScope() async {
        let f = fixture(cached: [card("cached"), card("externally-read", age: 60)]), a = f.accounts[0]
        check(f.store.sessionMessages.count == 2, "Cached cards are visible before network")
        check(f.store.remainingInFeed == nil && !f.store.completionVerified, "Cache does not fabricate authoritative counts")
        a.feed = { _, known in
            check(Set(known) == ["cached", "externally-read"], "Head request reconciles known cached IDs")
            return page([card("cached")], total: 23_000, next: "older", knownRead: ["externally-read"],
                        sections: ["today": 15, "yesterday": 30, "earlier": 22_955])
        }
        await f.store.refresh()
        check(f.store.remaining(in: "TODAY") == 15 && f.store.remaining(in: "YESTERDAY") == 30,
              "Section counts include unloaded mail")
        check(f.store.remaining(in: "EARLIER") == 22_955 && f.store.remainingInFeed == 23_000,
              "Historical section count is independent of loaded window")
        check(f.store.sessionMessages.first { $0.id == "externally-read" }?.isRead == true,
              "Provider-known read clears cached ghost without removing current card")
        check(!f.store.feedEndVerified && !f.store.completionVerified, "Unloaded backlog cannot present an ending")
        f.stop()
        check(f.store.sessionMessages.map(\.id) == ["cached"], "Next visit removes externally read cache entry")

        let scope = fixture(), b = scope.accounts[0]
        b.feed = { _, _ in page([card("archive", labels: ["UNREAD"]), card("spam", labels: ["UNREAD", "SPAM"]),
                                card("trash", labels: ["UNREAD", "TRASH"])], total: 1, provider: 3) }
        b.badge = 3
        await scope.store.start()
        check(scope.store.sessionMessages.map(\.id) == ["archive"], "Archived unread enters feed; Spam and Trash do not")
        await b.emit(.messageAdded(wire(card("newspam", labels: ["UNREAD", "SPAM"]))))
        await b.emit(.messageAdded(wire(card("newtrash", labels: ["UNREAD", "TRASH"]))))
        check(scope.store.eligiblePending.isEmpty, "Excluded live mail does not create a new-mail pill")
        await scope.store.markSeen(scope.store.sessionMessages[0])
        await scope.store.refreshUnreadBadge()
        check(scope.store.completionVerified && UNUserNotificationCenter.current().badge == 3,
              "Feed completion can coexist with provider badge containing excluded mail")
        scope.stop()
    }

    static func duplicatePages() async {
        let f = fixture(), a = f.accounts[0]
        var paths: [String] = []
        a.feed = { cursor, _ in
            paths.append(cursor ?? "head")
            switch cursor {
            case nil: return page([card("a")], total: 3, next: "p1")
            case "p1": return page([card("a")], total: 3, next: "p2")
            case "p2": return page([card("b", age: 60)], total: 3, next: "p3")
            default: return page([card("c", age: 120)], total: 3)
            }
        }
        await f.store.refresh()
        f.store.noteFeedInteraction()
        await f.store.loadMoreFeed()
        check(paths == ["head", "p1", "p2"], "Duplicate-only page continues until a visible page")
        check(f.store.sessionMessages.map(\.id) == ["a", "b"], "Pagination keeps existing session cards and deduplicates")
        await f.store.loadMoreFeed()
        check(f.store.sessionMessages.map(\.id) == ["a", "b", "c"], "All pages remain reachable")
        check(!f.store.hasMoreFeed && f.store.feedEndVerified, "Ending is verified only with full unread coverage")
        f.stop()
    }

    static func generationRace() async {
        let f = fixture(), a = f.accounts[0], old = HarnessGate(), fresh = HarnessGate()
        var currentHead = "old"
        a.feed = { cursor, _ in
            if cursor == "old" { return await old.wait() }
            if cursor == "fresh" { return await fresh.wait() }
            return page([card("head")], total: 2, next: currentHead)
        }
        await f.store.refresh()
        let oldRun = Task { await f.store.loadMoreFeed() }
        await until("old page", { old.waiting })
        f.store.beginFeedSession()
        currentHead = "fresh"
        await f.store.refresh()
        let newRun = Task { await f.store.loadMoreFeed() }
        await until("new page", { fresh.waiting })
        old.finish(page([card("obsolete", age: 50)], total: 2))
        await oldRun.value
        check(f.store.loadingMore, "Old generation defer cannot clear current loading state")
        check(!f.store.messages.contains { $0.id == "obsolete" }, "Obsolete page cannot enter new session")
        await f.store.loadMoreFeed()
        check(a.requests.filter { $0.url!.query?.contains("cursor=fresh") == true }.count == 1,
              "Old cleanup cannot allow a duplicate current page request")
        fresh.finish(page([card("current", age: 60)], total: 2))
        await newRun.value
        check(!f.store.loadingMore && f.store.sessionMessages.map(\.id) == ["head", "current"],
              "Current generation finishes and admits only its page")
        f.stop()
    }

    static func multiAccountOrdering() async {
        let f = fixture(2)
        f.accounts[0].feed = { cursor, _ in cursor == nil
            ? page([card("a100"), card("a80", age: 20)], total: 3, next: "a2")
            : page([card("a60", age: 40)], total: 3) }
        f.accounts[1].feed = { cursor, _ in cursor == nil
            ? page([card("b90", age: 10), card("b70", age: 30)], total: 3, next: "b2")
            : page([card("b50", age: 50)], total: 3) }
        await f.store.refresh()
        check(f.store.sessionMessages.map(\.id) == ["a100", "b90", "a80"],
              "Multi-account head reveals only a globally safe chronological prefix")
        check(f.store.remainingInFeed == 6, "Account counts add independently of visible prefix")
        f.store.noteFeedInteraction()
        await f.store.loadMoreFeed()
        await f.store.loadMoreFeed()
        check(f.store.sessionMessages.map(\.id) == ["a100", "b90", "a80", "b70", "a60", "b50"],
              "All account pages merge without newer mail appearing below older mail")
        check(f.store.feedEndVerified, "All six unread messages are reachable before end is confirmed")
        f.stop()
    }

    static func staleResponseAndPendingAdmission() async {
        let f = fixture(), a = f.accounts[0], gate = HarnessGate()
        a.feed = { _, _ in page([card("a"), card("b", age: 60)], total: 2) }
        await f.store.start()
        let original = f.store.sessionMessages[0]
        a.feed = { _, _ in await gate.wait() }
        let refresh = Task { await f.store.refresh() }
        await until("head requested before read", { gate.waiting })
        await f.store.markSeen(original)
        gate.finish(page([card("a"), card("b", age: 60)], total: 2))
        await refresh.value
        check(f.store.sessionMessages.first { $0.id == "a" }?.isRead == true,
              "Slow head response cannot undo a newer confirmed read")
        check(f.store.remainingInFeed == 1, "Slow head counts cannot overwrite a newer confirmed count")
        let incoming = wire(card("new", age: -60))
        await a.emit(.messageAdded(incoming))
        await a.emit(.messageAdded(incoming))
        check(f.store.sessionMessages.map(\.id) == ["a", "b"] && f.store.eligiblePending.count == 1,
              "New mail waits behind the pill and duplicate events are coalesced")
        check(f.store.remainingInFeed == 2, "New unread live event increases total only once")
        f.store.admitPending()
        check(f.store.sessionMessages.map(\.id) == ["new", "a", "b"] && !f.store.hasPendingInFeed,
              "Explicit admission adds new mail above stable existing cards")
        a.read = { _ in HarnessReply(json: ["success": true]) }
        await f.store.markSeen(f.store.sessionMessages[0])
        check(f.store.remainingInFeed == nil && !f.store.completionVerified,
              "Legacy confirmation without wasUnread invalidates precise counts")
        f.stop()
    }

    static func batchedKnownReadReconciliation() async {
        let cached = (0..<450).map { card("cached-\($0)", age: Double($0)) }
        let f = fixture(cached: cached), a = f.accounts[0]
        var batches: [[String]] = []
        a.feed = { _, _ in page(Array(cached.prefix(200)), total: 449, next: "rest") }
        a.counts = { known in
            batches.append(known)
            return page([], total: 449, knownRead: known.contains("cached-449") ? ["cached-449"] : [])
        }
        await f.store.refresh()
        await until("all known-card batches checked", { batches.count == 3 })
        await until("last cached read applied", {
            f.store.sessionMessages.first { $0.id == "cached-449" }?.isRead == true
        })
        check(batches.map(\.count) == [200, 200, 50], "Count reconciliation checks every loaded ID within bounded requests")
        check(Set(batches.flatMap { $0 }).count == 450, "Known-ID batches have no gaps or duplicate coverage")
        check(f.store.remainingInFeed == 449 && f.store.sessionMessages.count == 450,
              "External read beyond first 200 updates progress while preserving session")
        f.stop()

        let failure = fixture(cached: cached), b = failure.accounts[0]
        var requested = 0
        b.feed = { _, _ in page(Array(cached.prefix(200)), total: 449, next: "rest") }
        b.counts = { _ in
            requested += 1
            return requested == 1 ? page([], total: 449) : HarnessReply(status: 503, json: [:])
        }
        await failure.store.refresh()
        await until("failed reconciliation batch", { requested == 2 })
        await until("incomplete batch invalidates counts", { failure.store.remainingInFeed == nil })
        check(!failure.store.feedEndVerified, "A later failed batch cannot leave counts marked complete")
        failure.stop()
    }

    static func displayProgressDuringRevalidation() async {
        let f = fixture(), a = f.accounts[0]
        check(f.store.progressRemaining(in: "TODAY") == nil, "No display count is invented before verification")
        a.feed = { _, _ in page([card("progress")], total: 1) }
        await f.store.start()
        check(f.store.progressRemaining(in: "TODAY") == 1, "Verified count seeds the display baseline")
        a.feed = { _, _ in page([card("progress")], total: 99, complete: false) }
        await f.store.refresh()
        check(f.store.remainingInFeed == nil && f.store.progressRemaining(in: "TODAY") == 1,
              "Expired verification retains the last confirmed display count instead of a partial replacement")
        await f.store.markSeen(f.store.sessionMessages[0])
        check(f.store.progressRemaining(in: "TODAY") == 0,
              "A confirmed read continues counting down the retained baseline")
        check(f.store.remainingInFeed == nil && !f.store.completionVerified && !f.store.feedEndVerified,
              "A display-only zero never bypasses provider completion checks")
        f.store.beginFeedSession()
        check(f.store.progressRemaining(in: "TODAY") == nil,
              "A new visit clears display counts that belonged to the previous date boundary")
    }

    static func excludedAccountBadge() async {
        let f = fixture(2)
        f.accounts[0].feed = { _, _ in page([card("personal")], total: 1) }
        f.accounts[1].feed = { _, _ in page([card("work")], total: 1, provider: 6) }
        f.accounts[0].badge = 1
        f.accounts[1].badge = 6
        await f.store.start()
        f.store.setIncluded(f.ids[1], false)
        await f.store.refresh()
        check(f.store.sessionMessages.map(\.id) == ["personal"] && f.store.remainingInFeed == 1,
              "Excluded account contributes neither visible cards nor section counts")
        check(UNUserNotificationCenter.current().badge == 7, "Badge still includes every connected account")
        await f.accounts[1].emit(.messageAdded(wire(card("work-new"))))
        check(!f.store.hasPendingInFeed, "Excluded account cannot strand the new-mail pill")
        f.stop()
    }

    static func progressivePeopleDirectory() async {
        let f = fixture(), a = f.accounts[0]
        func person(_ id: String, _ date: Int, unread: Bool = true) -> [String: Any] {
            ["id": id, "participants": [["email": id, "name": "Person Reader"]],
             "lastAt": date, "unread": unread, "messageCount": 1]
        }
        func directory(_ rows: [[String: Any]], next: String? = nil, complete: Bool = false) -> HarnessReply {
            var json: [String: Any] = ["conversations": rows, "historyComplete": complete,
                "historySyncState": complete ? "complete" : "indexing"]
            if let next { json["nextCursor"] = next }
            if complete { json["totalConversations"] = rows.count; json["unreadConversations"] = rows.count }
            return HarnessReply(json: json)
        }
        a.conversations = { _ in directory([person("alice",300)], next: "after-alice") }
        await f.store.loadConversations(preservingLoaded: true)
        check(f.store.conversations.map(\.id) == ["alice"] && !f.store.conversationsHistoryComplete,
              "Partial People directory appears without claiming complete history")
        a.conversations = { cursor in
            check(cursor == "after-alice", "People requests its opaque older-page cursor")
            return directory([person("bob",200)], next: "after-bob")
        }
        await f.store.loadMoreConversations()
        check(f.store.conversations.map(\.id) == ["alice","bob"], "Older People page appends")
        a.conversations = { _ in directory([person("new",400),person("alice",300,unread: false)], next: "head-cursor") }
        await f.store.loadConversations(preservingLoaded: true)
        check(f.store.conversations.map(\.id) == ["new","alice","bob"], "Polling merges progress without discarding loaded older rows")
        check(f.store.conversations.first { $0.id == "alice" }?.unread == false, "Polled rows refresh their unread state")
        check(f.store.conversationsNextCursor == "after-bob", "Head polling preserves progress through older pages")
        a.conversations = { _ in directory([]) }
        await f.store.loadConversations(preservingLoaded: true)
        check(f.store.conversations.count == 3 && !f.store.conversationsHistoryComplete,
              "An empty in-progress snapshot cannot wipe known People rows")
        var cursors: [String?] = []
        a.conversations = { cursor in
            cursors.append(cursor)
            return cursor == "after-bob" ? directory([person("bob",200)], next: "older")
                : directory([person("oldest",100)])
        }
        await f.store.loadMoreConversations()
        check(cursors == ["after-bob","older"], "Duplicate-only People pages are traversed without repeated user taps")
        check(f.store.conversations.last?.id == "oldest", "New history beyond duplicate pages remains reachable")
        a.conversations = { _ in HarnessReply(status: 503, json: [:]) }
        await f.store.loadConversations(preservingLoaded: true)
        check(f.store.conversations.count == 4 && f.store.conversationsFailure != nil,
              "People polling failure preserves all loaded rows")
        a.conversations = { _ in directory([], complete: true) }
        await f.store.loadConversations(preservingLoaded: true)
        check(f.store.conversations.isEmpty && f.store.conversationsHistoryComplete,
              "Only a verified empty directory can replace known rows with an empty result")
        f.stop()
    }

    static func missedInterpretationCompletion() async {
        var interpreting = card("working", age: 60)
        interpreting["aiStatus"] = "pending"
        var finished = card("finished")
        finished["quote"] = "Already finished quote"
        finished["imageUrl"] = "https://images.example.invalid/original.jpg"
        let f = fixture(cached: [finished, interpreting]), a = f.accounts[0]
        let initial = f.store.sessionMessages
        let originalDate = initial.first { $0.id == "working" }!.receivedAt
        let working = initial.first { $0.id == "working" }!
        f.store.toggleSaved(working)
        f.store.react(working, "👍")
        f.store.noteFeedInteraction()
        var completion = card("working", age: 172800)
        completion["quote"] = "Completed source quotation"
        completion["summary"] = "Completed summary"
        completion["action"] = "Choose a meeting time"
        completion["actionUrl"] = "https://example.invalid/schedule"
        completion["requiresAttention"] = true
        completion["imageUrl"] = "https://images.example.invalid/completed.jpg"
        completion["avatarUri"] = "https://images.example.invalid/sender.jpg"
        var replacement = finished
        replacement["quote"] = "Changed server wording"
        replacement["imageUrl"] = "https://images.example.invalid/replacement.jpg"
        a.feed = { _, _ in page([completion, replacement], total: 2) }
        await f.store.refresh()
        let visible = f.store.sessionMessages
        check(visible.map(\.id) == initial.map(\.id), "Missed completion updates content without removing or reordering cards")
        let recovered = visible.first { $0.id == "working" }!
        check(!recovered.isInterpreting && recovered.quote == "Completed source quotation" && recovered.summary == "Completed summary",
              "Cached interpreting card recovers completed server content without an SSE event")
        check(recovered.kicker == .needsYou && recovered.actionLabel == "Choose a meeting time" && recovered.actionURL?.path == "/schedule",
              "Recovered presentation and action match the completed interpretation")
        check(recovered.receivedAt == originalDate, "Completion cannot move an existing card into another session date band")
        check(recovered.isSaved && recovered.reaction == "👍" && !recovered.isRead,
              "Recovery preserves read state and local save/reaction")
        check(recovered.imageURL?.lastPathComponent == "completed.jpg" && recovered.sender.logoURL?.lastPathComponent == "sender.jpg",
              "An unfinished card receives its recovered message image and sender identity")
        if case .media(let urls) = recovered.shape {
            check(urls.first == recovered.imageURL, "Recovered image and card shape agree")
        } else { check(false, "Completed image produces media content") }
        let stable = visible.first { $0.id == "finished" }!
        check(stable.quote == "Already finished quote" && stable.imageURL?.lastPathComponent == "original.jpg",
              "Already finished card keeps its content and art during a repeated refresh")
        check(f.store.messages.first { $0.id == "finished" }?.quote == "Changed server wording",
              "Backing records still refresh for the next session")
        f.store.beginFeedSession()
        check(f.store.sessionMessages.first { $0.id == "finished" }?.quote == "Changed server wording",
              "The next session uses refreshed server content")
        f.stop()
    }

    static func falseZeroAndDecodeFailure() async {
        let f = fixture(), a = f.accounts[0]
        a.feed = { _, _ in page([], total: 0, complete: false) }
        await f.store.refresh()
        check(f.store.remainingInFeed == nil && !f.store.completionVerified, "Incomplete synchronization cannot confirm zero")
        a.feed = { _, _ in page([], total: 23_000) }
        await f.store.refresh()
        check(f.store.remainingInFeed == 23_000 && !f.store.feedEndVerified, "Missing local cards cannot create false ending")
        f.stop()

        let malformed = fixture(), b = malformed.accounts[0]
        b.feed = { _, _ in page([["messageId": 42]], total: 0) }
        await malformed.store.refresh()
        check(!malformed.store.feedEndVerified && malformed.store.completionFailure != nil,
              "Dropped malformed card blocks completion instead of silently claiming zero")
        malformed.stop()
    }

    static func notificationLookup() async {
        let f = fixture(2, cached: [card("same")]), a = f.accounts[0], b = f.accounts[1]
        let first = NotificationOpenRequest(userInfo: ["messageId": "same", "userId": f.ids[0]])
        let cached = try? await f.store.notificationMessage(first)
        check(cached?.mailboxID == f.ids[0] && a.requests.isEmpty, "Notification opens cached mail without a network wait")
        f.store.setIncluded(f.ids[1], false)
        b.messageCard = { id in HarnessReply(json: ["card": card(id, age: 100000, labels: [])]) }
        let request = NotificationOpenRequest(userInfo: ["messageId": "same", "userId": f.ids[1]])
        let historical = try? await f.store.notificationMessage(request)
        check(historical?.mailboxID == f.ids[1] && historical?.isRead == true,
              "Same message ID in excluded mailbox fetches that account's historical read email")
        check(b.requests.last?.url?.path == "/messages/same/card", "Missing target uses direct authenticated lookup beyond feed pages")
        check(f.store.sessionMessages.allSatisfy { $0.mailboxID != f.ids[1] }, "Opening a notification never adds excluded or read mail to feed")
        let requestsBefore = b.requests.count
        _ = try? await f.store.notificationMessage(request)
        check(b.requests.count == requestsBefore, "Fetched history is retained for immediate repeat opening")
        b.messageCard = { _ in HarnessReply(status: 404, json: [:]) }
        do {
            _ = try await f.store.notificationMessage(NotificationOpenRequest(userInfo: ["messageId": "deleted", "userId": f.ids[1]]))
            check(false, "Deleted notification cannot silently succeed")
        } catch {
            check(error is NotificationOpenError, "Deleted notification supplies explicit user-facing failure")
        }
        let gate = HarnessGate()
        b.messageCard = { _ in await gate.wait() }
        let disappearing = Task { try await f.store.notificationMessage(NotificationOpenRequest(userInfo: ["messageId": "late", "userId": f.ids[1]])) }
        await until("notification lookup started", { gate.waiting })
        f.store.auth.disconnect(f.ids[1])
        gate.finish(HarnessReply(json: ["card": card("late")]))
        do { _ = try await disappearing.value; check(false, "Disconnected account cannot open late response") }
        catch { check(error is NotificationOpenError, "Late disconnected-account lookup is rejected") }
        let sample = FeedStore(sample: true)
        do { _ = try await sample.notificationMessage(first); check(false, "Sample must never perform mailbox lookup") }
        catch { check(true, "Sample notification lookup remains isolated") }
        f.stop()
    }

    static func main() async {
        check(URLProtocol.registerClass(HarnessURLProtocol.self), "Transport interception installed")
        await readRaceAndSession()
        await alreadyReadAndFailure()
        await cachedCountsAndScope()
        await duplicatePages()
        await generationRace()
        await multiAccountOrdering()
        await staleResponseAndPendingAdmission()
        await batchedKnownReadReconciliation()
        await displayProgressDuringRevalidation()
        await excludedAccountBadge()
        await progressivePeopleDirectory()
        await missedInterpretationCompletion()
        await falseZeroAndDecodeFailure()
        await notificationLookup()
        var sources = ConversationSourceRefresh()
        sources.record(cursor: nil, pending: true)
        sources.record(cursor: "older", pending: true)
        check(sources.readyPages == ["", "older"], "Source refresh tracks newest and older loaded pages independently")
        sources.record(cursor: nil, pending: false)
        check(sources.readyPages == ["older"] && sources.hasPending, "Completed newest files do not hide pending older files")
        for _ in 0..<sources.maximumAttempts { check(sources.beginAttempt("older"), "Bounded source refresh accepts its scheduled attempt") }
        check(!sources.beginAttempt("older") && sources.readyPages.isEmpty && sources.hasPending,
              "Exhausted refresh stays honestly pending and cannot loop forever")
        sources.record(cursor: "older", pending: true)
        check(sources.readyPages.isEmpty, "A still-pending response does not reset the retry budget")
        sources.retry()
        check(sources.readyPages == ["older"], "Explicit retry restores a bounded attempt budget")
        sources.record(cursor: "older", pending: false)
        check(!sources.hasPending, "Successful source inspection clears pending feedback")
        check(HarnessTransport.unexpected.isEmpty, "No unstubbed network path was reached")
        print("FeedStore production integration: \(checks) checks passed")
    }
}
