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

    /// Mail from people, grouped by who is in it. Loaded separately from the
    /// feed because it answers a different question — the feed asks what
    /// arrived, this asks who you are talking to.
    var conversations: [Conversation] = []
    var conversationsLoaded = false

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
    private var archiving: Task<Void, Never>?
    private var reconcile: Task<Void, Never>?

    init(auth: AuthService) {
        self.auth = auth
        syncMailboxes()
    }

    /// True only for the design-time store.
    private(set) var isSample = false

    /// Preview / design-time store. Never used by the running app.
    init(sample: Bool) {
        self.isSample = true
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
        (messages + pending)
            .filter { $0.sender.address.caseInsensitiveCompare(address) == .orderedSame }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

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
    func loadConversations() async {
        guard let account = auth.accounts.first else { return }

        if conversations.isEmpty, let cached = FeedCache.loadConversations(for: account.id) {
            conversations = cached.map(Self.conversation(from:))
            conversationsLoaded = true
        }

        do {
            let wire = try await client(account.id).conversations()
            conversations = wire.map(Self.conversation(from:))
            FeedCache.saveConversations(wire, for: account.id)
        } catch {
            print("[conversations] load failed: \(error)")
        }
        conversationsLoaded = true
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
                    logoURL: nil
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
        guard let account = auth.accounts.first,
              let wire = FeedCache.loadMessages(account: account.id, conversation: conversation.id)
        else { return [] }
        return wire.map(Self.message(from:))
    }

    func messages(in conversation: Conversation) async -> [ConversationMessage] {
        guard let account = auth.accounts.first else { return [] }
        do {
            let wire = try await client(account.id).conversationMessages(conversation.id)
            FeedCache.saveMessages(wire, account: account.id, conversation: conversation.id)
            return wire.map(Self.message(from:))
        } catch {
            print("[conversations] messages failed: \(error)")
            return []
        }
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
                        : .document(pages: wire.pages ?? 0)
                )
            }
        )
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

            // A post already on screen still takes the server's newer version
            // of itself. Interpretation arrives in stages — the quote lands
            // before the summary, a hero image finishes generating minutes
            // later — and a merge that only ever appended left every message
            // frozen at whatever it looked like when it first arrived. Saving
            // and reading are the reader's, so they survive the replacement;
            // everything else is the server's to restate.
            let byID = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            messages = messages.map { existing in
                guard var updated = byID[existing.id] else { return existing }
                updated.isSaved = existing.isSaved
                updated.reaction = existing.reaction
                updated.isRead = existing.isRead || updated.isRead
                return updated
            }

            if admitDirectly {
                // A refresh is the user asking, so mail lands directly — the
                // pill exists for mail that arrives unasked.
                messages = (fresh + messages).sorted { $0.receivedAt > $1.receivedAt }
            } else {
                pending.append(contentsOf: fresh)
            }
            mark(accountID, healthy: true)
            lastSynced = .now
            loadFailure = nil
            FeedCache.save(response.cards, recap: recap, for: accountID)
        } catch APIError.unauthorized, AuthError.signedOut {
            mark(accountID, healthy: false, reason: "needs reconnecting")
            loadFailure = "That mailbox needs reconnecting."
        } catch let error as URLError where Self.unresolved.contains(error.code) {
            loadFailure = error.localizedDescription
            condition = .statusStrip(state: "OFFLINE", freshness: freshness)
        } catch {
            // Anything else came back from our own server, so blaming the
            // user's connection for it would be a lie told in their direction.
            print("[feed] load failed: \(error)")
            loadFailure = error.localizedDescription
            condition = .statusStrip(state: "CAN\u{2019}T REACH THE READER", freshness: freshness)
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

    func suggestReply(to message: Message) async throws -> String {
        try await client(message.mailboxID).suggestReply(messageID: message.id)
    }

    func discuss(question: String, about message: Message) async throws -> String {
        try await client(message.mailboxID).discuss(messageID: message.id, question: question)
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
        guard let account = await auth.connect() else { return }
        syncMailboxes()
        guard !loaded.contains(account.id) else { return }
        loaded.insert(account.id)
        await bring(up: account.id)
    }

    func remove(_ mailboxID: String) {
        FeedCache.clear(for: mailboxID)
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
            let message = card.asMessage(mailboxID: accountID)
            guard !messages.contains(where: { $0.id == message.id }),
                  !pending.contains(where: { $0.id == message.id }) else { return }
            pending.append(message)

        case .messageRead(let id):
            found(mutate(id) { $0.isRead = true }, else: accountID)

        case .processing(let id):
            found(mutate(id) { $0.isInterpreting = true; $0.reinterpret() }, else: accountID)

        case .chunk(let id, let field, let text):
            // Appending as tokens land is what makes the caret honest — it sits
            // at the end of real text rather than animating over a placeholder.
            found(mutate(id) { message in
                switch field {
                case "quote": message.quote = (message.quote ?? "") + text
                case "summary": message.summary = (message.summary ?? "") + text
                case "action": message.actionLabel = (message.actionLabel ?? "") + text
                default: break
                }
            }, else: accountID)

        case .fieldComplete(let id, let field, let value):
            found(mutate(id) { message in
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
            found(mutate(id) { $0.isInterpreting = false; $0.reinterpret() }, else: accountID)

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
    private func mutate(_ id: String, _ change: (inout Message) -> Void) -> Bool {
        if let i = messages.firstIndex(where: { $0.id == id }) {
            change(&messages[i])
            return true
        }
        if let i = pending.firstIndex(where: { $0.id == id }) {
            change(&pending[i])
            return true
        }
        return false
    }

    /// An event about a message we have never heard of means the server knows
    /// about mail we do not — the first sync of a mailbox announces itself no
    /// other way. Debounced, because a backlog arrives as a burst and one
    /// fetch answers all of it.
    private func found(_ landed: Bool, else accountID: String) {
        guard !landed else { return }
        reconcile?.cancel()
        reconcile = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await load(accountID, admitDirectly: messages.isEmpty)
        }
    }

    // MARK: Actions — optimistic, with undo. No confirmation dialogs.

    /// Optimistic with a real undo — which the doc comment claimed and the
    /// code did not do. The row leaves immediately, the mailbox is not touched
    /// until the window closes, and undo puts the post back where it was
    /// rather than at the top.
    func archive(_ message: Message) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let removed = messages.remove(at: index)
        archiving?.cancel()

        receipt = Receipt(
            message: "Archived.",
            detail: removed.sender.displayName.uppercased(),
            undo: .archive(removed, index)
        )

        archiving = Task {
            try? await Task.sleep(for: .seconds(Move.undoWindow))
            guard !Task.isCancelled else { return }
            tally.archived += 1
            try? await GmailClient(auth: auth, accountID: removed.mailboxID)
                .archive(messageID: removed.id)
            archiving = nil
        }
    }

    func undoArchive(_ message: Message, at index: Int) {
        archiving?.cancel()
        archiving = nil
        messages.insert(message, at: min(index, messages.count))
        receipt = nil
    }

    func markRead(_ message: Message) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }),
              !messages[i].isRead else { return }
        messages[i].isRead = true
        Task { try? await client(message.mailboxID).markRead(message.id) }
    }

    /// Marks a message with an emoji, or clears it. Nothing leaves the device.
    func react(_ message: Message, _ emoji: String?) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index].reaction = emoji
        // A reaction is an accepted value change, so it earns a cue — but only
        // on setting one. Clearing is a correction, and a correction that
        // announces itself as loudly as the decision reads as an error.
        if emoji != nil { Haptics.detent() }
    }

    func toggleSaved(_ message: Message) {
        mutate(message.id) { $0.isSaved.toggle() }
        if messages.first(where: { $0.id == message.id })?.isSaved == true { tally.saved += 1 }
    }

    func unsubscribe(from message: Message) {
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
                Haptics.failed()
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
                Haptics.failed()
                receipt = Receipt(
                    message: "We couldn\u{2019}t confirm that send.",
                    detail: "CHECK YOUR SENT MAIL BEFORE WRITING IT AGAIN"
                )
            } catch {
                // Gmail answered and refused. No retry offered: a duplicate
                // send is worse than ambiguity.
                Haptics.failed()
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
            id: "m5", threadID: "t5", mailboxID: "mb1", sender: nike,
            subject: "Members get early access",
            snippet: "48 hours of early access.",
            receivedAt: .now.addingTimeInterval(-5 * 3600),
            quote: nil, summary: "Sale ends Sunday",
            actionLabel: nil, actionURL: nil,
            kicker: .promotion, shape: .text,
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
