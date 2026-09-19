import Foundation

/// Each tap is an event, even when the same email is opened a second time.
/// Gmail message IDs are scoped to their connected mailbox.
struct NotificationOpenRequest: Equatable, Sendable {
    let id = UUID()
    let messageID: String?
    let mailboxID: String?

    init(userInfo: [AnyHashable: Any]) {
        messageID = (userInfo["messageId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        mailboxID = (userInfo["userId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    func connectedMailboxID(in accounts: Set<String>) throws -> String {
        if let mailboxID {
            guard accounts.contains(mailboxID) else { throw NotificationOpenError.disconnectedMailbox }
            return mailboxID
        }
        guard accounts.count == 1, let only = accounts.first else { throw NotificationOpenError.ambiguousMailbox }
        return only
    }

    func matches(messageID: String, mailboxID: String, connectedMailboxIDs: Set<String>) -> Bool {
        guard self.messageID == messageID, connectedMailboxIDs.contains(mailboxID) else { return false }
        if let target = self.mailboxID { return target == mailboxID }
        // Older notifications may lack userId. Only a single connected
        // mailbox is unambiguous; never open another account's matching ID.
        return connectedMailboxIDs.count == 1
    }
}

enum NotificationOpenError: LocalizedError {
    case disconnectedMailbox, ambiguousMailbox, unavailableEmail
    var errorDescription: String? {
        switch self {
        case .disconnectedMailbox: return "This email’s mailbox is no longer connected."
        case .ambiguousMailbox: return "This older notification doesn’t identify its mailbox. Open the email from its mailbox."
        case .unavailableEmail: return "This email is no longer available."
        }
    }
}

/// UIKit may deliver a cold-launch tap before SwiftUI attaches its handler.
/// Keep the latest user intent and consume it exactly once when routing exists.
@MainActor
final class NotificationTapBuffer {
    private var pending: NotificationOpenRequest?
    private var handler: ((NotificationOpenRequest) -> Void)?

    func receive(_ request: NotificationOpenRequest) {
        pending = request
        deliverIfReady()
    }

    func install(_ handler: @escaping (NotificationOpenRequest) -> Void) {
        self.handler = handler
        deliverIfReady()
    }

    private func deliverIfReady() {
        guard let pending, let handler else { return }
        self.pending = nil
        handler(pending)
    }
}
