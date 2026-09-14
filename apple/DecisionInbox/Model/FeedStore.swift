import Foundation
import Observation

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
    var condition: FeedCondition = .normal

    /// Messages that arrived while the user was scrolled away. The feed set is
    /// frozen at load and this is the only path anything joins it by — which
    /// is what makes the list stable under the thumb.
    var pending: [Message] = []

    /// Live unsubscribe runs, keyed by message. The enum is fixed; the sentence
    /// is written by the model each step, so the UI shows what it is told.
    var unsubscribes: [String: SSEClient.UnsubscribeStatus] = [:]

    /// P5 — the action receipt. One at a time; a new one replaces the old.
    var receipt: Receipt?

    /// The masthead, written by the model rather than assembled from a
    /// template. Nil until it lands — the feed does not wait on it.
    var recap: APIClient.Recap?

    struct Receipt: Identifiable {
        enum Undo { case send }
        let id = UUID()
        var message: String
        var detail: String?
        var undo: Undo?
    }

    let auth: AuthService
    private var streams: [String: SSEClient] = [:]
    private var loaded: Set<String> = []
    private var outgoing: Task<Void, Never>?

    init(auth: AuthService) {
        self.auth = auth
        syncMailboxes()
    }

    /// Preview / design-time store. Never used by the running app.
    init(sample: Bool) {
        self.auth = AuthService()
        self.mailboxes = Sample.mailboxes
        self.messages = Sample.messages
    }

    private func client(_ accountID: String) -> APIClient {
        APIClient(auth: auth, accountID: accountID)
    }

    // MARK: Derived

    var saved: [Message] { messages.filter(\.isSaved) }

    var needsReconnect: [Mailbox] { mailboxes.filter { !$0.isHealthy } }

    var waitingCount: Int { messages.count { $0.kicker == .needsYou } }

    /// Only mailboxes the user has left in the unified feed. Excluding one
    /// hides its mail here without disconnecting it — the distinction matters
    /// for a work address you do not want in your evening.
    private var feedingIDs: Set<String> {
        Set(mailboxes.filter(\.includeInUnifiedFeed).map(\.id))
    }

    func mailbox(_ id: String) -> Mailbox? { mailboxes.first { $0.id == id } }

    /// The tag is shown on a post only when there is more than one mailbox to
    /// tell apart. With one, it is noise on every single row.
    var showsMailboxTags: Bool { mailboxes.count > 1 }

    // MARK: Lifecycle

    /// Brings every connected mailbox up. Safe to call repeatedly — each
    /// mailbox is only started once, so adding a fourth does not re-sync three.
    func start() async {
        syncMailboxes()
        await withTaskGroup(of: Void.self) { group in
            for account in auth.accounts where !loaded.contains(account.id) {
                loaded.insert(account.id)
                group.addTask { await self.bring(up: account.id) }
            }
        }
    }

    private func bring(up accountID: String) async {
        // Registering hands the server a refresh token so it can keep syncing
        // while the app is closed. It also kicks off the first backlog pull,
        // so it has to happen before the feed is worth reading.
        try? await client(accountID).register()
        await load(accountID, admitDirectly: true)

        let stream = SSEClient(baseURL: client(accountID).baseURL, auth: auth, accountID: accountID)
        streams[accountID] = stream
        await stream.connect { [weak self] event in
            await self?.apply(event, from: accountID)
        }
    }

    func refresh() async {
        syncMailboxes()
        await withTaskGroup(of: Void.self) { group in
            for account in auth.accounts {
                group.addTask { await self.load(account.id, admitDirectly: true) }
            }
        }
        await loadRecap()
    }

    /// Pulls one mailbox's feed and merges it in place, keeping every other
    /// mailbox's posts untouched.
    private func load(_ accountID: String, admitDirectly: Bool) async {
        do {
            let response = try await client(accountID).feed()
            let incoming = response.cards.map { $0.asMessage(mailboxID: accountID) }
            let known = Set(messages.map(\.id)).union(pending.map(\.id))
            let fresh = incoming.filter { !known.contains($0.id) }

            if admitDirectly {
                // A refresh is the user asking, so mail lands directly — the
                // pill exists for mail that arrives unasked.
                messages = (fresh + messages).sorted { $0.receivedAt > $1.receivedAt }
            } else {
                pending.append(contentsOf: fresh)
            }
            mark(accountID, healthy: true)
        } catch APIError.unauthorized, AuthError.signedOut {
            mark(accountID, healthy: false, reason: "needs reconnecting")
        } catch {
            condition = .statusStrip(state: "OFFLINE", freshness: freshness)
        }
        resolveCondition()
    }

    /// The briefing is a nicety, so it never blocks or reports failure — a
    /// missing recap just means the masthead shows counts and nothing else.
    private func loadRecap() async {
        guard let first = auth.accounts.first, !messages.isEmpty else { return }
        let hour = Calendar.current.component(.hour, from: .now)
        let timeOfDay = hour < 12 ? "morning" : (hour < 17 ? "afternoon" : "evening")
        let cards = messages.prefix(40).map(\.asRecapCard)
        recap = try? await client(first.id).sessionRecap(cards: cards, timeOfDay: timeOfDay)
    }

    func body(of message: Message) async throws -> APIClient.Body {
        try await client(message.mailboxID).body(of: message.id)
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
                includeInUnifiedFeed: true, notificationsEnabled: true
            )
        }
    }

    func add() async {
        guard let account = await auth.connect() else { return }
        syncMailboxes()
        guard !loaded.contains(account.id) else { return }
        loaded.insert(account.id)
        await bring(up: account.id)
    }

    func remove(_ mailboxID: String) {
        Task { await streams[mailboxID]?.disconnect() }
        streams[mailboxID] = nil
        loaded.remove(mailboxID)
        messages.removeAll { $0.mailboxID == mailboxID }
        pending.removeAll { $0.mailboxID == mailboxID }
        auth.disconnect(mailboxID)
        syncMailboxes()
        resolveCondition()
    }

    func rename(_ mailboxID: String, tag: String) {
        auth.rename(mailboxID, tag: tag)
        syncMailboxes()
    }

    func setIncluded(_ mailboxID: String, _ included: Bool) {
        guard let i = mailboxes.firstIndex(where: { $0.id == mailboxID }) else { return }
        mailboxes[i].includeInUnifiedFeed = included
    }

    func setNotifications(_ mailboxID: String, _ enabled: Bool) {
        guard let i = mailboxes.firstIndex(where: { $0.id == mailboxID }) else { return }
        mailboxes[i].notificationsEnabled = enabled
    }

    /// Re-consent for one mailbox. Every other mailbox keeps working through it.
    func reconnect(_ mailboxID: String? = nil) async {
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

    private var freshness: String {
        guard let newest = messages.map(\.receivedAt).max() else { return "Not synced yet" }
        let minutes = Int(Date().timeIntervalSince(newest) / 60)
        return minutes < 1 ? "Up to date" : "Current as of \(minutes) min ago"
    }

    // MARK: Live events

    private func apply(_ event: SSEClient.Event, from accountID: String) {
        switch event {
        case .messageAdded(let card):
            let message = card.asMessage(mailboxID: accountID)
            guard !messages.contains(where: { $0.id == message.id }),
                  !pending.contains(where: { $0.id == message.id }) else { return }
            pending.append(message)

        case .messageRead(let id):
            mutate(id) { $0.isRead = true }

        case .processing(let id):
            mutate(id) { $0.isInterpreting = true; $0.reinterpret() }

        case .chunk(let id, let field, let text):
            // Appending as tokens land is what makes the caret honest — it sits
            // at the end of real text rather than animating over a placeholder.
            mutate(id) { message in
                switch field {
                case "quote": message.quote = (message.quote ?? "") + text
                case "summary": message.summary = (message.summary ?? "") + text
                case "action": message.actionLabel = (message.actionLabel ?? "") + text
                default: break
                }
            }

        case .fieldComplete(let id, let field, let value):
            mutate(id) { message in
                switch field {
                case "quote": message.quote = value
                case "summary": message.summary = value
                case "action": message.actionLabel = value
                case "actionUrl": message.actionURL = value.flatMap(URL.init(string:))
                case "unsubscribeUrl": message.unsubscribeURL = value.flatMap(URL.init(string:))
                case "requiresAttention": message.requiresAttention = (value == "true")
                default: break
                }
                message.reinterpret()
            }

        case .messageReady(let id):
            mutate(id) { $0.isInterpreting = false; $0.reinterpret() }

        case .unsubscribeStatus(let status):
            unsubscribes[status.messageId] = status
            if status.status == "done" {
                messages.removeAll { $0.id == status.messageId }
                receipt = Receipt(
                    message: status.message ?? "Unsubscribed.",
                    detail: status.senderName?.uppercased()
                )
            }
        }
    }

    /// Applies an edit wherever the message currently lives. A message being
    /// interpreted while it sits behind the pill still has to update.
    private func mutate(_ id: String, _ change: (inout Message) -> Void) {
        if let i = messages.firstIndex(where: { $0.id == id }) {
            change(&messages[i])
        } else if let i = pending.firstIndex(where: { $0.id == id }) {
            change(&pending[i])
        }
    }

    // MARK: Actions — optimistic, with undo. No confirmation dialogs.

    func archive(_ message: Message) {
        messages.removeAll { $0.id == message.id }
        Task { try? await client(message.mailboxID).markRead(message.id) }
    }

    func markRead(_ message: Message) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }),
              !messages[i].isRead else { return }
        messages[i].isRead = true
        Task { try? await client(message.mailboxID).markRead(message.id) }
    }

    func toggleSaved(_ message: Message) {
        mutate(message.id) { $0.isSaved.toggle() }
    }

    func unsubscribe(from message: Message) {
        guard let url = message.unsubscribeURL else { return }
        // Seed the local status so the row reacts on tap rather than on the
        // server's first event — the round trip is not the user's problem.
        unsubscribes[message.id] = .init(
            messageId: message.id,
            senderName: message.sender.displayName,
            status: "queued",
            message: nil
        )
        Task {
            do {
                try await client(message.mailboxID).unsubscribe(
                    messageID: message.id,
                    url: url.absoluteString,
                    senderName: message.sender.displayName
                )
            } catch {
                unsubscribes[message.id] = .init(
                    messageId: message.id,
                    senderName: message.sender.displayName,
                    status: "error",
                    message: error.localizedDescription
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
        let from = mailboxID ?? auth.accounts.first?.id
        guard let from else { return }
        outgoing?.cancel()
        receipt = Receipt(message: "Sending\u{2026}", detail: draft.to.first?.uppercased(), undo: .send)
        outgoing = Task {
            try? await Task.sleep(for: .seconds(Move.sendUndoWindow))
            guard !Task.isCancelled else { return }
            do {
                try await GmailClient(auth: auth, accountID: from).send(draft)
                receipt = Receipt(message: "Sent.", detail: draft.to.first?.uppercased())
            } catch {
                // No retry offered: a duplicate send is worse than ambiguity.
                receipt = Receipt(
                    message: "That didn\u{2019}t send.",
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
        messages.insert(contentsOf: pending.sorted { $0.receivedAt > $1.receivedAt }, at: 0)
        pending.removeAll()
    }

    func messages(groupedBy calendar: Calendar = .current) -> [(String, [Message])] {
        let included = feedingIDs
        let visible = messages.filter { included.isEmpty || included.contains($0.mailboxID) }
        let groups = Dictionary(grouping: visible) { message -> String in
            if calendar.isDateInToday(message.receivedAt) { return "TODAY" }
            if calendar.isDateInYesterday(message.receivedAt) { return "YESTERDAY" }
            return "EARLIER"
        }
        return ["TODAY", "YESTERDAY", "EARLIER"].compactMap { key in
            guard let items = groups[key], !items.isEmpty else { return nil }
            return (key, items.sorted { $0.receivedAt > $1.receivedAt })
        }
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
            heroImageUrl: nil, heroImageBgColor: nil
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
                includeInUnifiedFeed: true, notificationsEnabled: true),
        Mailbox(id: "mb2", address: "craig@northwind.co", provider: "Outlook",
                status: .active(lastSynced: .now), tag: "WORK",
                includeInUnifiedFeed: true, notificationsEnabled: true),
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
            kicker: .needsYou, density: .standard, shape: .text,
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
            kicker: .needsYou, density: .lead, shape: .text,
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
            kicker: .fyi, density: .lead, shape: .text,
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
            kicker: .possibleScam, density: .standard, shape: .text,
            isRead: false, threadCount: 1, unsubscribeURL: nil, isInterpreting: false
        ),
        Message(
            id: "m5", threadID: "t5", mailboxID: "mb1", sender: nike,
            subject: "Members get early access",
            snippet: "48 hours of early access.",
            receivedAt: .now.addingTimeInterval(-5 * 3600),
            quote: nil, summary: "Sale ends Sunday",
            actionLabel: nil, actionURL: nil,
            kicker: .promotion, density: .compact, shape: .text,
            isRead: false, threadCount: 1,
            unsubscribeURL: URL(string: "https://nike.com/unsubscribe"), isInterpreting: false
        ),
        Message(
            id: "m6", threadID: "t6", mailboxID: "mb1", sender: figma,
            subject: "Config 2026",
            snippet: "Tickets go on sale Tuesday.",
            receivedAt: .now.addingTimeInterval(-6 * 3600),
            quote: nil, summary: nil, actionLabel: nil, actionURL: nil,
            kicker: .promotion, density: .standard, shape: .text,
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
            kicker: .handled, density: .standard,
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
