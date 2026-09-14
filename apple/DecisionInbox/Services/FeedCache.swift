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
    }

    private static var directory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        let url = base.appending(path: directoryName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// One file per mailbox, named by a hash rather than the address — the
    /// address is the user's identity and does not belong in a filename.
    private static func file(for accountID: String) -> URL? {
        directory?.appending(path: "\(abs(accountID.hashValue)).json")
    }

    static func save(_ cards: [APIClient.Card], recap: APIClient.Recap?, for accountID: String) {
        guard let file = file(for: accountID) else { return }
        let envelope = Envelope(cards: Array(cards.prefix(200)), savedAt: .now, recap: recap)
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

    static func clear(for accountID: String) {
        guard let file = file(for: accountID) else { return }
        try? FileManager.default.removeItem(at: file)
    }

    static func clearAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
