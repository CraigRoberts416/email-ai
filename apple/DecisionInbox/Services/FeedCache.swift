import CryptoKit
import Foundation

/// The feed on disk.
///
/// Without this every cold start showed an empty screen until the network
/// answered — on a slow connection, or a cold Render instance, that is several
/// seconds of a mail app that appears to have lost your mail. The feed you
/// were looking at a minute ago is still true, so it should still be there.
///
/// Cards are cached rather than `Message`s: the card is the wire shape, so a
/// change to how a card becomes a post re-reads correctly from an old cache
/// instead of restoring a stale interpretation.
enum FeedCache {
    private static let directoryName = "FeedCache"
    /// Beyond this the cache is stale enough that showing it would be a claim
    /// about the mailbox rather than a head start on loading it.
    private static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    private struct Envelope: Codable {
        let cards: [APIClient.Card]
        let savedAt: Date
        let recap: APIClient.Recap?
        /// Optional so an envelope written before conversations were cached
        /// still decodes rather than being thrown away as corrupt.
        var conversations: [APIClient.ConversationWire]?
    }

    private static var directory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        var url = base.appending(path: directoryName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Regenerable mail belongs only to this device's cache, not a backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    /// One file per mailbox, named by a digest rather than the address — the
    /// address is the user's identity and does not belong in a filename.
    ///
    /// SHA-256 and not `hashValue`. Swift seeds String hashing randomly at
    /// every process launch, so `hashValue` names a *different* file each run:
    /// the cache wrote a new file on every launch and never once read one
    /// back, which is exactly what "the emails don't stay" looks like from the
    /// outside. A cache keyed by something that changes per launch is not a
    /// cache, and the failure is silent — it looks like a cold start.
    private static func file(for accountID: String) -> URL? {
        let digest = SHA256.hash(data: Data(accountID.lowercased().utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory?.appending(path: "\(name).json")
    }

    /// Drops anything past its age, including files this app can no longer
    /// name. The `hashValue` era left one orphan per launch, and an orphan is
    /// never looked up — so it is never aged out by a lookup either. Someone's
    /// mail should not sit on disk indefinitely because of a naming bug.
    private static func sweep() {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
              )
        else { return }

        for file in files {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            guard let modified, Date.now.timeIntervalSince(modified) > maximumAge else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func save(_ cards: [APIClient.Card], recap: APIClient.Recap?, for accountID: String) {
        sweep()
        guard let file = file(for: accountID) else { return }
        // Conversations are carried forward rather than dropped: the feed and
        // the People list load independently, and whichever writes last must
        // not erase the other's cache.
        let existing = raw(for: accountID)
        let envelope = Envelope(
            cards: Array(cards.prefix(200)), savedAt: .now, recap: recap,
            conversations: existing?.conversations
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        // Written without file protection set to `complete` so a background
        // fetch before first unlock can still read it — the same reason the
        // tokens use `afterFirstUnlock`.
        try? data.write(to: file, options: [.atomic])
    }

    static func load(for accountID: String) -> (cards: [APIClient.Card], recap: APIClient.Recap?)? {
        guard let file = file(for: accountID),
              let data = try? Data(contentsOf: file),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }

        guard Date.now.timeIntervalSince(envelope.savedAt) < maximumAge else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return (envelope.cards, envelope.recap)
    }

    /// Mail from people, cached the same way and for the same reason — a cold
    /// start showed "Reading your mail…" where a list of names had been.
    static func saveConversations(_ conversations: [APIClient.ConversationWire], for accountID: String) {
        guard let file = file(for: accountID) else { return }
        let existing = raw(for: accountID)
        let envelope = Envelope(
            cards: existing?.cards ?? [], savedAt: .now, recap: existing?.recap,
            conversations: Array(conversations.prefix(80))
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: file, options: [.atomic])
    }

    static func loadConversations(for accountID: String) -> [APIClient.ConversationWire]? {
        guard let envelope = raw(for: accountID),
              Date.now.timeIntervalSince(envelope.savedAt) < maximumAge,
              let conversations = envelope.conversations
        else { return nil }
        return conversations
    }

    /// The envelope as written, with no age check — for read-modify-write,
    /// where expiring half of it would silently drop the other half.
    private static func raw(for accountID: String) -> Envelope? {
        guard let file = file(for: accountID),
              let data = try? Data(contentsOf: file)
        else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: data)
    }

    // MARK: - Threads
    //
    // One file per conversation. Opening a thread was a cold network wait every
    // single time — the server got fast, which is not the same as there being
    // nothing to wait for. What somebody said an hour ago has not changed.

    private static func legacyThreadFile(account: String, conversation: String) -> URL? {
        let digest = SHA256.hash(data: Data("\(account.lowercased())|\(conversation.lowercased())".utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory?.appending(path: "thread-\(name).json")
    }

    private struct ThreadEnvelope: Codable {
        let messages: [APIClient.ConversationMessageWire]
        let savedAt: Date
    }

    static func saveMessages(
        _ messages: [APIClient.ConversationMessageWire],
        account: String, conversation: String
    ) {
        sweep()
        guard let directory else { return }
        AccountMailCache(directory: directory).save(
            Array(messages.suffix(120)), account: account, kind: .thread, key: conversation
        )
        if let legacy = legacyThreadFile(account: account, conversation: conversation) {
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    static func loadMessages(
        account: String, conversation: String
    ) -> [APIClient.ConversationMessageWire]? {
        guard let directory else { return nil }
        if let messages = AccountMailCache(directory: directory).load(
            [APIClient.ConversationMessageWire].self, account: account,
            kind: .thread, key: conversation
        ) {
            return messages.isEmpty ? nil : messages
        }
        // Older installs used an opaque combined hash. Keep those messages
        // available until the next successful refresh writes the new format.
        guard let file = legacyThreadFile(account: account, conversation: conversation),
              let data = try? Data(contentsOf: file),
              let envelope = try? JSONDecoder().decode(ThreadEnvelope.self, from: data)
        else { return nil }
        guard Date.now.timeIntervalSince(envelope.savedAt) < maximumAge else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return envelope.messages.isEmpty ? nil : envelope.messages
    }

    // MARK: - Opened email bodies

    static func saveBody(_ body: APIClient.Body, account: String, message: String) {
        sweep()
        guard let directory else { return }
        AccountMailCache(directory: directory).save(
            body, account: account, kind: .body, key: message
        )
    }

    static func loadBody(account: String, message: String) -> APIClient.Body? {
        guard let directory else { return nil }
        return AccountMailCache(directory: directory).load(
            APIClient.Body.self, account: account, kind: .body, key: message
        )
    }

    static func clear(for accountID: String) {
        guard let directory else { return }
        AccountMailCache(directory: directory).clear(account: accountID)
    }

    static func clearAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A disk cache whose account namespace can be removed without knowing every
/// message ID. The directory and clock are values so expiry and isolation can
/// be checked without touching a real person's saved mail.
struct AccountMailCache {
    enum Kind: String { case body, thread }

    let directory: URL
    var now: Date = .now
    private let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    private struct Envelope<Value: Codable>: Codable {
        let value: Value
        let savedAt: Date
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
    }

    private func file(account: String, kind: Kind, key: String) -> URL {
        // Account addresses are case-insensitive; provider message IDs are
        // opaque and must retain their exact case.
        directory.appending(path: "\(kind.rawValue)-\(digest(account.lowercased()))-\(digest(key)).json")
    }

    func save<Value: Codable>(_ value: Value, account: String, kind: Kind, key: String) {
        let envelope = Envelope(value: value, savedAt: now)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        // Available to background refresh after the phone's first unlock,
        // while protected at rest before that unlock.
        try? data.write(to: file(account: account, kind: kind, key: key),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func load<Value: Codable>(_ type: Value.Type, account: String, kind: Kind, key: String) -> Value? {
        let file = file(account: account, kind: kind, key: key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        guard let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: data),
              now.timeIntervalSince(envelope.savedAt) < maximumAge,
              envelope.savedAt <= now.addingTimeInterval(300)
        else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return envelope.value
    }

    func clear(account: String) {
        let accountHash = digest(account.lowercased())
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            let name = file.lastPathComponent
            let oldParts = file.deletingPathExtension().lastPathComponent.split(separator: "-")
            // Legacy thread filenames cannot be attributed to an account.
            // Discard that legacy cache on disconnect rather than retaining
            // potentially disconnected mail. Other accounts' new files stay.
            let legacyThread = oldParts.count == 2 && oldParts[0] == "thread"
                && oldParts[1].count == 32
            if name == "\(accountHash).json"
                || name.hasPrefix("body-\(accountHash)-")
                || name.hasPrefix("thread-\(accountHash)-")
                || legacyThread {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
