import Foundation

// MARK: - Sender

struct Sender: Identifiable, Hashable {
    enum Kind: Hashable {
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
enum Kicker: String, Hashable {
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

/// How much room the message earns. The rule is whether it asks for something
/// only the user can give — a decision, a reply, money, or their time.
enum Density: Hashable {
    case lead      // direct ask, deadline or money. Filled summary panel, one CTA.
    case standard  // substantive, no ask. Margin-rule summary, no CTA.
    case compact   // broadcast. A single row and two actions.
}

/// Which card shape the message gets. Resolved first-match-wins, and the
/// underlying question is who did the design work: if the sender already
/// designed it we show theirs, if only the AI understands it we show ours.
enum PostShape: Hashable {
    case html(URL)            // bulk sender with a usable HTML body → their 1:1 section
    case media([URL])         // a human sender whose images carry the meaning
    case carousel([Attachment])
    case quoted(QuotedMessage)
    case text                 // lead / standard / compact all render as text
    case degraded             // interpretation failed; quote suppressed, never guessed
}

struct Attachment: Identifiable, Hashable {
    enum Preview: Hashable {
        case image(URL)
        case document(pages: Int)
    }
    let id: String
    var filename: String
    var byteCount: Int
    var preview: Preview

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

struct QuotedMessage: Hashable {
    var sender: Sender
    var body: String
    var receivedAt: Date
    var attachment: Attachment?
}

// MARK: - Message

struct Message: Identifiable, Hashable {
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
    var density: Density
    var shape: PostShape

    /// Generated per sender domain, not per email — one image stands for
    /// "Delta", so the feed stays recognisable without inventing a picture of
    /// something that did not happen. Its extracted ground colour sits under
    /// the image while it loads, so nothing flashes white.
    var heroImageURL: URL?
    var heroBackground: String?

    var isRead: Bool
    var isSaved: Bool = false
    var threadCount: Int
    var unsubscribeURL: URL?
    /// The model's own verdict on whether this asks something of you. Drives
    /// the kicker; everything else about the card follows from it.
    var requiresAttention: Bool = false

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
            density = .standard
            shape = .degraded
            return
        }

        if isInterpreting {
            kicker = .reading
        } else if isPromotion {
            kicker = .promotion
        } else if requiresAttention {
            kicker = .needsYou
        } else {
            kicker = .fyi
        }

        // Density follows what the message asks of you, not whether it
        // happens to carry a URL. Driving `.lead` off actionLabel meant a
        // NEEDS YOU post with nothing to click rendered byte-identical to an
        // FYI — the one distinction the feed exists to draw, lost to a field
        // that is about links.
        if isPromotion && quote == nil {
            density = .compact
        } else if requiresAttention || actionLabel?.isEmpty == false {
            density = .lead
        } else {
            density = .standard
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
    var notificationsEnabled: Bool

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
