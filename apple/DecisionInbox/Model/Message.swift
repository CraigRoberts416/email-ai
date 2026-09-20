import Foundation

// MARK: - Sender

struct Sender: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
        /// A person. Circle avatar.
        case person
        /// A brand or service. Rounded-rect tile, because circles crop logos badly.
        case brand
        /// No identity resolved. Absence of identity should look like absence.
        case unknown
    }

    var id: String { address }
    var name: String
    var address: String
    var kind: Kind
    var logoURL: URL?

    /// Local part stands in when a sender has no display name. Never "Unknown sender".
    var displayName: String {
        name.isEmpty ? String(address.prefix(while: { $0 != "@" })) : name
    }

    var monogram: String {
        String(displayName.first.map(String.init)?.uppercased() ?? "?")
    }
}

// MARK: - Interpretation

/// What the AI decided this message wants from you. Rendered as an uppercase
/// mono kicker above the quote — this is what stands in for an accent colour.
enum Kicker: String, Hashable, Codable {
    case original = "EMAIL"
    case needsYou = "NEEDS YOU"
    case waitingOnThem = "WAITING ON THEM"
    case fyi = "FYI"
    case receipt = "RECEIPT"
    case calendar = "CALENDAR"
    case promotion = "PROMOTION"
    case newsletter = "NEWSLETTER"
    case possibleScam = "POSSIBLE SCAM"
    case handled = "HANDLED"
    /// Interpretation has not landed yet, or failed. The quote slot stays empty.
    case reading = "READING"
    case notRead = "NOT READ"
}

/// Which card shape the message gets. Resolved first-match-wins, and the
/// underlying question is who did the design work: if the sender already
/// designed it we show theirs, if only the AI understands it we show ours.
enum PostShape: Hashable, Codable {
    case html(URL)            // bulk sender with a usable HTML body → their 1:1 section
    case media([URL])         // a human sender whose images carry the meaning
    case carousel([Attachment])
    case quoted(QuotedMessage)
    case text                 // no picture; the quote carries the post
    case degraded             // interpretation failed; quote suppressed, never guessed
}

struct Attachment: Identifiable, Hashable, Codable {
    enum Preview: Hashable, Codable {
        case image(URL)
        case document(pages: Int)
    }
    let id: String
    var filename: String
    var byteCount: Int
    var preview: Preview
    /// Where the file itself lives, signed. Distinct from the preview: a
    /// thumbnail is a picture of an attachment, this is the attachment.
    var fileURL: URL?
    /// What the sender said it is. Used only to recover a file extension when
    /// the filename has none — QuickLook chooses its renderer by extension.
    var mimeType: String?

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

struct QuotedMessage: Hashable, Codable {
    var sender: Sender
    var body: String
    var receivedAt: Date
    var attachment: Attachment?
}

// MARK: - Message

struct Message: Identifiable, Hashable, Codable {
    let id: String
    var threadID: String?
    var mailboxID: String

    var sender: Sender
    var subject: String
    var snippet: String
    var receivedAt: Date

    /// Verbatim from the email. The trust anchor — never a paraphrase.
    var quote: String?
    /// One or two lines the model wrote about what it costs you.
    var summary: String?
    /// Verb plus a specific object, or nil when there is nothing to do.
    var actionLabel: String?
    var actionURL: URL?

    var kicker: Kicker
    var shape: PostShape

    /// Generated per sender domain, not per email — one image stands for
    /// "Delta", so the feed stays recognisable without inventing a picture of
    /// something that did not happen. Its extracted ground colour sits under
    /// the image while it loads, so nothing flashes white.
    var heroImageURL: URL?
    var heroBackground: String?

    /// Who this sender is, in one line, generated per domain. Shown on the
    /// profile where a social app puts a bio. Nil when the model did not
    /// recognise them.
    var senderDescription: String?

    /// The picture this email actually contained, proxied through our server
    /// so fetching it cannot tell the sender when you looked. The hero says
    /// what a sender is like; this says what this message is about, and when
    /// both exist this one wins.
    var imageURL: URL?

    /// Files the email actually carried. Rendered as a scrolling row under the
    /// summary — attachments are objects in their own right, not a property of
    /// the body text, which is why they are a field here rather than a
    /// `PostShape` case competing with the picture.
    var attachments: [Attachment] = []

    var isRead: Bool
    var isFeedEligible: Bool = true
    var isSaved: Bool = false
    /// The emoji the reader put on this message. Local to them — nothing is
    /// sent to the sender. See `ActionRow.react`.
    var reaction: String?
    var threadCount: Int
    var unsubscribeURL: URL?
    /// The model's own verdict on whether this asks something of you. Drives
    /// the kicker; everything else about the card follows from it.
    var requiresAttention: Bool = false

    /// Structural risk signals were found — a domain that does not match the
    /// brand it claims, a link that goes elsewhere, urgency attached to a
    /// credential ask. Set only when the server could also say why.
    var isAtRisk: Bool = false

    /// True while the model is still writing. The quote slot is reserved at
    /// build time so nothing jumps when it lands.
    var isInterpreting: Bool

    var isPromotion: Bool { unsubscribeURL != nil }

    /// Recomputes the presentation from the interpretation.
    ///
    /// Fields arrive a token at a time over SSE, so this runs on every update
    /// rather than once at build time. Keeping the rule in one place is what
    /// stops a card from disagreeing with itself — a NEEDS YOU kicker above a
    /// summary that no longer asks for anything.
    mutating func reinterpret(failed: Bool = false) {
        if failed {
            kicker = .notRead
            shape = .degraded
            return
        }

        if isInterpreting {
            kicker = .reading
        } else if isAtRisk {
            // Outranks everything, including a promotion: the most dangerous
            // mail in an inbox is the mail that looks like routine business.
            kicker = .possibleScam
        } else if isPromotion {
            kicker = .promotion
        } else if requiresAttention {
            kicker = .needsYou
        } else {
            kicker = .fyi
        }

    }
}

// MARK: - Mailbox

struct Mailbox: Identifiable, Hashable {
    enum Status: Hashable {
        case active(lastSynced: Date)
        case needsReconnect(reason: String)
        case paused
    }

    let id: String
    var address: String
    var provider: String
    var status: Status

    /// Two to four characters, user-editable, resolved for collisions at
    /// creation. This is how a unified feed attributes a message without
    /// spending the one colour the product has.
    var tag: String

    var includeInUnifiedFeed: Bool

    var isHealthy: Bool {
        if case .active = status { return true }
        return false
    }
}

// MARK: - Degraded state
//
// Five patterns cover every failure the product has. None of them block the
// feed: nothing the AI does may stand between the user and mail that already
// exists on their server.

enum FeedCondition: Hashable {
    case normal
    /// P1 — a passive strip. No network, slow network, provider outage, rate limited.
    case statusStrip(state: String, freshness: String)
    /// P2 — one sentence and exactly one affirmative verb.
    case actionBar(message: String, verb: String)
    /// P4 — interpretation failed for everything. A flag, not a screen.
    case fallback(freshness: String)
}
