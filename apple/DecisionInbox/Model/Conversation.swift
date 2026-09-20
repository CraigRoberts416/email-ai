import Foundation

/// A conversation with one person, or with one set of people.
///
/// Built to `DirectMessages` / `DirectThread`. The identity is the participant
/// set, not the Gmail thread: two threads with the same people in them are one
/// conversation, and the same subject line with a new address on it is a
/// different one. That is what email already does when you reply-all to
/// someone new — mail clients hide the fork behind a shared subject line,
/// which is why nobody can predict where their reply lands.
struct Conversation: Identifiable, Hashable {
    /// The participant set, sorted and lowercased server-side, so the same
    /// people always resolve to the same conversation.
    let id: String
    var participants: [Sender]
    var preview: String
    var lastAt: Date
    /// The last thing said came from the reader. Drives the "You:" prefix.
    var lastFromMe: Bool
    var unread: Bool
    var messageCount: Int
    /// Explicit source account when routed from an account-scoped surface.
    var mailboxID: String? = nil

    var isGroup: Bool { participants.count > 1 }

    /// Given names for a group, full name for one person. "Vikram, Maya,
    /// Dorian" fits where three full names never would, and the given name is
    /// the half that identifies someone you already know.
    var title: String {
        guard isGroup else { return participants.first?.displayName ?? "Unknown" }
        return participants
            .map { $0.displayName.split(separator: " ").first.map(String.init) ?? $0.displayName }
            .joined(separator: ", ")
    }
}

/// One turn in a conversation.
struct ConversationMessage: Identifiable, Hashable {
    let id: String
    var sender: Sender
    /// Written by the reader rather than received. Decides which side of the
    /// thread it sits on and which fill it takes.
    var mine: Bool
    var body: String
    /// Kept only when the sender wrote one that is not merely a reply prefix.
    /// Email has a field chat does not, and dropping it entirely loses
    /// something real — but it is theirs, so it sits above their words rather
    /// than becoming a header we invented.
    var subject: String?
    var receivedAt: Date
    var attachments: [Attachment]
}

/// Inspection happens after a page's cached content is returned. Track each
/// loaded page independently so an older page cannot stop the newest page's
/// refresh, or make already-loaded correspondence disappear.
struct ConversationSourceRefresh {
    private var attempts: [String: Int] = [:]
    let maximumAttempts = 6
    var hasPending: Bool { !attempts.isEmpty }
    var readyPages: [String] { attempts.keys.filter { attempts[$0, default: 0] < maximumAttempts }.sorted() }

    mutating func record(cursor: String?, pending: Bool) {
        let key = cursor ?? ""
        if pending { if attempts[key] == nil { attempts[key] = 0 } }
        else { attempts.removeValue(forKey: key) }
    }
    mutating func beginAttempt(_ key: String) -> Bool {
        guard let count = attempts[key], count < maximumAttempts else { return false }
        attempts[key] = count + 1
        return true
    }
    mutating func retry() { for key in attempts.keys { attempts[key] = 0 } }
    mutating func clear() { attempts.removeAll() }
}
