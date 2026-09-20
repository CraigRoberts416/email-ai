import Foundation

/// Exercises production stores with intercepted transport and in-memory preferences.
/// Every identity and email is synthetic; no live account or mailbox is used.
@main @MainActor struct InteractionLifecycleTests {
    static var checks = 0
    static var failures: [String] = []

    static func check(_ value: @autoclosure () -> Bool, _ explanation: String) {
        checks += 1
        if !value() { failures.append(explanation); print("FAIL: \(explanation)") }
    }

    static func until(_ explanation: String, _ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() && Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        check(predicate(), "Timed out: \(explanation)")
    }

    struct Fixture {
        let store: FeedStore
        let ids: [String]
        let accounts: [HarnessAccount]
        let messages: [Message]
    }

    static func wire(_ id: String, sender: String = "Synthetic Sender") -> APIClient.Card {
        let json: [String: Any] = ["messageId": id, "subject": "Synthetic subject", "fromName": sender,
            "fromEmail": "sender@example.invalid", "snippet": "Synthetic original text", "aiStatus": "done",
            "labelIds": ["UNREAD", "INBOX"], "internalDate": Date().timeIntervalSince1970 * 1000]
        return try! JSONDecoder().decode(APIClient.Card.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static func fixture(count: Int = 1, messageIDs: [String] = ["same-message"]) -> Fixture {
        InteractionArchive.save([])
        InteractionArchive.saveRuns([:])
        MailDraftStore.clear()
        let ids = (0..<count).map { "interaction-\(UUID().uuidString)-\($0)" }
        let cards = messageIDs.map { wire($0) }
        let accounts = ids.map { id in
            let account = HarnessAccount()
            account.feed = { _, _ in HarnessReply(json: ["cards": [], "sections": ["today": 0, "yesterday": 0, "earlier": 0],
                "unreadCount": 0, "countsComplete": true, "syncState": "complete", "knownStateComplete": true]) }
            account.counts = { _ in HarnessReply(json: ["sections": ["today": 0, "yesterday": 0, "earlier": 0],
                "unreadCount": 0, "countsComplete": true, "syncState": "complete", "knownStateComplete": true]) }
            HarnessTransport.accounts[id] = account
            FeedCache.save(cards, recap: nil, for: id)
            return account
        }
        return Fixture(store: FeedStore(auth: AuthService(accounts: ids)), ids: ids, accounts: accounts,
                       messages: ids.flatMap { account in cards.map { $0.asMessage(mailboxID: account) } })
    }

    static func run(_ message: String = "same-message", attempt: String = "attempt-a", status: String,
                    at: Double, outcome: String? = nil, evidence: String? = nil) -> UnsubscribeRun {
        UnsubscribeRun(messageId: message, senderName: "Synthetic Sender", status: status, message: "Synthetic \(status)",
                       index: 1, total: 1, fieldIndex: nil, fieldTotal: nil, runId: attempt, updatedAt: at,
                       outcome: outcome, evidence: evidence, sourceURL: "https://example.invalid/preferences")
    }

    static func savedPersistenceAndIsolation() {
        let f = fixture(count: 2)
        let a = f.messages[0], b = f.messages[1]
        f.store.toggleSaved(a)
        check(f.store.currentVersion(of: a).isSaved, "Save updates the selected mailbox")
        check(!f.store.currentVersion(of: b).isSaved, "Same message ID in another mailbox remains unsaved")
        f.store.toggleSaved(b)
        check(Set(f.store.saved.map(\.feedKey)) == Set([a.feedKey, b.feedKey]), "Both same-ID messages can be saved independently")
        let restarted = FeedStore(auth: AuthService(accounts: f.ids))
        check(Set(restarted.saved.map(\.feedKey)) == Set([a.feedKey, b.feedKey]), "Saved records survive a new store")
        restarted.clearCachedContent()
        check(restarted.messages.isEmpty && restarted.saved.count == 2, "Clearing regenerable cache preserves explicit saved mail")
        let noCache = FeedStore(auth: AuthService(accounts: f.ids))
        check(noCache.messages.isEmpty && noCache.saved.count == 2, "Saved mail remains available after cache clear and restart")
        noCache.toggleSaved(a)
        check(noCache.saved.map(\.feedKey) == [b.feedKey], "Unsave one account does not remove the other same-ID record")
        noCache.removeLocalInteractions(for: f.ids[0])
        check(FeedStore(auth: AuthService(accounts: [f.ids[1]])).saved.map(\.feedKey) == [b.feedKey],
              "Removing one mailbox's local records preserves the other's persisted save")
        check(FeedStore(auth: AuthService(accounts: ["unconnected-fixture"])).saved.isEmpty,
              "Disconnected identities do not appear in another account's Saved")

        let reactions = fixture(count: 2)
        reactions.store.react(reactions.messages[1], "👀")
        check(reactions.store.currentVersion(of: reactions.messages[1]).reaction == "👀",
              "Reaction applies to the intended mailbox when message IDs collide")
        check(reactions.store.currentVersion(of: reactions.messages[0]).reaction == nil,
              "Reaction never marks another mailbox's same-ID email")
    }

    static func unsubscribeVisibilityAndEvidence() {
        let f = fixture(count: 2)
        let a = f.ids[0], b = f.ids[1]
        f.store.receiveUnsubscribe(run(status: "navigating", at: 100), accountID: a)
        f.store.receiveUnsubscribe(run(status: "needs_you", at: 110), accountID: b)
        let aid = a + ":same-message", bid = b + ":same-message"
        check(f.store.unsubscribes.count == 2, "Same message ID in two mailboxes creates independent jobs")
        f.store.isActivityTrayVisible = false
        f.store.activityPresented = false
        check(f.store.unsubscribes[aid]?.status == "navigating" && f.store.unsubscribes[bid]?.status == "needs_you",
              "Closing the tray and detail keeps both jobs")
        f.store.receiveUnsubscribe(run(status: "verifying", at: 120), accountID: a)
        check(!f.store.isActivityTrayVisible && f.store.unsubscribes[aid]?.status == "verifying",
              "Background progress updates the retained job without reopening a closed tray")
        f.store.removeUnsubscribeReceipt(aid)
        check(f.store.unsubscribes[aid] != nil, "Deleting an active task receipt is refused locally")
        let restarted = FeedStore(auth: AuthService(accounts: f.ids))
        check(restarted.unsubscribes.count == 2, "Activity is restored independently of an open SSE connection")
        restarted.clearCachedContent()
        check(restarted.unsubscribes.count == 2, "Clearing feed cache does not delete task records")

        let request = run(status: "done", at: 130, outcome: "request_sent", evidence: "Provider accepted an outgoing request email")
        f.store.receiveUnsubscribe(request, accountID: a)
        f.store.receiveUnsubscribe(request, accountID: a)
        check(f.store.unsubscribes[aid]?.isConfirmed == false, "Request-sent evidence never becomes sender confirmation")
        check(f.store.unsubscribes[aid]?.title == "Request sent" && f.store.tally.unsubscribed == 0,
              "Request-sent copy and tally remain distinct from confirmed removal")
        f.store.markUnsubscribeComplete(aid)
        check(f.store.unsubscribes[aid]?.isConfirmed == false && f.store.tally.unsubscribed == 0,
              "A user's completion report is retained as a report, not independent confirmation")
        check(f.store.unsubscribes[bid]?.status == "needs_you", "An outcome in mailbox A cannot finish B's same-ID job")

        let confirmed = run(status: "done", at: 140, outcome: "sender_confirmed", evidence: "Sender page explicitly confirmed removal")
        f.store.receiveUnsubscribe(confirmed, accountID: b)
        f.store.receiveUnsubscribe(confirmed, accountID: b)
        check(f.store.tally.unsubscribed == 1, "Repeated confirmed terminal events count once")
        let restored = FeedStore(auth: AuthService(accounts: f.ids))
        restored.receiveUnsubscribe(confirmed, accountID: b)
        check(restored.tally.unsubscribed == 0, "Replaying persisted confirmation does not count as new work")
        restored.receiveUnsubscribe(confirmed, accountID: "not-connected")
        check(restored.unsubscribes.count == 2, "A late disconnected-account event cannot create an activity record")
        restored.removeLocalInteractions(for: a)
        check(restored.unsubscribes[aid] == nil && restored.unsubscribes[bid] != nil,
              "Account-scoped task removal leaves other same-ID receipt intact")
    }

    static func unsubscribeEventOrdering() {
        let f = fixture(), account = f.ids[0], key = f.ids[0] + ":same-message"
        var older = run(attempt: "old", status: "needs_you", at: 100)
        older.handoffURL = "https://example.invalid/old-session"
        f.store.receiveUnsubscribe(older, accountID: account)
        f.store.markUnsubscribeComplete(key)
        f.store.openedUnsubscribePage(key)
        f.store.receiveUnsubscribe(run(attempt: "new", status: "queued", at: 200), accountID: account)
        check(f.store.unsubscribes[key]?.userReportedComplete == nil && f.store.unsubscribes[key]?.openedByUserAt == nil,
              "A new attempt does not inherit the previous human completion report")
        check(f.store.unsubscribes[key]?.history?.map(\.status) == ["queued"],
              "New attempt history starts at its own first event")
        check(f.store.unsubscribes[key]?.handoffURL == nil, "A new attempt does not inherit a stale session handoff")
        f.store.receiveUnsubscribe(run(attempt: "old", status: "done", at: 150, outcome: "sender_confirmed"), accountID: account)
        check(f.store.unsubscribes[key]?.runId == "new" && f.store.unsubscribes[key]?.status == "queued",
              "An older different-attempt event cannot overwrite the current run")
        check(f.store.tally.unsubscribed == 0, "Obsolete attempt confirmation does not count toward new session work")
        f.store.receiveUnsubscribe(run(attempt: "new", status: "verifying", at: 220), accountID: account)
        f.store.receiveUnsubscribe(run(attempt: "new", status: "navigating", at: 210), accountID: account)
        check(f.store.unsubscribes[key]?.status == "verifying", "Out-of-order progress in the same attempt is ignored")
        let terminal = run(attempt: "new", status: "done", at: 230, outcome: "sender_confirmed", evidence: "Confirmed on sender page")
        f.store.receiveUnsubscribe(terminal, accountID: account)
        f.store.receiveUnsubscribe(run(attempt: "new", status: "clicking", at: 230), accountID: account)
        check(f.store.unsubscribes[key]?.isConfirmed == true, "Equal-time progress cannot undo terminal confirmation")
        f.store.receiveUnsubscribe(terminal, accountID: account)
        check(f.store.tally.unsubscribed == 1, "Late progress and replayed confirmation cannot double-count a run")
    }

    static func unsubscribeAttemptIdentity() {
        let f = fixture(), account = f.ids[0], key = f.ids[0] + ":same-message"
        var old = run(attempt: "shared-batch", status: "needs_you", at: 100)
        old.attemptId = "first-intent"
        old.handoffURL = "https://example.invalid/previous-session"
        f.store.receiveUnsubscribe(old, accountID: account)
        f.store.markUnsubscribeComplete(key)
        f.store.openedUnsubscribePage(key)
        var retry = run(attempt: "shared-batch", status: "queued", at: 200)
        retry.attemptId = "second-intent"
        f.store.receiveUnsubscribe(retry, accountID: account)
        check(f.store.unsubscribes[key]?.status == "queued" && f.store.unsubscribes[key]?.attemptId == "second-intent",
              "A new sender attempt can begin while another sender keeps the same batch alive")
        check(f.store.unsubscribes[key]?.history?.map(\.status) == ["queued"] && f.store.unsubscribes[key]?.handoffURL == nil,
              "Same-batch retries do not inherit another attempt's history or handoff")
        check(f.store.unsubscribes[key]?.userReportedComplete == nil && f.store.unsubscribes[key]?.openedByUserAt == nil,
              "Same-batch retries clear the previous human report")

        // Before the server acknowledges a new request, the local timestamp can
        // be ahead of the server clock. Intent identity, not that clock, gates it.
        var pending = run(status: "queued", at: 90_000)
        pending.runId = nil
        pending.attemptId = "fresh-local-intent"
        pending.mailboxID = account
        f.store.unsubscribes[key] = pending
        var stale = run(attempt: "old-server-batch", status: "done", at: 300, outcome: "sender_confirmed")
        stale.attemptId = "first-intent"
        f.store.receiveUnsubscribe(stale, accountID: account)
        check(f.store.unsubscribes[key]?.attemptId == "fresh-local-intent" && f.store.tally.unsubscribed == 0,
              "A previous intent cannot finish a fresh local request before its first acknowledgement")
        stale.attemptId = nil
        f.store.receiveUnsubscribe(stale, accountID: account)
        check(f.store.unsubscribes[key]?.attemptId == "fresh-local-intent" && f.store.tally.unsubscribed == 0,
              "Legacy events without attempt identity cannot displace a pending identified request")
        var acknowledged = run(attempt: "current-server-batch", status: "navigating", at: 400)
        acknowledged.attemptId = "fresh-local-intent"
        f.store.receiveUnsubscribe(acknowledged, accountID: account)
        check(f.store.unsubscribes[key]?.runId == "current-server-batch" && f.store.unsubscribes[key]?.status == "navigating",
              "A matching first acknowledgement is accepted despite client/server clock difference")
    }

    static func receiptOwnershipAndCache() {
        let f = fixture()
        let first = FeedStore.Receipt(message: "First action")
        let second = FeedStore.Receipt(message: "Second action")
        f.store.receipt = first
        f.store.receipt = second
        f.store.dismissReceipt(id: first.id)
        check(f.store.receipt?.id == second.id && f.store.receipts.count == 1,
              "An old receipt's dismissal cannot clear the newer receipt")
        f.store.dismissReceipt(id: first.id)
        check(f.store.receipt?.id == second.id, "Repeated stale dismissal remains harmless")
        f.store.clearCachedContent()
        check(f.store.receipts.map(\.id) == [second.id], "Cache clearing preserves an explicit action receipt")
        f.store.isActivityTrayVisible = false
        check(f.store.receipts.map(\.id) == [second.id], "Closing activity hides presentation without deleting receipts")
    }

    static func unsubscribeTransportRaces() async {
        for retrying in [false, true] {
            let f = fixture(), account = f.ids[0], key = f.ids[0] + ":same-message", gate = HarnessGate()
            var message = f.messages[0]
            message.unsubscribeURL = URL(string: "https://example.invalid/preferences")
            f.accounts[0].unsubscribe = { _ in await gate.wait() }
            if retrying {
                var previous = run(status: "needs_you", at: 100, evidence: "Old attempt evidence")
                previous.handoffURL = "https://example.invalid/old-session"
                f.store.receiveUnsubscribe(previous, accountID: account)
                f.store.retryUnsubscribe(key)
                check(f.store.unsubscribes[key]?.handoffURL == nil && f.store.unsubscribes[key]?.evidence == nil,
                      "Retry immediately clears stale handoff and evidence before network acknowledgement")
            } else {
                f.store.unsubscribe(from: message)
            }
            await until("unsubscribe transport is waiting", { gate.waiting })
            let attempt = f.store.unsubscribes[key]?.attemptId
            check(attempt != nil && f.store.unsubscribes[key]?.runId == nil, "Outbound intent exists before first server acknowledgement")
            var confirmed = run(attempt: "acknowledged-batch", status: "done", at: 200,
                                outcome: "sender_confirmed", evidence: "Sender confirmed removal")
            confirmed.attemptId = attempt
            f.store.receiveUnsubscribe(confirmed, accountID: account)
            gate.finish(HarnessReply(status: 503, json: ["error": "Synthetic lost response after submission"]))
            // Allow the intercepted URLSession response and MainActor catch to
            // settle; the durable evidence must remain unchanged throughout.
            try? await Task.sleep(for: .milliseconds(60))
            check(f.store.unsubscribes[key]?.isConfirmed == true && f.store.unsubscribes[key]?.evidence == confirmed.evidence,
                  "Late HTTP failure cannot overwrite acknowledged sender evidence on \(retrying ? "retry" : "first request")")
            check(f.store.tally.unsubscribed == 1, "Lost HTTP response cannot erase or duplicate confirmed work")
        }

        let failed = fixture(), key = failed.ids[0] + ":same-message"
        var message = failed.messages[0]
        message.unsubscribeURL = URL(string: "https://example.invalid/preferences")
        failed.accounts[0].unsubscribe = { _ in HarnessReply(status: 503, json: ["error": "Synthetic unavailable transport"]) }
        failed.store.unsubscribe(from: message)
        await until("unacknowledged transport failure is represented", { failed.store.unsubscribes[key]?.isTerminal == true })
        check(failed.store.unsubscribes[key]?.outcome == "outcome_unknown" && failed.store.tally.unsubscribed == 0,
              "A transport failure with no acknowledgement remains uncertain, never confirmed")

        let deletion = fixture(), deletionKey = deletion.ids[0] + ":same-message", deleteGate = HarnessGate()
        deletion.accounts[0].unsubscribeReceipt = { _ in await deleteGate.wait() }
        deletion.store.receiveUnsubscribe(run(attempt: "old", status: "done", at: 100, outcome: "request_sent"), accountID: deletion.ids[0])
        deletion.store.removeUnsubscribeReceipt(deletionKey)
        await until("receipt deletion is waiting", { deleteGate.waiting })
        check(deletion.store.unsubscribes[deletionKey] == nil, "Receipt removal updates local presentation immediately")
        deletion.store.receiveUnsubscribe(run(attempt: "new", status: "navigating", at: 200), accountID: deletion.ids[0])
        deleteGate.finish(HarnessReply(status: 503, json: ["error": "Synthetic failed deletion"]))
        await until("failed receipt deletion is visible", { deletion.store.activitySyncFailure != nil })
        check(deletion.store.unsubscribes[deletionKey]?.runId == "new" && deletion.store.unsubscribes[deletionKey]?.status == "navigating",
              "Failed old receipt deletion cannot restore its evidence over a newly acknowledged attempt")
    }

    static func acknowledgedExistingAttemptAndRecovery() async {
        let f = fixture(), account = f.ids[0], key = f.ids[0] + ":same-message", gate = HarnessGate()
        var message = f.messages[0]
        message.unsubscribeURL = URL(string: "https://example.invalid/preferences")
        f.accounts[0].unsubscribe = { _ in await gate.wait() }
        f.store.unsubscribe(from: message)
        await until("new local intent waits for acknowledgement", { gate.waiting })
        let localIntent = f.store.unsubscribes[key]?.attemptId
        await f.store.refreshUnsubscribeActivity()
        check(f.store.unsubscribes[key]?.status == "queued", "An empty activity poll cannot interrupt an in-flight POST")

        var existing = run(attempt: "server-batch", status: "navigating", at: 100)
        existing.attemptId = "already-running-intent"
        f.store.receiveUnsubscribe(existing, accountID: account)
        check(f.store.unsubscribes[key]?.attemptId == localIntent, "An unrelated snapshot cannot replace a pending local intent")
        let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(existing))
        let oldPollGate = HarnessGate()
        var polls = 0
        f.accounts[0].unsubscribeRuns = {
            polls += 1
            if polls == 1 { return await oldPollGate.wait() }
            return HarnessReply(json: ["runs": [encoded]])
        }
        let oldPoll = Task { await f.store.refreshUnsubscribeActivity() }
        await until("old empty activity poll is held", { oldPollGate.waiting })
        gate.finish(HarnessReply(json: ["run": encoded, "alreadyRunning": true]))
        await until("authoritative POST acknowledges an already running sender", {
            f.store.unsubscribes[key]?.attemptId == "already-running-intent"
        })
        oldPollGate.finish(HarnessReply(json: ["runs": []]))
        await oldPoll.value
        check(f.store.unsubscribes[key]?.status == "navigating", "An older empty GET cannot erase a newer POST acknowledgement")
        existing.status = "verifying"; existing.updatedAt = 110
        f.store.receiveUnsubscribe(existing, accountID: account)
        check(f.store.unsubscribes[key]?.status == "verifying", "Progress remains live after adopting the server's existing attempt")
        check(f.accounts[0].requests.filter { $0.url?.path == "/unsubscribe" }.count == 1,
              "Acknowledging an existing worker never submits a second provider attempt")

        let crash = fixture(), crashKey = crash.ids[0] + ":same-message"
        var persisted = run(status: "queued", at: 200)
        persisted.runId = nil; persisted.attemptId = "interrupted-before-ack"; persisted.mailboxID = crash.ids[0]
        InteractionArchive.saveRuns([crashKey: persisted])
        let restored = FeedStore(auth: AuthService(accounts: crash.ids))
        check(restored.unsubscribes[crashKey]?.step == .unknown && restored.unsubscribes[crashKey]?.outcome == "outcome_unknown",
              "Restart after persisting a local intent cannot leave it indefinitely queued")
        check(crash.accounts[0].requests.filter { $0.url?.path == "/unsubscribe" }.isEmpty,
              "Restoring an uncertain intent never automatically resubmits it")

        let legacy = fixture(), legacyKey = legacy.ids[0] + ":same-message"
        var legacyMessage = legacy.messages[0]
        legacyMessage.unsubscribeURL = URL(string: "https://example.invalid/preferences")
        legacy.store.unsubscribe(from: legacyMessage)
        await until("success-only reply without server status becomes explicit uncertainty", {
            legacy.store.unsubscribes[legacyKey]?.step == .unknown
        })
        check(legacy.store.unsubscribes[legacyKey]?.outcome == "outcome_unknown" && legacy.store.tally.unsubscribed == 0,
              "A bare HTTP success cannot fabricate confirmed progress without a server record")
    }

    static func archiveUndoBoundary() async {
        let f = fixture(messageIDs: ["archive-a", "archive-b"])
        let a = f.messages[0], b = f.messages[1], gate = HarnessGate()
        f.accounts[0].read = { id in
            if id == b.id { return await gate.wait() }
            return HarnessReply(json: ["success": true, "wasUnread": true])
        }
        f.store.archive(a)
        let aid = f.store.receipt!.id
        f.store.archive(b)
        let bid = f.store.receipt!.id
        check(f.store.receipts.count == 2 && aid != bid, "Rapid archives retain independently owned receipts")
        f.store.undoArchive(a, at: 0)
        check(f.store.receipt?.id == bid, "Undoing A updates A's receipt without replacing B's latest receipt")
        check(f.store.sessionMessages.contains { $0.feedKey == a.feedKey }
              && !f.store.sessionMessages.contains { $0.feedKey == b.feedKey }, "Undo A does not restore queued B")
        await until("archive B reaches provider submission", { gate.waiting })
        check(f.store.receipts.first { $0.id == bid }?.undo == nil, "Archive Undo disappears before provider submission starts")
        f.store.undoArchive(b, at: 1)
        check(!f.store.sessionMessages.contains { $0.feedKey == b.feedKey }, "Late Undo cannot claim to reverse an in-flight provider action")
        gate.finish(HarnessReply(json: ["success": true, "wasUnread": true]))
        await until("archive B confirms", { f.store.tally.archived == 1 })
        check(f.accounts[0].archives == [b.id], "Only the non-cancelled archive reaches the provider")
        check(f.store.receipts.first { $0.id == aid }?.message == "Kept in Feed.", "A retains its own cancellation result")
        check(f.store.receipts.first { $0.id == bid }?.message == "Archived.", "B retains its own provider result")
        f.store.dismissReceipt(id: aid)
        check(f.store.receipt?.id == bid, "Dismissing A after B completes cannot remove B")
        f.store.beginFeedSession()
    }

    static func main() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("interaction-tests-\(UUID().uuidString)")
        MailDraftStore.directoryOverride = directory
        DiscussionStore.directoryOverride = directory
        defer { try? FileManager.default.removeItem(at: directory) }
        check(URLProtocol.registerClass(HarnessURLProtocol.self), "All URL requests are intercepted")
        savedPersistenceAndIsolation()
        unsubscribeVisibilityAndEvidence()
        unsubscribeEventOrdering()
        unsubscribeAttemptIdentity()
        receiptOwnershipAndCache()
        await unsubscribeTransportRaces()
        await acknowledgedExistingAttemptAndRecovery()
        await archiveUndoBoundary()
        check(HarnessTransport.unexpected.isEmpty, "No unstubbed or live network route was reached")
        print("Interaction lifecycle: \(checks) checks, \(failures.count) failures")
        if !failures.isEmpty { exit(1) }
    }
}
