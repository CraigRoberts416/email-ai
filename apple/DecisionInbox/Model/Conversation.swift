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
